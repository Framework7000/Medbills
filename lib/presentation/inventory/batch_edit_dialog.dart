import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../domain/models/batch.dart';
import '../../domain/services/batch_correction.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/ocr_text.dart' show parseMonthYear;
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Fixes a received batch: a mistyped expiry, received date, MRP or cost.
/// Owner and pharmacist only. The stock quantity is not editable here, and
/// bills already made keep the prices they were billed at.
class BatchEditDialog extends ConsumerStatefulWidget {
  const BatchEditDialog({super.key, required this.batch});
  final Batch batch;

  @override
  ConsumerState<BatchEditDialog> createState() => _BatchEditDialogState();
}

class _BatchEditDialogState extends ConsumerState<BatchEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _expiry = TextEditingController(
      text: '${widget.batch.expiryDate.month.toString().padLeft(2, '0')}/${widget.batch.expiryDate.year}');
  late final _mrp = TextEditingController(text: _rupees(widget.batch.mrpPaise));
  late final _cost = TextEditingController(text: _rupees(widget.batch.purchasePricePaise));
  late DateTime _received = widget.batch.createdAt;
  bool _saving = false;

  static String _rupees(int paise) => formatRupees(paise, symbol: false).replaceAll(',', '');

  @override
  void dispose() {
    for (final c in [_expiry, _mrp, _cost]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickReceived() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _received.isAfter(now) ? now : _received,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _received = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final my = parseMonthYear(_expiry.text)!;
    final correction = BatchCorrection(
      expiryDate: Batch.endOfMonth(my.year, my.month),
      receivedAt: _received,
      mrpPaise: parseRupeesToPaise(_mrp.text)!,
      purchasePricePaise: parseRupeesToPaise(_cost.text) ?? 0,
    );
    if (!correction.changes(widget.batch)) {
      Navigator.pop(context);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(repositoryProvider)!.correctBatch(widget.batch.id, correction);
      if (!mounted) return;
      Navigator.pop(context);
      showMessage(context, 'Batch ${widget.batch.batchNumber} updated.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: Space.m);
    return AlertDialog(
      title: Text('Batch ${widget.batch.batchNumber}'),
      content: DialogBody(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _expiry,
              decoration: const InputDecoration(labelText: 'Expiry', helperText: 'Month / year, e.g. 05/2027'),
              keyboardType: TextInputType.datetime,
              inputFormatters: [LengthLimitingTextInputFormatter(9)],
              validator: (v) => parseMonthYear(v ?? '') == null ? 'Enter month and year, like 05/27' : null,
            ),
            gap,
            OutlinedButton.icon(
              icon: const Icon(PhosphorIconsRegular.calendar, size: 18),
              label: Text('Received ${DateFormat('d MMM yyyy').format(_received)}'),
              onPressed: _pickReceived,
            ),
            gap,
            TextFormField(
              controller: _mrp,
              decoration: const InputDecoration(labelText: 'MRP per pack (₹)', helperText: 'As printed, includes GST'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => (parseRupeesToPaise(v ?? '') ?? 0) <= 0 ? 'Enter the MRP' : null,
            ),
            gap,
            TextFormField(
              controller: _cost,
              decoration: const InputDecoration(labelText: 'Cost per pack (₹)', helperText: 'What you paid the supplier'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => v != null && v.trim().isNotEmpty && parseRupeesToPaise(v) == null ? 'Enter a number' : null,
            ),
            gap,
            Text(
              'Stock quantity is not changed here. Bills already made keep their prices. This change is recorded.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
      ],
    );
  }
}
