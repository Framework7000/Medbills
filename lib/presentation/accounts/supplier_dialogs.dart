import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../domain/models/supplier_account.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/supplier_ledger.dart';
import '../../state/providers.dart';
import '../purchases/distributor_field.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _plain(int paise) => formatRupees(paise, symbol: false).replaceAll(',', '');

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initial, {DateTime? last}) => showDatePicker(
      context: context,
      firstDate: DateTime(2015),
      lastDate: last ?? DateTime.now().add(const Duration(days: 365)),
      initialDate: initial,
    );

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.date, required this.onTap, this.onClear});
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: date != null && onClear != null
                ? IconButton(icon: const Icon(PhosphorIconsRegular.x, size: 16), onPressed: onClear)
                : const Icon(PhosphorIconsRegular.calendar),
          ),
          child: Text(date == null ? '—' : DateFormat('d MMM yyyy').format(date!)),
        ),
      );
}

// ------------------------------------------------------------------ bills

/// Add or edit a supplier bill: a purchase in cash or on credit, or an old
/// bill still owed from before (opening dues).
Future<void> showSupplierBillDialog(BuildContext context, {SupplierBill? bill, bool oldBill = false}) =>
    showDialog<void>(context: context, builder: (_) => _SupplierBillDialog(bill: bill, oldBill: oldBill));

class _SupplierBillDialog extends ConsumerStatefulWidget {
  const _SupplierBillDialog({this.bill, this.oldBill = false});
  final SupplierBill? bill;
  final bool oldBill;

  @override
  ConsumerState<_SupplierBillDialog> createState() => _SupplierBillDialogState();
}

class _SupplierBillDialogState extends ConsumerState<_SupplierBillDialog> {
  late final b = widget.bill;
  late final _name = TextEditingController(text: b?.distributorName ?? '');
  late final _number = TextEditingController(text: b?.billNumber ?? '');
  late final _amount = TextEditingController(text: b == null ? '' : _plain(b!.totalPaise));
  late final _note = TextEditingController(text: b?.note ?? '');
  late DateTime _date = b?.billDate ?? _today();
  late DateTime? _due = b?.dueDate;
  late PurchasePayment _payment = b?.payment ?? PurchasePayment.credit;
  late bool _opening = b?.isOpening ?? widget.oldBill;
  bool _busy = false;
  String? _error;

  Future<void> _save({bool remove = false}) async {
    final repo = ref.read(repositoryProvider)!;
    final name = Distributor.tidyName(_name.text);
    final distributorId = Distributor.idFor(name);
    final amount = parseRupeesToPaise(_amount.text);
    if (!remove && (amount == null || amount <= 0)) {
      setState(() => _error = 'Enter the bill amount.');
      return;
    }
    if (distributorId.isEmpty) {
      setState(() => _error = 'Enter the distributor\'s name.');
      return;
    }
    final now = DateTime.now();
    final user = repo.actor;
    final payment = _opening ? PurchasePayment.credit : _payment;
    final SupplierBill next;
    if (b == null) {
      next = SupplierBill(
        id: SupplierBill.idFor(distributorId, _number.text.trim().isEmpty ? repo.newId() : _number.text, _date),
        storeId: repo.storeId,
        distributorId: distributorId,
        distributorName: name,
        billNumber: _number.text.trim(),
        billDate: _date,
        amountPaise: amount,
        payment: payment,
        dueDate: payment == PurchasePayment.credit ? _due : null,
        isOpening: _opening,
        note: _note.text.trim(),
        createdAt: now,
        createdBy: user.uid,
        createdByName: user.name,
      );
      final existing = (ref.read(supplierBillsProvider).valueOrNull ?? const <SupplierBill>[])
          .where((x) => x.id == next.id && !x.cancelled)
          .firstOrNull;
      if (existing != null) {
        setState(() => _error = 'Bill ${next.billNumber} from $name is already entered '
            '(${formatRupees(existing.totalPaise)}). Open it from the list to change it.');
        return;
      }
    } else {
      next = b!.copyWith(
        distributorId: distributorId,
        distributorName: name,
        billNumber: _number.text.trim(),
        billDate: _date,
        amountPaise: amount ?? b!.totalPaise,
        payment: payment,
        dueDate: _due,
        clearDueDate: _due == null || payment == PurchasePayment.cash,
        isOpening: _opening,
        note: _note.text.trim(),
        cancelled: remove,
      );
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.saveSupplierBill(next);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _number, _amount, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: Space.m);
    final credit = _opening || _payment == PurchasePayment.credit;
    return AlertDialog(
      title: Text(b == null ? (widget.oldBill ? 'Add old bill (udhaar)' : 'Add purchase bill') : 'Edit bill'),
      content: DialogBody(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DistributorField(controller: _name),
          gap,
          Row(children: [
            Expanded(child: TextField(controller: _number, decoration: const InputDecoration(labelText: 'Bill no.'))),
            const SizedBox(width: Space.m),
            Expanded(
              child: _DateField(
                label: 'Bill date',
                date: _date,
                onTap: () async {
                  final d = await _pickDate(context, _date, last: DateTime.now());
                  if (d != null) setState(() => _date = d);
                },
              ),
            ),
          ]),
          gap,
          TextField(
            key: const ValueKey('bill-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: InputDecoration(
              labelText: 'Bill amount (total)',
              prefixText: '₹ ',
              helperText: b != null && b!.itemsPaise > 0 ? 'Stock received on this bill: ${formatRupees(b!.itemsPaise)}' : null,
            ),
          ),
          gap,
          if (!_opening) PaymentToggle(value: _payment, onChanged: (p) => setState(() => _payment = p)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _opening,
            onChanged: (v) => setState(() => _opening = v),
            title: const Text('Old bill (owed from before)'),
            subtitle: const Text('Counts in udhaar, not in this period\'s purchases'),
          ),
          if (credit)
            _DateField(
              label: 'Pay by (reminder)',
              date: _due,
              onTap: () async {
                final d = await _pickDate(context, _due ?? _date.add(const Duration(days: 30)));
                if (d != null) setState(() => _due = d);
              },
              onClear: () => setState(() => _due = null),
            ),
          if (credit && _due == null)
            Text('No date: reminded 30 days after the bill date.', style: text.bodySmall?.copyWith(color: AppColors.muted)),
          gap,
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          if (_error != null) ...[
            gap,
            Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.danger)),
          ],
        ]),
      ),
      actions: [
        if (b != null && !b!.cancelled)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final ok = await confirmDialog(context,
                        title: 'Remove this bill?',
                        message: 'It stays on record as removed and no longer counts in totals or udhaar.',
                        confirmLabel: 'Remove',
                        danger: true);
                    if (ok) _save(remove: true);
                  },
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

// --------------------------------------------------------------- payments

/// Pay a distributor or MR: how much, how, for which bill, when.
Future<void> showSupplierPaymentDialog(
  BuildContext context, {
  SupplierPayment? payment,
  String? distributorName,
  BillBalance? forBill,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _SupplierPaymentDialog(payment: payment, distributorName: distributorName, forBill: forBill),
    );

class _SupplierPaymentDialog extends ConsumerStatefulWidget {
  const _SupplierPaymentDialog({this.payment, this.distributorName, this.forBill});
  final SupplierPayment? payment;
  final String? distributorName;
  final BillBalance? forBill;

  @override
  ConsumerState<_SupplierPaymentDialog> createState() => _SupplierPaymentDialogState();
}

class _SupplierPaymentDialogState extends ConsumerState<_SupplierPaymentDialog> {
  late final p = widget.payment;
  late final _name = TextEditingController(
      text: p?.distributorName ?? widget.forBill?.bill.distributorName ?? widget.distributorName ?? '');
  late final _amount = TextEditingController(
      text: p != null ? _plain(p!.amountPaise) : widget.forBill != null ? _plain(widget.forBill!.balancePaise) : '');
  late final _bill = TextEditingController(text: p?.billNumber ?? widget.forBill?.bill.billNumber ?? '');
  late final _note = TextEditingController(text: p?.note ?? '');
  late PaidVia _via = p?.via ?? PaidVia.cash;
  late DateTime _date = p?.paidOn ?? _today();
  bool _busy = false;
  String? _error;

  Future<void> _save({bool remove = false}) async {
    final repo = ref.read(repositoryProvider)!;
    final name = Distributor.tidyName(_name.text);
    final id = Distributor.idFor(name);
    final amount = parseRupeesToPaise(_amount.text);
    if (id.isEmpty) {
      setState(() => _error = 'Enter who was paid.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount paid.');
      return;
    }
    final now = DateTime.now();
    final next = p == null
        ? SupplierPayment(
            id: repo.newId(),
            storeId: repo.storeId,
            distributorId: id,
            distributorName: name,
            amountPaise: amount,
            via: _via,
            billNumber: _bill.text.trim(),
            paidOn: _date,
            note: _note.text.trim(),
            createdAt: now,
            createdBy: repo.actor.uid,
            createdByName: repo.actor.name,
          )
        : p!.copyWith(
            distributorId: id,
            distributorName: name,
            amountPaise: amount,
            via: _via,
            billNumber: _bill.text.trim(),
            paidOn: _date,
            note: _note.text.trim(),
            cancelled: remove,
          );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.saveSupplierPayment(next);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _amount, _bill, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: Space.m);
    final ledger = ref.watch(supplierLedgerProvider).valueOrNull;
    final account = ledger?.accounts[Distributor.idFor(_name.text)];
    final unpaid = account?.unpaid ?? const <BillBalance>[];
    return AlertDialog(
      title: Text(p == null ? 'Pay distributor / MR' : 'Edit payment'),
      content: DialogBody(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          DistributorField(controller: _name, label: 'Paid to', onChanged: (_) => setState(() {})),
          if (account != null && account.outstandingPaise > 0) ...[
            const SizedBox(height: Space.xs),
            Text('Udhaar with them: ${formatRupees(account.outstandingPaise)}',
                style: text.bodySmall?.copyWith(color: AppColors.warning)),
          ],
          gap,
          TextField(
            key: const ValueKey('payment-amount'),
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(labelText: 'Amount paid', prefixText: '₹ '),
          ),
          gap,
          Wrap(spacing: Space.s, runSpacing: Space.s, children: [
            for (final v in PaidVia.values)
              ChoiceChip(label: Text(v.label), selected: _via == v, onSelected: (_) => setState(() => _via = v)),
          ]),
          gap,
          Row(children: [
            Expanded(child: TextField(controller: _bill, decoration: const InputDecoration(labelText: 'For bill no. (optional)'))),
            const SizedBox(width: Space.m),
            Expanded(
              child: _DateField(
                label: 'Paid on',
                date: _date,
                onTap: () async {
                  final d = await _pickDate(context, _date, last: DateTime.now());
                  if (d != null) setState(() => _date = d);
                },
              ),
            ),
          ]),
          if (unpaid.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Wrap(spacing: Space.s, runSpacing: Space.xs, children: [
              for (final u in unpaid.take(6))
                ActionChip(
                  label: Text('${u.bill.billNumber.isEmpty ? DateFormat('d MMM').format(u.bill.billDate) : u.bill.billNumber} · '
                      '${formatRupees(u.balancePaise)}'),
                  onPressed: () => setState(() {
                    _bill.text = u.bill.billNumber;
                    _amount.text = _plain(u.balancePaise);
                  }),
                ),
            ]),
          ],
          gap,
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          if (_error != null) ...[
            gap,
            Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.danger)),
          ],
        ]),
      ),
      actions: [
        if (p != null && !p!.cancelled)
          TextButton(
            onPressed: _busy
                ? null
                : () async {
                    final ok = await confirmDialog(context,
                        title: 'Remove this payment?',
                        message: 'It stays on record as removed and the udhaar goes back up.',
                        confirmLabel: 'Remove',
                        danger: true);
                    if (ok) _save(remove: true);
                  },
            child: const Text('Remove', style: TextStyle(color: AppColors.danger)),
          ),
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}

// ----------------------------------------------------------- distributors

Future<void> showDistributorDialog(BuildContext context, {Distributor? distributor}) =>
    showDialog<void>(context: context, builder: (_) => _DistributorDialog(distributor: distributor));

class _DistributorDialog extends ConsumerStatefulWidget {
  const _DistributorDialog({this.distributor});
  final Distributor? distributor;

  @override
  ConsumerState<_DistributorDialog> createState() => _DistributorDialogState();
}

class _DistributorDialogState extends ConsumerState<_DistributorDialog> {
  late final d = widget.distributor;
  late final _name = TextEditingController(text: d?.name ?? '');
  late final _phone = TextEditingController(text: d?.phone ?? '');
  late final _gstin = TextEditingController(text: d?.gstin ?? '');
  late final _days = TextEditingController(text: '${d?.creditDays ?? Distributor.defaultCreditDays}');
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final repo = ref.read(repositoryProvider)!;
    final name = Distributor.tidyName(_name.text);
    // Renaming keeps the same distributor (and its bills); a new one gets
    // the id its name gives.
    final next = (d ??
            Distributor(id: Distributor.idFor(name), storeId: repo.storeId, name: name, createdAt: DateTime.now()))
        .copyWith(
      name: name,
      phone: _phone.text.trim(),
      gstin: _gstin.text.trim().toUpperCase(),
      creditDays: int.tryParse(_days.text) ?? Distributor.defaultCreditDays,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await repo.saveDistributor(next);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _gstin, _days]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.m);
    return AlertDialog(
      title: Text(d == null ? 'Add distributor / MR' : 'Edit distributor'),
      content: DialogBody(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name'), textCapitalization: TextCapitalization.words),
          gap,
          TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone),
          gap,
          TextField(controller: _gstin, decoration: const InputDecoration(labelText: 'GSTIN (optional)')),
          gap,
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: const InputDecoration(labelText: 'Credit days (for reminders)', suffixText: 'days'),
          ),
          if (_error != null) ...[
            gap,
            Text(_error!, style: TextStyle(color: AppColors.danger, fontSize: Theme.of(context).textTheme.bodySmall?.fontSize)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
