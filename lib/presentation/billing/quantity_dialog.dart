import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/stock_summary.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Asks how much to sell, as whole packs plus loose units, and returns the
/// total in base units — or null if cancelled.
Future<int?> showQuantityDialog(
  BuildContext context, {
  required StockSummary stock,
  required int alreadyInBill,
  int? initialUnits,
  String? batchNumber,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _QuantityDialog(
      stock: stock,
      alreadyInBill: alreadyInBill,
      initialUnits: initialUnits,
      batchNumber: batchNumber,
    ),
  );
}

class _QuantityDialog extends StatefulWidget {
  const _QuantityDialog({required this.stock, required this.alreadyInBill, this.initialUnits, this.batchNumber});

  final StockSummary stock;
  final int alreadyInBill;
  final int? initialUnits;

  /// Set when editing an existing bill line, which is fixed to one batch.
  final String? batchNumber;

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  late final TextEditingController _packs;
  late final TextEditingController _loose;
  String? _error;

  int get _perPack => widget.stock.medicine.unitsPerPack;
  bool get _hasLoose => _perPack > 1;
  int get _available => widget.stock.sellableUnits - widget.alreadyInBill;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialUnits ?? (_available >= _perPack ? _perPack : (_available > 0 ? _available : 0));
    final (packs, loose) = PackUnits.split(initial, _perPack);
    _packs = TextEditingController(text: '$packs');
    _loose = TextEditingController(text: _hasLoose ? '$loose' : '0');
  }

  @override
  void dispose() {
    _packs.dispose();
    _loose.dispose();
    super.dispose();
  }

  int get _units => (int.tryParse(_packs.text) ?? 0) * _perPack + (int.tryParse(_loose.text) ?? 0);

  void _submit() {
    final units = _units;
    String? error;
    if (units <= 0) {
      error = 'Enter a quantity.';
    } else if (units > _available) {
      error = _available <= 0
          ? 'No more stock available.'
          : 'Only ${PackUnits.describe(_available, _perPack)} available.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, units);
  }

  @override
  Widget build(BuildContext context) {
    final medicine = widget.stock.medicine;
    final next = widget.stock.nextBatch;
    final text = Theme.of(context).textTheme;
    final units = _units;
    final priceBatch = widget.batchNumber == null
        ? next
        : widget.stock.batches.where((b) => b.batchNumber == widget.batchNumber).firstOrNull ?? next;
    final price = priceBatch == null
        ? 0
        : BillingCalculator.linePaise(mrpPaisePerPack: priceBatch.mrpPaise, unitsPerPack: _perPack, quantityUnits: units);

    Widget field(TextEditingController c, String label, {bool autofocus = false}) => Expanded(
          child: TextField(
            controller: c,
            autofocus: autofocus,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
            decoration: InputDecoration(labelText: label),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _submit(),
          ),
        );

    return AlertDialog(
      title: Text(medicine.name, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: DialogBody(
        maxWidth: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${medicine.packSizeLabel} · ${PackUnits.describe(_available.clamp(0, 1 << 30), _perPack)} available',
                style: text.bodyMedium?.copyWith(color: AppColors.muted)),
            if (widget.batchNumber != null)
              Text('Batch ${widget.batchNumber}', style: text.bodySmall?.copyWith(color: AppColors.muted))
            else if (next != null)
              Text('Next batch ${next.batchNumber}, exp ${DateFormat('MM/yy').format(next.expiryDate)}, '
                  'MRP ${formatRupees(next.mrpPaise)}/${_hasLoose ? 'pack' : 'unit'}',
                  style: text.bodySmall?.copyWith(color: AppColors.muted)),
            const SizedBox(height: Space.l),
            Row(children: [
              field(_packs, _hasLoose ? 'Packs (×$_perPack)' : 'Quantity', autofocus: true),
              if (_hasLoose) ...[const SizedBox(width: Space.m), field(_loose, 'Loose units')],
            ]),
            const SizedBox(height: Space.m),
            Text('= $units ${_hasLoose ? 'units' : ''}  ·  ${formatRupees(price)}', style: text.titleSmall),
            if (_error != null) ...[
              const SizedBox(height: Space.s),
              Text(_error!, style: text.bodyMedium?.copyWith(color: AppColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}
