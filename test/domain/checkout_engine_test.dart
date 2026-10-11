import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/batch.dart';
import 'package:nuskha_pms/domain/models/medicine.dart';
import 'package:nuskha_pms/domain/models/sale_invoice.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';
import 'package:nuskha_pms/domain/services/checkout_engine.dart';

import '../support/fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 11, 10);
  final dolo = medicine('dolo');
  final alprax = medicine('alprax', name: 'Alprax 0.25', schedule: ScheduleType.scheduleH1, unitsPerPack: 10);
  final unknown = medicine('mystery', name: 'Mystery Syrup', schedule: ScheduleType.unknown, unitsPerPack: 1);

  final doloBatch = batch('dolo', 'D1', expiry: DateTime(2027, 6, 30), quantity: 45, mrpPaise: 3360, costPaise: 2400);
  final alpraxBatch = batch('alprax', 'A1', expiry: DateTime(2027, 6, 30), quantity: 20, mrpPaise: 4000);
  final expired = batch('dolo', 'OLD', expiry: DateTime(2026, 9, 30), quantity: 15);
  final unknownBatch = batch('mystery', 'M1', expiry: DateTime(2027, 6, 30), quantity: 5, mrpPaise: 9000);

  final medicines = {for (final m in [dolo, alprax, unknown]) m.id: m};
  final batches = {for (final b in [doloBatch, alpraxBatch, expired, unknownBatch]) b.id: b};

  CheckoutPlan plan(List<CheckoutLineRequest> lines,
          {PaymentMode mode = PaymentMode.cash, String? customerId, PrescriptionRecord? rx}) =>
      CheckoutEngine.plan(
        request: CheckoutRequest(lines: lines, paymentMode: mode, customerId: customerId, prescription: rx),
        medicines: medicines,
        batches: batches,
        now: now,
      );

  Matcher problemContaining(String text) =>
      isA<CheckoutException>().having((e) => e.problems.join(' '), 'problems', contains(text));

  test('prices from the batch MRP and decrements base units', () {
    final result = plan([CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatch.id, quantity: 20)]);
    final line = result.lines.single;
    expect(line.lineTotalPaise, 4480); // ₹33.60 × 20/15
    expect(line.costPaise, 3200); // ₹24.00 × 20/15
    expect(result.newBatchQuantities[doloBatch.id], 25);
    expect(result.summary.payablePaise, 4500);
  });

  test('merges repeated lines of the same batch before checking stock', () {
    final line = CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatch.id, quantity: 30);
    expect(() => plan([line, line]), throwsA(problemContaining('only 45 left, 60 on the bill')));
  });

  test('refuses to oversell, sell expired stock or sell unclassified drugs (Rule 11)', () {
    expect(() => plan([CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatch.id, quantity: 46)]),
        throwsA(problemContaining('only 45 left')));
    expect(() => plan([CheckoutLineRequest(medicineId: 'dolo', batchId: expired.id, quantity: 1)]),
        throwsA(problemContaining('has expired')));
    expect(() => plan([CheckoutLineRequest(medicineId: 'mystery', batchId: unknownBatch.id, quantity: 1)]),
        throwsA(problemContaining('unclassified')));
  });

  test('blocks a Schedule H1 sale until patient and prescriber are recorded (Rule 9)', () {
    final line = CheckoutLineRequest(medicineId: 'alprax', batchId: alpraxBatch.id, quantity: 10);
    expect(() => plan([line]), throwsA(problemContaining('Schedule H1/X')));
    const partial = PrescriptionRecord(patientName: 'Ramesh', patientPhone: '', doctorName: 'Dr Jain', doctorRegistrationNumber: 'MP-1');
    expect(() => plan([line], rx: partial), throwsA(problemContaining('Schedule H1/X')));
    const full = PrescriptionRecord(
        patientName: 'Ramesh', patientPhone: '9826000000', doctorName: 'Dr Jain', doctorRegistrationNumber: 'MP-1');
    expect(plan([line], rx: full).lines.single.quantity, 10);
  });

  test('a credit sale needs a customer account', () {
    final line = CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatch.id, quantity: 1);
    expect(() => plan([line], mode: PaymentMode.credit), throwsA(problemContaining('customer account')));
    expect(plan([line], mode: PaymentMode.credit, customerId: 'c1').lines, hasLength(1));
  });

  test('rejects an empty bill, zero quantities and unknown batches', () {
    expect(() => plan([]), throwsA(problemContaining('empty')));
    expect(() => plan([CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatch.id, quantity: 0)]),
        throwsA(problemContaining('greater than zero')));
    expect(() => plan([const CheckoutLineRequest(medicineId: 'dolo', batchId: 'nope', quantity: 1)]),
        throwsA(problemContaining('no longer exists')));
  });

  test('blocked batches cannot be sold', () {
    final blocked = batch('dolo', 'BLK', expiry: DateTime(2027, 1, 31), blocked: true);
    expect(
      () => CheckoutEngine.plan(
        request: CheckoutRequest(
            lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: blocked.id, quantity: 1)],
            paymentMode: PaymentMode.cash),
        medicines: <String, Medicine>{'dolo': dolo},
        batches: <String, Batch>{blocked.id: blocked},
        now: now,
      ),
      throwsA(problemContaining('blocked')),
    );
  });
}
