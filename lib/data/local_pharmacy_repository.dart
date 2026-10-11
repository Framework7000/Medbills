import 'dart:async';
import 'dart:typed_data';

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
import 'repositories/global_catalogue_repository.dart';

/// In-memory backend with the same contract and the same validation as the
/// Firestore one. Powers the web preview (which can't reach Firebase from
/// its sandbox) and the test suite. Nothing here is shared or persisted.
class LocalPharmacyRepository implements PharmacyRepository {
  LocalPharmacyRepository({required this.storeId, required this.actor, bool seedDemoData = true}) {
    _store = StoreProfile(
      storeId: storeId,
      name: 'MedBills Pharmacy (Demo)',
      addressLine: 'MG Road',
      city: 'Indore',
      state: 'Madhya Pradesh',
      phone: '0731-0000000',
    );
    if (seedDemoData) _seed();
  }

  @override
  final String storeId;

  @override
  Actor actor;

  @override
  bool get isShared => false;

  late StoreProfile _store;
  final _medicines = <String, Medicine>{};
  final _batches = <String, Batch>{};
  final _sales = <String, SaleInvoice>{};
  final _purchases = <PurchaseRecord>[];
  final _customers = <String, CustomerCredit>{};
  final _ledger = <String, List<CreditLedgerEntry>>{};
  final _counters = <String, int>{};
  final _billScans = <String, BillScan>{};
  final _billImages = <String, Uint8List>{};
  final _stations = <String, ScanStation>{};
  final _scanEvents = <String, ScanEvent>{};
  final _changes = StreamController<void>.broadcast();
  var _idCounter = 0;

  String _nextId(String prefix) => '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  void _notify() => _changes.add(null);

  Stream<T> _watch<T>(T Function() snapshot) {
    return Stream<T>.multi((controller) {
      controller.add(snapshot());
      final sub = _changes.stream.listen((_) => controller.add(snapshot()));
      controller.onCancel = sub.cancel;
    });
  }

  void _seed() {
    final catalogue = GlobalCatalogueRepository().search('');
    final now = DateTime.now();
    var i = 0;
    for (final entry in catalogue) {
      final medicine = entry.medicine.copyWith(storeId: storeId);
      _medicines[medicine.id] = medicine;
      // Deterministic demo stock: most items in stock, a few low or empty.
      i++;
      if (i % 11 == 0) continue; // out of stock
      final units = (i % 7 == 0 ? 1 : 6 + (i * 7) % 20) * medicine.unitsPerPack;
      final expiry = Batch.endOfMonth(now.year + 1 + i % 2, 1 + (i * 5) % 12);
      final batchNumber = 'DM${(now.year % 100)}${String.fromCharCode(65 + i % 12)}${(i % 90 + 10)}';
      final batch = Batch(
        id: Batch.idFor(medicine.id, batchNumber),
        storeId: storeId,
        medicineId: medicine.id,
        batchNumber: batchNumber,
        expiryDate: expiry,
        purchasePricePaise: (entry.referenceMrpPaise * 72) ~/ 100,
        mrpPaise: entry.referenceMrpPaise,
        quantity: units,
        createdAt: now,
      );
      _batches[batch.id] = batch;
      if (i % 5 == 0) {
        // A second, nearer-expiry batch so FEFO is visible in the demo.
        final near = Batch(
          id: Batch.idFor(medicine.id, '${batchNumber}N'),
          storeId: storeId,
          medicineId: medicine.id,
          batchNumber: '${batchNumber}N',
          expiryDate: Batch.endOfMonth(now.year, now.month + 2),
          purchasePricePaise: (entry.referenceMrpPaise * 70) ~/ 100,
          mrpPaise: entry.referenceMrpPaise,
          quantity: medicine.unitsPerPack * 2,
          createdAt: now,
        );
        _batches[near.id] = near;
      }
    }
  }

  // ---------------------------------------------------------------- reads

  @override
  Stream<StoreProfile> watchStore() => _watch(() => _store);

  @override
  Stream<List<Medicine>> watchMedicines() => _watch(() => _medicines.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  @override
  Stream<List<Batch>> watchBatches() => _watch(() => _batches.values.toList());

  List<SaleInvoice> _salesNewestFirst() =>
      _sales.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Stream<List<SaleInvoice>> watchRecentSales({int limit = 300}) =>
      _watch(() => _salesNewestFirst().take(limit).toList());

  @override
  Future<List<SaleInvoice>> salesBetween(DateTime from, DateTime to) async => _salesNewestFirst()
      .where((s) => !s.createdAt.isBefore(from) && s.createdAt.isBefore(to))
      .toList();

  @override
  Stream<List<PurchaseRecord>> watchRecentPurchases({int limit = 200}) =>
      _watch(() => (_purchases.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(limit).toList());

  @override
  Stream<List<CustomerCredit>> watchCustomers() => _watch(() => _customers.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));

  @override
  Stream<List<CreditLedgerEntry>> watchLedger(String customerId) => _watch(() =>
      (_ledger[customerId] ?? const <CreditLedgerEntry>[]).toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));

  // --------------------------------------------------------------- writes

  @override
  Future<SaleInvoice> checkout(CheckoutRequest request) async {
    final now = DateTime.now();
    CustomerCredit? customer;
    if (request.paymentMode == PaymentMode.credit && request.customerId != null) {
      customer = _customers[request.customerId];
      if (customer == null) throw const CheckoutException(['That customer account no longer exists.']);
    }
    final plan = CheckoutEngine.plan(request: request, medicines: _medicines, batches: _batches, now: now);
    if (customer != null &&
        customer.creditLimitPaise > 0 &&
        customer.outstandingBalancePaise + plan.summary.payablePaise > customer.creditLimitPaise) {
      throw CheckoutException([
        '${customer.name} would exceed their credit limit of ${formatRupees(customer.creditLimitPaise)}.',
      ]);
    }

    final fy = InvoiceNumber.financialYear(now);
    final serial = _counters[fy] ?? 1;
    final sale = SaleInvoice(
      id: _nextId('sale'),
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

    _counters[fy] = serial + 1;
    plan.newBatchQuantities.forEach((id, qty) => _batches[id] = _batches[id]!.copyWith(quantity: qty));
    _sales[sale.id] = sale;
    if (customer != null) {
      _customers[customer.id] =
          customer.copyWith(outstandingBalancePaise: customer.outstandingBalancePaise + sale.payablePaise);
      _addLedger(customer.id, CreditEntryType.creditSale, sale.payablePaise, sale.invoiceNumber, '', now);
    }
    _notify();
    return sale;
  }

  void _addLedger(String customerId, CreditEntryType type, int amount, String? invoice, String notes, DateTime at) {
    (_ledger[customerId] ??= []).add(CreditLedgerEntry(
      id: _nextId('led'),
      storeId: storeId,
      customerId: customerId,
      type: type,
      amountPaise: amount,
      invoiceNumber: invoice,
      notes: notes,
      timestamp: at,
      createdBy: actor.uid,
      createdByName: actor.name,
    ));
  }

  @override
  Future<void> cancelSale(String saleId, String reason) async {
    requireManager(actor, 'cancel a sale');
    final trimmed = reason.trim();
    if (trimmed.isEmpty) throw const OperationException(['Enter a reason for cancelling.']);
    final sale = _sales[saleId];
    if (sale == null) throw const OperationException(['Sale not found.']);
    if (sale.isCancelled) throw const OperationException(['This sale is already cancelled.']);
    final now = DateTime.now();
    for (final line in sale.lines) {
      final batch = _batches[line.batchId];
      if (batch != null) _batches[batch.id] = batch.copyWith(quantity: batch.quantity + line.quantity);
    }
    final customer = sale.customerId == null ? null : _customers[sale.customerId];
    if (customer != null) {
      _customers[customer.id] =
          customer.copyWith(outstandingBalancePaise: customer.outstandingBalancePaise - sale.payablePaise);
      _addLedger(customer.id, CreditEntryType.saleCancelled, sale.payablePaise, sale.invoiceNumber, trimmed, now);
    }
    _sales[saleId] = SaleInvoice.fromMap({
      ...sale.toMap(),
      'status': SaleStatus.cancelled.name,
      'cancellationReason': trimmed,
      'cancelledAt': now,
      'cancelledByName': actor.name,
    });
    _notify();
  }

  @override
  Future<void> receiveStock(StockReceipt receipt) async {
    requireManager(actor, 'receive stock');
    final now = DateTime.now();
    final existing = _batches[receipt.batchId];
    final problems = receipt.validate(now: now, existing: existing);
    if (problems.isNotEmpty) throw OperationException(problems);

    final medicine = _medicines[receipt.medicine.id] ??
        receipt.medicine.copyWith(storeId: storeId, updatedAt: now);
    _medicines[medicine.id] = medicine;
    _batches[receipt.batchId] = existing != null
        ? existing.copyWith(quantity: existing.quantity + receipt.totalUnits)
        : Batch(
            id: receipt.batchId,
            storeId: storeId,
            medicineId: medicine.id,
            batchNumber: receipt.normalisedBatchNumber,
            expiryDate: receipt.expiryDate,
            purchasePricePaise: receipt.purchasePricePaise,
            mrpPaise: receipt.mrpPaise,
            quantity: receipt.totalUnits,
            createdAt: now,
          );
    _purchases.add(PurchaseRecord(
      id: _nextId('pur'),
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
    ));
    _notify();
  }

  @override
  Future<void> saveMedicine(Medicine medicine) async {
    requireManager(actor, 'edit the medicine master');
    _medicines[medicine.id] = medicine.copyWith(storeId: storeId, updatedAt: DateTime.now());
    _notify();
  }

  @override
  String newMedicineId() => _nextId('med');

  @override
  Future<void> setBatchBlocked(String batchId, bool blocked) async {
    requireManager(actor, 'block or unblock a batch');
    final batch = _batches[batchId];
    if (batch == null) throw const OperationException(['Batch not found.']);
    _batches[batchId] = batch.copyWith(isBlocked: blocked);
    _notify();
  }

  @override
  Future<CustomerCredit> createCustomer({
    required String name,
    required String phone,
    int creditLimitPaise = 0,
  }) async {
    if (name.trim().isEmpty) throw const OperationException(['Enter the customer\'s name.']);
    final customer = CustomerCredit(
      id: _nextId('cust'),
      storeId: storeId,
      name: name.trim(),
      phoneNumber: phone.trim(),
      creditLimitPaise: creditLimitPaise,
      outstandingBalancePaise: 0,
      createdAt: DateTime.now(),
    );
    _customers[customer.id] = customer;
    _notify();
    return customer;
  }

  @override
  Future<void> receiveCreditPayment({
    required String customerId,
    required int amountPaise,
    String notes = '',
  }) async {
    if (amountPaise <= 0) throw const OperationException(['Enter the amount received.']);
    final customer = _customers[customerId];
    if (customer == null) throw const OperationException(['Customer not found.']);
    if (amountPaise > customer.outstandingBalancePaise) {
      throw OperationException(['Amount is more than the outstanding ${formatRupees(customer.outstandingBalancePaise)}.']);
    }
    _customers[customerId] = customer.copyWith(outstandingBalancePaise: customer.outstandingBalancePaise - amountPaise);
    _addLedger(customerId, CreditEntryType.paymentReceived, amountPaise, null, notes.trim(), DateTime.now());
    _notify();
  }

  @override
  Future<void> updateStore(StoreProfile profile) async {
    if (!actor.role.canEditStore) throw const NotPermittedException('Only the owner can edit store details.');
    _store = profile;
    _notify();
  }

  // ------------------------------------------------ photographed supplier bills

  @override
  Stream<List<BillScan>> watchBillScans({int limit = 60}) => _watch(() =>
      (_billScans.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(limit).toList());

  @override
  Future<BillScan> createBillScan({required BillDraft draft, required String ocrText, Uint8List? jpeg}) async {
    if (jpeg != null && jpeg.length > 900 * 1024) {
      throw const OperationException(['The bill photo is too large. Take it again a little further away.']);
    }
    final scan = BillScan(
      id: _nextId('bill'),
      storeId: storeId,
      createdAt: DateTime.now(),
      createdBy: actor.uid,
      createdByName: actor.name,
      draft: draft,
      ocrText: ocrText,
      hasImage: jpeg != null,
    );
    _billScans[scan.id] = scan;
    if (jpeg != null) _billImages[scan.id] = jpeg;
    _notify();
    return scan;
  }

  @override
  Future<void> updateBillScanDraft(String id, BillDraft draft) async {
    final scan = _billScans[id];
    if (scan == null) throw const OperationException(['Bill not found.']);
    _billScans[id] = scan.copyWith(draft: draft);
    _notify();
  }

  @override
  Future<Uint8List?> billScanImage(String id) async => _billImages[id];

  @override
  Future<void> setBillScanStatus(String id, BillScanStatus status, {int receivedLines = 0}) async {
    if (status == BillScanStatus.received) requireManager(actor, 'receive a supplier bill');
    final scan = _billScans[id];
    if (scan == null) throw const OperationException(['Bill not found.']);
    _billScans[id] = status == BillScanStatus.received
        ? scan.copyWith(status: status, receivedLines: receivedLines, receivedAt: DateTime.now(), receivedByName: actor.name)
        : scan.copyWith(status: status);
    _notify();
  }

  // ----------------------------------------------- phone → counter scanning

  @override
  Stream<List<ScanStation>> watchStations() => _watch(() => _stations.values.toList());

  @override
  Future<void> saveStation(ScanStation station) async {
    _stations[station.id] = station;
    _notify();
  }

  @override
  Future<void> sendScan(ScanEvent event) async {
    _scanEvents[event.id] = event;
    _notify();
  }

  @override
  Stream<List<ScanEvent>> watchScansFor(String stationId) =>
      _watch(() => _scanEvents.values.where((e) => e.stationId == stationId).toList());

  @override
  Future<void> markScanDone(String eventId) async {
    final e = _scanEvents[eventId];
    if (e == null) return;
    _scanEvents[eventId] = ScanEvent.fromMap({...e.toMap(), 'status': 'done'});
    _notify();
  }

  @override
  String newId() => _nextId('id');

  @override
  void dispose() => _changes.close();
}
