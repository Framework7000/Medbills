import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../domain/models/sale_invoice.dart';
import '../../domain/models/sale_return.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// A customer brings medicines back: choose how many of each line, how the
/// money goes back, and they return to stock.
Future<void> showReturnDialog(BuildContext context, WidgetRef ref, SaleInvoice sale) async {
  final done = await showDialog<SaleReturn>(context: context, builder: (_) => _ReturnDialog(sale: sale));
  if (done != null && context.mounted) {
    showMessage(context, 'Returned. Give back ${formatRupees(done.refundPaise)} (${done.refundMode.label}). Stock updated.');
  }
}

class _ReturnDialog extends ConsumerStatefulWidget {
  const _ReturnDialog({required this.sale});
  final SaleInvoice sale;

  @override
  ConsumerState<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends ConsumerState<_ReturnDialog> {
  late final List<int> _units = List.filled(widget.sale.lines.length, 0);
  late RefundMode _mode = widget.sale.paymentMode == PaymentMode.credit
      ? RefundMode.udhaar
      : widget.sale.paymentMode == PaymentMode.upi
          ? RefundMode.upi
          : RefundMode.cash;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  SaleInvoice get sale => widget.sale;

  ReturnPlan? get _plan {
    try {
      return SaleReturnPlanner.plan(
        sale: sale,
        units: {for (var i = 0; i < _units.length; i++) if (_units[i] > 0) i: _units[i]},
        mode: _mode,
      );
    } on ReturnException {
      return null;
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final r = await ref.read(repositoryProvider)!.returnSaleItems(
            saleId: sale.id,
            units: {for (var i = 0; i < _units.length; i++) if (_units[i] > 0) i: _units[i]},
            refundMode: _mode,
            reason: _reason.text,
          );
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final plan = _plan;
    return AlertDialog(
      title: Text('Return from ${sale.invoiceNumber}'),
      content: DialogBody(
        maxWidth: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < sale.lines.length; i++)
            if (sale.returnableOf(i) > 0) _lineRow(context, i),
          const SizedBox(height: Space.m),
          Wrap(spacing: Space.s, runSpacing: Space.s, children: [
            for (final m in RefundMode.values)
              if (m != RefundMode.udhaar || sale.customerId != null)
                ChoiceChip(label: Text(m.label), selected: _mode == m, onSelected: (_) => setState(() => _mode = m)),
          ]),
          const SizedBox(height: Space.s),
          TextField(
            controller: _reason,
            decoration: const InputDecoration(labelText: 'Reason (optional)'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: Space.m),
          Row(children: [
            Expanded(child: Text('Give back', style: text.titleMedium)),
            Text(formatRupees(plan?.refundPaise ?? 0), style: text.titleLarge?.copyWith(color: AppColors.primary)),
          ]),
          if (_error != null) ...[
            const SizedBox(height: Space.s),
            Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.danger)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton.icon(
          onPressed: _busy || plan == null ? null : _save,
          icon: const Icon(PhosphorIconsRegular.arrowUUpLeft),
          label: const Text('Return'),
        ),
      ],
    );
  }

  Widget _lineRow(BuildContext context, int i) {
    final text = Theme.of(context).textTheme;
    final line = sale.lines[i];
    final max = sale.returnableOf(i);
    final step = line.unitsPerPack > 1 && max >= line.unitsPerPack ? line.unitsPerPack : 1;
    void set(int v) => setState(() => _units[i] = v.clamp(0, max));
    final shown = _units[i] == 0
        ? '0'
        : line.unitsPerPack > 1
            ? PackUnits.describe(_units[i], line.unitsPerPack)
            : '${_units[i]}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(line.name, style: text.bodyLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
        Row(children: [
          Expanded(
            child: Text('Sold ${PackUnits.describe(line.quantity, line.unitsPerPack)} · up to ${PackUnits.describe(max, line.unitsPerPack)} back',
                style: text.bodySmall?.copyWith(color: AppColors.muted)),
          ),
          IconButton(
            tooltip: 'Less',
            visualDensity: VisualDensity.compact,
            icon: const Icon(PhosphorIconsRegular.minusCircle),
            onPressed: _units[i] == 0 ? null : () => set(_units[i] - step),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: Text(shown, textAlign: TextAlign.center, style: text.titleSmall),
          ),
          IconButton(
            key: ValueKey('return-more-$i'),
            tooltip: 'More',
            visualDensity: VisualDensity.compact,
            icon: const Icon(PhosphorIconsRegular.plusCircle),
            onPressed: _units[i] >= max ? null : () => set(_units[i] + step),
          ),
          TextButton(onPressed: () => set(max), child: const Text('All')),
        ]),
        const Divider(height: Space.s),
      ]),
    );
  }
}
