import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/pharmacy_repository.dart';
import '../../domain/models/customer_credit.dart';
import '../../domain/models/sale_invoice.dart';
import '../../domain/models/scan_link.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/gs1_parser.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/schedule_h1_compliance.dart';
import '../../domain/services/stock_summary.dart';
import '../../platform/device_features.dart';
import '../../state/providers.dart';
import '../customers/customer_dialogs.dart';
import '../scan/barcode_scanner_screen.dart';
import '../scan/scan_billing.dart';
import '../scan/scan_flows.dart';
import '../sales/invoice_view.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'prescription_dialog.dart';
import 'quantity_dialog.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _checkingOut = false;

  // Phone → this counter link.
  ScanStation? _station;
  PharmacyRepository? _stationRepo;
  StreamSubscription<List<ScanEvent>>? _scanSub;
  Timer? _heartbeat;
  final _handledScans = <String>{};
  final _appliedByEvent = <String, ({String batchId, int units})>{};
  final _incoming = <_IncomingScan>[];
  final _incomingTimers = <String, Timer>{};

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _stopStation(notify: false);
    for (final t in _incomingTimers.values) {
      t.cancel();
    }
    super.dispose();
  }

  // ------------------------------------------------------------- scanning

  ScanFeedback _addScanned(StockSummary stock, {String? batchNumber}) =>
      addScannedToBill(ref, stock, batchNumber: batchNumber);

  Future<ScanFeedback> _handleCode(String raw, {bool toCounter = true}) =>
      handleScannedCode(context, ref, raw, toCounter: toCounter);

  Future<void> _openSmartScan() => openSmartScanner(context, ref);

  /// Every way to scan from this device in one place (F3).
  Future<void> _openScanHub() => showDialog<void>(
        context: context,
        builder: (_) => _ScanHub(
          onCode: (raw) => _handleCode(raw, toCounter: false),
          onSmartScan: DeviceFeatures.cameraScanning ? _openSmartScan : null,
          stationName: () => _station?.name,
          onToggleStation: DeviceFeatures.isPhone ? null : _toggleStation,
        ),
      );

  // ------------------------------------------------- this device as a counter

  Future<void> _toggleStation() async {
    if (_station != null) {
      _stopStation();
      return;
    }
    final repo = ref.read(repositoryProvider)!;
    final name = await _askCounterName();
    if (name == null || !mounted) return;
    final station = ScanStation(
      id: repo.newId(),
      storeId: repo.storeId,
      name: name,
      active: true,
      uid: repo.actor.uid,
      updatedAt: DateTime.now(),
    );
    try {
      await repo.saveStation(station);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    setState(() => _station = station);
    _stationRepo = repo;
    _scanSub = repo.watchScansFor(station.id).listen(_onRemoteScans);
    // Keep the counter listed on phones while it stays open.
    _heartbeat = Timer.periodic(const Duration(hours: 1), (_) {
      final s = _station;
      if (s != null) {
        unawaited(repo.saveStation(ScanStation(
            id: s.id, storeId: s.storeId, name: s.name, active: true, uid: s.uid, updatedAt: DateTime.now())));
      }
    });
    showMessage(context, 'Phones can now send scans to "$name". On the phone: Billing → scan → choose $name.');
  }

  void _stopStation({bool notify = true}) {
    final station = _station;
    unawaited(_scanSub?.cancel());
    _heartbeat?.cancel();
    _scanSub = null;
    _heartbeat = null;
    if (station == null) return;
    _station = null;
    // Read from the field saved when the station started, not from `ref` —
    // this runs from dispose() too, where the widget's ref is already gone.
    final repo = _stationRepo;
    _stationRepo = null;
    if (repo != null) {
      unawaited(repo
          .saveStation(ScanStation(
              id: station.id,
              storeId: station.storeId,
              name: station.name,
              active: false,
              uid: station.uid,
              updatedAt: DateTime.now()))
          .catchError((_) {}));
    }
    if (notify && mounted) setState(() {});
  }

  Future<String?> _askCounterName() => showDialog<String>(context: context, builder: (_) => const _CounterNameDialog());

  /// Firestore pushes a new scan event the instant the phone sends one —
  /// this fires within a moment of that, for every scan, every time. Each
  /// one gets its own animated card (several in a row stack, not drop).
  void _onRemoteScans(List<ScanEvent> events) {
    if (!mounted) return;
    final now = DateTime.now();

    // A scan we already applied was undone on the sender within its
    // 3-second window — reverse exactly what it added, even if that
    // happens after it was already on the bill.
    for (final e in events) {
      final applied = e.cancelled ? _appliedByEvent.remove(e.id) : null;
      if (applied == null) continue;
      ref.read(cartProvider.notifier).removeUnits(applied.batchId, applied.units);
      unawaited(HapticFeedback.lightImpact());
      _showIncoming('${e.id}-undo', '${e.createdByName} (${e.deviceLabel})', 'Undone', true);
    }

    final pending = events
        .where((e) => e.status == ScanEventStatus.pending && !_handledScans.contains(e.id) && now.difference(e.scannedAt).inMinutes.abs() < 10)
        .toList()
      ..sort((a, b) => a.scannedAt.compareTo(b.scannedAt));
    final repo = ref.read(repositoryProvider);
    for (final e in pending) {
      _handledScans.add(e.id);
      final index = ref.read(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
      final stock = (e.medicineId == null ? null : index[e.medicineId]) ?? resolveBarcode(e.rawBarcode, index).stock;
      final feedback = stock == null
          ? ScanFeedback('Unknown barcode ${e.rawBarcode}', ok: false)
          : _addScanned(stock, batchNumber: e.batchNumber);
      if (feedback.ok && feedback.appliedBatchId != null && feedback.appliedUnits != null) {
        _appliedByEvent[e.id] = (batchId: feedback.appliedBatchId!, units: feedback.appliedUnits!);
      }
      if (repo != null) unawaited(repo.markScanDone(e.id).catchError((_) {}));
      unawaited(feedback.ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact());
      _showIncoming(e.id, '${e.createdByName} (${e.deviceLabel})', feedback.message, feedback.ok);
    }
  }

  void _showIncoming(String id, String from, String message, bool ok) {
    final toast = _IncomingScan(id: id, from: from, message: message, ok: ok);
    setState(() => _incoming.insert(0, toast));
    _incomingTimers[id] = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _incoming.removeWhere((t) => t.id == id));
      _incomingTimers.remove(id);
    });
  }

  String get _query => _search.text.trim();

  List<StockSummary> _results(Map<String, StockSummary> index) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];
    final matches = index.values.where((s) {
      final m = s.medicine;
      return m.name.toLowerCase().contains(q) ||
          m.genericName.toLowerCase().contains(q) ||
          m.manufacturer.toLowerCase().contains(q) ||
          (m.barcode != null && m.barcode == _query);
    }).toList()
      ..sort((a, b) {
        if (a.isOutOfStock != b.isOutOfStock) return a.isOutOfStock ? 1 : -1;
        final aStarts = a.medicine.name.toLowerCase().startsWith(q);
        final bStarts = b.medicine.name.toLowerCase().startsWith(q);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
        return a.medicine.name.toLowerCase().compareTo(b.medicine.name.toLowerCase());
      });
    return matches.take(40).toList();
  }

  /// Enter in the search box: a scanned barcode (EAN or GS1 DataMatrix) adds
  /// its medicine directly; otherwise the top match is picked.
  Future<void> _onSearchSubmitted(Map<String, StockSummary> index) async {
    if (_query.isEmpty) return;
    // USB/Bluetooth scanners type the code and press Enter: add one pack.
    if (Gs1Parser.parse(_query).gtin != null) {
      // A counter's own scanner always bills here.
      final feedback = await _handleCode(_query, toCounter: false);
      if (!mounted) return;
      _search.clear();
      setState(() {});
      showMessage(context, feedback.message, error: !feedback.ok);
      if (feedback.onAction != null && !feedback.ok) feedback.onAction!();
      _searchFocus.requestFocus();
      return;
    }
    final results = _results(index);
    if (results.isNotEmpty) {
      _pick(results.first);
    } else {
      showMessage(context, 'No medicine matches "$_query".');
    }
  }

  Future<void> _pick(StockSummary stock) async {
    if (!stock.medicine.scheduleType.isSellable) {
      showMessage(context, '${stock.medicine.name} is unclassified. A pharmacist must set its schedule in Stock first.',
          error: true);
      return;
    }
    final cart = ref.read(cartProvider);
    final inBill = stock.sellableBatches.fold<int>(0, (sum, b) => sum + (cart.unitsByBatch[b.id] ?? 0));
    if (stock.sellableUnits - inBill <= 0) {
      showMessage(context, stock.isOutOfStock ? '${stock.medicine.name} is out of stock.' : 'All available stock is already on this bill.',
          error: true);
      return;
    }
    final units = await showQuantityDialog(context, stock: stock, alreadyInBill: inBill);
    if (units == null || !mounted) return;
    try {
      ref.read(cartProvider.notifier).addMedicine(stock.medicine, stock.batches, units);
      _search.clear();
      setState(() {});
      _searchFocus.requestFocus();
    } catch (e) {
      showMessage(context, friendlyError(e), error: true);
    }
  }

  /// [sheetContext] is the phone checkout sheet, closed once the sale is saved.
  Future<void> _checkout({BuildContext? sheetContext}) async {
    if (_checkingOut) return;
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      showMessage(context, 'Add a medicine to the bill first.');
      return;
    }
    if (ScheduleCompliance.hasUnclassified(cart.schedules)) {
      showMessage(context, 'This bill has an unclassified medicine. Set its schedule in Stock before selling.',
          error: true);
      return;
    }
    PrescriptionRecord? prescription;
    if (ScheduleCompliance.requiresPrescriptionRecord(cart.schedules)) {
      prescription = await showPrescriptionDialog(
        context,
        patientName: cart.customerName,
        patientPhone: cart.customerPhone,
      );
      if (prescription == null || !mounted) return;
    }

    setState(() => _checkingOut = true);
    try {
      final sale = await ref.read(repositoryProvider)!.checkout(cart.toRequest(prescription: prescription));
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      if (sheetContext != null && sheetContext.mounted) Navigator.of(sheetContext).pop();
      await showInvoice(context, sale, justCompleted: true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockIndexProvider);
    final wide = context.isWide;

    final body = AsyncBody<Map<String, StockSummary>>(
      value: stockAsync,
      builder: (index) {
        final searchField = _SearchField(
          controller: _search,
          focusNode: _searchFocus,
          onChanged: (_) => setState(() {}),
          onSubmitted: () => _onSearchSubmitted(index),
        );
        final results = _results(index);
        final main = _query.isEmpty
            ? _CartList(index: index)
            : _SearchResults(results: results, onPick: _pick, query: _query);

        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s), child: searchField),
                Expanded(child: main),
              ]),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 360,
              child: _CheckoutPanel(onCheckout: _checkout, busy: _checkingOut),
            ),
          ]);
        }
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s), child: searchField),
          Expanded(child: main),
          _PhoneCheckoutBar(onOpen: () => _openCheckoutSheet(), busy: _checkingOut),
        ]);
      },
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f3): _openScanHub,
        const SingleActivator(LogicalKeyboardKey.f9): _checkout,
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(_search.clear),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Billing'),
            bottom: _station == null
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(32),
                    child: Container(
                      height: 32,
                      color: AppColors.primaryContainer,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: Space.l),
                      child: Text('Receiving phone scans as "${_station!.name}"',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
            actions: [
              if (DeviceFeatures.isPhone)
                IconButton(tooltip: 'Smart Scan', icon: const Icon(PhosphorIconsRegular.scanSmiley), onPressed: _openSmartScan)
              else
                wide
                    ? Padding(
                        padding: const EdgeInsets.only(right: Space.s),
                        child: FilledButton.tonalIcon(
                          onPressed: _openScanHub,
                          icon: const Icon(PhosphorIconsRegular.scanSmiley),
                          label: const Text('Scan (F3)'),
                        ),
                      )
                    : IconButton(tooltip: 'Scan (F3)', icon: const Icon(PhosphorIconsRegular.scanSmiley), onPressed: _openScanHub),
              if (!ref.watch(cartProvider.select((c) => c.isEmpty)))
                TextButton.icon(
                  onPressed: () async {
                    if (await confirmDialog(context, title: 'Clear this bill?', message: 'All lines will be removed.', confirmLabel: 'Clear')) {
                      ref.read(cartProvider.notifier).clear();
                    }
                  },
                  icon: const Icon(PhosphorIconsRegular.trashSimple),
                  label: const Text('Clear'),
                ),
              if (wide)
                const Padding(
                  padding: EdgeInsets.only(right: Space.l),
                  child: Center(child: Text('F2 search · F9 complete', style: TextStyle(color: AppColors.muted))),
                ),
            ],
          ),
          body: Stack(children: [
            body,
            if (_incoming.isNotEmpty)
              Positioned(
                top: Space.m,
                right: Space.m,
                left: wide ? null : Space.m,
                child: IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [for (final t in _incoming) _IncomingScanCard(key: ValueKey(t.id), scan: t)],
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  void _openCheckoutSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _CheckoutPanel(onCheckout: () => _checkout(sheetContext: context), busy: _checkingOut),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode, required this.onChanged, required this.onSubmitted});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: context.isWide,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search medicine, generic or scan barcode',
        prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(PhosphorIconsRegular.x),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results, required this.onPick, required this.query});
  final List<StockSummary> results;
  final ValueChanged<StockSummary> onPick;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return EmptyState(
        icon: PhosphorIconsRegular.magnifyingGlassMinus,
        title: 'No medicine matches "$query"',
        message: 'Owners and pharmacists can add new medicines from Purchases.',
      );
    }
    final text = Theme.of(context).textTheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: Space.l),
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(indent: Space.l, endIndent: Space.l),
      itemBuilder: (context, i) {
        final s = results[i];
        final next = s.nextBatch;
        return ListTile(
          onTap: () => onPick(s),
          title: Row(children: [
            Flexible(child: Text(s.medicine.name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Space.s),
            ScheduleBadge(s.medicine.scheduleType),
          ]),
          subtitle: Text('${s.medicine.genericName} · ${s.medicine.packSizeLabel}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(next == null ? '—' : formatRupees(next.mrpPaise), style: text.titleSmall),
              Text(
                s.isOutOfStock ? 'Out of stock' : PackUnits.describe(s.sellableUnits, s.medicine.unitsPerPack),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: s.isOutOfStock ? AppColors.danger : AppColors.muted),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _CartList extends ConsumerWidget {
  const _CartList({required this.index});
  final Map<String, StockSummary> index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) {
      return EmptyState(
        icon: PhosphorIconsRegular.basket,
        title: 'New bill',
        message: DeviceFeatures.isPhone
            ? 'Search a medicine above, or tap the scanner icon to scan its barcode.'
            : 'Search a medicine above, or press F3 / "Scan" — USB scanner, camera or phone.',
      );
    }
    final text = Theme.of(context).textTheme;
    final batchById = {for (final s in index.values) for (final b in s.batches) b.id: b};
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.l),
      itemCount: cart.lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.s),
      itemBuilder: (context, i) {
        final line = cart.lines[i];
        final batch = batchById[line.batchId];
        final available = batch?.quantity ?? 0;
        final short = line.quantity > available;
        final step = line.unitsPerPack > 1 ? line.unitsPerPack : 1;
        final stock = index[line.medicineId];
        final card = Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(line.name, style: text.titleSmall, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: Space.s),
                    ScheduleBadge(line.scheduleType),
                  ]),
                  Text(
                    'Batch ${line.batchNumber} · Exp ${DateFormat('MM/yy').format(line.expiryDate)} · '
                    '${formatRupees(line.mrpPaise)}${line.unitsPerPack > 1 ? '/${line.unitsPerPack}' : ''}',
                    style: text.bodySmall?.copyWith(color: AppColors.muted),
                    maxLines: 2,
                  ),
                  if (short)
                    Text(available == 0 ? 'This batch just ran out — remove the line.' : 'Only $available left in this batch.',
                        style: text.bodySmall?.copyWith(color: AppColors.danger)),
                ]),
              ),
              const SizedBox(width: Space.s),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatRupees(line.lineTotalPaise), style: text.titleSmall),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: step > 1 ? 'One pack less' : 'One less',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(PhosphorIconsRegular.minusCircle),
                    onPressed: () => ref.read(cartProvider.notifier).setQuantity(i, line.quantity - step, available: available),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: stock == null
                        ? null
                        : () async {
                            // Editing one line: cap at what this line's batch holds.
                            final units = await showQuantityDialog(context,
                                stock: stock,
                                alreadyInBill: (stock.sellableUnits - available).clamp(0, 1 << 30),
                                initialUnits: line.quantity,
                                batchNumber: line.batchNumber);
                            if (units != null) {
                              final ok = ref.read(cartProvider.notifier).setQuantity(i, units, available: available);
                              if (!ok && context.mounted) {
                                showMessage(context, 'Batch ${line.batchNumber} has only $available.', error: true);
                              }
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
                      child: Text(
                        line.unitsPerPack > 1 ? PackUnits.describe(line.quantity, line.unitsPerPack) : '${line.quantity}',
                        style: text.bodyMedium?.copyWith(decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: step > 1 ? 'One pack more' : 'One more',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(PhosphorIconsRegular.plusCircle),
                    onPressed: () {
                      final ok = ref.read(cartProvider.notifier).setQuantity(i, line.quantity + step, available: available);
                      if (!ok) showMessage(context, 'Batch ${line.batchNumber} has only $available.', error: true);
                    },
                  ),
                  IconButton(
                    tooltip: 'Remove line',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(PhosphorIconsRegular.trash, color: AppColors.danger),
                    onPressed: () => ref.read(cartProvider.notifier).remove(i),
                  ),
                ]),
              ]),
            ]),
          ),
        );
        return _CartRowAnimator(key: ValueKey(line.batchId), quantity: line.quantity, child: card);
      },
    );
  }
}

/// Wraps one bill line so it flies in the first time it appears (new key =
/// a fresh State, so this naturally only fires once) and pulses once
/// whenever its quantity changes after that — the only cue a counter has
/// that a phone's scan just landed, without having to stare at the list.
class _CartRowAnimator extends StatefulWidget {
  const _CartRowAnimator({super.key, required this.quantity, required this.child});
  final int quantity;
  final Widget child;

  @override
  State<_CartRowAnimator> createState() => _CartRowAnimatorState();
}

class _CartRowAnimatorState extends State<_CartRowAnimator> with TickerProviderStateMixin {
  late final _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 280))..forward();
  late final _enterCurve = CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic);
  late final _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final _pulse = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 1),
  ]).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));

  @override
  void didUpdateWidget(_CartRowAnimator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.quantity != oldWidget.quantity) _pulseController.forward(from: 0);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_enterCurve, _pulse]),
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _enterCurve.value,
        child: Transform.translate(
          offset: Offset((1 - _enterCurve.value) * 24, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Color.lerp(Colors.transparent, AppColors.accent.withValues(alpha: 0.18), _pulse.value),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _PhoneCheckoutBar extends ConsumerWidget {
  const _PhoneCheckoutBar({required this.onOpen, required this.busy});
  final VoidCallback onOpen;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final summary = cart.summary;
    final text = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surface,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              CountUpAmount(summary.payablePaise, style: text.titleLarge),
              Text('${cart.lines.length} line${cart.lines.length == 1 ? '' : 's'} · incl. GST ${formatRupees(summary.gstPaise)}',
                  style: text.bodySmall?.copyWith(color: AppColors.muted)),
            ]),
          ),
          FilledButton.icon(
            onPressed: cart.isEmpty || busy ? null : onOpen,
            icon: const Icon(PhosphorIconsRegular.shoppingCartSimple),
            label: const Text('Checkout'),
          ),
        ]),
      ),
    );
  }
}

class _CheckoutPanel extends ConsumerStatefulWidget {
  const _CheckoutPanel({required this.onCheckout, required this.busy});
  final Future<void> Function() onCheckout;
  final bool busy;

  @override
  ConsumerState<_CheckoutPanel> createState() => _CheckoutPanelState();
}

class _CheckoutPanelState extends ConsumerState<_CheckoutPanel> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _localBusy = false;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    _name = TextEditingController(text: cart.customerName);
    _phone = TextEditingController(text: cart.customerPhone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    setState(() => _localBusy = true);
    try {
      await widget.onCheckout();
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final summary = cart.summary;
    final text = Theme.of(context).textTheme;
    String rate(double r) => r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);

    // Keep the fields in step when the cart is cleared or a credit customer chosen.
    if (_name.text != cart.customerName) _name.text = cart.customerName;
    if (_phone.text != cart.customerPhone) _phone.text = cart.customerPhone;
    final udhaarEnabled = ref.watch(storeProvider).valueOrNull?.udhaarEnabled ?? false;
    final credit = udhaarEnabled && cart.paymentMode == PaymentMode.credit;
    final busy = widget.busy || _localBusy;

    return ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        Text('Customer', style: text.titleMedium),
        const SizedBox(height: Space.s),
        if (credit)
          _CreditCustomerPicker(selected: cart.creditCustomer, onChanged: notifier.setCreditCustomer)
        else ...[
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => notifier.setCustomer(name: v),
          ),
          const SizedBox(height: Space.s),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Mobile (for WhatsApp bill)'),
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(15)],
            onChanged: (v) => notifier.setCustomer(phone: v),
          ),
        ],
        const SizedBox(height: Space.l),
        Text('Payment', style: text.titleMedium),
        const SizedBox(height: Space.s),
        Wrap(spacing: Space.s, runSpacing: Space.s, children: [
          for (final mode in PaymentMode.values.where((m) => udhaarEnabled || m != PaymentMode.credit))
            ChoiceChip(
              label: Text(mode == PaymentMode.credit ? 'Udhaar' : mode.label),
              selected: cart.paymentMode == mode,
              onSelected: (_) => notifier.setPaymentMode(mode),
            ),
        ]),
        const Divider(height: Space.xl * 1.5),
        for (final slab in summary.slabs)
          AmountRow('GST ${rate(slab.rate)}% (on ${formatRupees(slab.taxablePaise)})', formatRupees(slab.gstPaise)),
        AmountRow('Taxable value', formatRupees(summary.taxablePaise)),
        AmountRow('Total (MRP)', formatRupees(summary.grossPaise)),
        AmountRow('Round off', formatRupees(summary.roundOffPaise)),
        const Divider(height: Space.l),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text('Payable', style: text.titleMedium)),
            const SizedBox(width: Space.s),
            CountUpAmount(summary.payablePaise, style: text.titleMedium, textAlign: TextAlign.right),
          ]),
        ),
        const SizedBox(height: Space.l),
        FilledButton.icon(
          onPressed: cart.isEmpty || busy ? null : _complete,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(PhosphorIconsRegular.check),
          label: Text(busy ? 'Saving…' : 'Complete sale'),
        ),
        if (ScheduleCompliance.requiresPrescriptionRecord(cart.schedules)) ...[
          const SizedBox(height: Space.s),
          Text('Schedule H1/X item on bill — you\'ll be asked for patient & doctor details.',
              style: text.bodySmall?.copyWith(color: AppColors.warning)),
        ],
      ],
    );
  }
}

/// Off by default (Settings → Udhaar accounts). Shown only once the owner
/// turns it on for this store.
class _CreditCustomerPicker extends ConsumerWidget {
  const _CreditCustomerPicker({required this.selected, required this.onChanged});
  final CustomerCredit? selected;
  final ValueChanged<CustomerCredit?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    if (selected != null) {
      final live = ref.watch(customersProvider).valueOrNull?.where((c) => c.id == selected!.id).firstOrNull ?? selected!;
      return Card(
        child: ListTile(
          title: Text(live.name, overflow: TextOverflow.ellipsis),
          subtitle: Text('${live.phoneNumber.isEmpty ? 'No phone' : live.phoneNumber} · ${live.outstandingBalancePaise < 0 ? 'advance' : 'owes'} ${formatRupees(live.outstandingBalancePaise.abs())}'
              '${live.creditLimitPaise > 0 ? ' of ${formatRupees(live.creditLimitPaise)} limit' : ''}'),
          trailing: IconButton(tooltip: 'Change customer', icon: const Icon(PhosphorIconsRegular.x), onPressed: () => onChanged(null)),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Udhaar sales go on a customer account.', style: text.bodySmall?.copyWith(color: AppColors.muted)),
      const SizedBox(height: Space.s),
      OutlinedButton.icon(
        onPressed: () async {
          final customer = await pickCustomer(context);
          if (customer != null) onChanged(customer);
        },
        icon: const Icon(PhosphorIconsRegular.userFocus),
        label: const Text('Choose customer'),
      ),
    ]);
  }
}

/// Owns its controller for its own real lifetime, not the dialog route's
/// pop future — that resolves before the exit transition finishes, which
/// disposed the controller while the (still-animating-out) field used it.
class _CounterNameDialog extends StatefulWidget {
  const _CounterNameDialog();

  @override
  State<_CounterNameDialog> createState() => _CounterNameDialogState();
}

class _CounterNameDialogState extends State<_CounterNameDialog> {
  late final _controller = TextEditingController(text: '${DeviceFeatures.label} counter');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Receive scans from phones'),
      content: DialogBody(
        child: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Counter name', helperText: 'Shown on the phone, e.g. "Counter 1"'),
          onSubmitted: (v) => Navigator.pop(context, v.trim().isEmpty ? null : v.trim()),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim().isEmpty ? null : _controller.text.trim()),
          child: const Text('Start'),
        ),
      ],
    );
  }
}

/// The scanner window: a USB scanner (or typing) works on every device;
/// Smart Scan and the phone link appear where the device has them.
class _ScanHub extends StatefulWidget {
  const _ScanHub({
    required this.onCode,
    required this.onSmartScan,
    required this.stationName,
    required this.onToggleStation,
  });

  final Future<ScanFeedback> Function(String raw) onCode;
  final Future<void> Function()? onSmartScan;
  final String? Function() stationName;
  final Future<void> Function()? onToggleStation;

  @override
  State<_ScanHub> createState() => _ScanHubState();
}

class _ScanHubState extends State<_ScanHub> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  ScanFeedback? _feedback;
  int _added = 0;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final raw = _code.text.trim();
    if (raw.isEmpty) return;
    final feedback = await widget.onCode(raw);
    if (!mounted) return;
    setState(() {
      _feedback = feedback;
      if (feedback.ok) _added++;
      _code.clear();
    });
    _focus.requestFocus();
  }

  Future<void> _then(Future<void> Function() action) async {
    Navigator.of(context).pop();
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final feedback = _feedback;
    final station = widget.stationName();
    return AlertDialog(
      title: const Text('Scan medicine'),
      content: DialogBody(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _code,
            focusNode: _focus,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Barcode',
              hintText: 'Scan with the USB scanner, or type and press Enter',
              prefixIcon: Icon(PhosphorIconsRegular.barcode),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: Space.s),
          if (feedback != null)
            Row(children: [
              Icon(feedback.ok ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.warningCircle,
                  color: feedback.ok ? AppColors.accent : AppColors.danger, size: 20),
              const SizedBox(width: Space.s),
              Expanded(child: Text(feedback.message, style: text.bodyMedium)),
              if (feedback.onAction != null)
                TextButton(onPressed: feedback.onAction, child: Text(feedback.actionLabel ?? 'Fix')),
            ])
          else
            Text('Each scan adds one pack to the bill. Keep scanning — this window stays open.',
                style: text.bodySmall?.copyWith(color: AppColors.muted)),
          const Divider(height: Space.xl),
          if (widget.onSmartScan != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(PhosphorIconsRegular.camera),
              title: const Text('Smart Scan'),
              subtitle: const Text('Point at a barcode to add it, or tap the camera button for a pack or a bill'),
              onTap: () => _then(widget.onSmartScan!),
            ),
          if (widget.onToggleStation != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(station == null ? PhosphorIconsRegular.deviceMobile : PhosphorIconsRegular.deviceMobileSlash),
              title: Text(station == null ? 'Use a phone as the scanner' : 'Stop receiving phone scans'),
              subtitle: Text(station == null
                  ? 'Scans made on the iPhone app appear on this bill'
                  : 'Receiving as "$station"'),
              onTap: () => _then(widget.onToggleStation!),
            ),
        ]),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(_added == 0 ? 'Close' : 'Done · $_added added'),
        ),
      ],
    );
  }
}

/// A scan that just arrived wirelessly from a phone, shown on screen briefly.
class _IncomingScan {
  const _IncomingScan({required this.id, required this.from, required this.message, required this.ok});
  final String id;
  final String from;
  final String message;
  final bool ok;
}

/// Pops in from the side the instant a phone's scan lands here, and fades
/// away a few seconds later — so every single scan, however many come in a
/// row, is seen arriving and being applied, not just logged silently.
class _IncomingScanCard extends StatelessWidget {
  const _IncomingScanCard({super.key, required this.scan});
  final _IncomingScan scan;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutBack,
        builder: (context, t, child) => Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(offset: Offset((1 - t.clamp(0.0, 1.0)) * 32, 0), child: child),
        ),
        child: Card(
          elevation: 4,
          color: scan.ok ? AppColors.primaryContainer : AppColors.dangerContainer,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
              child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(scan.ok ? PhosphorIconsRegular.bellRinging : PhosphorIconsRegular.warningCircle,
                    color: scan.ok ? AppColors.accent : AppColors.danger, size: 20),
                const SizedBox(width: Space.s),
                Flexible(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(scan.from, style: text.labelSmall?.copyWith(color: AppColors.muted)),
                    Text(scan.message, style: text.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
