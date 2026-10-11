import '../models/batch.dart';
import '../models/medicine.dart';
import '../models/sale_invoice.dart';
import '../models/schedule_type.dart';
import 'billing_calculator.dart';

/// What the counter asks to sell: a quantity from one specific batch.
class CheckoutLineRequest {
  final String medicineId;
  final String batchId;
  final int quantity; // base units

  const CheckoutLineRequest({required this.medicineId, required this.batchId, required this.quantity});
}

class CheckoutRequest {
  final List<CheckoutLineRequest> lines;
  final PaymentMode paymentMode;
  final String customerName;
  final String customerPhone;
  final String? customerId; // required for credit sales
  final PrescriptionRecord? prescription;

  const CheckoutRequest({
    required this.lines,
    required this.paymentMode,
    this.customerName = '',
    this.customerPhone = '',
    this.customerId,
    this.prescription,
  });
}

class CheckoutException implements Exception {
  final List<String> problems;
  const CheckoutException(this.problems);

  @override
  String toString() => problems.join('\n');
}

class CheckoutPlan {
  final List<SaleLine> lines;
  final BillSummary summary;
  final Map<String, int> newBatchQuantities; // batchId → remaining units

  const CheckoutPlan({required this.lines, required this.summary, required this.newBatchQuantities});
}

/// Validates a sale against the *current* medicine and batch records — read
/// inside the same transaction that will write the result (Rule 3) — and
/// prices it from the batch's MRP, not from whatever the cart displayed.
class CheckoutEngine {
  static CheckoutPlan plan({
    required CheckoutRequest request,
    required Map<String, Medicine> medicines,
    required Map<String, Batch> batches,
    required DateTime now,
  }) {
    final problems = <String>[];
    if (request.lines.isEmpty) {
      throw const CheckoutException(['The bill is empty.']);
    }

    final requestedPerBatch = <String, int>{};
    for (final line in request.lines) {
      if (line.quantity <= 0) {
        problems.add('Quantities must be greater than zero.');
        continue;
      }
      requestedPerBatch.update(line.batchId, (v) => v + line.quantity, ifAbsent: () => line.quantity);
    }

    final saleLines = <SaleLine>[];
    final newQuantities = <String, int>{};
    final schedules = <ScheduleType>{};

    for (final entry in requestedPerBatch.entries) {
      final batch = batches[entry.key];
      if (batch == null) {
        problems.add('A batch on this bill no longer exists. Remove it and add the medicine again.');
        continue;
      }
      final medicine = medicines[batch.medicineId];
      final name = medicine?.name ?? 'Unknown item';
      if (medicine == null) {
        problems.add('$name is no longer in the medicine master.');
        continue;
      }
      if (!medicine.scheduleType.isSellable) {
        problems.add('$name is unclassified. A pharmacist must set its drug schedule before it can be sold.');
      }
      if (batch.isBlocked) {
        problems.add('$name batch ${batch.batchNumber} is blocked.');
      }
      if (batch.isExpiredAt(now)) {
        problems.add('$name batch ${batch.batchNumber} has expired.');
      }
      if (batch.quantity < entry.value) {
        problems.add('$name batch ${batch.batchNumber}: only ${batch.quantity} left, ${entry.value} on the bill.');
      }
      schedules.add(medicine.scheduleType);
      newQuantities[batch.id] = batch.quantity - entry.value;

      final lineTotal = BillingCalculator.linePaise(
        mrpPaisePerPack: batch.mrpPaise,
        unitsPerPack: medicine.unitsPerPack,
        quantityUnits: entry.value,
      );
      final cost = BillingCalculator.linePaise(
        mrpPaisePerPack: batch.purchasePricePaise,
        unitsPerPack: medicine.unitsPerPack,
        quantityUnits: entry.value,
      );
      saleLines.add(SaleLine(
        medicineId: medicine.id,
        batchId: batch.id,
        name: medicine.name,
        batchNumber: batch.batchNumber,
        expiryDate: batch.expiryDate,
        hsnCode: medicine.hsnCode,
        gstRate: medicine.gstRate,
        scheduleType: medicine.scheduleType,
        unitsPerPack: medicine.unitsPerPack,
        quantity: entry.value,
        mrpPaise: batch.mrpPaise,
        lineTotalPaise: lineTotal,
        costPaise: cost,
      ));
    }

    if (schedules.any((s) => s.requiresRegisterEntry) &&
        !(request.prescription?.isComplete ?? false)) {
      problems.add('This bill has a Schedule H1/X medicine: patient name, mobile, doctor name '
          'and doctor registration number are required.');
    }
    if (request.paymentMode == PaymentMode.credit && request.customerId == null) {
      problems.add('Choose a customer account for a credit (udhaar) sale.');
    }

    if (problems.isNotEmpty) throw CheckoutException(problems.toSet().toList());

    return CheckoutPlan(
      lines: saleLines,
      summary: BillingCalculator.summarise(saleLines.map((l) => l.billLine)),
      newBatchQuantities: newQuantities,
    );
  }
}
