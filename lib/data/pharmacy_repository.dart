import '../domain/models/app_user.dart';
import 'dart:typed_data';

import '../domain/models/batch.dart';
import '../domain/models/bill_scan.dart';
import '../domain/models/customer_credit.dart';
import '../domain/models/medicine.dart';
import '../domain/models/purchase_record.dart';
import '../domain/models/sale_invoice.dart';
import '../domain/models/scan_link.dart';
import '../domain/models/store_profile.dart';
import '../domain/services/checkout_engine.dart';
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

  /// Records a supplier delivery: creates the medicine if it's new to the
  /// store, creates or tops up the batch, and logs the purchase. Managers only.
  Future<void> receiveStock(StockReceipt receipt);

  /// Creates or updates a medicine master record. Managers only.
  Future<void> saveMedicine(Medicine medicine);

  /// A fresh id for a medicine that isn't in the master catalogue.
  String newMedicineId();

  Future<void> setBatchBlocked(String batchId, bool blocked);

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
  Future<void> markScanDone(String eventId);
  String newId();

  void dispose() {}
}

void requireManager(Actor actor, String action) {
  if (!actor.role.canManageStock) {
    throw NotPermittedException('Only an owner or pharmacist can $action.');
  }
}
