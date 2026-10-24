import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../domain/services/billing_calculator.dart';
import '../../domain/models/medicine.dart';
import '../../domain/services/medicine_matcher.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/scanned_code.dart';
import '../../domain/services/stock_summary.dart';
import '../../state/providers.dart';
import '../theme.dart';

/// One line of what a scanned code says — for the result shown over the
/// camera, so the phone answers "what is this?" at a glance.
String describeScannedCode(ScannedCode code, {String? medicineName}) {
  final money = NumberFormat.decimalPattern('en_IN');
  switch (code) {
    case EInvoiceCode():
      return [
        '${code.docTypeLabel} ${code.docNo}'.trim(),
        if (code.docDate != null) DateFormat('d MMM yyyy').format(code.docDate!),
        if (code.totalPaise != null) '₹${money.format(code.totalPaise! / 100)}',
        if (code.itemCount != null) '${code.itemCount} items',
      ].join(' · ');
    case PackCode():
      return [
        medicineName ?? code.brand ?? code.genericName ?? (code.isPlainBarcode ? 'Barcode ${code.gtin}' : 'Medicine code'),
        if (code.batch != null) 'Batch ${code.batch}',
        if (code.expiry != null) 'Exp ${DateFormat('MM/yy').format(code.expiry!)}',
      ].join(' · ');
    case TextCode():
      return code.raw.length > 80 ? '${code.raw.substring(0, 80)}…' : code.raw;
  }
}

/// Everything a scanned code says, laid out plainly: a supplier bill's
/// e-invoice QR, or a medicine pack's code with the store's matching
/// medicine and stock. [onLink], when given, offers linking an unknown code.
Future<void> showScannedCodeDetails(
  BuildContext context,
  WidgetRef ref,
  ScannedCode code, {
  VoidCallback? onLink,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ScanDetailsSheet(code: code, onLink: onLink),
  );
}

class _ScanDetailsSheet extends ConsumerWidget {
  const _ScanDetailsSheet({required this.code, this.onLink});
  final ScannedCode code;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final rows = <Widget>[];
    String title;
    IconData icon;
    final day = DateFormat('d MMM yyyy');
    final month = DateFormat('MMM yyyy');
    final money = NumberFormat.decimalPattern('en_IN');

    switch (code) {
      case final EInvoiceCode bill:
        title = '${bill.docTypeLabel} (GST e-invoice)';
        icon = PhosphorIconsRegular.receipt;
        final ownGstin = ref.watch(storeProvider).valueOrNull?.gstin.trim().toUpperCase() ?? '';
        rows.addAll([
          _Row('Supplier GSTIN', bill.sellerGstin, copy: true),
          _Row('Bill to GSTIN', bill.buyerGstin,
              note: ownGstin.isEmpty
                  ? null
                  : bill.buyerGstin == ownGstin
                      ? '✓ This store'
                      : '✗ Not this store ($ownGstin)',
              warn: ownGstin.isNotEmpty && bill.buyerGstin != ownGstin),
          _Row('Invoice no.', bill.docNo, copy: true),
          if (bill.docDate != null) _Row('Invoice date', day.format(bill.docDate!)),
          if (bill.totalPaise != null) _Row('Invoice total', '₹${money.format(bill.totalPaise! / 100)}'),
          if (bill.itemCount != null) _Row('Items', '${bill.itemCount}'),
          if (bill.mainHsn.isNotEmpty) _Row('Main HSN', bill.mainHsn),
          if (bill.irn.isNotEmpty) _Row('IRN', bill.irn, copy: true, small: true),
          if (bill.irnDate.isNotEmpty) _Row('IRN date', bill.irnDate),
        ]);
      case final PackCode pack:
        icon = PhosphorIconsRegular.pill;
        final index = ref.watch(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
        final stock = _storeMatch(pack, index);
        final catalogue = stock == null ? _catalogueMatch(ref, pack) : null;
        final medicine = stock?.medicine ?? catalogue;
        title = medicine?.name ?? pack.brand ?? (pack.isPlainBarcode ? 'Barcode' : 'Medicine code');
        final expired = pack.isExpiredAt(DateTime.now());
        rows.addAll([
          if (medicine != null) ...[
            _Row('Composition', medicine.genericName),
            _Row('Maker', medicine.manufacturer),
            _Row('Schedule', medicine.scheduleType.label,
                warn: medicine.scheduleType.requiresRegisterEntry,
                note: medicine.scheduleType.requiresRegisterEntry ? 'Patient + doctor needed' : null),
            _Row('GST', '${medicine.gstRate % 1 == 0 ? medicine.gstRate.toInt() : medicine.gstRate}%  ·  HSN ${medicine.hsnCode}'),
            if (stock != null)
              _Row('In stock',
                  stock.isOutOfStock ? 'None' : PackUnits.describe(stock.sellableUnits, medicine.unitsPerPack),
                  warn: stock.isOutOfStock)
            else
              const _Row('In stock', 'Not stocked yet', warn: true),
          ],
          if (pack.brand != null && pack.brand != medicine?.name) _Row('Brand (on code)', pack.brand!),
          if (pack.genericName != null) _Row('Generic name (on code)', pack.genericName!),
          if (pack.manufacturer != null) _Row('Manufacturer (on code)', pack.manufacturer!),
          if (pack.batch != null) _Row('Batch', pack.batch!, copy: true),
          if (pack.manufactured != null) _Row('Mfg', month.format(pack.manufactured!)),
          if (pack.expiry != null)
            _Row('Expiry', month.format(pack.expiry!), warn: expired, note: expired ? 'EXPIRED — do not sell' : null),
          if (pack.mrpPaise != null) _Row('MRP (on code)', formatRupees(pack.mrpPaise!)),
          if (pack.gtin != null) _Row('Product code (GTIN)', pack.gtin!, copy: true),
          if (pack.serial != null) _Row('Pack serial', pack.serial!, small: true),
          if (pack.licence != null) _Row('Mfg licence', pack.licence!),
          if (pack.url != null) _Row('Link', pack.url!, copy: true, small: true),
          if (medicine == null && pack.brand == null && pack.genericName == null)
            const _Row('Medicine', 'Not linked yet — link this code once and it is recognised everywhere.', warn: true),
        ]);
      case final TextCode other:
        title = other.isUrl ? 'Link' : 'Code';
        icon = PhosphorIconsRegular.qrCode;
        rows.add(_Row(other.isUrl ? 'Address' : 'Text', other.raw, copy: true));
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(icon, color: AppColors.primary),
            const SizedBox(width: Space.s),
            Expanded(child: Text(title, style: text.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: Space.m),
          Flexible(child: SingleChildScrollView(child: Column(children: rows))),
          if (onLink != null) ...[
            const SizedBox(height: Space.m),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onLink!();
              },
              icon: const Icon(PhosphorIconsRegular.link),
              label: const Text('Link to a medicine'),
            ),
          ],
        ]),
      ),
    );
  }

  static String _digits(String s) => s.replaceFirst(RegExp(r'^0+'), '');

  StockSummary? _storeMatch(PackCode pack, Map<String, StockSummary> index) {
    for (final s in index.values) {
      final linked = s.medicine.barcode;
      if (linked == null || linked.isEmpty) continue;
      if (linked == pack.raw || (pack.gtin != null && _digits(linked) == _digits(pack.gtin!))) return s;
    }
    final named = [pack.brand, pack.genericName].whereType<String>().join(' ');
    if (named.isEmpty) return null;
    final match = MedicineMatcher.match(named, index.values.map((s) => s.medicine));
    return match.isConfident ? index[match.best!.medicine.id] : null;
  }

  Medicine? _catalogueMatch(WidgetRef ref, PackCode pack) {
    final named = [pack.brand, pack.genericName].whereType<String>().join(' ');
    if (named.isEmpty) return null;
    final all = ref.read(catalogueProvider).search('').map((e) => e.medicine);
    final match = MedicineMatcher.match(named, all);
    return match.isConfident ? match.best!.medicine : null;
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.note, this.warn = false, this.copy = false, this.small = false});
  final String label;
  final String value;
  final String? note;
  final bool warn;
  final bool copy;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 128, child: Text(label, style: text.bodySmall?.copyWith(color: AppColors.muted))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(value,
                style: (small ? text.bodySmall : text.bodyLarge)?.copyWith(color: warn ? AppColors.danger : null)),
            if (note != null)
              Text(note!, style: text.bodySmall?.copyWith(color: warn ? AppColors.danger : AppColors.accent)),
          ]),
        ),
        if (copy)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Copy',
            icon: const Icon(PhosphorIconsRegular.copy, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
          ),
      ]),
    );
  }
}
