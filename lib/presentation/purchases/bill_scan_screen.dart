import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../domain/models/batch.dart';
import '../../domain/models/bill_scan.dart';
import '../../domain/models/medicine.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/ocr_text.dart';
import '../../domain/services/stock_receipt.dart';
import '../../domain/services/supplier_bill_parser.dart';
import '../../platform/device_features.dart';
import '../../platform/photo_compress.dart';
import '../../platform/text_reader.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'medicine_picker.dart';

final _billImageProvider = FutureProvider.autoDispose.family<Uint8List?, String>((ref, id) {
  return ref.watch(repositoryProvider)?.billScanImage(id);
});

/// Every medicine a bill line can refer to: the store's own, plus the master
/// catalogue for products the store hasn't stocked yet.
List<Medicine> _knownMedicines(WidgetRef ref) {
  final store = (ref.read(stockIndexProvider).valueOrNull ?? const {}).values.map((s) => s.medicine).toList();
  final ids = {for (final m in store) m.catalogueId ?? m.id, for (final m in store) m.id};
  final catalogue = ref.read(catalogueProvider).search('').map((e) => e.medicine).where((m) => !ids.contains(m.id));
  return [...store, ...catalogue];
}

Medicine? _resolveMedicine(WidgetRef ref, String? id) {
  if (id == null) return null;
  final store = ref.read(stockIndexProvider).valueOrNull?[id]?.medicine;
  return store ?? ref.read(catalogueProvider).byId(id)?.medicine;
}

/// Photograph (phone) or pick (computer) a supplier bill, read it on the
/// device, save the picture with what was read, and open it for review.
/// Returns whether a bill was actually saved (false if the user cancelled).
Future<bool> captureSupplierBill(BuildContext context, WidgetRef ref) async {
  ImageSource? source = ImageSource.gallery;
  if (DeviceFeatures.cameraScanning) {
    source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(PhosphorIconsRegular.camera),
            title: const Text('Take a photo of the bill'),
            subtitle: const Text('Flat, in good light, whole page in view'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(PhosphorIconsRegular.uploadSimple),
            title: const Text('Choose a file'),
            subtitle: const Text('Pick an existing photo or scan from this computer'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
  }
  if (source == null || !context.mounted) return false;
  final file = await ImagePicker().pickImage(source: source, maxWidth: 2400, imageQuality: 95);
  if (file == null || !context.mounted) return false;
  return receiveBillPhoto(context, ref, file);
}

/// Reads [file] as a supplier bill, saves it and opens it for review.
/// Shared by [captureSupplierBill] and Smart Scan — Smart Scan has usually
/// already read the photo once (to decide it's a bill, not a pack), so it
/// passes [page] to avoid reading it twice. Returns whether the bill was saved.
Future<bool> receiveBillPhoto(BuildContext context, WidgetRef ref, XFile file, {OcrPage? page}) async {
  final repo = ref.read(repositoryProvider)!;
  final ownGstin = ref.read(storeProvider).valueOrNull?.gstin ?? '';
  final medicines = _knownMedicines(ref);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: Space.l),
          Expanded(child: Text('Reading the bill…')),
        ]),
      ),
    ),
  );
  BillScan? scan;
  Object? failure;
  try {
    final bytes = await file.readAsBytes();
    final jpeg = await compressPhoto(bytes);
    final ocrPage = page ?? (DeviceFeatures.textReading ? await readTextFromPhoto(file.path) : null);
    final draft = ocrPage == null || ocrPage.isEmpty
        ? const BillDraft()
        : SupplierBillParser.parse(ocrPage, medicines, ownGstin: ownGstin);
    scan = await repo.createBillScan(draft: draft, ocrText: ocrPage?.text ?? '', jpeg: jpeg);
  } catch (e) {
    failure = e;
  }
  if (!context.mounted) return false;
  Navigator.of(context).pop(); // progress
  if (scan == null) {
    showMessage(context, friendlyError(failure ?? 'Could not save the bill.'), error: true);
    return false;
  }
  if (!DeviceFeatures.textReading) {
    showMessage(context, 'Bill photo saved. Text reading runs on the phone app — enter the lines here, '
        'or photograph the bill with the phone and it will appear on every device.');
  }
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BillReviewScreen(scanId: scan!.id)));
  return true;
}

const _imageExtensions = ['.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp'];

/// Lets a supplier bill photo be dropped straight onto the Mac/Windows
/// window, not just picked through a file dialog — wraps [child] so the
/// rest of the screen is unaffected. A phone has no OS drag source to drop
/// from, so this only does anything on desktop.
class SupplierBillDropZone extends ConsumerStatefulWidget {
  const SupplierBillDropZone({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<SupplierBillDropZone> createState() => _SupplierBillDropZoneState();
}

class _SupplierBillDropZoneState extends ConsumerState<SupplierBillDropZone> {
  bool _hovering = false;
  bool _busy = false;

  Future<void> _drop(DropDoneDetails details) async {
    setState(() => _hovering = false);
    if (_busy || details.files.isEmpty) return;
    final file = details.files.first;
    final lower = file.name.toLowerCase();
    if (!_imageExtensions.any(lower.endsWith)) {
      showMessage(context, 'Drop a photo of the bill (JPG, PNG or HEIC) — "${file.name}" isn\'t one.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await receiveBillPhoto(context, ref, file);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (DeviceFeatures.isPhone) return widget.child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _hovering = true),
      onDragExited: (_) => setState(() => _hovering = false),
      onDragDone: _drop,
      child: Stack(children: [
        widget.child,
        if (_hovering)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                color: AppColors.primaryContainer.withValues(alpha: 0.85),
                child: const Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(PhosphorIconsRegular.downloadSimple, size: 40, color: AppColors.primary),
                    SizedBox(height: Space.s),
                    Text('Drop to add as a supplier bill', style: TextStyle(color: AppColors.primary)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Recently photographed bills, newest first.
class BillScanList extends ConsumerWidget {
  const BillScanList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return AsyncBody<List<BillScan>>(
      value: ref.watch(billScansProvider),
      builder: (scans) {
        if (scans.isEmpty) {
          return const EmptyState(
            icon: PhosphorIconsRegular.receipt,
            title: 'No scanned bills yet',
            message: 'Use "Scan supplier bill" — the photo is kept with what was read from it.',
          );
        }
        return ListView.separated(
          itemCount: scans.length,
          separatorBuilder: (_, _) => const Divider(indent: Space.l, endIndent: Space.l),
          itemBuilder: (context, i) {
            final s = scans[i];
            final d = s.draft;
            final (label, fg, bg) = switch (s.status) {
              BillScanStatus.draft => ('To check', AppColors.warning, AppColors.warningContainer),
              BillScanStatus.received => ('Received', AppColors.accent, AppColors.primaryContainer),
              BillScanStatus.discarded => ('Discarded', AppColors.muted, AppColors.infoContainer),
            };
            return ListTile(
              leading: Icon(s.hasImage ? PhosphorIconsRegular.receipt : PhosphorIconsRegular.receipt),
              title: Row(children: [
                Flexible(
                  child: Text(d.supplierName.isEmpty ? 'Supplier not read' : d.supplierName,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: Space.s),
                Pill(label, foreground: fg, background: bg),
              ]),
              subtitle: Text(
                '${d.invoiceNumber.isEmpty ? 'Bill no. —' : 'Bill ${d.invoiceNumber}'} · '
                '${d.lines.length} line${d.lines.length == 1 ? '' : 's'} · '
                '${DateFormat('d MMM, hh:mm a').format(s.createdAt)} · ${s.createdByName}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: d.billTotalPaise == null ? null : Text(formatRupees(d.billTotalPaise!), style: text.titleSmall),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BillReviewScreen(scanId: s.id))),
            );
          },
        );
      },
    );
  }
}

/// Check and correct what was read from a bill, then receive it as stock.
class BillReviewScreen extends ConsumerStatefulWidget {
  const BillReviewScreen({super.key, required this.scanId});
  final String scanId;

  @override
  ConsumerState<BillReviewScreen> createState() => _BillReviewScreenState();
}

class _BillReviewScreenState extends ConsumerState<BillReviewScreen> {
  BillDraft? _draft; // local edits; null until the scan has loaded
  bool _dirty = false;
  bool _busy = false;
  final _lineErrors = <int, String>{};

  void _change(BillDraft draft) => setState(() {
        _draft = draft;
        _dirty = true;
      });

  Future<void> _save({bool quiet = false}) async {
    final draft = _draft;
    if (draft == null) return;
    try {
      await ref.read(repositoryProvider)!.updateBillScanDraft(widget.scanId, draft);
      if (!mounted) return;
      setState(() => _dirty = false);
      if (!quiet) showMessage(context, 'Saved.');
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  StockReceipt? _receiptFor(BillDraftLine line, BillDraft draft, List<String> problems) {
    final medicine = _resolveMedicine(ref, line.medicineId);
    if (medicine == null) problems.add('Choose the medicine.');
    if (line.expiryMonth == null || line.expiryYear == null) problems.add('Enter the expiry.');
    if (medicine == null || line.expiryMonth == null || line.expiryYear == null) return null;
    final receipt = StockReceipt(
      medicine: medicine,
      batchNumber: line.batchNumber,
      expiryMonth: line.expiryMonth!,
      expiryYear: line.expiryYear!,
      packs: line.packs,
      freePacks: line.freePacks,
      purchasePricePaise: line.ratePaise,
      mrpPaise: line.mrpPaise,
      supplierName: draft.supplierName,
      supplierInvoiceNumber: draft.invoiceNumber,
      billScanId: widget.scanId,
    );
    final batch = ref.read(batchesProvider).valueOrNull?.where((b) => b.id == receipt.batchId).firstOrNull;
    problems.addAll(receipt.validate(now: DateTime.now(), existing: batch));
    return problems.isEmpty ? receipt : null;
  }

  Future<void> _receive() async {
    var draft = _draft!;
    final todo = [
      for (var i = 0; i < draft.lines.length; i++)
        if (draft.lines[i].include && !draft.lines[i].received) i,
    ];
    if (todo.isEmpty) {
      showMessage(context, 'No lines selected to receive.', error: true);
      return;
    }
    _lineErrors.clear();
    final receipts = <int, StockReceipt>{};
    for (final i in todo) {
      final problems = <String>[];
      final r = _receiptFor(draft.lines[i], draft, problems);
      if (r == null) {
        _lineErrors[i] = problems.join(' ');
      } else {
        receipts[i] = r;
      }
    }
    if (_lineErrors.isNotEmpty) {
      setState(() {});
      showMessage(context, 'Fix the ${_lineErrors.length} highlighted line${_lineErrors.length == 1 ? '' : 's'} first.',
          error: true);
      return;
    }

    // Same supplier + bill number already received from a different scan —
    // most likely this bill was already entered once; let the pharmacist
    // decide rather than silently double-counting the stock.
    final invoice = draft.invoiceNumber.trim();
    final supplier = draft.supplierName.trim();
    if (invoice.isNotEmpty && supplier.isNotEmpty) {
      final duplicate = (ref.read(purchasesProvider).valueOrNull ?? const [])
          .where((p) =>
              p.billScanId != widget.scanId &&
              p.supplierInvoiceNumber.trim().toLowerCase() == invoice.toLowerCase() &&
              p.supplierName.trim().toLowerCase() == supplier.toLowerCase())
          .firstOrNull;
      if (duplicate != null) {
        final proceed = await confirmDialog(
          context,
          title: 'Already received?',
          message: 'Bill $invoice from $supplier was already received on '
              '${DateFormat('d MMM yyyy').format(duplicate.createdAt)}. Receiving this one too will add the '
              'stock again — only continue if this is really a different bill.',
          confirmLabel: 'Receive anyway',
          danger: true,
        );
        if (!proceed || !mounted) return;
      }
    }

    final ok = await confirmDialog(
      context,
      title: 'Receive ${receipts.length} line${receipts.length == 1 ? '' : 's'}?',
      message: 'Stock is added for each line and recorded against bill '
          '${draft.invoiceNumber.isEmpty ? '(no number)' : draft.invoiceNumber} from '
          '${draft.supplierName.isEmpty ? 'this supplier' : draft.supplierName}.',
      confirmLabel: 'Receive',
    );
    if (!ok || !mounted) return;

    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider)!;
    var done = 0;
    for (final entry in receipts.entries) {
      try {
        await repo.receiveStock(entry.value);
        final lines = [...draft.lines];
        lines[entry.key] = lines[entry.key].copyWith(received: true);
        draft = draft.copyWith(lines: lines);
        done++;
      } catch (e) {
        _lineErrors[entry.key] = friendlyError(e);
      }
    }
    // Record progress even if some lines failed, so nothing is received twice.
    try {
      await repo.updateBillScanDraft(widget.scanId, draft);
      final remaining = draft.lines.where((l) => l.include && !l.received).length;
      final receivedTotal = draft.lines.where((l) => l.received).length;
      if (remaining == 0) {
        await repo.setBillScanStatus(widget.scanId, BillScanStatus.received, receivedLines: receivedTotal);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _draft = draft;
      _dirty = false;
    });
    showMessage(
      context,
      _lineErrors.isEmpty ? 'Received $done line${done == 1 ? '' : 's'} into stock.' : 'Received $done; ${_lineErrors.length} need attention.',
      error: _lineErrors.isNotEmpty,
    );
  }

  Future<void> _discard() async {
    final ok = await confirmDialog(context,
        title: 'Discard this bill scan?',
        message: 'Nothing is added to stock. The photo stays on record marked "discarded".',
        confirmLabel: 'Discard',
        danger: true);
    if (!ok || !mounted) return;
    try {
      await ref.read(repositoryProvider)!.setBillScanStatus(widget.scanId, BillScanStatus.discarded);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    }
  }

  Future<void> _editHeader() async {
    final result = await showDialog<BillDraft>(context: context, builder: (_) => _HeaderDialog(draft: _draft!));
    if (result != null) _change(result);
  }

  Future<void> _editLine(int index) async {
    final draft = _draft!;
    final isNew = index >= draft.lines.length;
    final line = isNew ? const BillDraftLine(rawText: '(added by hand)') : draft.lines[index];
    final result = await showDialog<BillDraftLine>(
      context: context,
      builder: (_) => _LineDialog(line: line, medicine: _resolveMedicine(ref, line.medicineId)),
    );
    if (result == null) return;
    final lines = [...draft.lines];
    if (isNew) {
      lines.add(result);
    } else {
      lines[index] = result;
    }
    _lineErrors.remove(index);
    _change(draft.copyWith(lines: lines));
  }

  @override
  Widget build(BuildContext context) {
    final scans = ref.watch(billScansProvider);
    final scan = scans.valueOrNull?.where((s) => s.id == widget.scanId).firstOrNull;
    if (scan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Supplier bill')),
        body: scans.hasError ? ErrorPanel(message: friendlyError(scans.error!)) : const Center(child: CircularProgressIndicator()),
      );
    }
    _draft ??= scan.draft;
    final draft = _draft!;
    final user = ref.watch(currentUserProvider);
    final manager = user?.role.canManageStock ?? false;
    final editable = scan.status == BillScanStatus.draft && (manager || scan.createdBy == user?.uid);
    final text = Theme.of(context).textTheme;
    final image = scan.hasImage ? ref.watch(_billImageProvider(scan.id)) : null;

    Widget photo({required bool large}) {
      if (!scan.hasImage) {
        return const Card(child: Padding(padding: EdgeInsets.all(Space.l), child: Text('No photo kept for this bill.')));
      }
      return image!.when(
        loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
        error: (e, _) => Text(friendlyError(e)),
        data: (bytes) => bytes == null
            ? const Text('Photo not found.')
            : GestureDetector(
                onTap: () => _showPhoto(context, bytes),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: large
                      ? InteractiveViewer(maxScale: 5, child: Image.memory(bytes, fit: BoxFit.contain))
                      : Image.memory(bytes, height: 180, width: double.infinity, fit: BoxFit.cover),
                ),
              ),
      );
    }

    final header = Card(
      child: ListTile(
        onTap: editable ? _editHeader : null,
        title: Text(draft.supplierName.isEmpty ? 'Supplier not read — tap to enter' : draft.supplierName,
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            'Bill ${draft.invoiceNumber.isEmpty ? '—' : draft.invoiceNumber}'
                '${draft.invoiceDate == null ? '' : ' · ${DateFormat('d MMM yyyy').format(draft.invoiceDate!)}'}',
            if (draft.supplierGstin.isNotEmpty) 'GSTIN ${draft.supplierGstin}',
            if (draft.supplierDrugLicence.isNotEmpty) 'DL ${draft.supplierDrugLicence}',
          ].join('\n'),
        ),
        isThreeLine: draft.supplierGstin.isNotEmpty || draft.supplierDrugLicence.isNotEmpty,
        trailing: editable ? const Icon(PhosphorIconsRegular.pencilSimple) : null,
      ),
    );

    final lines = <Widget>[
      for (var i = 0; i < draft.lines.length; i++)
        _LineCard(
          line: draft.lines[i],
          medicine: _resolveMedicine(ref, draft.lines[i].medicineId),
          error: _lineErrors[i],
          editable: editable && !draft.lines[i].received,
          onTap: () => _editLine(i),
          onInclude: (v) {
            final list = [...draft.lines];
            list[i] = list[i].copyWith(include: v);
            _change(draft.copyWith(lines: list));
          },
        ),
    ];

    final totals = Text(
      'Lines at purchase rate ${formatRupees(draft.linesTotalPaise)}'
      '${draft.billTotalPaise == null ? '' : ' · bill total ${formatRupees(draft.billTotalPaise!)} (incl. GST)'}',
      style: text.bodySmall?.copyWith(color: AppColors.muted),
    );

    final details = ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        if (!context.isWide) ...[photo(large: false), const SizedBox(height: Space.m)],
        header,
        const SizedBox(height: Space.l),
        Row(children: [
          Expanded(child: Text('Items (${draft.lines.length})', style: text.titleMedium)),
          if (editable)
            TextButton.icon(onPressed: () => _editLine(draft.lines.length), icon: const Icon(PhosphorIconsRegular.plus), label: const Text('Add line')),
        ]),
        if (draft.lines.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(Space.l),
              child: Text('No item lines were read. Add them with "Add line", or retake the photo flat and in good light.'),
            ),
          ),
        for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: Space.s), child: l),
        const SizedBox(height: Space.s),
        totals,
        if (scan.ocrText.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('All text read from the bill', style: text.bodySmall),
            children: [SelectableText(scan.ocrText, style: text.bodySmall)],
          ),
        const SizedBox(height: 80),
      ],
    );

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDialog(context,
            title: 'Leave without saving?', message: 'Your corrections to this bill will be lost.', confirmLabel: 'Leave');
        if (leave && context.mounted) {
          setState(() => _dirty = false);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(scan.status == BillScanStatus.draft ? 'Check supplier bill' : 'Supplier bill'),
          actions: [
            if (editable)
              IconButton(tooltip: 'Discard', icon: const Icon(PhosphorIconsRegular.trash), onPressed: _busy ? null : _discard),
            if (editable && _dirty) TextButton(onPressed: _busy ? null : () => _save(), child: const Text('Save')),
          ],
        ),
        body: SafeArea(
          child: context.isWide
              ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: Padding(padding: const EdgeInsets.all(Space.l), child: photo(large: true))),
                  const VerticalDivider(width: 1),
                  SizedBox(width: 520, child: details),
                ])
              : details,
        ),
        bottomNavigationBar: scan.status == BillScanStatus.draft
            ? SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
                  child: manager
                      ? FilledButton.icon(
                          onPressed: _busy ? null : _receive,
                          icon: _busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(PhosphorIconsRegular.archive),
                          label: Text('Receive ${draft.lines.where((l) => l.include && !l.received).length} lines into stock'),
                        )
                      : FilledButton(
                          onPressed: _busy || !_dirty ? null : () => _save(),
                          child: const Text('Save for the pharmacist to receive'),
                        ),
                ),
              )
            : null,
      ),
    );
  }

  void _showPhoto(BuildContext context, Uint8List bytes) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: InteractiveViewer(maxScale: 6, child: Center(child: Image.memory(bytes))),
      ),
    ));
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.line,
    required this.medicine,
    required this.error,
    required this.editable,
    required this.onTap,
    required this.onInclude,
  });
  final BillDraftLine line;
  final Medicine? medicine;
  final String? error;
  final bool editable;
  final VoidCallback onTap;
  final ValueChanged<bool> onInclude;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final missing = <String>[
      if (medicine == null) 'medicine',
      if (line.batchNumber.isEmpty) 'batch',
      if (line.expiryMonth == null) 'expiry',
      if (line.packs <= 0) 'qty',
      if (line.ratePaise <= 0) 'rate',
      if (line.mrpPaise <= 0) 'MRP',
    ];
    final expiry = line.expiryMonth == null ? '—' : '${line.expiryMonth.toString().padLeft(2, '0')}/${line.expiryYear}';
    return Card(
      shape: error == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.danger, width: 1.5)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: editable ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.s, Space.s, Space.m, Space.s),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (line.received)
              const Padding(padding: EdgeInsets.all(Space.m), child: Icon(PhosphorIconsRegular.checkCircle, color: AppColors.accent))
            else
              Checkbox(value: line.include, onChanged: editable ? (v) => onInclude(v ?? false) : null),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(medicine?.name ?? (line.medicineName.isEmpty ? 'Unknown item' : '${line.medicineName} (not matched)'),
                    style: text.titleSmall?.copyWith(color: medicine == null ? AppColors.warning : null),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  'Batch ${line.batchNumber.isEmpty ? '—' : line.batchNumber} · Exp $expiry · '
                  'Qty ${line.packs}${line.freePacks > 0 ? '+${line.freePacks} free' : ''}',
                  style: text.bodySmall,
                ),
                Text(
                  'Rate ${line.ratePaise > 0 ? formatRupees(line.ratePaise) : '—'} · MRP ${line.mrpPaise > 0 ? formatRupees(line.mrpPaise) : '—'}',
                  style: text.bodySmall,
                ),
                if (line.received)
                  Text('Received into stock', style: text.bodySmall?.copyWith(color: AppColors.accent))
                else if (missing.isNotEmpty)
                  Text('Check: ${missing.join(', ')}', style: text.bodySmall?.copyWith(color: AppColors.warning)),
                if (error != null) Text(error!, style: text.bodySmall?.copyWith(color: AppColors.danger)),
                Text(line.rawText, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(color: AppColors.muted)),
              ]),
            ),
            if (editable) const Padding(padding: EdgeInsets.only(top: Space.m), child: Icon(PhosphorIconsRegular.pencilSimple, size: 18)),
          ]),
        ),
      ),
    );
  }
}

class _HeaderDialog extends StatefulWidget {
  const _HeaderDialog({required this.draft});
  final BillDraft draft;

  @override
  State<_HeaderDialog> createState() => _HeaderDialogState();
}

class _HeaderDialogState extends State<_HeaderDialog> {
  late final _supplier = TextEditingController(text: widget.draft.supplierName);
  late final _gstin = TextEditingController(text: widget.draft.supplierGstin);
  late final _dl = TextEditingController(text: widget.draft.supplierDrugLicence);
  late final _number = TextEditingController(text: widget.draft.invoiceNumber);
  late DateTime? _date = widget.draft.invoiceDate;

  @override
  void dispose() {
    for (final c in [_supplier, _gstin, _dl, _number]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.m);
    return AlertDialog(
      title: const Text('Supplier details'),
      content: DialogBody(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _supplier, decoration: const InputDecoration(labelText: 'Supplier / distributor'),
              textCapitalization: TextCapitalization.words),
          gap,
          TextField(controller: _number, decoration: const InputDecoration(labelText: 'Bill number')),
          gap,
          OutlinedButton.icon(
            icon: const Icon(PhosphorIconsRegular.calendar, size: 18),
            label: Text(_date == null ? 'Bill date' : DateFormat('d MMM yyyy').format(_date!)),
            onPressed: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _date != null && !_date!.isAfter(now) ? _date! : now,
                firstDate: DateTime(now.year - 2),
                lastDate: now,
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          gap,
          TextField(
            controller: _gstin,
            decoration: const InputDecoration(labelText: 'Supplier GSTIN'),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [LengthLimitingTextInputFormatter(15)],
          ),
          gap,
          TextField(controller: _dl, decoration: const InputDecoration(labelText: 'Supplier drug licence')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            BillDraft(
              supplierName: _supplier.text.trim(),
              supplierGstin: _gstin.text.trim().toUpperCase(),
              supplierDrugLicence: _dl.text.trim(),
              invoiceNumber: _number.text.trim(),
              invoiceDate: _date,
              billTotalPaise: widget.draft.billTotalPaise,
              lines: widget.draft.lines,
            ),
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _LineDialog extends StatefulWidget {
  const _LineDialog({required this.line, required this.medicine});
  final BillDraftLine line;
  final Medicine? medicine;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  final _formKey = GlobalKey<FormState>();
  late Medicine? _medicine = widget.medicine;
  late final _batch = TextEditingController(text: widget.line.batchNumber);
  late final _expiry = TextEditingController(
      text: widget.line.expiryMonth == null
          ? ''
          : '${widget.line.expiryMonth.toString().padLeft(2, '0')}/${widget.line.expiryYear! % 100}');
  late final _packs = TextEditingController(text: widget.line.packs > 0 ? '${widget.line.packs}' : '');
  late final _free = TextEditingController(text: '${widget.line.freePacks}');
  late final _rate = TextEditingController(
      text: widget.line.ratePaise > 0 ? formatRupees(widget.line.ratePaise, symbol: false).replaceAll(',', '') : '');
  late final _mrp = TextEditingController(
      text: widget.line.mrpPaise > 0 ? formatRupees(widget.line.mrpPaise, symbol: false).replaceAll(',', '') : '');

  @override
  void dispose() {
    for (final c in [_batch, _expiry, _packs, _free, _rate, _mrp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseMedicine() async {
    final picked = await pickMedicine(context, initialQuery: _medicine == null ? widget.line.medicineName : '');
    if (picked == null) return;
    setState(() {
      _medicine = picked.medicine;
      if (_mrp.text.isEmpty && picked.referenceMrpPaise > 0) {
        _mrp.text = formatRupees(picked.referenceMrpPaise, symbol: false).replaceAll(',', '');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.m);
    Widget pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: a),
          const SizedBox(width: Space.m),
          Expanded(child: b),
        ]);
    final perPack = _medicine?.unitsPerPack ?? 1;
    return AlertDialog(
      title: const Text('Bill line'),
      content: DialogBody(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.line.rawText, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted)),
            gap,
            Card(
              child: ListTile(
                onTap: _chooseMedicine,
                leading: const Icon(PhosphorIconsRegular.pill),
                title: Text(_medicine?.name ?? 'Choose medicine', overflow: TextOverflow.ellipsis),
                subtitle: _medicine == null ? null : Text('${_medicine!.packSizeLabel} · GST ${_medicine!.gstRate.toStringAsFixed(0)}%'),
                trailing: const Icon(PhosphorIconsRegular.caretRight),
              ),
            ),
            gap,
            pair(
              TextFormField(
                controller: _batch,
                decoration: const InputDecoration(labelText: 'Batch'),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
              ),
              TextFormField(
                controller: _expiry,
                decoration: const InputDecoration(labelText: 'Expiry', hintText: 'MM/YY'),
                keyboardType: TextInputType.datetime,
                validator: (v) => parseMonthYear(v ?? '') == null ? 'MM/YY' : null,
              ),
            ),
            gap,
            pair(
              TextFormField(
                controller: _packs,
                decoration: InputDecoration(labelText: perPack > 1 ? 'Packs (×$perPack)' : 'Quantity'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
                validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'At least 1' : null,
              ),
              TextFormField(
                controller: _free,
                decoration: const InputDecoration(labelText: 'Free'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              ),
            ),
            gap,
            pair(
              TextFormField(
                controller: _rate,
                decoration: const InputDecoration(labelText: 'Rate ₹/pack', helperText: 'Incl. GST'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => (parseRupeesToPaise(v ?? '') ?? 0) <= 0 ? 'Enter rate' : null,
              ),
              TextFormField(
                controller: _mrp,
                decoration: const InputDecoration(labelText: 'MRP ₹/pack'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  final mrp = parseRupeesToPaise(v ?? '') ?? 0;
                  if (mrp <= 0) return 'Enter MRP';
                  if ((parseRupeesToPaise(_rate.text) ?? 0) > mrp) return 'Below rate';
                  return null;
                },
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (_medicine == null) {
              showMessage(context, 'Choose the medicine.', error: true);
              return;
            }
            if (!_formKey.currentState!.validate()) return;
            final expiry = parseMonthYear(_expiry.text)!;
            Navigator.pop(
              context,
              widget.line.copyWith(
                medicineId: _medicine!.id,
                medicineName: _medicine!.name,
                batchNumber: Batch.normaliseBatchNumber(_batch.text),
                expiryMonth: expiry.month,
                expiryYear: expiry.year,
                packs: int.parse(_packs.text),
                freePacks: int.tryParse(_free.text) ?? 0,
                ratePaise: parseRupeesToPaise(_rate.text),
                mrpPaise: parseRupeesToPaise(_mrp.text),
                include: true,
              ),
            );
          },
          child: const Text('Done'),
        ),
      ],
    );
  }
}
