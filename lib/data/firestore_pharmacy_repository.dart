import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

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
import '../domain/services/batch_correction.dart';
import '../domain/services/stock_adjustment.dart';
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
  CollectionReference<Map<String, dynamic>> get _returns => _store.collection('saleReturns');
  CollectionReference<Map<String, dynamic>> get _distributors => _store.collection('distributors');
  CollectionReference<Map<String, dynamic>> get _supplierBills => _store.collection('supplierBills');
  CollectionReference<Map<String, dynamic>> get _supplierPayments => _store.collection('supplierPayments');

  /// Firestore documents are limited to 1 MiB; keep the picture well under.
  static const maxImageBytes = 900 * 1024;

  /// Firestore returns [Timestamp]s; domain models only know [DateTime].
  static Object? _normalise(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is Blob) return value.bytes;
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
        billDiscountPaise: request.billDiscountPaise,
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
      if (sale.hasReturns) {
        throw const OperationException(['Items from this bill were returned. Return the rest instead of cancelling.']);
      }

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
  Future<bool> receiveStock(StockReceipt receipt) async {
    requireManager(actor, 'receive stock');
    try {
      await _receiveStock(receipt, withAccounts: true);
      return true;
    } on FirebaseException catch (e) {
      // Until the owner publishes the rules for Purchase & Payment, the
      // supplier-bill part is refused; the stock itself must still go in.
      if (e.code != 'permission-denied' || receipt.distributorId.isEmpty) rethrow;
      await _receiveStock(receipt, withAccounts: false);
      return false;
    }
  }

  Future<void> _receiveStock(StockReceipt receipt, {required bool withAccounts}) async {
    final medicine = receipt.medicine.copyWith(storeId: storeId);
    final batchRef = _batches.doc(receipt.batchId);
    final medicineRef = _medicines.doc(medicine.id);
    final purchaseRef = _purchases.doc();

    await _db.runTransaction<void>((tx) async {
      final now = DateTime.now();
      final medicineSnap = await tx.get(medicineRef);
      final batchSnap = await tx.get(batchRef);
      final existing = batchSnap.exists ? Batch.fromMap(_read(batchSnap)) : null;
      final hasSupplier = withAccounts && receipt.distributorId.isNotEmpty;
      final billRef = hasSupplier ? _supplierBills.doc(receipt.supplierBillId(now)) : null;
      final distRef = hasSupplier ? _distributors.doc(receipt.distributorId) : null;
      final billSnap = billRef == null ? null : await tx.get(billRef);
      final distSnap = distRef == null ? null : await tx.get(distRef);

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
          supplierName: receipt.distributorName,
          supplierInvoiceNumber: receipt.supplierInvoiceNumber.trim(),
          billScanId: receipt.billScanId,
          createdAt: now,
          createdBy: actor.uid,
          createdByName: actor.name,
        ).toMap(),
      );
      if (billRef != null && distRef != null) {
        final before = billSnap!.exists ? SupplierBill.fromMap(_read(billSnap)) : null;
        final bill = receipt.billAfter(before, storeId: storeId, uid: actor.uid, userName: actor.name, now: now)!;
        if (before == null) {
          tx.set(billRef, bill.toMap());
        } else {
          tx.update(billRef, {
            'itemsPaise': bill.itemsPaise,
            'amountPaise': bill.amountPaise,
            'payment': bill.payment.name,
            'cancelled': false,
          });
        }
        if (!distSnap!.exists) {
          tx.set(distRef, Distributor(id: distRef.id, storeId: storeId, name: receipt.distributorName, createdAt: now).toMap());
        }
      }
    });
  }

  @override
  Future<SaleReturn> returnSaleItems({
    required String saleId,
    required Map<int, int> units,
    required RefundMode refundMode,
    String reason = '',
  }) async {
    requireManager(actor, 'take back a return');
    final returnRef = _returns.doc();
    return _db.runTransaction<SaleReturn>((tx) async {
      final saleSnap = await tx.get(_sales.doc(saleId));
      if (!saleSnap.exists) throw const OperationException(['Bill not found.']);
      final sale = SaleInvoice.fromMap(_read(saleSnap));
      final ReturnPlan plan;
      try {
        plan = SaleReturnPlanner.plan(sale: sale, units: units, mode: refundMode);
      } on ReturnException catch (e) {
        throw OperationException(e.problems);
      }
      final back = <String, int>{};
      for (final l in plan.lines) {
        back.update(l.batchId, (v) => v + l.quantity, ifAbsent: () => l.quantity);
      }
      final quantities = <String, int>{};
      for (final id in back.keys) {
        final snap = await tx.get(_batches.doc(id));
        if (snap.exists) quantities[id] = (snap.data()!['quantity'] as num).toInt();
      }
      CustomerCredit? customer;
      if (refundMode == RefundMode.udhaar) {
        final snap = sale.customerId == null ? null : await tx.get(_customers.doc(sale.customerId));
        if (snap == null || !snap.exists) throw const OperationException(['The udhaar account no longer exists.']);
        customer = CustomerCredit.fromMap(_read(snap));
        if (plan.refundPaise > customer.outstandingBalancePaise) {
          throw OperationException(['Only ${formatRupees(customer.outstandingBalancePaise)} udhaar is left; '
              'give the rest back in cash.']);
        }
      }

      final now = DateTime.now();
      final ret = SaleReturn(
        id: returnRef.id,
        storeId: storeId,
        saleId: sale.id,
        invoiceNumber: sale.invoiceNumber,
        customerName: sale.customerName,
        lines: plan.lines,
        refundMode: refundMode,
        reason: reason.trim(),
        createdAt: now,
        createdBy: actor.uid,
        createdByName: actor.name,
      );
      for (final entry in quantities.entries) {
        tx.update(_batches.doc(entry.key), {'quantity': entry.value + back[entry.key]!});
      }
      tx.update(_sales.doc(sale.id), {
        'returnedUnits': plan.newReturnedUnits,
        'refundedPaise': sale.refundedPaise + plan.refundPaise,
      });
      tx.set(returnRef, ret.toMap());
      if (customer != null) {
        final entryRef = _customers.doc(customer.id).collection('ledger').doc();
        tx.update(_customers.doc(customer.id), {
          'outstandingBalancePaise': customer.outstandingBalancePaise - plan.refundPaise,
        });
        tx.set(
          entryRef,
          CreditLedgerEntry(
            id: entryRef.id,
            storeId: storeId,
            customerId: customer.id,
            type: CreditEntryType.saleCancelled,
            amountPaise: plan.refundPaise,
            invoiceNumber: sale.invoiceNumber,
            notes: 'Return${reason.trim().isEmpty ? '' : ': ${reason.trim()}'}',
            timestamp: now,
            createdBy: actor.uid,
            createdByName: actor.name,
          ).toMap(),
        );
      }
      tx.set(_audit.doc(), _auditEntry('sale_return', sale.id,
          '${sale.invoiceNumber}: ${formatRupees(plan.refundPaise)} back (${refundMode.label})'
              '${reason.trim().isEmpty ? '' : ' — ${reason.trim()}'}'));
      return ret;
    });
  }

  @override
  Future<List<SaleReturn>> returnsBetween(DateTime from, DateTime to) async {
    final q = await _returns
        .where('createdAt', isGreaterThanOrEqualTo: from)
        .where('createdAt', isLessThan: to)
        .orderBy('createdAt', descending: true)
        .get();
    return q.docs.map((d) => SaleReturn.fromMap(_read(d))).toList();
  }

  @override
  Stream<List<SaleReturn>> watchReturnsFor(String saleId) => _returns
      .where('saleId', isEqualTo: saleId)
      .snapshots()
      .map((q) => q.docs.map((d) => SaleReturn.fromMap(_read(d))).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  @override
  Future<void> adjustBatchStock(String batchId, StockAdjustment adjustment) async {
    requireManager(actor, 'change stock');
    final problems = adjustment.problems();
    if (problems.isNotEmpty) throw OperationException(problems);
    final ref = _batches.doc(batchId);
    await _db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref); // read first (Rule 3)
      if (!snap.exists) throw const OperationException(['Batch not found.']);
      final batch = Batch.fromMap(_read(snap));
      if (batch.quantity == adjustment.newQuantity) return;
      tx.update(ref, {'quantity': adjustment.newQuantity});
      tx.set(_audit.doc(), _auditEntry('stock_adjusted', batchId, '${batch.batchNumber}: ${adjustment.describe(batch.quantity)}'));
    });
  }

  // ---------------------------------------- distributors, purchase & payment

  @override
  Stream<List<Distributor>> watchDistributors() => _distributors.snapshots().map((q) =>
      q.docs.map((d) => Distributor.fromMap(_read(d))).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  @override
  Stream<List<SupplierBill>> watchSupplierBills() => _supplierBills.snapshots().map((q) =>
      q.docs.map((d) => SupplierBill.fromMap(_read(d))).toList()..sort((a, b) => b.billDate.compareTo(a.billDate)));

  @override
  Stream<List<SupplierPayment>> watchSupplierPayments() => _supplierPayments.snapshots().map((q) =>
      q.docs.map((d) => SupplierPayment.fromMap(_read(d))).toList()..sort((a, b) => b.paidOn.compareTo(a.paidOn)));

  @override
  Future<void> saveDistributor(Distributor distributor) async {
    requireManager(actor, 'edit distributors');
    final problems = distributorProblems(distributor);
    if (problems.isNotEmpty) throw OperationException(problems);
    final ref = _distributors.doc(distributor.id);
    final before = await ref.get();
    final batch = _db.batch()
      ..set(ref, distributor.copyWith().toMap()..['storeId'] = storeId)
      ..set(_audit.doc(), _auditEntry('distributor_saved', distributor.id, distributor.name));
    final oldName = before.exists ? readName(before.data()) : null;
    if (oldName != null && oldName != distributor.name) {
      // Bills and payments show the name; keep them in step.
      final bills = await _supplierBills.where('distributorId', isEqualTo: distributor.id).get();
      final pays = await _supplierPayments.where('distributorId', isEqualTo: distributor.id).get();
      for (final d in [...bills.docs, ...pays.docs]) {
        batch.update(d.reference, {'distributorName': distributor.name});
      }
    }
    await batch.commit();
  }

  static String? readName(Map<String, dynamic>? data) => data?['name'] as String?;

  @override
  Future<void> saveSupplierBill(SupplierBill bill) async {
    requireManager(actor, 'record supplier bills');
    final problems = supplierBillProblems(bill);
    if (problems.isNotEmpty) throw OperationException(problems);
    final distRef = _distributors.doc(bill.distributorId);
    await _db.runTransaction<void>((tx) async {
      final ref = _supplierBills.doc(bill.id);
      final snap = await tx.get(ref);
      final distSnap = await tx.get(distRef);
      final data = bill.toMap()..['storeId'] = storeId;
      if (snap.exists) {
        final before = SupplierBill.fromMap(_read(snap));
        data
          ..remove('createdAt')
          ..remove('createdBy')
          ..remove('createdByName')
          // Stock received meanwhile on another device keeps counting.
          ..['itemsPaise'] = before.itemsPaise;
        tx.update(ref, data);
        tx.set(_audit.doc(), _auditEntry('supplier_bill_edited', bill.id,
            '${bill.distributorName} ${bill.billNumber}: ${formatRupees(before.totalPaise)} → ${formatRupees(bill.totalPaise)}'
                '${before.payment != bill.payment ? ', ${before.payment.label} → ${bill.payment.label}' : ''}'
                '${bill.cancelled && !before.cancelled ? ', removed' : ''}'));
      } else {
        tx.set(ref, data
          ..['createdBy'] = actor.uid
          ..['createdByName'] = actor.name);
        tx.set(_audit.doc(), _auditEntry('supplier_bill_added', bill.id,
            '${bill.distributorName} ${bill.billNumber}: ${formatRupees(bill.totalPaise)} ${bill.payment.label}'));
      }
      if (!distSnap.exists) {
        tx.set(distRef, Distributor(id: bill.distributorId, storeId: storeId, name: bill.distributorName, createdAt: DateTime.now()).toMap());
      }
    });
  }

  @override
  Future<void> saveSupplierPayment(SupplierPayment payment) async {
    requireManager(actor, 'record payments');
    final problems = supplierPaymentProblems(payment);
    if (problems.isNotEmpty) throw OperationException(problems);
    final distRef = _distributors.doc(payment.distributorId);
    await _db.runTransaction<void>((tx) async {
      final ref = _supplierPayments.doc(payment.id);
      final snap = await tx.get(ref);
      final distSnap = await tx.get(distRef);
      final data = payment.toMap()..['storeId'] = storeId;
      if (snap.exists) {
        final before = SupplierPayment.fromMap(_read(snap));
        data
          ..remove('createdAt')
          ..remove('createdBy')
          ..remove('createdByName');
        tx.update(ref, data);
        tx.set(_audit.doc(), _auditEntry('supplier_payment_edited', payment.id,
            '${payment.distributorName}: ${formatRupees(before.amountPaise)} → ${formatRupees(payment.amountPaise)}'
                '${payment.cancelled && !before.cancelled ? ', removed' : ''}'));
      } else {
        tx.set(ref, data
          ..['createdBy'] = actor.uid
          ..['createdByName'] = actor.name);
        tx.set(_audit.doc(), _auditEntry('supplier_payment_added', payment.id,
            '${payment.distributorName}: ${formatRupees(payment.amountPaise)} ${payment.via.label}'
                '${payment.billNumber.isEmpty ? '' : ' (bill ${payment.billNumber})'}'));
      }
      if (!distSnap.exists) {
        tx.set(distRef, Distributor(id: payment.distributorId, storeId: storeId, name: payment.distributorName, createdAt: DateTime.now()).toMap());
      }
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
  Future<void> correctBatch(String batchId, BatchCorrection correction) async {
    requireManager(actor, 'correct a batch');
    final problems = correction.problems(DateTime.now());
    if (problems.isNotEmpty) throw OperationException(problems);
    final ref = _batches.doc(batchId);
    await _db.runTransaction<void>((tx) async {
      final snap = await tx.get(ref); // read first (Rule 3)
      if (!snap.exists) throw const OperationException(['Batch not found.']);
      final batch = Batch.fromMap(_read(snap));
      if (!correction.changes(batch)) return;
      // Only these four fields: the quantity belongs to receiving, selling
      // and cancelling, and may have changed since this screen opened.
      tx.update(ref, {
        'expiryDate': correction.expiryDate,
        'createdAt': correction.receivedAt,
        'mrpPaise': correction.mrpPaise,
        'purchasePricePaise': correction.purchasePricePaise,
      });
      tx.set(_audit.doc(), _auditEntry('batch_corrected', batchId, '${batch.batchNumber}: ${correction.describeAgainst(batch)}'));
    });
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
    for (final key in ['logoImage', 'signatureImage', 'sealImage']) {
      final v = data[key];
      if (v is Uint8List) data[key] = Blob(v);
    }
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
  Stream<List<ScanEvent>> watchSentScans(String uid) => _scanEvents
      .where('createdBy', isEqualTo: uid)
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
