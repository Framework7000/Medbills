import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/customer_credit.dart';
import '../../domain/services/billing_calculator.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'customers_screen.dart' show balanceLabel;

/// Search existing customer accounts or open a new one.
Future<CustomerCredit?> pickCustomer(BuildContext context) {
  return showDialog<CustomerCredit>(context: context, builder: (_) => const _CustomerPicker());
}

class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customers = ref.watch(customersProvider);
    final q = _query.text.trim().toLowerCase();
    return AlertDialog(
      title: const Text('Udhaar customer'),
      contentPadding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _query,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Search name or mobile', prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass)),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s),
          Expanded(
            child: AsyncBody<List<CustomerCredit>>(
              value: customers,
              builder: (list) {
                final matches = list
                    .where((c) => q.isEmpty || c.name.toLowerCase().contains(q) || c.phoneNumber.contains(q))
                    .toList();
                if (matches.isEmpty) {
                  return EmptyState(icon: PhosphorIconsRegular.userMinus, title: list.isEmpty ? 'No customers yet' : 'No match');
                }
                return ListView.builder(
                  itemCount: matches.length,
                  itemBuilder: (context, i) {
                    final c = matches[i];
                    return ListTile(
                      title: Text(c.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(c.phoneNumber.isEmpty ? 'No phone' : c.phoneNumber),
                      trailing: Text(balanceLabel(c.outstandingBalancePaise),
                          style: TextStyle(color: c.isOverLimit ? AppColors.danger : null)),
                      onTap: () => Navigator.pop(context, c),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          icon: const Icon(PhosphorIconsRegular.userPlus),
          label: const Text('New customer'),
          onPressed: () async {
            final created = await showNewCustomerDialog(context, initialName: _query.text.trim());
            if (created != null && context.mounted) Navigator.pop(context, created);
          },
        ),
      ],
    );
  }
}

Future<CustomerCredit?> showNewCustomerDialog(BuildContext context, {String initialName = ''}) {
  return showDialog<CustomerCredit>(context: context, builder: (_) => _NewCustomerDialog(initialName: initialName));
}

class _NewCustomerDialog extends ConsumerStatefulWidget {
  const _NewCustomerDialog({required this.initialName});
  final String initialName;

  @override
  ConsumerState<_NewCustomerDialog> createState() => _NewCustomerDialogState();
}

class _NewCustomerDialogState extends ConsumerState<_NewCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initialName);
  final _phone = TextEditingController();
  final _limit = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _limit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = _phone.text.trim();
    final existing = (ref.read(customersProvider).valueOrNull ?? const <CustomerCredit>[])
        .where((c) => phone.isNotEmpty && c.phoneNumber.replaceAll(RegExp(r'\D'), '') == phone.replaceAll(RegExp(r'\D'), ''))
        .firstOrNull;
    if (existing != null) {
      showMessage(context, '${existing.name} already has an account with this number.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final customer = await ref.read(repositoryProvider)!.createCustomer(
            name: _name.text,
            phone: phone,
            creditLimitPaise: _limit.text.trim().isEmpty ? 0 : parseRupeesToPaise(_limit.text)!,
          );
      if (mounted) Navigator.pop(context, customer);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New udhaar customer'),
      content: DialogBody(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: Space.m),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Mobile'),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(15)],
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 10 ? 'Enter a 10-digit mobile number' : null;
              },
            ),
            const SizedBox(height: Space.m),
            TextFormField(
              controller: _limit,
              decoration: const InputDecoration(labelText: 'Credit limit ₹ (optional)', helperText: 'Leave empty for no limit'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => (v == null || v.trim().isEmpty || parseRupeesToPaise(v) != null) ? null : 'Enter an amount like 2000',
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

Future<void> showReceivePaymentDialog(BuildContext context, WidgetRef ref, CustomerCredit customer) async {
  final amount = TextEditingController();
  final notes = TextEditingController();
  final formKey = GlobalKey<FormState>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Payment from ${customer.name}'),
      content: DialogBody(
        child: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Outstanding ${formatRupees(customer.outstandingBalancePaise)}'),
            const SizedBox(height: Space.m),
            TextFormField(
              controller: amount,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Amount received ₹'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) {
                final paise = parseRupeesToPaise(v ?? '');
                if (paise == null || paise <= 0) return 'Enter an amount';
                if (paise > customer.outstandingBalancePaise) return 'More than the outstanding amount';
                return null;
              },
            ),
            const SizedBox(height: Space.m),
            TextFormField(controller: notes, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (formKey.currentState!.validate()) Navigator.pop(context, true);
          },
          child: const Text('Record payment'),
        ),
      ],
    ),
  );
  final paise = parseRupeesToPaise(amount.text);
  final note = notes.text;
  amount.dispose();
  notes.dispose();
  if (confirmed != true || paise == null || !context.mounted) return;
  try {
    await ref.read(repositoryProvider)!.receiveCreditPayment(customerId: customer.id, amountPaise: paise, notes: note);
    if (context.mounted) showMessage(context, 'Recorded ${formatRupees(paise)} from ${customer.name}.');
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
}
