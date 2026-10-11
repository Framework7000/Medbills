import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/sale_invoice.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/profit_loss_service.dart';
import '../../domain/services/stock_summary.dart';
import '../../state/providers.dart';
import '../sales/invoice_view.dart';
import '../theme.dart';
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
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_salesInRangeProvider(range)),
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
            builder: (list) => _ReportBody(sales: list, rangeLabel: rangeLabel),
          ),
        ),
      ]),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.sales, required this.rangeLabel});
  final List<SaleInvoice> sales;
  final String rangeLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final report = ProfitLossService.calculate(sales);
    final live = sales.where((s) => !s.isCancelled).toList();
    final payable = live.fold<int>(0, (s, i) => s + i.payablePaise);
    final roundOff = live.fold<int>(0, (s, i) => s + i.roundOffPaise);

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

    final cards = <Widget>[
      _Section(
        title: 'Sales · $rangeLabel',
        children: [
          AmountRow('Bills', '${report.invoiceCount}'
              '${report.cancelledCount > 0 ? ' (+${report.cancelledCount} cancelled)' : ''}'),
          AmountRow('Collected / billed', formatRupees(payable), emphasis: true),
          AmountRow('MRP value of goods', formatRupees(report.salesPaise)),
          AmountRow('Round-off', formatRupees(roundOff)),
          AmountRow('GST included', formatRupees(report.gstPaise)),
          const Divider(height: Space.l),
          AmountRow('Purchase cost of goods sold', formatRupees(report.costPaise)),
          AmountRow(
            'Gross margin',
            '${formatRupees(report.grossProfitPaise)} (${report.marginPercent.toStringAsFixed(1)}%)',
            emphasis: true,
          ),
          Text('MRP value minus purchase rate, both including GST.',
              style: text.bodySmall?.copyWith(color: AppColors.muted)),
        ],
      ),
      _Section(
        title: 'By payment mode',
        children: [
          if (report.byPaymentMode.isEmpty) const Text('No sales.'),
          for (final mode in PaymentMode.values)
            if (report.byPaymentMode[mode] != null)
              AmountRow(mode == PaymentMode.credit ? 'Udhaar (credit)' : mode.label,
                  formatRupees(report.byPaymentMode[mode]!)),
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
        child: Wrap(
          spacing: Space.l,
          runSpacing: Space.l,
          children: [for (final card in cards) SizedBox(width: width, child: card)],
        ),
      );
    });
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
