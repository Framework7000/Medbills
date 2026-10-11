import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/customer_credit.dart';
import '../../domain/models/sale_invoice.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/gs1_parser.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/schedule_h1_compliance.dart';
import '../../domain/services/stock_summary.dart';
import '../../state/providers.dart';
import '../customers/customer_dialogs.dart';
import '../sales/invoice_view.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'prescription_dialog.dart';
import 'quantity_dialog.dart';

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _checkingOut = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim();

  List<StockSummary> _results(Map<String, StockSummary> index) {
    final q = _query.toLowerCase();
    if (q.isEmpty) return const [];
    final matches = index.values.where((s) {
      final m = s.medicine;
      return m.name.toLowerCase().contains(q) ||
          m.genericName.toLowerCase().contains(q) ||
          m.manufacturer.toLowerCase().contains(q) ||
          (m.barcode != null && m.barcode == _query);
    }).toList()
      ..sort((a, b) {
        if (a.isOutOfStock != b.isOutOfStock) return a.isOutOfStock ? 1 : -1;
        final aStarts = a.medicine.name.toLowerCase().startsWith(q);
        final bStarts = b.medicine.name.toLowerCase().startsWith(q);
        if (aStarts != bStarts) return aStarts ? -1 : 1;
        return a.medicine.name.toLowerCase().compareTo(b.medicine.name.toLowerCase());
      });
    return matches.take(40).toList();
  }

  /// Enter in the search box: a scanned barcode (EAN or GS1 DataMatrix) adds
  /// its medicine directly; otherwise the top match is picked.
  void _onSearchSubmitted(Map<String, StockSummary> index) {
    if (_query.isEmpty) return;
    final parsed = Gs1Parser.parse(_query);
    final gtin = parsed.gtin;
    if (gtin != null) {
      final match = index.values.where((s) {
        final code = s.medicine.barcode;
        return code != null && (code == gtin || code.endsWith(gtin) || gtin.endsWith(code));
      }).firstOrNull;
      if (match != null) {
        _pick(match);
        return;
      }
    }
    final results = _results(index);
    if (results.isNotEmpty) {
      _pick(results.first);
    } else {
      showMessage(context, 'No medicine matches "$_query".');
    }
  }

  Future<void> _pick(StockSummary stock) async {
    if (!stock.medicine.scheduleType.isSellable) {
      showMessage(context, '${stock.medicine.name} is unclassified. A pharmacist must set its schedule in Stock first.',
          error: true);
      return;
    }
    final cart = ref.read(cartProvider);
    final inBill = stock.sellableBatches.fold<int>(0, (sum, b) => sum + (cart.unitsByBatch[b.id] ?? 0));
    if (stock.sellableUnits - inBill <= 0) {
      showMessage(context, stock.isOutOfStock ? '${stock.medicine.name} is out of stock.' : 'All available stock is already on this bill.',
          error: true);
      return;
    }
    final units = await showQuantityDialog(context, stock: stock, alreadyInBill: inBill);
    if (units == null || !mounted) return;
    try {
      ref.read(cartProvider.notifier).addMedicine(stock.medicine, stock.batches, units);
      _search.clear();
      setState(() {});
      _searchFocus.requestFocus();
    } catch (e) {
      showMessage(context, friendlyError(e), error: true);
    }
  }

  /// [sheetContext] is the phone checkout sheet, closed once the sale is saved.
  Future<void> _checkout({BuildContext? sheetContext}) async {
    if (_checkingOut) return;
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      showMessage(context, 'Add a medicine to the bill first.');
      return;
    }
    if (ScheduleCompliance.hasUnclassified(cart.schedules)) {
      showMessage(context, 'This bill has an unclassified medicine. Set its schedule in Stock before selling.',
          error: true);
      return;
    }
    if (cart.paymentMode == PaymentMode.credit && cart.creditCustomer == null) {
      showMessage(context, 'Choose the customer account for this udhaar sale.', error: true);
      return;
    }
    PrescriptionRecord? prescription;
    if (ScheduleCompliance.requiresPrescriptionRecord(cart.schedules)) {
      prescription = await showPrescriptionDialog(
        context,
        patientName: cart.customerName,
        patientPhone: cart.customerPhone,
      );
      if (prescription == null || !mounted) return;
    }

    setState(() => _checkingOut = true);
    try {
      final sale = await ref.read(repositoryProvider)!.checkout(cart.toRequest(prescription: prescription));
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      if (sheetContext != null && sheetContext.mounted) Navigator.of(sheetContext).pop();
      await showInvoice(context, sale, justCompleted: true);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockIndexProvider);
    final wide = context.isWide;

    final body = AsyncBody<Map<String, StockSummary>>(
      value: stockAsync,
      builder: (index) {
        final searchField = _SearchField(
          controller: _search,
          focusNode: _searchFocus,
          onChanged: (_) => setState(() {}),
          onSubmitted: () => _onSearchSubmitted(index),
        );
        final results = _results(index);
        final main = _query.isEmpty
            ? _CartList(index: index)
            : _SearchResults(results: results, onPick: _pick, query: _query);

        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(Space.l, Space.l, Space.l, Space.s), child: searchField),
                Expanded(child: main),
              ]),
            ),
            const VerticalDivider(width: 1),
            SizedBox(
              width: 360,
              child: _CheckoutPanel(onCheckout: _checkout, busy: _checkingOut),
            ),
          ]);
        }
        return Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.m, Space.s), child: searchField),
          Expanded(child: main),
          _PhoneCheckoutBar(onOpen: () => _openCheckoutSheet(), busy: _checkingOut),
        ]);
      },
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f2): () => _searchFocus.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.f9): _checkout,
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(_search.clear),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Billing'),
            actions: [
              if (!ref.watch(cartProvider.select((c) => c.isEmpty)))
                TextButton.icon(
                  onPressed: () async {
                    if (await confirmDialog(context, title: 'Clear this bill?', message: 'All lines will be removed.', confirmLabel: 'Clear')) {
                      ref.read(cartProvider.notifier).clear();
                    }
                  },
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Clear'),
                ),
              if (wide)
                const Padding(
                  padding: EdgeInsets.only(right: Space.l),
                  child: Center(child: Text('F2 search · F9 complete', style: TextStyle(color: AppColors.muted))),
                ),
            ],
          ),
          body: body,
        ),
      ),
    );
  }

  void _openCheckoutSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.9,
        child: _CheckoutPanel(onCheckout: () => _checkout(sheetContext: context), busy: _checkingOut),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.focusNode, required this.onChanged, required this.onSubmitted});

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: context.isWide,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search medicine, generic or scan barcode',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
      onChanged: onChanged,
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.results, required this.onPick, required this.query});
  final List<StockSummary> results;
  final ValueChanged<StockSummary> onPick;
  final String query;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: 'No medicine matches "$query"',
        message: 'Owners and pharmacists can add new medicines from Purchases.',
      );
    }
    final text = Theme.of(context).textTheme;
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: Space.l),
      itemCount: results.length,
      separatorBuilder: (_, _) => const Divider(indent: Space.l, endIndent: Space.l),
      itemBuilder: (context, i) {
        final s = results[i];
        final next = s.nextBatch;
        return ListTile(
          onTap: () => onPick(s),
          title: Row(children: [
            Flexible(child: Text(s.medicine.name, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Space.s),
            ScheduleBadge(s.medicine.scheduleType),
          ]),
          subtitle: Text('${s.medicine.genericName} · ${s.medicine.packSizeLabel}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(next == null ? '—' : formatRupees(next.mrpPaise), style: text.titleSmall),
              Text(
                s.isOutOfStock ? 'Out of stock' : PackUnits.describe(s.sellableUnits, s.medicine.unitsPerPack),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(color: s.isOutOfStock ? AppColors.danger : AppColors.muted),
              ),
            ]),
          ),
        );
      },
    );
  }
}

class _CartList extends ConsumerWidget {
  const _CartList({required this.index});
  final Map<String, StockSummary> index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty) {
      return const EmptyState(
        icon: Icons.shopping_basket_outlined,
        title: 'New bill',
        message: 'Search a medicine above, or scan its barcode, to add it.',
      );
    }
    final text = Theme.of(context).textTheme;
    final batchById = {for (final s in index.values) for (final b in s.batches) b.id: b};
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.m, Space.l),
      itemCount: cart.lines.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.s),
      itemBuilder: (context, i) {
        final line = cart.lines[i];
        final batch = batchById[line.batchId];
        final available = batch?.quantity ?? 0;
        final short = line.quantity > available;
        final step = line.unitsPerPack > 1 ? line.unitsPerPack : 1;
        final stock = index[line.medicineId];
        return Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.xs, Space.s),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(line.name, style: text.titleSmall, overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: Space.s),
                    ScheduleBadge(line.scheduleType),
                  ]),
                  Text(
                    'Batch ${line.batchNumber} · Exp ${DateFormat('MM/yy').format(line.expiryDate)} · '
                    '${formatRupees(line.mrpPaise)}${line.unitsPerPack > 1 ? '/${line.unitsPerPack}' : ''}',
                    style: text.bodySmall?.copyWith(color: AppColors.muted),
                    maxLines: 2,
                  ),
                  if (short)
                    Text(available == 0 ? 'This batch just ran out — remove the line.' : 'Only $available left in this batch.',
                        style: text.bodySmall?.copyWith(color: AppColors.danger)),
                ]),
              ),
              const SizedBox(width: Space.s),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(formatRupees(line.lineTotalPaise), style: text.titleSmall),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: step > 1 ? 'One pack less' : 'One less',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => ref.read(cartProvider.notifier).setQuantity(i, line.quantity - step, available: available),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: stock == null
                        ? null
                        : () async {
                            // Editing one line: cap at what this line's batch holds.
                            final units = await showQuantityDialog(context,
                                stock: stock,
                                alreadyInBill: (stock.sellableUnits - available).clamp(0, 1 << 30),
                                initialUnits: line.quantity,
                                batchNumber: line.batchNumber);
                            if (units != null) {
                              final ok = ref.read(cartProvider.notifier).setQuantity(i, units, available: available);
                              if (!ok && context.mounted) {
                                showMessage(context, 'Batch ${line.batchNumber} has only $available.', error: true);
                              }
                            }
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: Space.xs),
                      child: Text(
                        line.unitsPerPack > 1 ? PackUnits.describe(line.quantity, line.unitsPerPack) : '${line.quantity}',
                        style: text.bodyMedium?.copyWith(decoration: TextDecoration.underline),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: step > 1 ? 'One pack more' : 'One more',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      final ok = ref.read(cartProvider.notifier).setQuantity(i, line.quantity + step, available: available);
                      if (!ok) showMessage(context, 'Batch ${line.batchNumber} has only $available.', error: true);
                    },
                  ),
                  IconButton(
                    tooltip: 'Remove line',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    onPressed: () => ref.read(cartProvider.notifier).remove(i),
                  ),
                ]),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _PhoneCheckoutBar extends ConsumerWidget {
  const _PhoneCheckoutBar({required this.onOpen, required this.busy});
  final VoidCallback onOpen;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final summary = cart.summary;
    final text = Theme.of(context).textTheme;
    return Material(
      color: AppColors.surface,
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.s),
        child: Row(children: [
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(formatRupees(summary.payablePaise), style: text.titleLarge),
              Text('${cart.lines.length} line${cart.lines.length == 1 ? '' : 's'} · incl. GST ${formatRupees(summary.gstPaise)}',
                  style: text.bodySmall?.copyWith(color: AppColors.muted)),
            ]),
          ),
          FilledButton.icon(
            onPressed: cart.isEmpty || busy ? null : onOpen,
            icon: const Icon(Icons.shopping_cart_checkout),
            label: const Text('Checkout'),
          ),
        ]),
      ),
    );
  }
}

class _CheckoutPanel extends ConsumerStatefulWidget {
  const _CheckoutPanel({required this.onCheckout, required this.busy});
  final Future<void> Function() onCheckout;
  final bool busy;

  @override
  ConsumerState<_CheckoutPanel> createState() => _CheckoutPanelState();
}

class _CheckoutPanelState extends ConsumerState<_CheckoutPanel> {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _localBusy = false;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    _name = TextEditingController(text: cart.customerName);
    _phone = TextEditingController(text: cart.customerPhone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    setState(() => _localBusy = true);
    try {
      await widget.onCheckout();
    } finally {
      if (mounted) setState(() => _localBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final summary = cart.summary;
    final text = Theme.of(context).textTheme;
    String rate(double r) => r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);

    // Keep the fields in step when the cart is cleared or a credit customer chosen.
    if (_name.text != cart.customerName) _name.text = cart.customerName;
    if (_phone.text != cart.customerPhone) _phone.text = cart.customerPhone;
    final credit = cart.paymentMode == PaymentMode.credit;
    final busy = widget.busy || _localBusy;

    return ListView(
      padding: const EdgeInsets.all(Space.l),
      children: [
        Text('Customer', style: text.titleMedium),
        const SizedBox(height: Space.s),
        if (credit)
          _CreditCustomerPicker(selected: cart.creditCustomer, onChanged: notifier.setCreditCustomer)
        else ...[
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name (optional)'),
            textCapitalization: TextCapitalization.words,
            onChanged: (v) => notifier.setCustomer(name: v),
          ),
          const SizedBox(height: Space.s),
          TextField(
            controller: _phone,
            decoration: const InputDecoration(labelText: 'Mobile (for WhatsApp bill)'),
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(15)],
            onChanged: (v) => notifier.setCustomer(phone: v),
          ),
        ],
        const SizedBox(height: Space.l),
        Text('Payment', style: text.titleMedium),
        const SizedBox(height: Space.s),
        Wrap(spacing: Space.s, runSpacing: Space.s, children: [
          for (final mode in PaymentMode.values)
            ChoiceChip(
              label: Text(mode == PaymentMode.credit ? 'Udhaar' : mode.label),
              selected: cart.paymentMode == mode,
              onSelected: (_) => notifier.setPaymentMode(mode),
            ),
        ]),
        const Divider(height: Space.xl * 1.5),
        for (final slab in summary.slabs)
          AmountRow('GST ${rate(slab.rate)}% (on ${formatRupees(slab.taxablePaise)})', formatRupees(slab.gstPaise)),
        AmountRow('Taxable value', formatRupees(summary.taxablePaise)),
        AmountRow('Total (MRP)', formatRupees(summary.grossPaise)),
        AmountRow('Round off', formatRupees(summary.roundOffPaise)),
        const Divider(height: Space.l),
        AmountRow('Payable', formatRupees(summary.payablePaise), emphasis: true),
        const SizedBox(height: Space.l),
        FilledButton.icon(
          onPressed: cart.isEmpty || busy ? null : _complete,
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check),
          label: Text(busy ? 'Saving…' : 'Complete sale'),
        ),
        if (ScheduleCompliance.requiresPrescriptionRecord(cart.schedules)) ...[
          const SizedBox(height: Space.s),
          Text('Schedule H1/X item on bill — you\'ll be asked for patient & doctor details.',
              style: text.bodySmall?.copyWith(color: AppColors.warning)),
        ],
      ],
    );
  }
}

class _CreditCustomerPicker extends ConsumerWidget {
  const _CreditCustomerPicker({required this.selected, required this.onChanged});
  final CustomerCredit? selected;
  final ValueChanged<CustomerCredit?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    if (selected != null) {
      final live = ref.watch(customersProvider).valueOrNull?.where((c) => c.id == selected!.id).firstOrNull ?? selected!;
      return Card(
        child: ListTile(
          title: Text(live.name, overflow: TextOverflow.ellipsis),
          subtitle: Text('${live.phoneNumber.isEmpty ? 'No phone' : live.phoneNumber} · ${live.outstandingBalancePaise < 0 ? 'advance' : 'owes'} ${formatRupees(live.outstandingBalancePaise.abs())}'
              '${live.creditLimitPaise > 0 ? ' of ${formatRupees(live.creditLimitPaise)} limit' : ''}'),
          trailing: IconButton(tooltip: 'Change customer', icon: const Icon(Icons.close), onPressed: () => onChanged(null)),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Udhaar sales go on a customer account.', style: text.bodySmall?.copyWith(color: AppColors.muted)),
      const SizedBox(height: Space.s),
      OutlinedButton.icon(
        onPressed: () async {
          final customer = await pickCustomer(context);
          if (customer != null) onChanged(customer);
        },
        icon: const Icon(Icons.person_search_outlined),
        label: const Text('Choose customer'),
      ),
    ]);
  }
}
