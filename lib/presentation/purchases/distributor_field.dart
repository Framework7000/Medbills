import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../domain/models/supplier_account.dart';
import '../../state/providers.dart';

/// Distributor name with suggestions from the shop's shared list (the same
/// on every device). A new name is added to the list when stock or a bill
/// is saved with it.
class DistributorField extends ConsumerStatefulWidget {
  const DistributorField({super.key, required this.controller, this.label = 'Distributor / MR', this.onChanged, this.validator});
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  @override
  ConsumerState<DistributorField> createState() => _DistributorFieldState();
}

class _DistributorFieldState extends ConsumerState<DistributorField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final label = widget.label;
    final onChanged = widget.onChanged;
    final validator = widget.validator;
    final list = ref.watch(distributorsProvider).valueOrNull ?? const <Distributor>[];
    // Most-used names first: those with the most bills.
    final bills = ref.watch(supplierBillsProvider).valueOrNull ?? const <SupplierBill>[];
    final uses = <String, int>{};
    for (final b in bills) {
      uses.update(b.distributorId, (v) => v + 1, ifAbsent: () => 1);
    }
    final names = [...list]..sort((a, b) => (uses[b.id] ?? 0).compareTo(uses[a.id] ?? 0));
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: _focus,
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        final all = names.map((d) => d.name);
        if (q.isEmpty) return all.take(8);
        return all.where((n) => n.toLowerCase().contains(q) && n.toLowerCase() != q).take(8);
      },
      onSelected: (v) => onChanged?.call(v),
      fieldViewBuilder: (context, c, focus, onSubmit) => TextFormField(
        controller: c,
        focusNode: focus,
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(PhosphorIconsRegular.truck)),
        textCapitalization: TextCapitalization.words,
        onChanged: onChanged,
        validator: validator,
      ),
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280, maxWidth: 420),
            child: ListView(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              children: [
                for (final o in options)
                  ListTile(
                    dense: true,
                    leading: const Icon(PhosphorIconsRegular.truck, size: 18),
                    title: Text(o),
                    onTap: () => onSelected(o),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cash (paid now) or Udhaar (credit, pay later), as two big buttons.
class PaymentToggle extends StatelessWidget {
  const PaymentToggle({super.key, required this.value, required this.onChanged});
  final PurchasePayment value;
  final ValueChanged<PurchasePayment> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<PurchasePayment>(
      segments: const [
        ButtonSegment(value: PurchasePayment.cash, icon: Icon(PhosphorIconsRegular.money), label: Text('Cash (paid)')),
        ButtonSegment(value: PurchasePayment.credit, icon: Icon(PhosphorIconsRegular.clockCountdown), label: Text('Udhaar (credit)')),
      ],
      selected: {value},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}
