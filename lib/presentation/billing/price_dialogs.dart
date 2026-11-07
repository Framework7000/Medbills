import 'package:flutter/material.dart';

import '../../domain/services/billing_calculator.dart';
import '../../state/cart.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The answer from the price dialog: a price per pack, or back to MRP.
class PriceChoice {
  final int? ratePaise; // null = full MRP
  const PriceChoice(this.ratePaise);
}

/// Sell one line cheaper: type the price per pack, or tap a ready discount.
/// Never above MRP.
Future<PriceChoice?> showLinePriceDialog(BuildContext context, CartLine line) =>
    showDialog<PriceChoice>(context: context, builder: (_) => _LinePriceDialog(line: line));

class _LinePriceDialog extends StatefulWidget {
  const _LinePriceDialog({required this.line});
  final CartLine line;

  @override
  State<_LinePriceDialog> createState() => _LinePriceDialogState();
}

class _LinePriceDialogState extends State<_LinePriceDialog> {
  late final _rate = TextEditingController(text: _plain(widget.line.effectiveRatePaise));
  late final _amount = TextEditingController(text: _plain(widget.line.lineTotalPaise));
  String? _error;

  static String _plain(int paise) => formatRupees(paise, symbol: false).replaceAll(',', '');

  CartLine get line => widget.line;
  String get unitWord => line.unitsPerPack > 1 ? 'pack' : 'unit';

  int _lineFor(int rate) =>
      BillingCalculator.linePaise(mrpPaisePerPack: rate, unitsPerPack: line.unitsPerPack, quantityUnits: line.quantity);

  void _setRate(int rate) {
    _rate.text = _plain(rate);
    _amount.text = _plain(_lineFor(rate));
    setState(() => _error = null);
  }

  /// Typing the line amount works out the price per pack from it.
  void _fromAmount(String v) {
    final paise = parseRupeesToPaise(v);
    if (paise == null || line.quantity <= 0) return;
    final rate = (paise * line.unitsPerPack * 2 + line.quantity) ~/ (line.quantity * 2);
    _rate.text = _plain(rate);
    setState(() => _error = null);
  }

  void _save() {
    final rate = parseRupeesToPaise(_rate.text);
    if (rate == null || rate <= 0) {
      setState(() => _error = 'Enter the price.');
      return;
    }
    if (rate > line.mrpPaise) {
      setState(() => _error = 'Cannot sell above MRP ${formatRupees(line.mrpPaise)}.');
      return;
    }
    Navigator.pop(context, PriceChoice(rate >= line.mrpPaise ? null : rate));
  }

  @override
  void dispose() {
    _rate.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rate = parseRupeesToPaise(_rate.text) ?? line.mrpPaise;
    final off = line.mrpLinePaise - _lineFor(rate.clamp(0, line.mrpPaise));
    return AlertDialog(
      title: Text(line.name, overflow: TextOverflow.ellipsis),
      content: DialogBody(
        maxWidth: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('MRP ${formatRupees(line.mrpPaise)}/$unitWord · this line ${formatRupees(line.mrpLinePaise)}',
              style: text.bodyMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: Space.m),
          Wrap(spacing: Space.s, runSpacing: Space.s, children: [
            ActionChip(label: const Text('MRP'), onPressed: () => _setRate(line.mrpPaise)),
            for (final pct in const [5, 10, 15, 20])
              ActionChip(
                label: Text('−$pct%'),
                onPressed: () => _setRate((line.mrpPaise * (100 - pct) * 2 + 100) ~/ 200),
              ),
          ]),
          const SizedBox(height: Space.m),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('line-rate'),
                controller: _rate,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Price ₹/$unitWord', prefixText: '₹ '),
                onChanged: (v) {
                  final p = parseRupeesToPaise(v);
                  if (p != null) _amount.text = _plain(_lineFor(p));
                  setState(() => _error = null);
                },
                onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(width: Space.m),
            Expanded(
              child: TextField(
                key: const ValueKey('line-amount'),
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Line total', prefixText: '₹ '),
                onChanged: _fromAmount,
                onSubmitted: (_) => _save(),
              ),
            ),
          ]),
          const SizedBox(height: Space.s),
          if (_error != null)
            Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.danger))
          else if (off > 0)
            Text('Saving ${formatRupees(off)} on this line', style: text.bodySmall?.copyWith(color: AppColors.accent)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Done')),
      ],
    );
  }
}

/// Rupees (or a %) off the whole bill. Returns the paise, 0 to remove.
Future<int?> showBillDiscountDialog(BuildContext context, {required int subtotalPaise, required int currentPaise}) =>
    showDialog<int>(
      context: context,
      builder: (_) => _BillDiscountDialog(subtotal: subtotalPaise, current: currentPaise),
    );

class _BillDiscountDialog extends StatefulWidget {
  const _BillDiscountDialog({required this.subtotal, required this.current});
  final int subtotal;
  final int current;

  @override
  State<_BillDiscountDialog> createState() => _BillDiscountDialogState();
}

class _BillDiscountDialogState extends State<_BillDiscountDialog> {
  late final _amount = TextEditingController(
      text: widget.current > 0 ? formatRupees(widget.current, symbol: false).replaceAll(',', '') : '');
  bool _percent = false;
  String? _error;

  int? get _paise {
    final t = _amount.text.trim();
    if (t.isEmpty) return 0;
    if (_percent) {
      final pct = double.tryParse(t);
      if (pct == null || pct < 0 || pct >= 100) return null;
      return (widget.subtotal * pct / 100).round();
    }
    return parseRupeesToPaise(t);
  }

  void _save() {
    final p = _paise;
    if (p == null) {
      setState(() => _error = _percent ? 'Enter a % below 100.' : 'Enter the amount.');
      return;
    }
    if (p >= widget.subtotal) {
      setState(() => _error = 'The discount must be less than the bill (${formatRupees(widget.subtotal)}).');
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = _paise;
    return AlertDialog(
      title: const Text('Discount on bill'),
      content: DialogBody(
        maxWidth: 360,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Bill ${formatRupees(widget.subtotal)}', style: text.bodyMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: Space.m),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('₹ off')),
              ButtonSegment(value: true, label: Text('% off')),
            ],
            selected: {_percent},
            onSelectionChanged: (s) => setState(() {
              _percent = s.first;
              _error = null;
            }),
          ),
          const SizedBox(height: Space.m),
          TextField(
            key: const ValueKey('bill-discount'),
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: _percent ? 'Percent' : 'Amount',
              prefixText: _percent ? null : '₹ ',
              suffixText: _percent ? '%' : null,
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Space.s),
          if (_error != null)
            Text(_error!, style: text.bodySmall?.copyWith(color: AppColors.danger))
          else if (p != null && p > 0 && p < widget.subtotal)
            Text('New total ${formatRupees(widget.subtotal - p)} (before round-off)',
                style: text.bodySmall?.copyWith(color: AppColors.accent)),
        ]),
      ),
      actions: [
        if (widget.current > 0) TextButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Apply')),
      ],
    );
  }
}
