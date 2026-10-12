import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/batch.dart';
import '../domain/models/bill_scan.dart';
import '../domain/models/customer_credit.dart';
import '../domain/models/medicine.dart';
import '../domain/models/purchase_record.dart';
import '../domain/models/sale_invoice.dart';
import '../domain/models/scan_link.dart';
import '../domain/models/store_profile.dart';
import '../domain/services/billing_calculator.dart';
import '../domain/services/checkout_engine.dart';
import '../domain/services/invoice_number.dart';
import '../domain/services/stock_receipt.dart';
import 'pharmacy_repository.dart';

/// Cloud Firestore backend shared by every device of the store.
///
/// Layout (all under stores/{storeId}, see firestore.rules):
///   medicines/{id}, batches/{id}, sales/{id}, purchases/{id},
///   customers/{id}/ledger/{id}, counters/{financialYear}, auditLog/{id}
///
/// Every stock movement runs in a transaction that reads everything it needs
/// before writing anything (Rule 3), so two counters selling the last strip
/// at the same moment cannot both succeed.
class FirestorePharmacyRepository implements PharmacyRepository {
  FirestorePharmacyRepository(this._db, {required this.storeId, required this.actor});

  final FirebaseFirestore _db;

  @override
  final String storeId;

  @override
  final Actor actor;

  @override
  bool get isShared => true;

  DocumentReference<Map<String, dynamic>> get _store => _db.collection('stores').doc(storeId);
  CollectionReference<Map<String, dynamic>> get _medicines => _store.collection('medicines');
  CollectionReference<Map<String, dynamic>> get _batches => _store.collection('batches');
  CollectionReference<Map<String, dynamic>> get _sales => _store.collection('sales');
  CollectionReference<Map<String, dynamic>> get _purchases => _store.collection('purchases');
  CollectionReference<Map<String, dynamic>> get _customers => _store.collection('customers');
  CollectionReference<Map<String, dynamic>> get _audit => _store.collection('auditLog');
  CollectionReference<Map<String, dynamic>> get _billScans => _store.collection('billScans');
  CollectionReference<Map<String, dynamic>> get _billImages => _store.collection('billScanImages');
  CollectionReference<Map<String, dynamic>> get _stations => _store.collection('stations');
  CollectionReference<Map<String, dynamic>> get _scanEvents => _store.collection('scanEvents');

  /// Firestore documents are limited to 1 MiB; keep the picture well under.
  static const maxImageBytes = 900 * 1024;

  /// Firestore returns [Timestamp]s; domain models only know [DateTime].
  static Object? _normalise(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is Map) return value.map((k, v) => MapEntry(k as String, _normalise(v)));
    if (value is List) return value.map(_normalise).toList();
    return value;
  }

  static Map<String, dynamic> _read(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = Map<String, dynamic>.from(_normalise(snapshot.data() ?? const {}) as Map);
    data['id'] = (data['id'] as String?)?.isNotEmpty == true ? data['id'] : snapshot.id;
    return data;
  }

  Map<String, dynamic> _auditEntry(String action, String refId, String details) => {
        'storeId': storeId,
        'action': action,
        'refId': refId,
        'details': details,
        'uid': actor.uid,
        'userName': actor.name,
        'timestamp': DateTime.now(),
      };

  @override
  Stream<StoreProfile> watchStore() => _store.snapshots().map((s) {
        final data = _read(s);
        data['storeId'] = storeId;
        return StoreProfile.fromMap(data);
      });

  @override
  Stream<List<Medicine>> watchMedicines() => _medicines.snapshots().map((q) =>
      q.docs.map((d) => Medicine.fromMap(_read(d))).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  @override
  Stream<List<Batch>> watchBatches() =>
      _batches.snapshots().map((q) => q.docs.map((d) => Batch.fromMap(_read(d))).toList());

  @override
  Stream<List<SaleInvoice>> watchRecentSales({int limit = 300}) => _sales
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map((d) => SaleInvoice.fromMap(_read(d))).toList());

  @override
  Future<List<SaleInvoice>> salesBetween(DateTime from, DateTime to) async {
    final q = await _sales
        .where('createdAt', isGreaterThanOrEqualTo: from)
        .where('createdAt', isLessThan: to)
        .orderBy('createdAt', descending: true)
        .get();
    return q.docs.map((d) => SaleInvoice.fromMap(_read(d))).toList();
  }

  @override
  Stream<List<PurchaseRecord>> watchRecentPurchases({int limit = 200}) => _purchases
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map((d) => PurchaseRecord.fromMap(_read(d))).toList());

  @override
  Stream<List<CustomerCredit>> watchCustomers() => _customers.snapshots().map((q) =>
      q.docs.map((d) => CustomerCredit.fromMap(_read(d))).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  @override
  Stream<List<CreditLedgerEntry>> watchLedger(String customerId) => _customers
      .doc(customerId)
      .collection('ledger')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((q) => q.docs.map((d) => CreditLedgerEntry.fromMap(_read(d))).toList());

  @override
  Future<SaleInvoice> checkout(CheckoutRequest request) {
    final saleRef = _sales.doc();
    return _db.runTransaction<SaleInvoice>((tx) async {
      final now = DateTime.now();
      final counterRef = _store.collection('counters').doc(InvoiceNumber.financialYear(now));

      // ---- reads (all before any write) ----
      final counterSnap = await tx.get(counterRef);
      final batches = <String, Batch>{};
      for (final id in request.lines.map((l) => l.batchId).toSet()) {
        final snap = await tx.get(_batches.doc(id));
        if (snap.exists) batches[id] = Batch.fromMap(_read(snap));
      }
      final medicines = <String, Medicine>{};
      for (final id in batches.values.map((b) => b.medicineId).toSet()) {
        final snap = await tx.get(_medicines.doc(id));
        if (snap.exists) medicines[id] = Medicine.fromMap(_read(snap));
      }
      CustomerCredit? customer;
      if (request.paymentMode == PaymentMode.credit && request.customerId != null) {
        final snap = await tx.get(_customers.doc(request.customerId));
        if (!snap.exists) throw const CheckoutException(['That customer account no longer exists.']);
        customer = CustomerCredit.fromMap(_read(snap));
      }

      final plan = CheckoutEngine.plan(request: request, medicines: medicines, batches: batches, now: now);
      if (customer != null &&
          customer.creditLimitPaise > 0 &&
          customer.outstandingBalancePaise + plan.summary.payablePaise > customer.creditLimitPaise) {
        throw CheckoutException([
          '${customer.name} would exceed their credit limit of ${formatRupees(customer.creditLimitPaise)} '
              '(outstanding ${formatRupees(customer.outstandingBalancePaise)}).',
        ]);
      }

      final serial = counterSnap.exists ? (counterSnap.data()!['next'] as num).toInt() : 1;
      final sale = SaleInvoice(
        id: saleRef.id,
        storeId: storeId,
        invoiceNumber: InvoiceNumber.format(now, serial),
        createdAt: now,
        createdBy: actor.uid,
        createdByName: actor.name,
        customerName: customer?.name ??
            (request.customerName.trim().isEmpty ? 'Walk-in Customer' : request.customerName.trim()),
        customerPhone: customer?.phoneNumber ?? request.customerPhone.trim(),
        customerId: customer?.id,
        paymentMode: request.paymentMode,
        lines: plan.lines,
        slabs: plan.summary.slabs,
        grossPaise: plan.summary.grossPaise,
        payablePaise: plan.summary.payablePaise,
        prescription: plan.lines.any((l) => l.scheduleType.requiresRegisterEntry) ? request.prescription : null,
      );

      // ---- writes ----
      for (final entry in plan.newBatchQuantities.entries) {
        tx.update(_batches.doc(entry.key), {'quantity': entry.value});
      }
      if (counterSnap.exists) {
        tx.update(counterRef, {'next': serial + 1});
      } else {
        tx.set(counterRef, {'storeId': storeId, 'next': serial + 1});
      }
      tx.set(saleRef, sale.toMap());
      if (customer != null) {
        final entryRef = _customers.doc(customer.id).collection('ledger').doc();
        tx.update(_customers.doc(customer.id), {
          'outstandingBalancePaise': customer.outstandingBalancePaise + sale.payablePaise,
        });
        tx.set(
          entryRef,
          CreditLedgerEntry(
            id: entryRef.id,
            storeId: storeId,
            customerId: customer.id,
            type: CreditEntryType.creditSale,
            amountPaise: sale.payablePaise,
            invoiceNumber: sale.invoiceNumber,
            timestamp: now,
            createdBy: actor.uid,
            createdByName: actor.name,
          ).toMap(),
        );
      }
      return sale;
    });
  }

  @override
  Future<void> cancelSale(String saleId, String reason) async {
    requireManager(actor, 'cancel a sale');
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw const OperationException(['Enter a reason for cancelling.']);
    await _db.runTransaction<void>((tx) async {
      final saleSnap = await tx.get(_sales.doc(saleId));
      if (!saleSnap.exists) throw const OperationException(['Sale not found.']);
      final sale = SaleInvoice.fromMap(_read(saleSnap));
      if (sale.isCancelled) throw const OperationException(['This sale is already cancelled.']);

      final returned = <String, int>{};
      for (final line in sale.lines) {
        returned.update(line.batchId, (v) => v + line.quantity, ifAbsent: () => line.quantity);
      }
      final batchQuantities = <String, int>{};
      for (final id in returned.keys) {
        final snap = await tx.get(_batches.doc(id));
        if (snap.exists) batchQuantities[id] = (snap.data()!['quantity'] as num).toInt();
      }
      CustomerCredit? customer;
      if (sale.customerId != null) {
        final snap = await tx.get(_customers.doc(sale.customerId));
        if (snap.exists) customer = CustomerCredit.fromMap(_read(snap));
      }

      final now = DateTime.now();
      tx.update(_sales.doc(saleId), {
        'status': SaleStatus.cancelled.name,
        'cancellationReason': trimmed,
        'cancelledAt': now,
        'cancelledBy': actor.uid,
        'cancelledByName': actor.name,
      });
      for (final entry in batchQuantities.entries) {
        tx.update(_batches.doc(entry.key), {'quantity': entry.value + returned[entry.key]!});
      }
      if (customer != null) {
        final entryRef = _customers.doc(customer.id).collection('ledger').doc();
        tx.update(_customers.doc(customer.id), {
          'outstandingBalancePaise': customer.outstandingBalancePaise - sale.payablePaise,
        });
        tx.set(
          entryRef,
          CreditLedgerEntry(
            id: entryRef.id,
            storeId: storeId,
            customerId: customer.id,
            type: CreditEntryType.saleCancelled,
            amountPaise: sale.payablePaise,
            invoiceNumber: sale.invoiceNumber,
            notes: trimmed,
            timestamp: now,
            createdBy: actor.uid,
            createdByName: actor.name,
          ).toMap(),
        );
      }
      tx.set(_audit.doc(), _auditEntry('sale_cancelled', saleId, '${sale.invoiceNumber}: $trimmed'));
    });
  }

  @override
  Future<void> receiveStock(StockReceipt receipt) async {
    requireManager(actor, 'receive stock');
    final medicine = receipt.medicine.copyWith(storeId: storeId);
    final batchRef = _batches.doc(receipt.batchId);
    final medicineRef = _medicines.doc(medicine.id);
    final purchaseRef = _purchases.doc();

    await _db.runTransaction<void>((tx) async {
      final now = DateTime.now();
      final medicineSnap = await tx.get(medicineRef);
      final batchSnap = await tx.get(batchRef);
      final existing = batchSnap.exists ? Batch.fromMap(_read(batchSnap)) : null;

      final problems = receipt.validate(now: now, existing: existing);
      if (problems.isNotEmpty) throw OperationException(problems);

      if (!medicineSnap.exists) {
        tx.set(medicineRef, medicine.copyWith(updatedAt: now).toMap());
      }
      if (existing != null) {
        tx.update(batchRef, {
          'quantity': existing.quantity + receipt.totalUnits,
          'purchasePricePaise': receipt.purchasePricePaise,
        });
      } else {
        tx.set(
          batchRef,
          Batch(
            id: receipt.batchId,
            storeId: storeId,
            medicineId: medicine.id,
            batchNumber: receipt.normalisedBatchNumber,
            expiryDate: receipt.expiryDate,
            purchasePricePaise: receipt.purchasePricePaise,
            mrpPaise: receipt.mrpPaise,
            quantity: receipt.totalUnits,
            createdAt: now,
          ).toMap(),
        );
      }
      tx.set(
        purchaseRef,
        PurchaseRecord(
          id: purchaseRef.id,
          storeId: storeId,
          medicineId: medicine.id,
          medicineName: medicine.name,
          batchId: receipt.batchId,
          batchNumber: receipt.normalisedBatchNumber,
          expiryDate: receipt.expiryDate,
          unitsPerPack: medicine.unitsPerPack,
          quantity: receipt.totalUnits,
          freeQuantity: receipt.freeUnits,
          purchasePricePaise: receipt.purchasePricePaise,
          mrpPaise: receipt.mrpPaise,
          supplierName: receipt.supplierName.trim(),
          supplierInvoiceNumber: receipt.supplierInvoiceNumber.trim(),
          billScanId: receipt.billScanId,
          createdAt: now,
          createdBy: actor.uid,
          createdByName: actor.name,
        ).toMap(),
      );
    });
  }

  @override
  Future<void> saveMedicine(Medicine medicine) async {
    requireManager(actor, 'edit the medicine master');
    final record = medicine.copyWith(storeId: storeId, updatedAt: DateTime.now());
    final batch = _db.batch()
      ..set(_medicines.doc(record.id), record.toMap())
      ..set(_audit.doc(), _auditEntry('medicine_saved', record.id,
          '${record.name}: ${record.scheduleType.label}, GST ${record.gstRate}%, HSN ${record.hsnCode}'));
    await batch.commit();
  }

  @override
  String newMedicineId() => _medicines.doc().id;

  @override
  Future<void> setBatchBlocked(String batchId, bool blocked) async {
    requireManager(actor, 'block or unblock a batch');
    final batch = _db.batch()
      ..update(_batches.doc(batchId), {'isBlocked': blocked})
      ..set(_audit.doc(), _auditEntry(blocked ? 'batch_blocked' : 'batch_unblocked', batchId, batchId));
    await batch.commit();
  }

  @override
  Future<CustomerCredit> createCustomer({
    required String name,
    required String phone,
    int creditLimitPaise = 0,
  }) async {
    if (name.trim().isEmpty) throw const OperationException(['Enter the customer\'s name.']);
    final ref = _customers.doc();
    final customer = CustomerCredit(
      id: ref.id,
      storeId: storeId,
      name: name.trim(),
      phoneNumber: phone.trim(),
      creditLimitPaise: creditLimitPaise,
      outstandingBalancePaise: 0,
      createdAt: DateTime.now(),
    );
    await ref.set(customer.toMap());
    return customer;
  }

  @override
  Future<void> receiveCreditPayment({
    required String customerId,
    required int amountPaise,
    String notes = '',
  }) async {
    if (amountPaise <= 0) throw const OperationException(['Enter the amount received.']);
    final customerRef = _customers.doc(customerId);
    final entryRef = customerRef.collection('ledger').doc();
    await _db.runTransaction<void>((tx) async {
      final snap = await tx.get(customerRef);
      if (!snap.exists) throw const OperationException(['Customer not found.']);
      final customer = CustomerCredit.fromMap(_read(snap));
      if (amountPaise > customer.outstandingBalancePaise) {
        throw OperationException([
          'Amount is more than the outstanding ${formatRupees(customer.outstandingBalancePaise)}.',
        ]);
      }
      final now = DateTime.now();
      tx.update(customerRef, {'outstandingBalancePaise': customer.outstandingBalancePaise - amountPaise});
      tx.set(
        entryRef,
        CreditLedgerEntry(
          id: entryRef.id,
          storeId: storeId,
          customerId: customerId,
          type: CreditEntryType.paymentReceived,
          amountPaise: amountPaise,
          notes: notes.trim(),
          timestamp: now,
          createdBy: actor.uid,
          createdByName: actor.name,
        ).toMap(),
      );
    });
  }

  @override
  Future<void> updateStore(StoreProfile profile) async {
    if (!actor.role.canEditStore) throw const NotPermittedException('Only the owner can edit store details.');
    final data = profile.toMap()..remove('storeId');
    final batch = _db.batch()
      ..update(_store, data)
      ..set(_audit.doc(), _auditEntry('store_updated', storeId, profile.name));
    await batch.commit();
  }

  // ------------------------------------------------ photographed supplier bills

  @override
  Stream<List<BillScan>> watchBillScans({int limit = 60}) => _billScans
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((q) => q.docs.map((d) => BillScan.fromMap(_read(d))).toList());

  @override
  Future<BillScan> createBillScan({required BillDraft draft, required String ocrText, Uint8List? jpeg}) async {
    if (jpeg != null && jpeg.length > maxImageBytes) {
      throw const OperationException(['The bill photo is too large. Take it again a little further away.']);
    }
    final ref = _billScans.doc();
    final scan = BillScan(
      id: ref.id,
      storeId: storeId,
      createdAt: DateTime.now(),
      createdBy: actor.uid,
      createdByName: actor.name,
      draft: draft,
      ocrText: ocrText,
      hasImage: jpeg != null,
    );
    final batch = _db.batch()..set(ref, scan.toMap());
    if (jpeg != null) {
      batch.set(_billImages.doc(ref.id), {'storeId': storeId, 'createdBy': actor.uid, 'jpeg': Blob(jpeg)});
    }
    await batch.commit();
    return scan;
  }

  @override
  Future<void> updateBillScanDraft(String id, BillDraft draft) =>
      _billScans.doc(id).update({'draft': draft.toMap()});

  @override
  Future<Uint8List?> billScanImage(String id) async {
    final snap = await _billImages.doc(id).get();
    final blob = snap.data()?['jpeg'];
    return blob is Blob ? blob.bytes : null;
  }

  @override
  Future<void> setBillScanStatus(String id, BillScanStatus status, {int receivedLines = 0}) async {
    if (status == BillScanStatus.received) requireManager(actor, 'receive a supplier bill');
    await _billScans.doc(id).update({
      'status': status.name,
      if (status == BillScanStatus.received) ...{
        'receivedLines': receivedLines,
        'receivedAt': DateTime.now(),
        'receivedByName': actor.name,
      },
    });
  }

  // ----------------------------------------------- phone → counter scanning

  @override
  Stream<List<ScanStation>> watchStations() =>
      _stations.snapshots().map((q) => q.docs.map((d) => ScanStation.fromMap(_read(d))).toList());

  @override
  Future<void> saveStation(ScanStation station) => _stations.doc(station.id).set(station.toMap());

  @override
  Future<void> sendScan(ScanEvent event) => _scanEvents.doc(event.id).set(event.toMap());

  @override
  Stream<List<ScanEvent>> watchScansFor(String stationId) => _scanEvents
      .where('stationId', isEqualTo: stationId)
      .snapshots()
      .map((q) => q.docs.map((d) => ScanEvent.fromMap(_read(d))).toList());

  @override
  Future<void> markScanDone(String eventId) => _scanEvents.doc(eventId).update({'status': 'done'});

  @override
  Future<void> markScanCancelled(String eventId) => _scanEvents.doc(eventId).update({'status': 'cancelled'});

  @override
  String newId() => _store.collection('_ids').doc().id;

  @override
  void dispose() {}
}
