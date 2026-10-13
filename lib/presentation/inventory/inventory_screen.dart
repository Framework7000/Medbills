import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/batch.dart';
import '../../domain/models/sale_invoice.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/stock_summary.dart';
import '../../state/providers.dart';
import '../sales/invoice_view.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'medicine_edit_dialog.dart';

enum _Filter {
  all('All'),
  low('Low'),
  out('Out of stock'),
  expiring('Expiring ≤ 90 days'),
  expired('Expired'),
  unclassified('Unclassified');

  const _Filter(this.label);
  final String label;

  bool matches(StockSummary s) => switch (this) {
        _Filter.all => true,
        _Filter.low => s.isLowStock,
        _Filter.out => s.isOutOfStock,
        _Filter.expiring => s.hasExpiringSoon,
        _Filter.expired => s.hasExpiredStock,
        _Filter.unclassified => !s.medicine.scheduleType.isSellable,
      };
}

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _query = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(stockIndexProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Stock')),
      body: AsyncBody<Map<String, StockSummary>>(
        value: index,
        builder: (index) {
          final q = _query.text.trim().toLowerCase();
          final all = index.values.toList();
          final shown = all
              .where(_filter.matches)
              .where((s) =>
                  q.isEmpty ||
                  s.medicine.name.toLowerCase().contains(q) ||
                  s.medicine.genericName.toLowerCase().contains(q) ||
                  s.medicine.manufacturer.toLowerCase().contains(q) ||
                  s.medicine.shelfLocation.toLowerCase() == q)
              .toList()
            ..sort((a, b) => a.medicine.name.toLowerCase().compareTo(b.medicine.name.toLowerCase()));
          int count(_Filter f) => all.where(f.matches).length;

          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 0),
              child: TextField(
                controller: _query,
                decoration: const InputDecoration(hintText: 'Search name, generic, manufacturer or shelf', prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass)),
                onChanged: (_) => setState(() {}),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                children: [
                  for (final f in _Filter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: Space.s),
                      child: ChoiceChip(
                        label: Text('${f.label} (${count(f)})'),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: shown.isEmpty
                  ? EmptyState(
                      icon: PhosphorIconsRegular.package,
                      title: all.isEmpty ? 'No medicines in stock yet' : 'Nothing here',
                      message: all.isEmpty ? 'Owners and pharmacists receive stock from Purchases.' : null,
                    )
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(indent: Space.l, endIndent: Space.l),
                      itemBuilder: (context, i) => _StockTile(stock: shown[i]),
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

class _StockTile extends StatelessWidget {
  const _StockTile({required this.stock});
  final StockSummary stock;

  @override
  Widget build(BuildContext context) {
    final m = stock.medicine;
    final text = Theme.of(context).textTheme;
    final next = stock.nextBatch;
    return ListTile(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => MedicineDetailScreen(medicineId: m.id)),
      ),
      title: Row(children: [
        Flexible(child: Text(m.name, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: Space.s),
        ScheduleBadge(m.scheduleType),
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${m.manufacturer} · ${m.packSizeLabel}${m.shelfLocation.isEmpty ? '' : ' · ${m.shelfLocation}'}',
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: Space.xs),
        StockFlags(stock),
      ]),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 140),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(PackUnits.describe(stock.sellableUnits, m.unitsPerPack),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
          if (next != null)
            Text('Exp ${DateFormat('MM/yy').format(next.expiryDate)}',
                style: text.bodySmall?.copyWith(color: next.daysToExpiry(stock.asOf) <= StockSummary.expiringSoonDays ? AppColors.warning : AppColors.muted)),
        ]),
      ),
    );
  }
}

class MedicineDetailScreen extends ConsumerWidget {
  const MedicineDetailScreen({super.key, required this.medicineId});
  final String medicineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(stockIndexProvider).valueOrNull?[medicineId];
    final user = ref.watch(currentUserProvider);
    final manager = user?.role.canManageStock ?? false;
    final text = Theme.of(context).textTheme;
    if (stock == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final m = stock.medicine;
    String rate(double r) => r.toStringAsFixed(0);

    return Scaffold(
      appBar: AppBar(
        title: Text(m.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (manager)
            IconButton(
              tooltip: 'Edit medicine',
              icon: const Icon(PhosphorIconsRegular.pencilSimple),
              onPressed: () => showMedicineEditor(context, initial: m),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Space.l),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: Space.s, runSpacing: Space.xs, children: [
                    ScheduleBadge(m.scheduleType),
                    StockFlags(stock),
                  ]),
                  const SizedBox(height: Space.s),
                  Text(m.genericName, style: text.bodyLarge),
                  Text('${m.manufacturer} · ${m.type}', style: text.bodyMedium?.copyWith(color: AppColors.muted)),
                  const Divider(height: Space.xl),
                  AmountRow('Pack', '${m.packSizeLabel} (${m.unitsPerPack} unit${m.unitsPerPack == 1 ? '' : 's'})'),
                  AmountRow('Schedule', m.scheduleType.label),
                  AmountRow('GST / HSN', '${rate(m.gstRate)}% / ${m.hsnCode}'),
                  AmountRow('Sellable stock', PackUnits.describe(stock.sellableUnits, m.unitsPerPack)),
                  AmountRow('Reorder below', PackUnits.describe(m.minStock, m.unitsPerPack)),
                  if (m.shelfLocation.isNotEmpty) AmountRow('Shelf', m.shelfLocation),
                  if ((m.barcode ?? '').isNotEmpty) AmountRow('Barcode', m.barcode!),
                ]),
              ),
            ),
            const SizedBox(height: Space.l),
            Text('Batches (nearest expiry first)', style: text.titleMedium),
            const SizedBox(height: Space.s),
            if (stock.batches.isEmpty)
              const Card(child: Padding(padding: EdgeInsets.all(Space.l), child: Text('No batches received yet.'))),
            for (final b in stock.batches) ...[
              _BatchCard(batch: b, unitsPerPack: m.unitsPerPack, asOf: stock.asOf, manager: manager),
              const SizedBox(height: Space.s),
            ],
            const SizedBox(height: Space.l),
            _RecentSales(medicineId: medicineId, manager: manager),
          ],
        ),
      ),
    );
  }
}

/// This medicine's own sale history and, for managers, the profit it has
/// actually made — not just the store-wide figure in Reports.
class _RecentSales extends ConsumerWidget {
  const _RecentSales({required this.medicineId, required this.manager});
  final String medicineId;
  final bool manager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final sales = ref.watch(recentSalesProvider).valueOrNull ?? const <SaleInvoice>[];
    final rows = <(SaleInvoice, SaleLine)>[
      for (final s in sales)
        if (!s.isCancelled)
          for (final l in s.lines)
            if (l.medicineId == medicineId) (s, l),
    ];
    final units = rows.fold<int>(0, (sum, r) => sum + r.$2.quantity);
    final revenue = rows.fold<int>(0, (sum, r) => sum + r.$2.lineTotalPaise);
    final cost = rows.fold<int>(0, (sum, r) => sum + r.$2.costPaise);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Sales', style: text.titleMedium),
      const SizedBox(height: Space.s),
      if (manager)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AmountRow('Units sold', '$units'),
              AmountRow('Revenue', formatRupees(revenue)),
              AmountRow('Cost', formatRupees(cost)),
              AmountRow('Profit', formatRupees(revenue - cost), emphasis: true),
            ]),
          ),
        ),
      const SizedBox(height: Space.s),
      if (rows.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(Space.l), child: Text('No sales of this medicine yet.')))
      else
        Card(
          child: Column(children: [
            for (var i = 0; i < rows.length && i < 20; i++) ...[
              if (i > 0) const Divider(height: 1, indent: Space.l, endIndent: Space.l),
              ListTile(
                onTap: () => showInvoice(context, rows[i].$1),
                title: Text('${PackUnits.describe(rows[i].$2.quantity, rows[i].$2.unitsPerPack)} · ${rows[i].$1.invoiceNumber}'),
                subtitle: Text(DateFormat('d MMM yyyy, hh:mm a').format(rows[i].$1.createdAt)),
                trailing: Text(formatRupees(rows[i].$2.lineTotalPaise), style: text.titleSmall),
              ),
            ],
            if (rows.length > 20)
              Padding(
                padding: const EdgeInsets.all(Space.m),
                child: Text('+ ${rows.length - 20} more — see Bills for the full history.',
                    style: text.bodySmall?.copyWith(color: AppColors.muted)),
              ),
          ]),
        ),
    ]);
  }
}

class _BatchCard extends ConsumerWidget {
  const _BatchCard({required this.batch, required this.unitsPerPack, required this.asOf, required this.manager});
  final Batch batch;
  final int unitsPerPack;
  final DateTime asOf;
  final bool manager;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final expired = batch.isExpiredAt(asOf);
    final days = batch.daysToExpiry(asOf);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.m),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: Space.s, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(batch.batchNumber, style: text.titleSmall),
                if (expired)
                  const Pill('Expired', foreground: AppColors.danger, background: AppColors.dangerContainer)
                else if (days <= StockSummary.expiringSoonDays)
                  Pill('$days days left', foreground: AppColors.warning, background: AppColors.warningContainer),
                if (batch.isBlocked)
                  const Pill('Blocked', foreground: AppColors.danger, background: AppColors.dangerContainer),
              ]),
              const SizedBox(height: Space.xs),
              Text(
                'Received ${DateFormat('d MMM yyyy').format(batch.createdAt)} · Exp ${DateFormat('MMM yyyy').format(batch.expiryDate)}',
                style: text.bodySmall?.copyWith(color: AppColors.muted),
              ),
              Text(
                'MRP ${formatRupees(batch.mrpPaise)}'
                '${manager ? ' · cost ${formatRupees(batch.purchasePricePaise)} · margin ${_margin(batch)}' : ''}',
                style: text.bodySmall?.copyWith(color: AppColors.muted),
              ),
              Text(PackUnits.describe(batch.quantity, unitsPerPack), style: text.bodyMedium),
            ]),
          ),
          if (manager)
            TextButton(
              onPressed: () async {
                try {
                  await ref.read(repositoryProvider)!.setBatchBlocked(batch.id, !batch.isBlocked);
                } catch (e) {
                  if (context.mounted) showMessage(context, friendlyError(e), error: true);
                }
              },
              child: Text(batch.isBlocked ? 'Unblock' : 'Block'),
            ),
        ]),
      ),
    );
  }

  static String _margin(Batch batch) {
    if (batch.mrpPaise <= 0) return '—';
    final pct = (batch.mrpPaise - batch.purchasePricePaise) * 100 / batch.mrpPaise;
    return '${pct.toStringAsFixed(0)}%';
  }
}
