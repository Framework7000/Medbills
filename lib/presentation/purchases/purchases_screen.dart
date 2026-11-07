import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/date_value.dart';
import '../../domain/models/medicine.dart';
import '../../domain/models/purchase_record.dart';
import '../../domain/models/supplier_account.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/stock_receipt.dart';
import '../../domain/services/stock_summary.dart';
import '../../state/providers.dart';
import '../../platform/device_features.dart';
import '../scan/scan_flows.dart';
import 'bill_scan_screen.dart';
import 'distributor_field.dart';
import 'medicine_picker.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchasesProvider);
    final form = const _ReceiveStockForm();
    final history = AsyncBody<List<PurchaseRecord>>(
      value: purchases,
      builder: (list) => _PurchaseHistory(purchases: list),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Purchases (stock in)')),
      body: SupplierBillDropZone(
        child: context.isWide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 460, child: SingleChildScrollView(padding: const EdgeInsets.all(Space.l), child: form)),
                const VerticalDivider(width: 1),
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(children: [
                      const TabBar(tabs: [Tab(text: 'Received stock'), Tab(text: 'Scanned bills')]),
                      Expanded(child: TabBarView(children: [history, const BillScanList()])),
                    ]),
                  ),
                ),
              ])
            : DefaultTabController(
                length: 3,
                child: Column(children: [
                  const TabBar(tabs: [Tab(text: 'Receive'), Tab(text: 'Bills'), Tab(text: 'History')]),
                  Expanded(
                    child: TabBarView(children: [
                      SingleChildScrollView(padding: const EdgeInsets.all(Space.l), child: form),
                      const BillScanList(),
                      history,
                    ]),
                  ),
                ]),
              ),
      ),
    );
  }
}

class _ReceiveStockForm extends ConsumerStatefulWidget {
  const _ReceiveStockForm();

  @override
  ConsumerState<_ReceiveStockForm> createState() => _ReceiveStockFormState();
}

class _ReceiveStockFormState extends ConsumerState<_ReceiveStockForm> {
  final _formKey = GlobalKey<FormState>();
  final _supplier = TextEditingController();
  final _supplierInvoice = TextEditingController();
  final _batch = TextEditingController();
  final _packs = TextEditingController();
  final _free = TextEditingController(text: '0');
  final _rate = TextEditingController();
  final _mrp = TextEditingController();
  Medicine? _medicine;
  late int _expiryYear;
  int? _expiryMonth;
  bool _busy = false;
  PurchasePayment _payment = PurchasePayment.credit;
  DateTime _billDate = DateTime.now();

  /// Fill the rate and MRP from the last time this medicine was bought.
  void _prefillFromHistory(Medicine m) {
    final last = (ref.read(purchasesProvider).valueOrNull ?? const <PurchaseRecord>[])
        .where((p) => p.medicineId == m.id)
        .firstOrNull;
    if (last == null) return;
    String plain(int p) => formatRupees(p, symbol: false).replaceAll(',', '');
    if (_rate.text.isEmpty) _rate.text = plain(last.purchasePricePaise);
    if (_mrp.text.isEmpty) _mrp.text = plain(last.mrpPaise);
    if (_supplier.text.isEmpty && last.supplierName.isNotEmpty) _supplier.text = last.supplierName;
  }

  Future<void> _pickBillDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, firstDate: DateTime(now.year - 3), lastDate: now, initialDate: _billDate);
    if (d != null) setState(() => _billDate = d);
  }

  @override
  void initState() {
    super.initState();
    _expiryYear = DateTime.now().year + 1;
  }

  @override
  void dispose() {
    for (final c in [_supplier, _supplierInvoice, _batch, _packs, _free, _rate, _mrp]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _chooseMedicine() async {
    final chosen = await pickMedicine(context);
    if (chosen == null || !mounted) return;
    setState(() {
      _medicine = chosen.medicine;
      _prefillFromHistory(chosen.medicine);
      if (chosen.referenceMrpPaise > 0 && _mrp.text.isEmpty) {
        _mrp.text = formatRupees(chosen.referenceMrpPaise, symbol: false).replaceAll(',', '');
      }
    });
  }

  /// Fills medicine, batch, expiry and MRP from a photo of the pack.
  Future<void> _readPack() async {
    final store = (ref.read(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{}).values.map((s) => s.medicine).toList();
    final inStore = {for (final m in store) m.catalogueId ?? m.id};
    final medicines = [
      ...store,
      ...ref.read(catalogueProvider).search('').map((e) => e.medicine).where((m) => !inStore.contains(m.id)),
    ];
    final scan = await scanPackPhoto(context, medicines: medicines);
    if (scan == null || !mounted) return;
    final info = scan.info;
    setState(() {
      _medicine = scan.medicine;
      if (info.batchNumber != null) _batch.text = info.batchNumber!;
      if (info.hasExpiry) {
        _expiryMonth = info.expiryMonth;
        final now = DateTime.now().year;
        if (info.expiryYear! >= now && info.expiryYear! <= now + 10) _expiryYear = info.expiryYear!;
      }
      final mrp = info.mrpPaise ?? ref.read(catalogueProvider).byId(scan.medicine.catalogueId ?? scan.medicine.id)?.referenceMrpPaise;
      if (mrp != null && mrp > 0) _mrp.text = formatRupees(mrp, symbol: false).replaceAll(',', '');
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_medicine == null) {
      showMessage(context, 'Choose the medicine first.', error: true);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final receipt = StockReceipt(
      medicine: _medicine!,
      batchNumber: _batch.text,
      expiryMonth: _expiryMonth!,
      expiryYear: _expiryYear,
      packs: parsePacks(_packs.text)!,
      freePacks: parsePacks(_free.text) ?? 0,
      purchasePricePaise: parseRupeesToPaise(_rate.text)!,
      mrpPaise: parseRupeesToPaise(_mrp.text)!,
      supplierName: _supplier.text,
      supplierInvoiceNumber: _supplierInvoice.text,
      payment: _payment,
      billDate: DateTime(_billDate.year, _billDate.month, _billDate.day),
    );
    final problems = receipt.validate(now: DateTime.now());
    if (problems.isNotEmpty) {
      showMessage(context, problems.join('\n'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final onBill = await ref.read(repositoryProvider)!.receiveStock(receipt);
      if (!mounted) return;
      showMessage(
        context,
        'Received ${PackUnits.describe(receipt.totalUnits, receipt.medicine.unitsPerPack)} of ${receipt.medicine.name} '
        '(batch ${receipt.normalisedBatchNumber}).'
        '${onBill ? '' : '\nStock saved, but the supplier bill was not: the owner must publish the new database rules (see INSTALL).'}',
        error: !onBill,
      );
      // Keep supplier + invoice for the next line of the same delivery.
      setState(() {
        _medicine = null;
        _expiryMonth = null;
        for (final c in [_batch, _packs, _rate, _mrp]) {
          c.clear();
        }
        _free.text = '0';
      });
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final medicine = _medicine;
    final perPack = medicine?.unitsPerPack ?? 1;
    final packs = parsePacks(_packs.text) ?? 0;
    final free = parsePacks(_free.text) ?? 0;
    final rate = parseRupeesToPaise(_rate.text) ?? 0;
    final mrp = parseRupeesToPaise(_mrp.text) ?? 0;
    final margin = mrp > 0 && rate > 0 ? (mrp - rate) * 100 / mrp : null;

    Widget pair(Widget a, Widget b) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: a),
          const SizedBox(width: Space.m),
          Expanded(child: b),
        ]);

    return Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FilledButton.tonalIcon(
          onPressed: () => captureSupplierBill(context, ref),
          icon: const Icon(PhosphorIconsRegular.fileText),
          label: Text(DeviceFeatures.textReading ? 'Scan supplier bill' : 'Add supplier bill photo'),
        ),
        const SizedBox(height: Space.xs),
        Text(
          DeviceFeatures.textReading
              ? 'Reads supplier, bill no., GSTIN and every line; you check it before stock is added.'
              : 'Bills photographed on the phone appear under "Scanned bills" on every device.',
          style: text.bodySmall?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: Space.l),
        Text('Or enter one line by hand', style: text.titleMedium),
        const SizedBox(height: Space.s),
        const SizedBox(height: Space.s),
        DistributorField(controller: _supplier),
        const SizedBox(height: Space.m),
        pair(
          TextFormField(controller: _supplierInvoice, decoration: const InputDecoration(labelText: 'Bill no.')),
          InkWell(
            onTap: _pickBillDate,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Bill date', suffixIcon: Icon(PhosphorIconsRegular.calendar)),
              child: Text(DateFormat('d MMM yyyy').format(_billDate)),
            ),
          ),
        ),
        const SizedBox(height: Space.m),
        PaymentToggle(value: _payment, onChanged: (p) => setState(() => _payment = p)),
        const SizedBox(height: Space.l),
        Row(children: [
          Expanded(child: Text('Medicine', style: text.titleMedium)),
          if (DeviceFeatures.textReading)
            TextButton.icon(onPressed: _readPack, icon: const Icon(PhosphorIconsRegular.camera), label: const Text('Read pack')),
        ]),
        const SizedBox(height: Space.s),
        _RecentMedicines(onPick: (m) => setState(() {
              _medicine = m;
              _rate.clear();
              _mrp.clear();
              _prefillFromHistory(m);
            })),
        Card(
          child: ListTile(
            onTap: _chooseMedicine,
            leading: const Icon(PhosphorIconsRegular.pill),
            title: Text(medicine?.name ?? 'Choose medicine', overflow: TextOverflow.ellipsis),
            subtitle: medicine == null
                ? const Text('From your stock, the master catalogue, or a new one')
                : Text('${medicine.packSizeLabel} · ${medicine.unitsPerPack} unit${medicine.unitsPerPack == 1 ? '' : 's'}/pack · '
                    '${medicine.scheduleType.label} · GST ${medicine.gstRate.toStringAsFixed(0)}%'),
            trailing: const Icon(PhosphorIconsRegular.caretRight),
          ),
        ),
        if (medicine != null && medicine.unitsPerPack > 1 && PackUnits.isMeasured(medicine.packSizeLabel))
          Padding(
            padding: const EdgeInsets.only(top: Space.s),
            child: Text(
              'This bottle/tube is counted as ${medicine.unitsPerPack} units. Settings → Update medicines makes it 1 per bottle.',
              style: text.bodySmall?.copyWith(color: AppColors.warning),
            ),
          ),
        const SizedBox(height: Space.l),
        Text('Batch', style: text.titleMedium),
        const SizedBox(height: Space.s),
        TextFormField(
          controller: _batch,
          decoration: const InputDecoration(labelText: 'Batch number (as printed)'),
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [LengthLimitingTextInputFormatter(20)],
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        ),
        const SizedBox(height: Space.m),
        pair(
          DropdownButtonFormField<int>(
            initialValue: _expiryMonth,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Expiry month'),
            items: [
              for (var m = 1; m <= 12; m++)
                DropdownMenuItem(value: m, child: Text('${m.toString().padLeft(2, '0')} ${DateFormat('MMM').format(DateTime(2000, m))}')),
            ],
            onChanged: (v) => setState(() => _expiryMonth = v),
            validator: (v) => v == null ? 'Required' : null,
          ),
          DropdownButtonFormField<int>(
            initialValue: _expiryYear,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Expiry year'),
            items: [for (var y = now.year; y <= now.year + 10; y++) DropdownMenuItem(value: y, child: Text('$y'))],
            onChanged: (v) => setState(() => _expiryYear = v ?? _expiryYear),
          ),
        ),
        const SizedBox(height: Space.m),
        pair(
          TextFormField(
            controller: _packs,
            decoration: InputDecoration(
              labelText: perPack > 1 ? 'Paid packs (×$perPack)' : 'Paid quantity',
              helperText: perPack > 1 ? '4.5 = 4½ packs' : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(8)],
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final p = parsePacks(v ?? '');
              if (p == null || p <= 0) return 'Enter packs';
              if ((p * perPack - (p * perPack).round()).abs() > 1e-6) return 'Not whole units';
              return null;
            },
          ),
          TextFormField(
            controller: _free,
            decoration: const InputDecoration(labelText: 'Free (scheme)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')), LengthLimitingTextInputFormatter(7)],
            onChanged: (_) => setState(() {}),
            validator: (v) => (v ?? '').trim().isEmpty || parsePacks(v!) != null ? null : 'Number',
          ),
        ),
        const SizedBox(height: Space.m),
        pair(
          TextFormField(
            controller: _rate,
            decoration: InputDecoration(
              labelText: 'Purchase rate ₹/${perPack > 1 ? 'pack' : 'unit'}',
              helperText: 'Net of discount, incl. GST',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            validator: (v) => (parseRupeesToPaise(v ?? '') ?? 0) <= 0 ? 'Enter rate' : null,
          ),
          TextFormField(
            controller: _mrp,
            decoration: InputDecoration(labelText: 'MRP ₹/${perPack > 1 ? 'pack' : 'unit'}'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final paise = parseRupeesToPaise(v ?? '') ?? 0;
              if (paise <= 0) return 'Enter MRP';
              if (rate > paise) return 'Below purchase rate';
              return null;
            },
          ),
        ),
        const SizedBox(height: Space.m),
        if (medicine != null && packs > 0)
          Text(
            'Adds ${PackUnits.describe(((packs + free) * perPack).round(), perPack)} · '
            'cost ${formatRupees((rate * packs).round())} · ${_payment == PurchasePayment.cash ? 'paid in cash' : 'on udhaar'}'
            '${margin == null ? '' : ' · margin ${margin.toStringAsFixed(1)}% on MRP'}',
            style: text.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        const SizedBox(height: Space.l),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(PhosphorIconsRegular.plusSquare),
          label: const Text('Receive stock'),
        ),
      ]),
    );
  }
}

/// Medicines bought recently, one tap to pick again (rate and MRP filled
/// from the last purchase).
class _RecentMedicines extends ConsumerWidget {
  const _RecentMedicines({required this.onPick});
  final ValueChanged<Medicine> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchasesProvider).valueOrNull ?? const <PurchaseRecord>[];
    final stock = ref.watch(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
    final seen = <String>{};
    final recent = <Medicine>[];
    for (final p in purchases) {
      final m = stock[p.medicineId]?.medicine;
      if (m != null && seen.add(m.id)) recent.add(m);
      if (recent.length == 8) break;
    }
    if (recent.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Wrap(spacing: Space.s, runSpacing: Space.xs, children: [
        for (final m in recent)
          ActionChip(
            avatar: const Icon(PhosphorIconsRegular.clockCounterClockwise, size: 16),
            label: Text(m.name, overflow: TextOverflow.ellipsis),
            onPressed: () => onPick(m),
          ),
      ]),
    );
  }
}

class _PurchaseHistory extends StatelessWidget {
  const _PurchaseHistory({required this.purchases});
  final List<PurchaseRecord> purchases;

  @override
  Widget build(BuildContext context) {
    if (purchases.isEmpty) {
      return const EmptyState(icon: PhosphorIconsRegular.truck, title: 'No purchases yet');
    }
    final text = Theme.of(context).textTheme;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: Space.s),
      itemCount: purchases.length,
      separatorBuilder: (_, _) => const Divider(indent: Space.l, endIndent: Space.l),
      itemBuilder: (context, i) {
        final p = purchases[i];
        return ListTile(
          title: Text(p.medicineName, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            'Batch ${p.batchNumber} · exp ${DateFormat('MM/yy').format(p.expiryDate)} · '
            '${PackUnits.describe(p.quantity, p.unitsPerPack)}${p.freeQuantity > 0 ? ' (incl. ${PackUnits.describe(p.freeQuantity, p.unitsPerPack)} free)' : ''}\n'
            '${p.supplierName.isEmpty ? 'No supplier' : p.supplierName}'
            '${p.supplierInvoiceNumber.isEmpty ? '' : ' · bill ${p.supplierInvoiceNumber}'} · '
            '${DateFormat('dd MMM, hh:mm a').format(p.createdAt)} · ${p.createdByName}',
          ),
          isThreeLine: true,
          trailing: Text(formatRupees(p.totalCostPaise), style: text.titleSmall),
        );
      },
    );
  }
}
