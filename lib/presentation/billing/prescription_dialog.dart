import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/sale_invoice.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Rule 9: Schedule H1/X sales are blocked until patient and prescriber are
/// recorded. Returns null if the pharmacist backs out (the sale isn't made).
Future<PrescriptionRecord?> showPrescriptionDialog(
  BuildContext context, {
  String patientName = '',
  String patientPhone = '',
  String doctorName = '',
  String doctorRegistrationNumber = '',
}) {
  return showDialog<PrescriptionRecord>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PrescriptionDialog(
      patientName: patientName,
      patientPhone: patientPhone,
      doctorName: doctorName,
      doctorRegistrationNumber: doctorRegistrationNumber,
    ),
  );
}

class _PrescriptionDialog extends StatefulWidget {
  const _PrescriptionDialog({
    required this.patientName,
    required this.patientPhone,
    required this.doctorName,
    required this.doctorRegistrationNumber,
  });
  final String patientName;
  final String patientPhone;
  final String doctorName;
  final String doctorRegistrationNumber;

  @override
  State<_PrescriptionDialog> createState() => _PrescriptionDialogState();
}

class _PrescriptionDialogState extends State<_PrescriptionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _patient = TextEditingController(text: widget.patientName);
  late final _phone = TextEditingController(text: widget.patientPhone);
  late final _doctor = TextEditingController(text: widget.doctorName);
  late final _registration = TextEditingController(text: widget.doctorRegistrationNumber);

  @override
  void dispose() {
    for (final c in [_patient, _phone, _doctor, _registration]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Schedule H1 register entry'),
      content: DialogBody(
        child: Form(
          key: _formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'This bill contains a Schedule H1/X medicine. Record the patient and prescribing doctor '
              'before dispensing — this entry is kept for 3 years.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: Space.l),
            TextFormField(
              controller: _patient,
              decoration: const InputDecoration(labelText: 'Patient name'),
              textCapitalization: TextCapitalization.words,
              validator: _required,
            ),
            const SizedBox(height: Space.m),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(labelText: 'Patient mobile'),
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')), LengthLimitingTextInputFormatter(15)],
              validator: (v) {
                final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                return digits.length < 10 ? 'Enter a 10-digit mobile number' : null;
              },
            ),
            const SizedBox(height: Space.m),
            TextFormField(
              controller: _doctor,
              decoration: const InputDecoration(labelText: 'Doctor name'),
              textCapitalization: TextCapitalization.words,
              validator: _required,
            ),
            const SizedBox(height: Space.m),
            TextFormField(
              controller: _registration,
              decoration: const InputDecoration(labelText: 'Doctor registration no.'),
              textCapitalization: TextCapitalization.characters,
              validator: _required,
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back to bill')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              PrescriptionRecord(
                patientName: _patient.text.trim(),
                patientPhone: _phone.text.trim(),
                doctorName: _doctor.text.trim(),
                doctorRegistrationNumber: _registration.text.trim().toUpperCase(),
              ),
            );
          },
          child: const Text('Save & continue'),
        ),
      ],
    );
  }
}
