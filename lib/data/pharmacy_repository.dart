import '../domain/services/batch_correction.dart';
import '../domain/models/app_user.dart';
import 'dart:typed_data';

import '../domain/models/batch.dart';
import '../domain/models/bill_scan.dart';
import '../domain/models/customer_credit.dart';
import '../domain/models/medicine.dart';
import '../domain/models/purchase_record.dart';
import '../domain/models/sale_invoice.dart';
import '../domain/models/scan_link.dart';
import '../domain/models/sale_return.dart';
import '../domain/models/store_profile.dart';
import '../domain/models/supplier_account.dart';
import '../domain/services/checkout_engine.dart';
import '../domain/services/stock_adjustment.dart';
import '../domain/services/stock_receipt.dart';

/// Who is performing an operation — recorded on every write.
class Actor {
  final String uid;
  final String name;
  final UserRole role;

  const Actor({required this.uid, required this.name, required this.role});

  factory Actor.of(AppUser user) => Actor(uid: user.uid, name: user.name, role: user.role);
}

/// An operation the signed-in role isn't allowed to perform. The Firestore
/// security rules enforce the same thing server-side; this check just gives
/// a clear message instead of a generic permission-denied error.
class NotPermittedException implements Exception {
  final String message;
  const NotPermittedException(this.message);

  @override
  String toString() => message;
}

/// A business-rule failure the user can fix (bad input, stale data).
class OperationException implements Exception {
  final List<String> problems;
  const OperationException(this.problems);

  @override
  String toString() => problems.join('\n');
}

/// Everything the app reads and writes for one store. Implementations:
/// [FirestorePharmacyRepository] (shared by every device, real-time) and
/// [LocalPharmacyRepository] (in-memory demo, used by the web preview and tests).
abstract class PharmacyRepository {
  String get storeId;
  Actor get actor;

  /// True when backed by the shared cloud database.
  bool get isShared;

  Stream<StoreProfile> watchStore();
  Stream<List<Medicine>> watchMedicines();
  Stream<List<Batch>> watchBatches();
  Stream<List<SaleInvoice>> watchRecentSales({int limit = 300});
  Future<List<SaleInvoice>> salesBetween(DateTime from, DateTime to);
  Stream<List<PurchaseRecord>> watchRecentPurchases({int limit = 200});
  Stream<List<CustomerCredit>> watchCustomers();
  Stream<List<CreditLedgerEntry>> watchLedger(String customerId);

  /// Atomically validates the bill against current stock, decrements the
  /// batches, issues the next invoice number, and records the sale (plus the
  /// credit-ledger entry for udhaar sales). Throws [CheckoutException].
  Future<SaleInvoice> checkout(CheckoutRequest request);

  /// Marks a sale cancelled with a reason, returns its stock, reverses any
  /// credit, and writes an audit entry. Managers only.
  Future<void> cancelSale(String saleId, String reason);

  /// Changes a completed bill, all at once: the old bill's stock goes back,
  /// the corrected bill is checked against stock and saved under the same
  /// invoice number and date, the old bill is kept (cancelled, marked
  /// "edited") as the record of what it said, and any udhaar is moved from
  /// the old amount to the new. Managers only; not for bills with returns.
  Future<SaleInvoice> editSale(String saleId, CheckoutRequest request);

  /// Records a supplier delivery: creates the medicine if it's new to the
  /// store, creates or tops up the batch, and logs the purchase. Managers only.
  /// With a supplier name it also adds the cost to that supplier's bill
  /// (cash or credit) in Purchase & Payment; returns false if only the stock
  /// could be saved (the bill part was refused, e.g. rules not yet published).
  Future<bool> receiveStock(StockReceipt receipt);

  /// A customer returning medicines from a bill: puts them back in stock,
  /// records the refund (cash, UPI, or less udhaar) on today's figures, and
  /// notes the returned units on the bill. Managers only.
  Future<SaleReturn> returnSaleItems({
    required String saleId,
    required Map<int, int> units,
    required RefundMode refundMode,
    String reason = '',
  });

  Future<List<SaleReturn>> returnsBetween(DateTime from, DateTime to);
  Stream<List<SaleReturn>> watchReturnsFor(String saleId);

  /// Sets a batch's stock to a counted figure (empty it, more, less), with
  /// the reason in the audit trail. Managers only.
  Future<void> adjustBatchStock(String batchId, StockAdjustment adjustment);

  // ---------------------------------------- distributors, purchase & payment

  Stream<List<Distributor>> watchDistributors();
  Stream<List<SupplierBill>> watchSupplierBills();
  Stream<List<SupplierPayment>> watchSupplierPayments();

  /// Adds or edits a distributor. Managers only.
  Future<void> saveDistributor(Distributor distributor);

  /// Adds or edits a supplier bill (also old bills owed from before).
  /// Never deleted — set [SupplierBill.cancelled]. Managers only.
  Future<void> saveSupplierBill(SupplierBill bill);

  /// Adds or edits a payment to a distributor or MR. Managers only.
  Future<void> saveSupplierPayment(SupplierPayment payment);

  /// Creates or updates a medicine master record. Managers only.
  Future<void> saveMedicine(Medicine medicine);

  /// A fresh id for a medicine that isn't in the master catalogue.
  String newMedicineId();

  Future<void> setBatchBlocked(String batchId, bool blocked);

  /// Corrects how many units one pack holds (e.g. a syrup stored as 60 per
  /// bottle → 1) and converts every batch's stock and the reorder level so
  /// the number of packs stays the same. Managers only; in the audit trail.
  Future<void> changeUnitsPerPack(String medicineId, int newUnitsPerPack);

  /// Fixes a received batch's expiry, received date, MRP or purchase price.
  /// Managers only; never changes the quantity; logged in the audit trail.
  Future<void> correctBatch(String batchId, BatchCorrection correction);

  Future<CustomerCredit> createCustomer({
    required String name,
    required String phone,
    int creditLimitPaise = 0,
  });

  Future<void> receiveCreditPayment({
    required String customerId,
    required int amountPaise,
    String notes = '',
  });

  Future<void> updateStore(StoreProfile profile);

  // ------------------------------------------------ photographed supplier bills

  Stream<List<BillScan>> watchBillScans({int limit = 60});

  /// Saves a photographed bill (any staff member may capture one). The
  /// [jpeg] picture is stored separately and must be under 900 KB.
  Future<BillScan> createBillScan({required BillDraft draft, required String ocrText, Uint8List? jpeg});

  /// Saves corrections to a draft. Managers, or the person who captured it.
  Future<void> updateBillScanDraft(String id, BillDraft draft);

  Future<Uint8List?> billScanImage(String id);

  /// Marks a bill received (managers, after its lines became stock) or
  /// discarded (never deleted — the picture stays on record).
  Future<void> setBillScanStatus(String id, BillScanStatus status, {int receivedLines = 0});

  // ----------------------------------------------- phone → counter scanning

  Stream<List<ScanStation>> watchStations();
  Future<void> saveStation(ScanStation station);
  Future<void> sendScan(ScanEvent event);
  Stream<List<ScanEvent>> watchScansFor(String stationId);
  /// Every scan this device/user has sent, whatever its status — powers the
  /// "not delivered" list (scans no counter picked up in time).
  Stream<List<ScanEvent>> watchSentScans(String uid);
  Future<void> markScanDone(String eventId);
  /// Only the phone that sent it can call this — the 3-second undo window.
  Future<void> markScanCancelled(String eventId);
  String newId();

  void dispose() {}
}

void requireManager(Actor actor, String action) {
  if (!actor.role.canManageStock) {
    throw NotPermittedException('Only an owner or pharmacist can $action.');
  }
}
