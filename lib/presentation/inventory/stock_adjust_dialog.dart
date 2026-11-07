import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../domain/models/batch.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/stock_adjustment.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Change how much of a batch is on the shelf: type the counted packs (and
/// loose tablets), tap − / +, or empty it. The reason is recorded.
Future<void> showStockAdjustDialog(BuildContext context, Batch batch, int unitsPerPack) =>
    showDialog<void>(context: context, builder: (_) => StockAdjustDialog(batch: batch, unitsPerPack: unitsPerPack));

class StockAdjustDialog extends ConsumerStatefulWidget {
  const StockAdjustDialog({super.key, required this.batch, required this.unitsPerPack});
  final Batch batch;
  final int unitsPerPack;

  @override
  ConsumerState<StockAdjustDialog> createState() => _StockAdjustDialogState();
}

class _StockAdjustDialogState extends ConsumerState<StockAdjustDialog> {
  late final int perPack = widget.unitsPerPack < 1 ? 1 : widget.unitsPerPack;
  late final _packs = TextEditingController(text: '${widget.batch.quantity ~/ perPack}');
  late final _loose = TextEditingController(text: '${widget.batch.quantity % perPack}');
  final _note = TextEditingController();
  AdjustReason _reason = AdjustReason.count;
  bool _busy = false;
  String? _error;

  int get _units => (int.tryParse(_packs.text) ?? 0) * perPack + (perPack > 1 ? int.tryParse(_loose.text) ?? 0 : 0);

  void _set(int units) {
    final u = units < 0 ? 0 : units;
    _packs.text = '${u ~/ perPack}';
    _loose.text = '${u % perPack}';
    setState(() => _error = null);
  }

  Future<void> _save() async {
    final adjustment = StockAdjustment(newQuantity: _units, reason: _reason, note: _note.text);
    final problems = adjustment.problems();
    if (perPack > 1 && (int.tryParse(_loose.text) ?? 0) >= perPack) {
      problems.add('Loose must be less than $perPack (one pack).');
    }
    if (problems.isNotEmpty) {
      setState(() => _error = problems.join(' '));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider)!.adjustBatchStock(widget.batch.id, adjustment);
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Stock of ${widget.batch.batchNumber} is now ${PackUnits.describe(_units, perPack)}.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _packs.dispose();
    _loose.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = widget.batch;
    final units = _units;
    final change = units - b.quantity;
    final valueChange = (b.purchasePricePaise * change * 2 + (change >= 0 ? perPack : -perPack)) ~/ (perPack * 2);
    return AlertDialog(
      title: Text('Stock · ${b.batchNumber}'),
      content: DialogBody(
        maxWidth: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Now ${PackUnits.describe(b.quantity, perPack)}${perPack > 1 ? ' · $perPack per pack' : ''}',
              style: text.bodyMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: Space.m),
          Row(children: [
            IconButton.filledTonal(
              tooltip: perPack > 1 ? 'One pack less' : 'One less',
              icon: const Icon(PhosphorIconsRegular.minus),
              onPressed: () => _set(units - perPack),
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: TextField(
                key: const ValueKey('adjust-packs'),
                controller: _packs,
                autofocus: true,
                textAlign: TextAlign.center,
                style: text.headlineSmall,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                decoration: InputDecoration(labelText: perPack > 1 ? 'Packs' : 'Quantity'),
                onChanged: (_) => setState(() => _error = null),
              ),
            ),
            if (perPack > 1) ...[
              const SizedBox(width: Space.s),
              SizedBox(
                width: 84,
                child: TextField(
                  key: const ValueKey('adjust-loose'),
                  controller: _loose,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
                  decoration: const InputDecoration(labelText: 'Loose'),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
            ],
            const SizedBox(width: Space.s),
            IconButton.filledTonal(
              tooltip: perPack > 1 ? 'One pack more' : 'One more',
              icon: const Icon(PhosphorIconsRegular.plus),
              onPressed: () => _set(units + perPack),
            ),
          ]),
          const SizedBox(height: Space.s),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                _set(0);
                if (_reason == AdjustReason.count) setState(() => _reason = AdjustReason.expired);
              },
              icon: const Icon(PhosphorIconsRegular.trash, color: AppColors.danger),
              label: const Text('Empty this batch', style: TextStyle(color: AppColors.danger)),
            ),
          ),
          const SizedBox(height: Space.s),
          Wrap(spacing: Space.s, runSpacing: Space.s, children: [
            for (final r in AdjustReason.values)
              ChoiceChip(label: Text(r.label), selected: _reason == r, onSelected: (_) => setState(() => _reason = r)),
          ]),
          if (_reason == AdjustReason.other) ...[
            const SizedBox(height: Space.s),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Reason')),
          ],
          const SizedBox(height: Space.m),
          if (change != 0)
            Text(
              '${change > 0 ? '+' : '−'}${PackUnits.describe(change.abs(), perPack)} · '
              '${change > 0 ? '+' : '−'}${formatRupees(valueChange.abs())} stock value',
              style: text.bodyMedium?.copyWith(color: change > 0 ? AppColors.accent : AppColors.warning),
            ),
          if (_error != null) Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.danger)),
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy || change == 0 ? null : _save, child: const Text('Save')),
      ],
    );
  }
}
