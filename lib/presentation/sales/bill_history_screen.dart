import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/sale_invoice.dart';
import '../../domain/services/billing_calculator.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'invoice_view.dart';

/// Sales for one calendar day, fetched on demand (older than the live list).
final _salesOnDayProvider = FutureProvider.autoDispose.family<List<SaleInvoice>, DateTime>((ref, day) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) return const <SaleInvoice>[];
  // Re-query when a new sale arrives or one is cancelled.
  ref.watch(recentSalesProvider);
  return repo.salesBetween(day, DateTime(day.year, day.month, day.day + 1));
});

enum _Show { all, cancelled, credit }

class BillHistoryScreen extends ConsumerStatefulWidget {
  const BillHistoryScreen({super.key});

  @override
  ConsumerState<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends ConsumerState<BillHistoryScreen> {
  final _query = TextEditingController();
  DateTime? _day; // null = most recent bills
  _Show _show = _Show.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? now,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Show bills of',
    );
    if (picked != null) setState(() => _day = DateTime(picked.year, picked.month, picked.day));
  }

  bool _matches(SaleInvoice s, String q) {
    if (_show == _Show.cancelled && !s.isCancelled) return false;
    if (_show == _Show.credit && s.paymentMode != PaymentMode.credit) return false;
    if (q.isEmpty) return true;
    return s.invoiceNumber.toLowerCase().contains(q) ||
        s.customerName.toLowerCase().contains(q) ||
        s.customerPhone.contains(q) ||
        (s.prescription?.patientName.toLowerCase().contains(q) ?? false) ||
        s.lines.any((l) => l.name.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    final sales = day == null ? ref.watch(recentSalesProvider) : ref.watch(_salesOnDayProvider(day));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Bills')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
          child: TextField(
            controller: _query,
            decoration: InputDecoration(
              hintText: 'Invoice no., customer, mobile or medicine',
              prefixIcon: const Icon(PhosphorIconsRegular.magnifyingGlass),
              suffixIcon: _query.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(PhosphorIconsRegular.x),
                      onPressed: () => setState(_query.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
            children: [
              InputChip(
                avatar: const Icon(PhosphorIconsRegular.calendar, size: 16),
                label: Text(day == null ? 'Latest bills' : DateFormat('d MMM yyyy').format(day)),
                onPressed: _pickDay,
                onDeleted: day == null ? null : () => setState(() => _day = null),
              ),
              const SizedBox(width: Space.s),
              for (final (value, label) in const [
                (_Show.all, 'All'),
                (_Show.credit, 'Udhaar'),
                (_Show.cancelled, 'Cancelled'),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _show == value,
                  onSelected: (_) => setState(() => _show = value),
                ),
                const SizedBox(width: Space.s),
              ],
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: AsyncBody<List<SaleInvoice>>(
            value: sales,
            builder: (list) {
              final q = _query.text.trim().toLowerCase();
              final shown = list.where((s) => _matches(s, q)).toList();
              final live = shown.where((s) => !s.isCancelled);
              final total = live.fold<int>(0, (sum, s) => sum + s.payablePaise);
              if (shown.isEmpty) {
                return EmptyState(
                  icon: PhosphorIconsRegular.receipt,
                  title: list.isEmpty ? (day == null ? 'No bills yet' : 'No bills on this day') : 'Nothing matches',
                  message: list.isEmpty && day == null ? 'Completed sales from every counter appear here.' : null,
                );
              }
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
                  child: Row(children: [
                    Expanded(
                      child: Text('${shown.length} bill${shown.length == 1 ? '' : 's'}',
                          style: text.bodyMedium?.copyWith(color: AppColors.muted)),
                    ),
                    Text('Total ${formatRupees(total)}', style: text.titleSmall),
                  ]),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: shown.length,
                    separatorBuilder: (_, _) => const Divider(indent: Space.l, endIndent: Space.l),
                    itemBuilder: (context, i) => _SaleTile(sale: shown[i]),
                  ),
                ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale});
  final SaleInvoice sale;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final who = sale.customerName.isNotEmpty
        ? sale.customerName
        : (sale.prescription?.patientName.isNotEmpty ?? false)
            ? sale.prescription!.patientName
            : 'Walk-in';
    return ListTile(
      onTap: () => showInvoice(context, sale),
      title: Row(children: [
        Flexible(child: Text(sale.invoiceNumber, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: Space.s),
        if (sale.isCancelled)
          const Pill('Cancelled', foreground: AppColors.danger, background: AppColors.dangerContainer)
        else if (sale.paymentMode == PaymentMode.credit)
          const Pill('Udhaar', foreground: AppColors.warning, background: AppColors.warningContainer),
      ]),
      subtitle: Text(
        '${DateFormat('d MMM, hh:mm a').format(sale.createdAt)} · $who · '
        '${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'} · ${sale.createdByName}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 120),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            formatRupees(sale.payablePaise),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.titleSmall?.copyWith(
              decoration: sale.isCancelled ? TextDecoration.lineThrough : null,
              color: sale.isCancelled ? AppColors.muted : null,
            ),
          ),
          Text(sale.paymentMode.label, style: text.bodySmall?.copyWith(color: AppColors.muted)),
        ]),
      ),
    );
  }
}
