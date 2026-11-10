import '../models/medicine.dart';
import '../models/sale_invoice.dart';
import 'checkout_engine.dart';

/// Shared rules for changing a completed bill (see
/// `PharmacyRepository.editSale`).
class SaleEdit {
  /// Why [sale] can't be edited, or null if it can.
  static String? refusal(SaleInvoice sale) {
    if (sale.isCancelled) return 'This bill is cancelled and can no longer be edited.';
    if (sale.hasReturns) return 'Items from this bill were returned, so it can no longer be edited.';
    return null;
  }

  /// Units of each batch that go back into stock when [sale] is replaced
  /// (in today's units, if a medicine's pack size changed since).
  static Map<String, int> stockBack(SaleInvoice sale, Map<String, Medicine> medicines) {
    final back = <String, int>{};
    for (final line in sale.lines) {
      final units = medicines[line.medicineId]?.unitsNowFor(line.quantity, line.unitsPerPack) ?? line.quantity;
      back.update(line.batchId, (v) => v + units, ifAbsent: () => units);
    }
    return back;
  }

  /// The corrected bill: same id-less identity as the old one (number, date,
  /// who first billed it), with the newly checked lines and payment.
  static SaleInvoice corrected({
    required String id,
    required SaleInvoice old,
    required CheckoutRequest request,
    required CheckoutPlan plan,
    required String actorUid,
    required String actorName,
    required DateTime now,
    required String customerName,
    required String customerPhone,
    required String? customerId,
  }) {
    final split = CheckoutEngine.splitOf(request, plan.summary.payablePaise);
    return SaleInvoice(
      id: id,
      storeId: old.storeId,
      invoiceNumber: old.invoiceNumber,
      createdAt: old.createdAt,
      createdBy: actorUid,
      createdByName: old.createdByName,
      customerName: customerName,
      customerPhone: customerPhone,
      customerId: customerId,
      paymentMode: request.paymentMode,
      lines: plan.lines,
      slabs: plan.summary.slabs,
      grossPaise: plan.summary.grossPaise,
      payablePaise: plan.summary.payablePaise,
      billDiscountPaise: request.billDiscountPaise,
      cashPaise: split.cash,
      upiPaise: split.upi,
      prescription: plan.lines.any((l) => l.scheduleType.requiresRegisterEntry) ? request.prescription : null,
      revisionOf: old.id,
      editedAt: now,
      editedByName: actorName,
    );
  }
}
