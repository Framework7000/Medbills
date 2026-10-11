import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/medicine.dart';
import '../../domain/models/purchase_record.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/stock_receipt.dart';
import '../../domain/services/stock_summary.dart';
import '../../state/providers.dart';
import '../../platform/device_features.dart';
import '../scan/scan_flows.dart';
import 'bill_scan_screen.dart';
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
      body: context.isWide
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
      packs: int.parse(_packs.text),
      freePacks: int.tryParse(_free.text) ?? 0,
      purchasePricePaise: parseRupeesToPaise(_rate.text)!,
      mrpPaise: parseRupeesToPaise(_mrp.text)!,
      supplierName: _supplier.text,
      supplierInvoiceNumber: _supplierInvoice.text,
    );
    final problems = receipt.validate(now: DateTime.now());
    if (problems.isNotEmpty) {
      showMessage(context, problems.join('\n'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider)!.receiveStock(receipt);
      if (!mounted) return;
      showMessage(context,
          'Received ${PackUnits.describe(receipt.totalUnits, receipt.medicine.unitsPerPack)} of ${receipt.medicine.name} '
          '(batch ${receipt.normalisedBatchNumber}).');
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
    final packs = int.tryParse(_packs.text) ?? 0;
    final free = int.tryParse(_free.text) ?? 0;
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
          icon: const Icon(Icons.document_scanner_outlined),
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
        pair(
          TextFormField(controller: _supplier, decoration: const InputDecoration(labelText: 'Supplier / distributor'),
              textCapitalization: TextCapitalization.words),
          TextFormField(controller: _supplierInvoice, decoration: const InputDecoration(labelText: 'Supplier bill no.')),
        ),
        const SizedBox(height: Space.l),
        Row(children: [
          Expanded(child: Text('Medicine', style: text.titleMedium)),
          if (DeviceFeatures.textReading)
            TextButton.icon(onPressed: _readPack, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Read pack')),
        ]),
        const SizedBox(height: Space.s),
        Card(
          child: ListTile(
            onTap: _chooseMedicine,
            leading: const Icon(Icons.medication_outlined),
            title: Text(medicine?.name ?? 'Choose medicine', overflow: TextOverflow.ellipsis),
            subtitle: medicine == null
                ? const Text('From your stock, the master catalogue, or a new one')
                : Text('${medicine.packSizeLabel} · ${medicine.unitsPerPack} unit${medicine.unitsPerPack == 1 ? '' : 's'}/pack · '
                    '${medicine.scheduleType.label} · GST ${medicine.gstRate.toStringAsFixed(0)}%'),
            trailing: const Icon(Icons.chevron_right),
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
            decoration: InputDecoration(labelText: perPack > 1 ? 'Paid packs (×$perPack)' : 'Paid quantity'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
            onChanged: (_) => setState(() {}),
            validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? 'At least 1' : null,
          ),
          TextFormField(
            controller: _free,
            decoration: const InputDecoration(labelText: 'Free (scheme)'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            onChanged: (_) => setState(() {}),
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
            'Adds ${PackUnits.describe((packs + free) * perPack, perPack)} · '
            'cost ${formatRupees(rate * packs)}'
            '${margin == null ? '' : ' · margin ${margin.toStringAsFixed(1)}% on MRP'}',
            style: text.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        const SizedBox(height: Space.l),
        FilledButton.icon(
          onPressed: _busy ? null : _submit,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add_box_outlined),
          label: const Text('Receive stock'),
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
      return const EmptyState(icon: Icons.local_shipping_outlined, title: 'No purchases yet');
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
