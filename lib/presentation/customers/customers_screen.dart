import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/customer_credit.dart';
import '../../domain/services/billing_calculator.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'customer_dialogs.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _query = TextEditingController();
  bool _onlyOwing = true;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Udhaar (customer credit)'),
        actions: [
          IconButton(
            tooltip: 'New customer',
            icon: const Icon(PhosphorIconsRegular.userPlus),
            onPressed: () => showNewCustomerDialog(context),
          ),
        ],
      ),
      body: AsyncBody<List<CustomerCredit>>(
        value: customers,
        builder: (list) {
          final q = _query.text.trim().toLowerCase();
          final total = list.fold<int>(0, (s, c) => s + c.outstandingBalancePaise);
          final shown = list
              .where((c) => !_onlyOwing || c.outstandingBalancePaise > 0)
              .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.phoneNumber.contains(q))
              .toList()
            ..sort((a, b) => b.outstandingBalancePaise.compareTo(a.outstandingBalancePaise));
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Total outstanding ${formatRupees(total)}', style: text.titleMedium),
                const SizedBox(height: Space.s),
                TextField(
                  controller: _query,
                  decoration: const InputDecoration(hintText: 'Search name or mobile', prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass)),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Space.s),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    label: const Text('Only customers who owe'),
                    selected: _onlyOwing,
                    onSelected: (v) => setState(() => _onlyOwing = v),
                  ),
                ),
              ]),
            ),
            Expanded(
              child: shown.isEmpty
                  ? EmptyState(
                      icon: PhosphorIconsRegular.wallet,
                      title: list.isEmpty ? 'No udhaar customers yet' : 'Nobody matches',
                      message: list.isEmpty ? 'Choose "Udhaar" as the payment mode on a bill to start an account.' : null,
                    )
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const Divider(indent: Space.l, endIndent: Space.l),
                      itemBuilder: (context, i) {
                        final c = shown[i];
                        return ListTile(
                          title: Text(c.name, overflow: TextOverflow.ellipsis),
                          subtitle: Text(c.phoneNumber.isEmpty ? 'No phone' : c.phoneNumber),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(balanceLabel(c.outstandingBalancePaise), style: text.titleSmall),
                              if (c.isOverLimit)
                                const Pill('Over limit', foreground: AppColors.danger, background: AppColors.dangerContainer),
                            ],
                          ),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(builder: (_) => CustomerLedgerScreen(customerId: c.id)),
                          ),
                        );
                      },
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

/// A negative balance is money the customer has paid in advance.
String balanceLabel(int paise) => paise < 0 ? 'Advance ${formatRupees(-paise)}' : formatRupees(paise);

class CustomerLedgerScreen extends ConsumerWidget {
  const CustomerLedgerScreen({super.key, required this.customerId});
  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customersProvider).valueOrNull?.where((c) => c.id == customerId).firstOrNull;
    final ledger = ref.watch(ledgerProvider(customerId));
    final text = Theme.of(context).textTheme;
    if (customer == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: Text(customer.name, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(customer.outstandingBalancePaise < 0 ? 'Advance with store' : 'Outstanding',
                          style: text.bodyMedium?.copyWith(color: AppColors.muted)),
                      Text(formatRupees(customer.outstandingBalancePaise.abs()), style: text.headlineSmall),
                      Text(
                        '${customer.phoneNumber.isEmpty ? 'No phone' : customer.phoneNumber}'
                        '${customer.creditLimitPaise > 0 ? ' · limit ${formatRupees(customer.creditLimitPaise)}' : ''}',
                        style: text.bodySmall?.copyWith(color: AppColors.muted),
                      ),
                    ]),
                  ),
                  FilledButton.icon(
                    onPressed: customer.outstandingBalancePaise <= 0
                        ? null
                        : () => showReceivePaymentDialog(context, ref, customer),
                    icon: const Icon(PhosphorIconsRegular.coins),
                    label: const Text('Receive'),
                  ),
                ]),
              ),
            ),
          ),
          Expanded(
            child: AsyncBody<List<CreditLedgerEntry>>(
              value: ledger,
              builder: (entries) => entries.isEmpty
                  ? const EmptyState(icon: PhosphorIconsRegular.clockCounterClockwise, title: 'No entries yet')
                  : ListView.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(indent: Space.l, endIndent: Space.l),
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final increases = e.type == CreditEntryType.creditSale;
                        return ListTile(
                          leading: Icon(increases ? PhosphorIconsRegular.arrowUp : PhosphorIconsRegular.arrowDown,
                              color: increases ? AppColors.danger : AppColors.accent),
                          title: Text(e.type.label + (e.invoiceNumber == null ? '' : ' · ${e.invoiceNumber}')),
                          subtitle: Text(
                            '${DateFormat('dd MMM yyyy, hh:mm a').format(e.timestamp)} · ${e.createdByName}'
                            '${e.notes.isEmpty ? '' : '\n${e.notes}'}',
                          ),
                          isThreeLine: e.notes.isNotEmpty,
                          trailing: Text('${increases ? '+' : '−'}${formatRupees(e.amountPaise)}', style: text.titleSmall),
                        );
                      },
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}
