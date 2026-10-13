import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/medicine.dart';
import '../../domain/models/schedule_type.dart';
import '../../domain/services/gs1_parser.dart';
import '../../domain/services/pack_units.dart';
import '../../platform/device_features.dart';
import '../../state/providers.dart';
import '../scan/barcode_scanner_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';

const gstRates = [0.0, 5.0, 12.0, 18.0];

/// Create or edit a medicine master record. With [save] false the edited
/// record is just returned (used by Purchases before the first stock-in).
Future<Medicine?> showMedicineEditor(BuildContext context, {required Medicine initial, bool isNew = false, bool save = true}) {
  return showDialog<Medicine>(
    context: context,
    builder: (_) => _MedicineEditor(initial: initial, isNew: isNew, save: save),
  );
}

class _MedicineEditor extends ConsumerStatefulWidget {
  const _MedicineEditor({required this.initial, required this.isNew, required this.save});
  final Medicine initial;
  final bool isNew;
  final bool save;

  @override
  ConsumerState<_MedicineEditor> createState() => _MedicineEditorState();
}

class _MedicineEditorState extends ConsumerState<_MedicineEditor> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.initial.name);
  late final _generic = TextEditingController(text: widget.initial.genericName);
  late final _manufacturer = TextEditingController(text: widget.initial.manufacturer);
  late final _category = TextEditingController(text: widget.initial.type);
  late final _pack = TextEditingController(text: widget.initial.packSizeLabel);
  late final _units = TextEditingController(text: '${widget.initial.unitsPerPack}');
  late final _hsn = TextEditingController(text: widget.initial.hsnCode);
  late final _minStock = TextEditingController(
      text: '${(widget.initial.minStock / (widget.initial.unitsPerPack < 1 ? 1 : widget.initial.unitsPerPack)).ceil()}');
  late final _shelf = TextEditingController(text: widget.initial.shelfLocation);
  late final _barcode = TextEditingController(text: widget.initial.barcode ?? '');
  late double _gst = gstRates.contains(widget.initial.gstRate) ? widget.initial.gstRate : 12.0;
  late ScheduleType _schedule = widget.initial.scheduleType;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _generic, _manufacturer, _category, _pack, _units, _hsn, _minStock, _shelf, _barcode]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final units = int.parse(_units.text);
    final medicine = widget.initial.copyWith(
      name: _name.text.trim(),
      genericName: _generic.text.trim(),
      manufacturer: _manufacturer.text.trim(),
      type: _category.text.trim(),
      packSizeLabel: _pack.text.trim(),
      unitsPerPack: units,
      hsnCode: _hsn.text.trim(),
      gstRate: _gst,
      scheduleType: _schedule,
      barcode: _barcode.text.trim(),
      minStock: (int.tryParse(_minStock.text) ?? 0) * units,
      shelfLocation: _shelf.text.trim(),
    );
    if (!widget.save) {
      Navigator.pop(context, medicine);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider)!.saveMedicine(medicine);
      if (mounted) Navigator.pop(context, medicine);
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> children) => LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < 360) {
            return Column(children: [
              for (final child in children) Padding(padding: const EdgeInsets.only(bottom: Space.m), child: child),
            ]);
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: Space.m),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(width: Space.m),
                Expanded(child: children[i]),
              ],
            ]),
          );
        });

    return AlertDialog(
      title: Text(widget.isNew ? 'New medicine' : 'Edit ${widget.initial.name}', overflow: TextOverflow.ellipsis),
      content: DialogBody(
        maxWidth: 560,
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            row([
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Brand name'),
                textCapitalization: TextCapitalization.words,
                validator: _required,
              ),
            ]),
            row([
              TextFormField(controller: _generic, decoration: const InputDecoration(labelText: 'Generic / composition'), validator: _required),
              TextFormField(controller: _manufacturer, decoration: const InputDecoration(labelText: 'Manufacturer'), validator: _required),
            ]),
            row([
              TextFormField(
                controller: _pack,
                decoration: const InputDecoration(labelText: 'Pack', hintText: 'Strip of 15'),
                validator: _required,
                onChanged: (v) {
                  if (widget.isNew) _units.text = '${PackUnits.fromLabel(v)}';
                },
              ),
              TextFormField(
                controller: _units,
                decoration: const InputDecoration(labelText: 'Units per pack', helperText: 'Tablets in a strip; 1 for bottles'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'At least 1' : null,
              ),
            ]),
            row([
              DropdownButtonFormField<ScheduleType>(
                initialValue: _schedule,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Drug schedule'),
                items: [
                  for (final s in ScheduleType.values) DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() => _schedule = v ?? ScheduleType.unknown),
                validator: (v) => v == ScheduleType.unknown ? 'Classify before selling' : null,
                autovalidateMode: AutovalidateMode.onUserInteraction,
              ),
              DropdownButtonFormField<double>(
                initialValue: _gst,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'GST rate'),
                items: [for (final r in gstRates) DropdownMenuItem(value: r, child: Text('${r.toStringAsFixed(0)}%'))],
                onChanged: (v) => setState(() => _gst = v ?? 12.0),
              ),
            ]),
            row([
              TextFormField(
                controller: _hsn,
                decoration: const InputDecoration(labelText: 'HSN code'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
                validator: (v) => (v ?? '').length < 4 ? '4–8 digits' : null,
              ),
              TextFormField(controller: _category, decoration: const InputDecoration(labelText: 'Category')),
            ]),
            row([
              TextFormField(
                controller: _minStock,
                decoration: const InputDecoration(labelText: 'Reorder below (packs)'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              TextFormField(controller: _shelf, decoration: const InputDecoration(labelText: 'Shelf / rack')),
            ]),
            row([
              TextFormField(
                controller: _barcode,
                decoration: InputDecoration(
                  labelText: 'Barcode (EAN/GTIN)',
                  helperText: 'Scan the pack to fill',
                  suffixIcon: DeviceFeatures.cameraScanning
                      ? IconButton(
                          tooltip: 'Scan with camera',
                          icon: const Icon(PhosphorIconsRegular.scanSmiley),
                          onPressed: () async {
                            final code = await scanSingleBarcode(context);
                            final gtin = code == null ? null : (Gs1Parser.parse(code).gtin ?? code);
                            if (gtin != null && RegExp(r'^\d{8,14}$').hasMatch(gtin)) _barcode.text = gtin;
                          },
                        )
                      : null,
                ),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
              ),
            ]),
            if (_schedule == ScheduleType.unknown)
              Text('Unclassified medicines can\'t be sold (Rule 11). Pick OTC, H, H1 or X.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.warning)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _busy ? null : _submit, child: Text(widget.save ? 'Save' : 'Use')),
      ],
    );
  }
}
