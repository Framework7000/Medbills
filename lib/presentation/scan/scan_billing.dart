import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../domain/models/batch.dart';
import '../../domain/models/bill_scan.dart';
import '../../domain/models/scan_link.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/scanned_code.dart';
import '../../domain/services/smart_scan_classifier.dart';
import '../../domain/services/stock_summary.dart';
import '../../platform/code_reader.dart';
import '../../platform/device_features.dart';
import '../../platform/scan_target_memory.dart';
import '../../platform/text_reader.dart';
import '../../state/providers.dart';
import '../purchases/bill_scan_screen.dart' show BillReviewScreen, captureSupplierBill, receiveBillPhoto;
import '../purchases/medicine_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'barcode_scanner_screen.dart';
import 'scan_details.dart';
import 'scan_flows.dart';

/// On a phone: the counter that camera scans are sent to (null = this
/// phone's own bill).
final scanTargetProvider = StateProvider<ScanStation?>((ref) => null);

/// Smart Scan on the phone: selling adds a pack to a bill (this device's or
/// a counter's); receiving instead builds up one draft purchase, pack by
/// pack, for a pharmacist to price-check and receive — scanning a delivery
/// must never put stock straight onto a customer's bill.
enum ScanMode { selling, receiving }

final scanModeProvider = StateProvider<ScanMode>((ref) => ScanMode.selling);

/// The in-progress draft built by scanning packs in receiving mode. Cleared
/// once it's handed off to the pharmacist for review (or the user signs out).
final receivingDraftProvider = StateNotifierProvider<ReceivingDraftNotifier, BillDraft>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.uid));
  return ReceivingDraftNotifier();
});

class ReceivingDraftNotifier extends StateNotifier<BillDraft> {
  ReceivingDraftNotifier() : super(const BillDraft());

  /// One pack read off a delivery — merged into an existing line for the
  /// same medicine and batch, or added as a new one.
  void addPack({
    required String? medicineId,
    required String medicineName,
    String batchNumber = '',
    int? expiryMonth,
    int? expiryYear,
    int mrpPaise = 0,
  }) {
    final lines = [...state.lines];
    final i = lines.indexWhere((l) => l.medicineId == medicineId && l.batchNumber == batchNumber);
    if (i >= 0) {
      lines[i] = lines[i].copyWith(packs: lines[i].packs + 1);
    } else {
      lines.add(BillDraftLine(
        rawText: medicineName,
        medicineId: medicineId,
        medicineName: medicineName,
        batchNumber: batchNumber,
        expiryMonth: expiryMonth,
        expiryYear: expiryYear,
        packs: 1,
        mrpPaise: mrpPaise,
      ));
    }
    state = state.copyWith(lines: lines);
  }

  void clear() => state = const BillDraft();
}

/// Adds a scanned medicine to this device's bill — the scanned batch when
/// it is on the shelf, otherwise nearest expiry first. One pack by default
/// (a physical scan); [requestedUnits] adds exactly that many base units
/// instead — capped at what's actually free, never more — for transferring
/// an already-built line (e.g. a phone's bill sent to a counter) rather
/// than a single pack scan.
ScanFeedback addScannedToBill(WidgetRef ref, StockSummary stock, {String? batchNumber, int? requestedUnits}) {
  final m = stock.medicine;
  if (!m.scheduleType.isSellable) {
    return ScanFeedback('${m.name} is unclassified — set its schedule in Stock first.', ok: false);
  }
  final now = DateTime.now();
  final cart = ref.read(cartProvider);
  final batches = batchesFor(stock, batchNumber);
  final free = batches
      .where((b) => b.isSellableAt(now))
      .fold<int>(0, (sum, b) => sum + b.quantity - (cart.unitsByBatch[b.id] ?? 0));
  if (free <= 0) {
    return ScanFeedback(
        stock.isOutOfStock ? '${m.name} is out of stock.' : 'All ${m.name} in stock is already on this bill.',
        ok: false);
  }
  final wantedUnits = requestedUnits ?? m.unitsPerPack;
  final units = free < wantedUnits ? free : wantedUnits;
  try {
    ref.read(cartProvider.notifier).addMedicine(m, batches, units, now: now);
  } catch (e) {
    return ScanFeedback(friendlyError(e), ok: false);
  }
  final wanted = batchNumber == null || batchNumber.isEmpty ? null : Batch.normaliseBatchNumber(batchNumber);
  final usedWanted = wanted != null && batches.length == 1 && batches.first.batchNumber == wanted;
  // FEFO allocates nearest-expiry first — for one pack's worth this is
  // almost always a single batch, which is what undo needs to know.
  final usedBatch = batches.where((b) => b.isSellableAt(now)).firstOrNull;
  return ScanFeedback(
    'Added ${PackUnits.describe(units, m.unitsPerPack)} · ${m.name}'
    '${wanted != null && !usedWanted ? ' (batch $wanted not in stock — billed nearest expiry)' : ''}'
    '${units < wantedUnits ? ' (only $units of $wantedUnits available)' : ''}',
    appliedBatchId: usedBatch?.id,
    appliedUnits: units,
  );
}

/// Adds a scan to this device's own bill, or — when a counter is chosen —
/// sends it there instead, exactly the same way whether it came from a
/// barcode or a photographed pack: the phone is a capture device first,
/// its own bill second.
Future<ScanFeedback> _sendOrAddToBill(
  WidgetRef ref, {
  required StockSummary stock,
  String? batchNumber,
  String rawBarcode = '',
  int? units,
  ScanStation? target,
}) async {
  if (target != null) {
    final repo = ref.read(repositoryProvider)!;
    final eventId = repo.newId();
    await repo.sendScan(ScanEvent(
      id: eventId,
      storeId: repo.storeId,
      stationId: target.id,
      rawBarcode: rawBarcode.isEmpty ? stock.medicine.name : rawBarcode,
      medicineId: stock.medicine.id,
      batchNumber: batchNumber,
      units: units,
      deviceLabel: DeviceFeatures.label,
      createdBy: repo.actor.uid,
      createdByName: repo.actor.name,
      scannedAt: DateTime.now(),
    ));
    return ScanFeedback('Sent ${stock.medicine.name} to ${target.name}', undoToken: eventId);
  }
  return addScannedToBill(ref, stock, batchNumber: batchNumber, requestedUnits: units);
}

/// Handles one scanned code. A medicine is added to this device's bill or
/// sent to the chosen counter; anything else is read out plainly instead of
/// failing: a supplier bill's GST e-invoice QR (supplier, invoice no., date,
/// total), an unlinked pack's code (batch, expiry, what it names), or plain
/// text — each with a Details sheet. [toCounter] false always bills here (a
/// counter's own USB scanner).
Future<ScanFeedback> handleScannedCode(BuildContext context, WidgetRef ref, String raw, {bool toCounter = true}) async {
  final code = ScannedCode.decode(raw);
  void details({VoidCallback? onLink}) => showScannedCodeDetails(context, ref, code, onLink: onLink);

  if (code is EInvoiceCode) {
    return ScanFeedback('Supplier bill · ${describeScannedCode(code)}',
        actionLabel: 'Details', onAction: details);
  }
  final index = ref.read(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
  final hit = resolveBarcode(raw, index);
  if (hit.expiry != null && hit.expiry!.isBefore(DateTime.now())) {
    return ScanFeedback(
      '${hit.stock?.medicine.name ?? 'This pack'} is EXPIRED (${DateFormat('MM/yy').format(hit.expiry!)}). Do not sell it.',
      ok: false,
      actionLabel: 'Details',
      onAction: details,
    );
  }
  final stock = hit.stock;
  // Receiving a delivery on the phone: the code's batch, expiry and MRP go
  // onto the receiving list (never the sale bill). A code that names a
  // medicine not stocked yet is added by name, to be matched on review.
  if (DeviceFeatures.isPhone && ref.read(scanModeProvider) == ScanMode.receiving) {
    final pack = code is PackCode ? code : null;
    final name = stock?.medicine.name ?? pack?.brand ?? pack?.genericName;
    if (name != null) {
      ref.read(receivingDraftProvider.notifier).addPack(
            medicineId: stock?.medicine.id,
            medicineName: name,
            batchNumber: hit.batchNumber ?? '',
            expiryMonth: hit.expiry?.month,
            expiryYear: hit.expiry?.year,
            mrpPaise: pack?.mrpPaise ?? 0,
          );
      return ScanFeedback('Added to receiving draft · $name${hit.batchNumber == null ? '' : ' (batch ${hit.batchNumber})'}',
          actionLabel: 'Details', onAction: details);
    }
  }
  if (stock == null) {
    if (code is TextCode) {
      return ScanFeedback('Read: ${describeScannedCode(code)}', actionLabel: 'Details', onAction: details);
    }
    final manager = ref.read(currentUserProvider)?.role.canManageStock ?? false;
    return ScanFeedback(
      '${describeScannedCode(code)} — not linked to a medicine yet${manager ? '' : ' (ask the pharmacist)'}.',
      ok: false,
      actionLabel: 'Details',
      onAction: () => details(onLink: manager ? () => linkBarcode(context, ref, raw) : null),
    );
  }
  return _sendOrAddToBill(ref,
      stock: stock, batchNumber: hit.batchNumber, rawBarcode: raw, target: toCounter ? ref.read(scanTargetProvider) : null);
}

/// Sends every line on this device's own bill to a chosen counter in one
/// go — the phone picks the items, the counter (PC) finishes the sale.
/// Clears this device's bill once sent; it's the counter's bill now.
Future<void> sendCartToStation(BuildContext context, WidgetRef ref) async {
  final cart = ref.read(cartProvider);
  if (cart.isEmpty) return;
  final now = DateTime.now();
  final stations =
      (ref.read(stationsProvider).valueOrNull ?? const <ScanStation>[]).where((s) => s.isAvailableAt(now)).toList();
  if (stations.isEmpty) {
    showMessage(context, 'No counter is online right now.', error: true);
    return;
  }
  final target = stations.length == 1
      ? stations.first
      : await showDialog<ScanStation>(
          context: context,
          builder: (_) => SimpleDialog(
            title: const Text('Send this bill to'),
            children: [
              for (final s in stations) SimpleDialogOption(onPressed: () => Navigator.pop(context, s), child: Text(s.name)),
            ],
          ),
        );
  if (target == null || !context.mounted) return;
  final repo = ref.read(repositoryProvider)!;
  try {
    for (final line in cart.lines) {
      await repo.sendScan(ScanEvent(
        id: repo.newId(),
        storeId: repo.storeId,
        stationId: target.id,
        rawBarcode: line.name,
        medicineId: line.medicineId,
        batchNumber: line.batchNumber,
        units: line.quantity,
        deviceLabel: DeviceFeatures.label,
        createdBy: repo.actor.uid,
        createdByName: repo.actor.name,
        scannedAt: DateTime.now(),
      ));
    }
    ref.read(cartProvider.notifier).clear();
    if (context.mounted) {
      showMessage(context, 'Sent ${cart.lines.length} line${cart.lines.length == 1 ? '' : 's'} to ${target.name}.');
    }
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
}

/// Cancels a scan this device sent to a counter — the 3-second undo window.
Future<void> undoSentScan(WidgetRef ref, String eventId) =>
    ref.read(repositoryProvider)!.markScanCancelled(eventId);

/// Saves an unknown barcode on the medicine it belongs to, so the next scan
/// of that pack — on any device — finds it.
Future<void> linkBarcode(BuildContext context, WidgetRef ref, String raw) async {
  final picked = await pickMedicine(context);
  if (picked == null || !context.mounted) return;
  try {
    await ref.read(repositoryProvider)!.saveMedicine(picked.medicine.copyWith(barcode: linkableCode(raw)));
    if (context.mounted) showMessage(context, 'Barcode linked to ${picked.medicine.name}. Scan it again to add it.');
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
}

/// Opens the camera for scanning pack after pack into the bill.
Future<void> openBillScanner(BuildContext context, WidgetRef ref) => openContinuousScanner(
      context,
      title: 'Scan medicines',
      onScan: (raw) => handleScannedCode(context, ref, raw),
      header: const ScanTargetPicker(),
    );

/// Smart Scan: one camera, one button. A barcode goes straight to the bill
/// (or the chosen counter) like [openBillScanner]; the capture button — for
/// anything without a barcode — photographs it and figures out on its own
/// whether it's a single pack (added to the bill) or a supplier bill (saved
/// for review), so nobody has to pick which kind of scan this is first.
Future<void> openSmartScanner(BuildContext context, WidgetRef ref) => openContinuousScanner(
      context,
      title: 'Smart Scan',
      onScan: (raw) => handleScannedCode(context, ref, raw),
      header: const SmartScanHeader(),
      onCapturePhoto: DeviceFeatures.cameraScanning ? (path) => smartPhotoCapture(context, ref, photoPath: path) : null,
      pendingLabel: () {
        if (ref.read(scanModeProvider) == ScanMode.receiving) return 'Adding to draft…';
        final target = ref.read(scanTargetProvider);
        return target == null ? 'Adding…' : 'Sending to ${target.name}…';
      },
      onUndo: (feedback) => undoSentScan(ref, feedback.undoToken!),
    );

/// What shows above the live Smart Scan camera: selling's counter picker, or
/// receiving's mode toggle and running draft — reactive to the mode switch
/// without having to reopen the scanner.
class SmartScanHeader extends ConsumerWidget {
  const SmartScanHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!DeviceFeatures.isPhone) return const ScanTargetPicker();
    final mode = ref.watch(scanModeProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const ScanModeToggle(),
      if (mode == ScanMode.receiving) const ReceivingSummary() else const ScanTargetPicker(),
    ]);
  }
}

/// Reads whatever was photographed, on the device, and routes it:
///
/// 1. a barcode / QR / DataMatrix anywhere in the photo is the most exact
///    source (GS1 and Schedule H2 codes carry batch and expiry), so it is
///    used first, exactly like a live scan;
/// 2. otherwise the printed text decides: a supplier bill is saved for
///    review, a pack is matched (brand + strength) and added to the bill.
///
/// [photoPath] is the photo the in-app camera just took; without it (no
/// in-app camera) the system camera is opened. Returns null when the user
/// cancelled (nothing to show), otherwise the result to animate on screen.
Future<ScanFeedback?> smartPhotoCapture(BuildContext context, WidgetRef ref, {String? photoPath}) async {
  if (!DeviceFeatures.textReading) {
    // No on-device text reading here (Mac/Windows/web) — offer the camera
    // or an existing file, same as Purchases, and attach it as a supplier
    // bill for review (a phone can read its text later; it shows on every
    // device either way).
    final saved = await captureSupplierBill(context, ref);
    if (saved && context.mounted) Navigator.of(context).pop(); // close Smart Scan behind the review screen
    return null;
  }
  final photo = photoPath != null
      ? XFile(photoPath)
      : await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2400, imageQuality: 93);
  if (photo == null || !context.mounted) return null;

  final index = ref.read(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
  final code = await readCodeFromPhoto(photo.path);
  if (!context.mounted) return null;
  final eInvoice = code == null ? null : switch (ScannedCode.decode(code)) { final EInvoiceCode e => e, _ => null };
  if (code != null && eInvoice == null) {
    final hit = resolveBarcode(code, index);
    // A known code (or an expired one) is answered by the code itself. An
    // unlinked code falls through to reading the pack's text, which can
    // still name the medicine.
    if (hit.stock != null || (hit.expiry != null && hit.expiry!.isBefore(DateTime.now()))) {
      return handleScannedCode(context, ref, code);
    }
  }

  final page = await readTextFromPhoto(photo.path);
  if (!context.mounted) return null;
  if ((page == null || page.isEmpty) && eInvoice == null) {
    return const ScanFeedback('No printed text found. Hold it flat, in good light, and try again.', ok: false);
  }
  final medicines = index.values.map((s) => s.medicine).toList();
  final ownGstin = ref.read(storeProvider).valueOrNull?.gstin ?? '';

  // A GST e-invoice QR in the photo settles it: this is a supplier bill.
  if (eInvoice != null || classifyCapture(page!, medicines, ownGstin: ownGstin) == CaptureKind.supplierBill) {
    final saved = await receiveBillPhoto(context, ref, photo, page: page, eInvoice: eInvoice);
    // Receiving a bill opens its own review screen — close Smart Scan behind
    // it too, rather than leaving the camera open underneath.
    if (saved && context.mounted) Navigator.of(context).pop();
    return null;
  }

  final scan = await scanPackPhoto(context, medicines: medicines, photo: photo, page: page);
  if (scan == null || !context.mounted) return null;
  final info = scan.info;
  if (info.hasExpiry && Batch.endOfMonth(info.expiryYear!, info.expiryMonth!).isBefore(DateTime.now())) {
    return const ScanFeedback('That pack is expired — not added.', ok: false);
  }
  if (ref.read(scanModeProvider) == ScanMode.receiving) {
    ref.read(receivingDraftProvider.notifier).addPack(
          medicineId: scan.medicine.id,
          medicineName: scan.medicine.name,
          batchNumber: info.batchNumber ?? '',
          expiryMonth: info.expiryMonth,
          expiryYear: info.expiryYear,
          mrpPaise: info.mrpPaise ?? 0,
        );
    return ScanFeedback('Added to receiving draft · ${scan.medicine.name}'
        '${info.batchNumber == null ? '' : ' (batch ${info.batchNumber})'}');
  }
  final stock = index[scan.medicine.id];
  if (stock == null) return const ScanFeedback('Medicine not found in this store\'s stock.', ok: false);
  final feedback = await _sendOrAddToBill(ref,
      stock: stock, batchNumber: info.batchNumber, target: ref.read(scanTargetProvider));
  if (info.mrpPaise != null && feedback.ok) {
    final billed = batchesFor(stock, info.batchNumber).firstOrNull;
    if (billed != null && billed.mrpPaise != info.mrpPaise) {
      return ScanFeedback(
        '${feedback.message}. Note: pack MRP ${formatRupees(info.mrpPaise!)} differs from stock record ${formatRupees(billed.mrpPaise)}.',
        ok: false,
      );
    }
  }
  return feedback;
}

/// Where scanned items go: this device's own bill, or a specific counter.
/// Remembers the choice across restarts and shows "Counter offline" if the
/// remembered one isn't listening right now, instead of silently falling
/// back to this device.
class ScanTargetPicker extends ConsumerStatefulWidget {
  const ScanTargetPicker({super.key});

  @override
  ConsumerState<ScanTargetPicker> createState() => _ScanTargetPickerState();
}

class _ScanTargetPickerState extends ConsumerState<ScanTargetPicker> {
  (String, String)? _remembered;
  bool _applied = false;

  @override
  void initState() {
    super.initState();
    ScanTargetMemory.load().then((saved) {
      if (mounted) setState(() => _remembered = saved);
    });
  }

  void _choose(ScanStation? station) {
    _applied = true;
    ref.read(scanTargetProvider.notifier).state = station;
    unawaited(ScanTargetMemory.save(station?.id ?? '', station?.name ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final stations = (ref.watch(stationsProvider).valueOrNull ?? const <ScanStation>[])
        .where((s) => s.isAvailableAt(now))
        .toList();
    final target = ref.watch(scanTargetProvider);
    final remembered = _remembered;

    String? offlineName;
    if (!_applied && target == null && remembered != null && remembered.$1.isNotEmpty) {
      final match = stations.where((s) => s.id == remembered.$1).firstOrNull;
      if (match != null) {
        _applied = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(scanTargetProvider.notifier).state = match;
        });
      } else {
        offlineName = remembered.$2;
      }
    }

    final offlineNotice = offlineName == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: Space.s),
            child: Row(children: [
              const Icon(PhosphorIconsRegular.wifiSlash, size: 16, color: AppColors.muted),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text('Counter offline: $offlineName',
                    style: text.bodySmall?.copyWith(color: AppColors.muted))),
            ]),
          );

    if (stations.isEmpty) return offlineNotice ?? const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ?offlineNotice,
      DropdownButtonFormField<String>(
        initialValue: stations.any((s) => s.id == target?.id) ? target!.id : '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Add scanned items to'),
        items: [
          const DropdownMenuItem(value: '', child: Text('The bill on this device')),
          for (final s in stations) DropdownMenuItem(value: s.id, child: Text('${s.name} (counter)')),
        ],
        onChanged: (id) => _choose(stations.where((s) => s.id == id).firstOrNull),
      ),
    ]);
  }
}

/// Scans this device sent that no counter picked up within 10 minutes —
/// shown on the phone so a missed scan is never just silently forgotten.
class NotDeliveredScans extends ConsumerWidget {
  const NotDeliveredScans({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!DeviceFeatures.isPhone) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final stale = (ref.watch(sentScansProvider).valueOrNull ?? const <ScanEvent>[])
        .where((e) => e.status == ScanEventStatus.pending && now.difference(e.scannedAt) > const Duration(minutes: 10))
        .toList()
      ..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    if (stale.isEmpty) return const SizedBox.shrink();

    return Card(
      color: AppColors.warningContainer,
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(PhosphorIconsRegular.warningCircle, color: AppColors.warning, size: 20),
            const SizedBox(width: Space.s),
            Text('Not delivered (${stale.length})',
                style: text.titleSmall?.copyWith(color: AppColors.warning)),
          ]),
          const SizedBox(height: Space.xs),
          Text('No counter picked these up. Check it\'s still open, or scan them again.',
              style: text.bodySmall?.copyWith(color: AppColors.warning)),
          const SizedBox(height: Space.s),
          for (final e in stale)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text('• ${e.rawBarcode} — ${DateFormat('hh:mm a').format(e.scannedAt)}',
                  style: text.bodySmall),
            ),
        ]),
      ),
    );
  }
}

/// Selling vs receiving, shown above [ScanTargetPicker] / [ReceivingSummary]
/// on the phone — receiving a delivery must never look like selling to a
/// customer, so it's a deliberate switch, not a side effect of what's scanned.
class ScanModeToggle extends ConsumerWidget {
  const ScanModeToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(scanModeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: SegmentedButton<ScanMode>(
        segments: const [
          ButtonSegment(value: ScanMode.selling, label: Text('Selling'), icon: Icon(PhosphorIconsRegular.cashRegister)),
          ButtonSegment(
              value: ScanMode.receiving, label: Text('Receiving'), icon: Icon(PhosphorIconsRegular.package)),
        ],
        selected: {mode},
        onSelectionChanged: (s) => ref.read(scanModeProvider.notifier).state = s.first,
      ),
    );
  }
}

/// The draft purchase built up by scanning a delivery pack by pack — shown
/// instead of [ScanTargetPicker] while receiving. Nothing here is stock yet;
/// "Review & receive" hands it to the normal bill-review screen, where a
/// pharmacist prices, checks and receives it like any other supplier bill.
class ReceivingSummary extends ConsumerWidget {
  const ReceivingSummary({super.key});

  Future<void> _review(BuildContext context, WidgetRef ref) async {
    final draft = ref.read(receivingDraftProvider);
    try {
      final scan = await ref.read(repositoryProvider)!.createBillScan(
            draft: draft,
            ocrText: 'Built on ${DeviceFeatures.label} from ${draft.lines.length} scanned pack'
                '${draft.lines.length == 1 ? '' : 's'}.',
          );
      ref.read(receivingDraftProvider.notifier).clear();
      if (!context.mounted) return;
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BillReviewScreen(scanId: scan.id)));
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final draft = ref.watch(receivingDraftProvider);
    final packs = draft.lines.fold<int>(0, (sum, l) => sum + l.packs);
    if (draft.lines.isEmpty) {
      return Text(
        'Scan packs from a delivery — they build into one bill to receive.',
        style: text.bodySmall?.copyWith(color: AppColors.muted),
      );
    }
    return Row(children: [
      Expanded(
        child: Text(
          '${draft.lines.length} medicine${draft.lines.length == 1 ? '' : 's'} · $packs pack${packs == 1 ? '' : 's'} scanned',
          style: text.bodyMedium,
        ),
      ),
      const SizedBox(width: Space.s),
      FilledButton.tonal(onPressed: () => _review(context, ref), child: const Text('Review & receive')),
    ]);
  }
}

/// Photographs a pack, identifies it and adds one pack to the bill.
Future<void> readPackIntoBill(BuildContext context, WidgetRef ref) async {
  final index = ref.read(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
  final scan = await scanPackPhoto(context, medicines: index.values.map((s) => s.medicine).toList());
  if (scan == null || !context.mounted) return;
  final info = scan.info;
  if (info.hasExpiry && Batch.endOfMonth(info.expiryYear!, info.expiryMonth!).isBefore(DateTime.now())) {
    showMessage(context, 'That pack is expired — not added.', error: true);
    return;
  }
  final stock = index[scan.medicine.id];
  if (stock == null) return;
  final feedback = addScannedToBill(ref, stock, batchNumber: info.batchNumber);
  if (info.mrpPaise != null && feedback.ok) {
    final billed = batchesFor(stock, info.batchNumber).firstOrNull;
    if (billed != null && billed.mrpPaise != info.mrpPaise) {
      showMessage(context,
          '${feedback.message}. Note: pack MRP ${formatRupees(info.mrpPaise!)} differs from stock record ${formatRupees(billed.mrpPaise)}.',
          error: true);
      return;
    }
  }
  showMessage(context, feedback.message, error: !feedback.ok);
}
