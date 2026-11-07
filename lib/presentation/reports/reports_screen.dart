import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/purchase_record.dart';
import '../../domain/models/sale_invoice.dart';
import '../../domain/models/sale_return.dart';
import '../../domain/models/supplier_account.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/day_book.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/stock_summary.dart';
import '../../state/providers.dart';
import '../accounts/supplier_dialogs.dart';
import '../sales/invoice_view.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';

typedef _Range = ({DateTime from, DateTime to});

/// Sales in [from, to), refreshed whenever a sale is made or cancelled on
/// any device.
final _salesInRangeProvider = FutureProvider.autoDispose.family<List<SaleInvoice>, _Range>((ref, range) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const <SaleInvoice>[];
  ref.watch(recentSalesProvider);
  return repo.salesBetween(range.from, range.to);
});

/// Customer returns in [from, to), refreshed with the sales.
final _returnsInRangeProvider = FutureProvider.autoDispose.family<List<SaleReturn>, _Range>((ref, range) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const <SaleReturn>[];
  ref.watch(recentSalesProvider);
  return repo.returnsBetween(range.from, range.to);
});

enum _Preset {
  today('Today'),
  yesterday('Yesterday'),
  month('This month'),
  lastMonth('Last month'),
  custom('Custom');

  const _Preset(this.label);
  final String label;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

_Range _rangeFor(_Preset preset, DateTime now, _Range? custom) {
  final today = _day(now);
  return switch (preset) {
    _Preset.today => (from: today, to: today.add(const Duration(days: 1))),
    _Preset.yesterday => (from: DateTime(today.year, today.month, today.day - 1), to: today),
    _Preset.month => (from: DateTime(today.year, today.month), to: DateTime(today.year, today.month + 1)),
    _Preset.lastMonth => (from: DateTime(today.year, today.month - 1), to: DateTime(today.year, today.month)),
    _Preset.custom => custom ?? (from: today, to: today.add(const Duration(days: 1))),
  };
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  _Preset _preset = _Preset.today;
  _Range? _custom;

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _custom == null
          ? DateTimeRange(start: _day(now), end: _day(now))
          : DateTimeRange(start: _custom!.from, end: _custom!.to.subtract(const Duration(days: 1))),
    );
    if (picked == null) return;
    setState(() {
      _custom = (from: _day(picked.start), to: _day(picked.end).add(const Duration(days: 1)));
      _preset = _Preset.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
    final range = _rangeFor(_preset, now, _custom);
    final sales = ref.watch(_salesInRangeProvider(range));
    final lastDay = range.to.subtract(const Duration(days: 1));
    final dates = DateFormat('d MMM yyyy');
    final rangeLabel = _day(range.from) == lastDay
        ? dates.format(range.from)
        : '${dates.format(range.from)} – ${dates.format(lastDay)}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports · Profit & Loss'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(PhosphorIconsRegular.arrowClockwise),
            onPressed: () {
              ref.invalidate(_salesInRangeProvider(range));
              ref.invalidate(_returnsInRangeProvider(range));
            },
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
            children: [
              for (final p in _Preset.values)
                Padding(
                  padding: const EdgeInsets.only(right: Space.s),
                  child: ChoiceChip(
                    label: Text(p.label),
                    selected: _preset == p,
                    onSelected: (_) => p == _Preset.custom ? _pickCustom() : setState(() => _preset = p),
                  ),
                ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: AsyncBody<List<SaleInvoice>>(
            value: sales,
            builder: (list) => _ReportBody(
              sales: list,
              returns: ref.watch(_returnsInRangeProvider(range)).valueOrNull ?? const [],
              range: range,
              rangeLabel: rangeLabel,
            ),
          ),
        ),
      ]),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.sales, required this.returns, required this.range, required this.rangeLabel});
  final List<SaleInvoice> sales;
  final List<SaleReturn> returns;
  final _Range range;
  final String rangeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final bills = ref.watch(supplierBillsProvider).valueOrNull ?? const <SupplierBill>[];
    final payments = ref.watch(supplierPaymentsProvider).valueOrNull ?? const <SupplierPayment>[];
    final book = DayBook.build(from: range.from, to: range.to, sales: sales, returns: returns, bills: bills, payments: payments);
    final t = book.total;
    final live = sales.where((s) => !s.isCancelled).toList();
    final roundOff = live.fold<int>(0, (s, i) => s + i.roundOffPaise);
    final owed = ref.watch(supplierLedgerProvider).valueOrNull?.totalOutstandingPaise;
    final items = (ref.watch(purchasesProvider).valueOrNull ?? const <PurchaseRecord>[])
        .where((p) => !p.createdAt.isBefore(range.from) && p.createdAt.isBefore(range.to))
        .toList();

    // GST return figures per slab (taxable value, CGST, SGST).
    final slabs = <double, ({int taxable, int cgst, int sgst})>{};
    for (final sale in live) {
      for (final slab in sale.slabs) {
        final cur = slabs[slab.rate] ?? (taxable: 0, cgst: 0, sgst: 0);
        slabs[slab.rate] = (
          taxable: cur.taxable + slab.taxablePaise,
          cgst: cur.cgst + slab.cgstPaise,
          sgst: cur.sgst + slab.sgstPaise,
        );
      }
    }
    final rates = slabs.keys.toList()..sort();

    // Schedule H1 / X register: every restricted line sold in the period.
    final register = [
      for (final sale in live)
        for (final line in sale.lines)
          if (line.scheduleType.requiresRegisterEntry) (sale: sale, line: line),
    ];

    // Top sellers by value.
    final byMedicine = <String, ({String name, int units, int perPack, int value})>{};
    for (final sale in live) {
      for (final l in sale.lines) {
        final cur = byMedicine[l.medicineId];
        byMedicine[l.medicineId] = (
          name: l.name,
          units: (cur?.units ?? 0) + l.quantity,
          perPack: l.unitsPerPack,
          value: (cur?.value ?? 0) + l.lineTotalPaise,
        );
      }
    }
    final top = byMedicine.values.toList()..sort((a, b) => b.value.compareTo(a.value));

    final stock = ref.watch(stockIndexProvider).valueOrNull?.values.toList() ?? const <StockSummary>[];
    final low = stock.where((s) => s.isLowStock).length;
    final out = stock.where((s) => s.isOutOfStock).length;
    final expiring = stock.where((s) => s.hasExpiringSoon).length;
    final expired = stock.where((s) => s.hasExpiredStock).length;

    final days = book.byDay.keys.toList()..sort();
    final perDay = [for (final d in days) book.byDay[d]!];
    final dayFormat = days.length > 31 ? DateFormat('MMM') : DateFormat('d');

    final cards = <Widget>[
      _Section(
        title: 'Sales by payment · $rangeLabel',
        children: [
          DonutChart(
            centerLabel: 'net sales',
            slices: [
              ChartSlice('Cash', t.cashSalesPaise, ChartColors.cash),
              ChartSlice('UPI', t.upiSalesPaise, ChartColors.upi),
              ChartSlice('Card', t.cardSalesPaise, ChartColors.card),
              ChartSlice('Udhaar', t.udhaarSalesPaise, ChartColors.udhaar),
            ],
          ),
        ],
      ),
      _Section(
        title: 'Money in and out',
        children: [
          DonutChart(
            centerLabel: t.netCashPaise >= 0 ? 'plus' : 'minus',
            centerValue: '${t.netCashPaise >= 0 ? '+' : '−'}${formatRupees(t.netCashPaise.abs())}',
            centerColor: t.netCashPaise >= 0 ? AppColors.accent : AppColors.danger,
            slices: [
              ChartSlice('Came in', t.cashInPaise, ChartColors.cash),
              ChartSlice('Paid out', t.paidOutPaise, ChartColors.out),
            ],
          ),
          const SizedBox(height: Space.s),
          AmountRow('Plus / minus', '${t.netCashPaise >= 0 ? '+' : '−'}${formatRupees(t.netCashPaise.abs())}', emphasis: true),
        ],
      ),
      if (days.length > 1)
        _Section(
          title: 'Day by day',
          children: [
            GroupedBarChart(
              labels: [for (final d in days) dayFormat.format(d)],
              series: [
                BarSeries('Sales', ChartColors.cash, [for (final f in perDay) f.netSalesPaise]),
                BarSeries('Profit', ChartColors.upi, [for (final f in perDay) f.grossProfitPaise.clamp(0, 1 << 40)]),
                BarSeries('Paid out', ChartColors.out, [for (final f in perDay) f.paidOutPaise]),
              ],
            ),
          ],
        ),
      // Table 1 — Sales.
      _Section(
        title: '1 · Sales',
        children: [
          AmountRow('Bills', '${t.bills}${t.cancelledBills > 0 ? ' (+${t.cancelledBills} cancelled)' : ''}'),
          AmountRow('Sales (after discount)', formatRupees(t.salesPaise)),
          if (t.discountPaise > 0) AmountRow('Discount given', formatRupees(t.discountPaise)),
          if (t.refundPaise > 0) AmountRow('Returns (${t.returnsCount})', '−${formatRupees(t.refundPaise)}'),
          AmountRow('Net sales', formatRupees(t.netSalesPaise), emphasis: true),
          AmountRow('Cash', formatRupees(t.cashSalesPaise)),
          AmountRow('UPI', formatRupees(t.upiSalesPaise)),
          if (t.cardSalesPaise != 0) AmountRow('Card', formatRupees(t.cardSalesPaise)),
          if (t.udhaarSalesPaise != 0) AmountRow('Udhaar (credit)', formatRupees(t.udhaarSalesPaise)),
          AmountRow('Round-off', formatRupees(roundOff)),
          AmountRow('GST included', formatRupees(t.netGstPaise)),
          const Divider(height: Space.l),
          AmountRow('Cost of goods sold', formatRupees(t.netCostPaise)),
          AmountRow(
            'Gross profit',
            '${formatRupees(t.grossProfitPaise)} (${t.marginPercent.toStringAsFixed(1)}%)',
            emphasis: true,
          ),
          Text('Net sales minus the purchase rate of what was sold (returns taken out).',
              style: text.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ),
      // Table 2 — Purchase & Payment.
      _Section(
        title: '2 · Purchase & Payment',
        children: [
          AmountRow('Purchases in cash', formatRupees(t.cashPurchasePaise)),
          AmountRow('Purchases on udhaar', formatRupees(t.creditPurchasePaise)),
          AmountRow('Total purchases', formatRupees(t.purchasePaise), emphasis: true),
          AmountRow('Payments of old bills', formatRupees(t.paymentsPaise)),
          AmountRow('Total paid out', formatRupees(t.paidOutPaise), emphasis: true),
          if (book.purchases.isNotEmpty) ...[
            const Divider(height: Space.l),
            Text('Purchases', style: text.titleSmall),
            for (final b in book.purchases)
              _RowLink(
                onTap: () => showSupplierBillDialog(context, bill: b),
                title: '${b.distributorName} · ${b.billNumber.isEmpty ? 'no bill no.' : 'bill ${b.billNumber}'}',
                subtitle: '${DateFormat('d MMM').format(b.billDate)} · ${b.isCredit ? 'Udhaar' : 'Cash'}',
                amount: b.totalPaise,
              ),
          ],
          if (items.isNotEmpty) ...[
            const Divider(height: Space.l),
            Text('What was bought', style: text.titleSmall),
            for (final p in items.take(60))
              _RowLink(
                title: '${p.medicineName} · ${PackUnits.describe(p.quantity, p.unitsPerPack)}',
                subtitle: '${p.supplierName.isEmpty ? 'No supplier' : p.supplierName}'
                    '${p.supplierInvoiceNumber.isEmpty ? '' : ' · bill ${p.supplierInvoiceNumber}'} · '
                    '${DateFormat('d MMM').format(p.createdAt)}',
                amount: p.totalCostPaise,
              ),
            if (items.length > 60)
              Text('+ ${items.length - 60} more in Purchases', style: text.bodySmall?.copyWith(color: AppColors.muted)),
          ],
          if (book.payments.isNotEmpty) ...[
            const Divider(height: Space.l),
            Text('Payments', style: text.titleSmall),
            for (final p in book.payments)
              _RowLink(
                onTap: () => showSupplierPaymentDialog(context, payment: p),
                title: '${p.distributorName}${p.billNumber.isEmpty ? '' : ' · bill ${p.billNumber}'}',
                subtitle: '${DateFormat('d MMM').format(p.paidOn)} · ${p.via.label}',
                amount: p.amountPaise,
              ),
          ],
        ],
      ),
      // Table 3 — Totals.
      _Section(
        title: '3 · Total',
        children: [
          AmountRow('Total sales (net)', formatRupees(t.netSalesPaise)),
          AmountRow('Money came in (cash + UPI + card)', formatRupees(t.cashInPaise)),
          AmountRow('Total paid (purchases + payments)', formatRupees(t.paidOutPaise)),
          AmountRow('Plus / minus', '${t.netCashPaise >= 0 ? '+' : '−'}${formatRupees(t.netCashPaise.abs())}', emphasis: true),
          const Divider(height: Space.l),
          AmountRow('Gross profit on sales', formatRupees(t.grossProfitPaise), emphasis: true),
          if (t.udhaarSalesPaise != 0) AmountRow('Udhaar given to customers', formatRupees(t.udhaarSalesPaise)),
          if (owed != null) AmountRow('Udhaar owed to distributors (now)', formatRupees(owed)),
        ],
      ),
      _Section(
        title: 'GST summary (intra-state)',
        children: [
          if (rates.isEmpty) const Text('No taxable sales.'),
          for (final r in rates) ...[
            Text('GST ${r.toStringAsFixed(0)}%', style: text.titleSmall),
            AmountRow('Taxable value', formatRupees(slabs[r]!.taxable)),
            AmountRow('CGST ${(r / 2).toStringAsFixed(1)}%', formatRupees(slabs[r]!.cgst)),
            AmountRow('SGST ${(r / 2).toStringAsFixed(1)}%', formatRupees(slabs[r]!.sgst)),
            const SizedBox(height: Space.s),
          ],
        ],
      ),
      _Section(
        title: 'Stock alerts (now)',
        children: [
          AmountRow('Low stock', '$low'),
          AmountRow('Out of stock', '$out'),
          AmountRow('Expiring in 90 days', '$expiring'),
          AmountRow('Holding expired stock', '$expired'),
        ],
      ),
      _Section(
        title: 'Top medicines',
        children: [
          if (top.isEmpty) const Text('No sales.'),
          for (final t in top.take(10))
            AmountRow('${t.name} · ${PackUnits.describe(t.units, t.perPack)}', formatRupees(t.value)),
        ],
      ),
      _Section(
        title: 'Schedule H1 / X register',
        children: [
          if (register.isEmpty) const Text('No restricted medicines sold in this period.'),
          for (final e in register)
            InkWell(
              onTap: () => showInvoice(context, e.sale),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${e.line.name} · ${PackUnits.describe(e.line.quantity, e.line.unitsPerPack)} · batch ${e.line.batchNumber}',
                      style: text.bodyMedium),
                  Text(
                    '${DateFormat('d MMM, hh:mm a').format(e.sale.createdAt)} · ${e.sale.invoiceNumber}\n'
                    'Patient ${e.sale.prescription?.patientName ?? '—'} (${e.sale.prescription?.patientPhone ?? '—'}) · '
                    'Dr ${e.sale.prescription?.doctorName ?? '—'}, Reg. ${e.sale.prescription?.doctorRegistrationNumber ?? '—'}',
                    style: text.bodySmall?.copyWith(color: AppColors.muted),
                  ),
                ]),
              ),
            ),
        ],
      ),
    ];

    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 1100 ? 3 : (c.maxWidth >= 720 ? 2 : 1);
      final width = (c.maxWidth - Space.l * (columns + 1)) / columns;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          StatGrid(children: [
            StatTile(label: 'Net sales', paise: t.netSalesPaise, caption: '${t.bills} bills'),
            StatTile(
              label: 'Gross profit',
              paise: t.grossProfitPaise,
              color: AppColors.accent,
              caption: '${t.marginPercent.toStringAsFixed(1)}% margin',
            ),
            StatTile(label: 'Paid out', paise: t.paidOutPaise, color: AppColors.warning, caption: 'Cash buys + payments'),
            StatTile(label: 'Plus / minus', paise: t.netCashPaise, signed: true, caption: 'Came in − paid out'),
          ]),
          const SizedBox(height: Space.l),
          Wrap(
            spacing: Space.l,
            runSpacing: Space.l,
            children: [for (final card in cards) SizedBox(width: width, child: card)],
          ),
        ]),
      );
    });
  }
}

class _RowLink extends StatelessWidget {
  const _RowLink({required this.title, required this.subtitle, required this.amount, this.onTap});
  final String title;
  final String subtitle;
  final int amount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xs),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: text.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(subtitle, style: text.bodySmall?.copyWith(color: AppColors.muted)),
            ]),
          ),
          const SizedBox(width: Space.s),
          Text(formatRupees(amount), style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Space.s),
          ...children,
        ]),
      ),
    );
  }
}
