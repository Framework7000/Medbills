import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../domain/models/supplier_account.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/day_book.dart';
import '../../domain/services/supplier_ledger.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/charts.dart';
import '../widgets/common.dart';
import 'supplier_dialogs.dart';

final _dates = DateFormat('d MMM yyyy');

void _noop() {}

/// Purchases (cash and udhaar), payments to distributors and MRs, and what
/// is still owed — one place, the same on every device.
class PurchasePaymentScreen extends ConsumerWidget {
  const PurchasePaymentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledgerAsync = ref.watch(supplierLedgerProvider);
    final bills = ref.watch(supplierBillsProvider).valueOrNull ?? const <SupplierBill>[];
    final payments = ref.watch(supplierPaymentsProvider).valueOrNull ?? const <SupplierPayment>[];
    final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase & Payment'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Add',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.m),
              child: IgnorePointer(
                child: FilledButton.tonalIcon(
                    onPressed: _noop, icon: const Icon(PhosphorIconsRegular.plus), label: const Text('Add')),
              ),
            ),
            onSelected: (v) => switch (v) {
              'bill' => showSupplierBillDialog(context),
              'old' => showSupplierBillDialog(context, oldBill: true),
              'pay' => showSupplierPaymentDialog(context),
              _ => showDistributorDialog(context),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'bill', child: ListTile(leading: Icon(PhosphorIconsRegular.receipt), title: Text('Purchase bill'))),
              PopupMenuItem(value: 'old', child: ListTile(leading: Icon(PhosphorIconsRegular.clockCounterClockwise), title: Text('Old bill (udhaar)'))),
              PopupMenuItem(value: 'pay', child: ListTile(leading: Icon(PhosphorIconsRegular.handCoins), title: Text('Payment'))),
              PopupMenuItem(value: 'dist', child: ListTile(leading: Icon(PhosphorIconsRegular.truck), title: Text('Distributor / MR'))),
            ],
          ),
        ],
      ),
      body: AsyncBody<SupplierLedger>(
        value: ledgerAsync,
        builder: (ledger) {
          final today = DateTime(now.year, now.month, now.day);
          final day = DayBook.build(from: today, to: today.add(const Duration(days: 1)), sales: const [], bills: bills, payments: payments).total;
          final month = DayBook.build(
                  from: DateTime(now.year, now.month), to: DateTime(now.year, now.month + 1), sales: const [], bills: bills, payments: payments)
              .total;
          final reminders = ledger.remindersAt(now);
          final top = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            StatGrid(children: [
              StatTile(
                label: 'Udhaar owed',
                paise: ledger.totalOutstandingPaise,
                color: AppColors.danger,
                caption: '${ledger.accounts.values.where((a) => a.outstandingPaise > 0).length} distributors',
              ),
              StatTile(
                label: 'Purchase today',
                paise: day.purchasePaise,
                caption: 'Cash ${formatRupees(day.cashPurchasePaise)} · Udhaar ${formatRupees(day.creditPurchasePaise)}',
              ),
              StatTile(
                label: 'Paid today',
                paise: day.paidOutPaise,
                color: AppColors.warning,
                caption: 'Cash buys ${formatRupees(day.cashPurchasePaise)} + payments ${formatRupees(day.paymentsPaise)}',
              ),
              StatTile(
                label: 'This month',
                paise: month.purchasePaise,
                caption: 'Bought · paid ${formatRupees(month.paidOutPaise)}',
              ),
            ]),
            if (reminders.isNotEmpty) ...[
              const SizedBox(height: Space.m),
              _Reminders(reminders: reminders, now: now),
            ],
          ]);
          final sections = [
            _Section(title: 'Purchases', icon: PhosphorIconsRegular.receipt, child: _BillList(bills: bills, ledger: ledger)),
            _Section(title: 'Payments', icon: PhosphorIconsRegular.handCoins, child: _PaymentList(payments: payments)),
            _Section(title: 'Distributors', icon: PhosphorIconsRegular.truck, child: _DistributorList(ledger: ledger)),
          ];
          return LayoutBuilder(builder: (context, c) {
            if (c.maxWidth >= 1100) {
              return Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  top,
                  const SizedBox(height: Space.l),
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (var i = 0; i < sections.length; i++) ...[
                        if (i > 0) const SizedBox(width: Space.l),
                        Expanded(child: Card(margin: EdgeInsets.zero, child: sections[i])),
                      ],
                    ]),
                  ),
                ]),
              );
            }
            return DefaultTabController(
              length: 3,
              child: NestedScrollView(
                headerSliverBuilder: (_, _) => [
                  SliverPadding(padding: const EdgeInsets.all(Space.l), sliver: SliverToBoxAdapter(child: top)),
                  const SliverToBoxAdapter(
                    child: TabBar(tabs: [Tab(text: 'Purchases'), Tab(text: 'Payments'), Tab(text: 'Distributors')]),
                  ),
                ],
                body: TabBarView(children: [for (final s in sections) s.child]),
              ),
            );
          });
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.s),
          child: Row(children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: Space.s),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: child),
      ]);
}

class _Reminders extends StatelessWidget {
  const _Reminders({required this.reminders, required this.now});
  final List<PaymentReminder> reminders;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final total = reminders.fold<int>(0, (s, r) => s + r.bill.balancePaise);
    return Card(
      key: const ValueKey('payment-reminders'),
      margin: EdgeInsets.zero,
      color: AppColors.warningContainer,
      child: Padding(
        padding: const EdgeInsets.all(Space.m),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(PhosphorIconsRegular.bellRinging, color: AppColors.warning),
            const SizedBox(width: Space.s),
            Expanded(child: Text('To pay: ${formatRupees(total)}', style: text.titleMedium?.copyWith(color: AppColors.warning))),
          ]),
          const SizedBox(height: Space.xs),
          for (final r in reminders.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Expanded(
                  child: Text(
                    '${r.account.distributor.name} · ${r.bill.bill.billNumber.isEmpty ? _dates.format(r.bill.bill.billDate) : 'bill ${r.bill.bill.billNumber}'}'
                    ' · ${_due(r.bill)}',
                    style: text.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
                Text(formatRupees(r.bill.balancePaise), style: text.titleSmall),
                const SizedBox(width: Space.s),
                FilledButton.tonal(
                  onPressed: () => showSupplierPaymentDialog(context, forBill: r.bill),
                  child: const Text('Pay'),
                ),
              ]),
            ),
          if (reminders.length > 5)
            Text('+ ${reminders.length - 5} more under Distributors', style: text.bodySmall),
        ]),
      ),
    );
  }

  String _due(BillBalance b) {
    final late = b.daysOverdue(now);
    if (late > 0) return '$late day${late == 1 ? '' : 's'} late';
    if (late == 0) return 'due today';
    return 'due in ${-late} day${late == -1 ? '' : 's'}';
  }
}

enum _BillFilter { all, cash, udhaar, unpaid }

class _BillList extends StatefulWidget {
  const _BillList({required this.bills, required this.ledger});
  final List<SupplierBill> bills;
  final SupplierLedger ledger;

  @override
  State<_BillList> createState() => _BillListState();
}

class _BillListState extends State<_BillList> {
  _BillFilter _filter = _BillFilter.all;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final balances = {
      for (final a in widget.ledger.accounts.values)
        for (final b in a.creditBills) b.bill.id: b,
    };
    final shown = widget.bills.where((b) {
      if (b.cancelled) return false;
      return switch (_filter) {
        _BillFilter.all => true,
        _BillFilter.cash => !b.isCredit,
        _BillFilter.udhaar => b.isCredit,
        _BillFilter.unpaid => b.isCredit && !(balances[b.id]?.isPaid ?? false),
      };
    }).toList();
    final total = shown.fold<int>(0, (s, b) => s + b.totalPaise);
    return Column(children: [
      SizedBox(
        height: 52,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.s),
          children: [
            for (final f in _BillFilter.values)
              Padding(
                padding: const EdgeInsets.only(right: Space.s),
                child: ChoiceChip(
                  label: Text(switch (f) {
                    _BillFilter.all => 'All',
                    _BillFilter.cash => 'Cash',
                    _BillFilter.udhaar => 'Udhaar',
                    _BillFilter.unpaid => 'Unpaid',
                  }),
                  selected: _filter == f,
                  onSelected: (_) => setState(() => _filter = f),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l),
        child: AmountRow('${shown.length} bill${shown.length == 1 ? '' : 's'}', formatRupees(total)),
      ),
      Expanded(
        child: shown.isEmpty
            ? const EmptyState(
                icon: PhosphorIconsRegular.receipt,
                title: 'No bills',
                message: 'Stock received with a distributor\'s name appears here. Old bills: + → Old bill.',
              )
            : ListView.separated(
                itemCount: shown.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: Space.l, endIndent: Space.l),
                itemBuilder: (context, i) {
                  final b = shown[i];
                  final bal = balances[b.id];
                  final (label, fg, bg) = !b.isCredit
                      ? ('Cash', AppColors.accent, AppColors.primaryContainer)
                      : bal == null || bal.isPaid
                          ? ('Paid', AppColors.accent, AppColors.primaryContainer)
                          : bal.isPartlyPaid
                              ? ('Part paid', AppColors.warning, AppColors.warningContainer)
                              : ('Udhaar', AppColors.danger, AppColors.dangerContainer);
                  return _EditableTile(
                    onEdit: () => showSupplierBillDialog(context, bill: b),
                    title: Row(children: [
                      Flexible(child: Text(b.distributorName, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: Space.s),
                      Pill(label, foreground: fg, background: bg),
                      if (b.isOpening) ...[
                        const SizedBox(width: Space.xs),
                        const Pill('Old', foreground: AppColors.muted, background: AppColors.infoContainer),
                      ],
                    ]),
                    subtitle: '${b.billNumber.isEmpty ? 'No bill no.' : 'Bill ${b.billNumber}'} · ${_dates.format(b.billDate)}'
                        '${bal != null && bal.isPartlyPaid ? ' · ${formatRupees(bal.balancePaise)} left' : ''}',
                    trailing: Text(formatRupees(b.totalPaise), style: text.titleSmall),
                  );
                },
              ),
      ),
    ]);
  }
}

class _PaymentList extends StatelessWidget {
  const _PaymentList({required this.payments});
  final List<SupplierPayment> payments;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shown = payments.where((p) => !p.cancelled).toList();
    if (shown.isEmpty) {
      return EmptyState(
        icon: PhosphorIconsRegular.handCoins,
        title: 'No payments yet',
        message: 'Record money paid to a distributor or MR.',
        action: FilledButton.icon(
          onPressed: () => showSupplierPaymentDialog(context),
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('Payment'),
        ),
      );
    }
    return ListView.separated(
      itemCount: shown.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: Space.l, endIndent: Space.l),
      itemBuilder: (context, i) {
        final p = shown[i];
        return _EditableTile(
          onEdit: () => showSupplierPaymentDialog(context, payment: p),
          title: Text(p.distributorName, overflow: TextOverflow.ellipsis),
          subtitle: '${p.via.label}${p.billNumber.isEmpty ? '' : ' · bill ${p.billNumber}'} · ${_dates.format(p.paidOn)}'
              '${p.note.isEmpty ? '' : ' · ${p.note}'}',
          trailing: Text(formatRupees(p.amountPaise), style: text.titleSmall?.copyWith(color: AppColors.warning)),
        );
      },
    );
  }
}

class _DistributorList extends StatelessWidget {
  const _DistributorList({required this.ledger});
  final SupplierLedger ledger;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final list = ledger.sorted;
    if (list.isEmpty) {
      return EmptyState(
        icon: PhosphorIconsRegular.truck,
        title: 'No distributors yet',
        action: FilledButton.icon(
          onPressed: () => showDistributorDialog(context),
          icon: const Icon(PhosphorIconsRegular.plus),
          label: const Text('Distributor'),
        ),
      );
    }
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: Space.l, endIndent: Space.l),
      itemBuilder: (context, i) {
        final a = list[i];
        final owed = a.outstandingPaise;
        return _EditableTile(
          onEdit: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => DistributorScreen(distributorId: a.distributor.id)),
          ),
          title: Text(a.distributor.name, overflow: TextOverflow.ellipsis),
          subtitle: '${a.bills.length} bill${a.bills.length == 1 ? '' : 's'} · paid ${formatRupees(a.paidPaise)}'
              '${a.nextDue == null ? '' : ' · next due ${DateFormat('d MMM').format(a.nextDue!.dueOn)}'}',
          trailing: Text(
            owed > 0 ? formatRupees(owed) : (owed < 0 ? 'Advance ${formatRupees(-owed)}' : 'Clear'),
            style: text.titleSmall?.copyWith(color: owed > 0 ? AppColors.danger : AppColors.accent),
          ),
        );
      },
    );
  }
}

/// A list row that opens for editing with one tap or click (PC and phone).
class _EditableTile extends StatelessWidget {
  const _EditableTile({required this.onEdit, required this.title, required this.subtitle, required this.trailing});
  final VoidCallback onEdit;
  final Widget title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => ListTile(onTap: onEdit, title: title, subtitle: Text(subtitle), trailing: trailing);
}

/// One distributor: what is owed, every bill and payment, and Pay.
class DistributorScreen extends ConsumerWidget {
  const DistributorScreen({super.key, required this.distributorId});
  final String distributorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(supplierLedgerProvider).valueOrNull;
    final a = ledger?.accounts[distributorId];
    final text = Theme.of(context).textTheme;
    if (a == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final now = DateTime.now();
    final balances = {for (final b in a.creditBills) b.bill.id: b};
    return Scaffold(
      appBar: AppBar(
        title: Text(a.distributor.name, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Edit name, phone, credit days',
            icon: const Icon(PhosphorIconsRegular.pencilSimple),
            onPressed: () => showDistributorDialog(context, distributor: a.distributor),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showSupplierPaymentDialog(context, distributorName: a.distributor.name),
        icon: const Icon(PhosphorIconsRegular.handCoins),
        label: const Text('Pay'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, 96), children: [
        StatGrid(children: [
          StatTile(label: 'Udhaar owed', paise: a.outstandingPaise, color: AppColors.danger),
          StatTile(label: 'Credit bills', paise: a.creditBilledPaise),
          StatTile(label: 'Paid', paise: a.paidPaise, color: AppColors.warning),
          StatTile(label: 'Cash bills', paise: a.cashBilledPaise),
        ]),
        if (a.distributor.phone.isNotEmpty) ...[
          const SizedBox(height: Space.s),
          Text('Phone ${a.distributor.phone}${a.distributor.gstin.isEmpty ? '' : ' · GSTIN ${a.distributor.gstin}'}',
              style: text.bodyMedium?.copyWith(color: AppColors.muted)),
        ],
        const SizedBox(height: Space.l),
        Text('Bills', style: text.titleMedium),
        Card(
          child: Column(children: [
            if (a.bills.isEmpty) const ListTile(title: Text('No bills')),
            for (final b in a.bills)
              _EditableTile(
                onEdit: () => showSupplierBillDialog(context, bill: b),
                title: Text(b.billNumber.isEmpty ? _dates.format(b.billDate) : 'Bill ${b.billNumber}'),
                subtitle: '${_dates.format(b.billDate)} · ${b.isCredit ? 'Udhaar' : 'Cash'}${b.isOpening ? ' · old bill' : ''}'
                    '${balances[b.id] == null ? '' : balances[b.id]!.isPaid ? ' · paid' : ' · ${formatRupees(balances[b.id]!.balancePaise)} left'
                        '${balances[b.id]!.isOverdueAt(now) ? ' (${balances[b.id]!.daysOverdue(now)} days late)' : ''}'}',
                trailing: Text(formatRupees(b.totalPaise), style: text.titleSmall),
              ),
          ]),
        ),
        const SizedBox(height: Space.l),
        Text('Payments', style: text.titleMedium),
        Card(
          child: Column(children: [
            if (a.payments.isEmpty) const ListTile(title: Text('No payments')),
            for (final p in a.payments)
              _EditableTile(
                onEdit: () => showSupplierPaymentDialog(context, payment: p),
                title: Text(formatRupees(p.amountPaise)),
                subtitle: '${p.via.label}${p.billNumber.isEmpty ? '' : ' · bill ${p.billNumber}'} · ${_dates.format(p.paidOn)}',
                trailing: const Icon(PhosphorIconsRegular.pencilSimple, size: 18),
              ),
          ]),
        ),
      ]),
    );
  }
}
