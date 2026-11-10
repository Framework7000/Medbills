import 'dart:typed_data';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/data/firestore_pharmacy_repository.dart';
import 'package:nuskha_pms/data/local_pharmacy_repository.dart';
import 'package:nuskha_pms/data/pharmacy_repository.dart';
import 'package:nuskha_pms/domain/models/app_user.dart';
import 'package:nuskha_pms/domain/models/bill_scan.dart';
import 'package:nuskha_pms/domain/models/customer_credit.dart';
import 'package:nuskha_pms/domain/models/sale_invoice.dart';
import 'package:nuskha_pms/domain/models/scan_link.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';
import 'package:nuskha_pms/domain/models/sale_return.dart';
import 'package:nuskha_pms/domain/models/store_profile.dart';
import 'package:nuskha_pms/domain/models/supplier_account.dart';
import 'package:nuskha_pms/domain/services/stock_adjustment.dart';
import 'package:nuskha_pms/domain/services/supplier_ledger.dart';
import 'package:nuskha_pms/domain/services/batch_correction.dart';
import 'package:nuskha_pms/domain/services/checkout_engine.dart';
import 'package:nuskha_pms/domain/services/invoice_number.dart';
import 'package:nuskha_pms/domain/services/stock_receipt.dart';

import '../support/fixtures.dart';

const owner = Actor(uid: 'u-owner', name: 'Owner', role: UserRole.owner);
const counter = Actor(uid: 'u-counter', name: 'Counter', role: UserRole.counterStaff);

typedef RepoFactory = PharmacyRepository Function(Actor actor);

void main() {
  group('LocalPharmacyRepository', () {
    late LocalPharmacyRepository shared;
    contract((actor) {
      // One store, many actors — like several devices on one account.
      shared = LocalPharmacyRepository(storeId: storeId, actor: owner, seedDemoData: false);
      return shared;
    }, as: (actor) {
      shared.actor = actor;
      return shared;
    });
  });

  group('FirestorePharmacyRepository', () {
    late FakeFirebaseFirestore db;
    contract((actor) {
      db = FakeFirebaseFirestore();
      db.collection('stores').doc(storeId).set({'storeId': storeId, 'name': 'Test Pharmacy'});
      return FirestorePharmacyRepository(db, storeId: storeId, actor: actor);
    }, as: (actor) => FirestorePharmacyRepository(db, storeId: storeId, actor: actor));

    test('correcting a batch writes who changed what, old to new, to the audit log', () async {
      db = FakeFirebaseFirestore();
      final repo = FirestorePharmacyRepository(db, storeId: storeId, actor: owner);
      await repo.receiveStock(receipt(medicine('dolo')));
      final id = receipt(medicine('dolo')).batchId;
      await repo.correctBatch(
        id,
        BatchCorrection(
          expiryDate: DateTime(2029, 1, 31),
          receivedAt: DateTime(2026, 9, 14),
          mrpPaise: 3500,
          purchasePricePaise: 2400,
        ),
      );
      final audit = (await db.collection('stores').doc(storeId).collection('auditLog').get())
          .docs
          .map((d) => d.data())
          .where((d) => d['action'] == 'batch_corrected')
          .toList();
      expect(audit, hasLength(1));
      expect(audit.single['uid'], owner.uid);
      expect(audit.single['storeId'], storeId);
      expect(audit.single['refId'], id);
      expect(audit.single['details'], allOf(contains('expiry 12/'), contains('→ 01/2029'), contains('MRP'), contains('→ ₹35')));
      expect(audit.single['details'], isNot(contains('cost')), reason: 'only what changed is listed');
    });

    test('documents carry storeId and live under the store (Rule 8)', () async {
      db = FakeFirebaseFirestore();
      final repo = FirestorePharmacyRepository(db, storeId: storeId, actor: owner);
      await repo.receiveStock(receipt(medicine('dolo')));
      await repo.checkout(CheckoutRequest(
        lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: receipt(medicine('dolo')).batchId, quantity: 1)],
        paymentMode: PaymentMode.cash,
      ));
      for (final name in ['medicines', 'batches', 'sales', 'purchases', 'counters']) {
        final docs = (await db.collection('stores').doc(storeId).collection(name).get()).docs;
        expect(docs, isNotEmpty, reason: name);
        for (final d in docs) {
          expect(d.data()['storeId'], storeId, reason: '$name/${d.id}');
        }
      }
    });
  });
}

/// The behaviour every backend must share, so the demo and the real store
/// never disagree about money or stock.
void contract(RepoFactory create, {required RepoFactory as}) {
  late PharmacyRepository repo;
  final dolo = medicine('dolo'); // strip of 15, 12% GST, MRP ₹33.60, cost ₹24.00
  final alprax = medicine('alprax', name: 'Alprax 0.25', unitsPerPack: 10, schedule: ScheduleType.scheduleH1);
  final doloBatchId = receipt(dolo).batchId;

  setUp(() async {
    repo = create(owner);
    await repo.receiveStock(receipt(dolo, packs: 10)); // 150 tablets
  });

  Future<SaleInvoice> sell(int units, {PaymentMode mode = PaymentMode.cash, String? customerId}) =>
      repo.checkout(CheckoutRequest(
        lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: units)],
        paymentMode: mode,
        customerId: customerId,
      ));

  Future<int> stock() async =>
      (await repo.watchBatches().first).firstWhere((b) => b.id == doloBatchId).quantity;

  test('receiving stock creates the medicine, the batch (in units) and a purchase record', () async {
    final medicines = await repo.watchMedicines().first;
    expect(medicines.single.id, 'dolo');
    expect(await stock(), 150);
    final purchases = await repo.watchRecentPurchases().first;
    expect(purchases.single.quantity, 150);
    expect(purchases.single.totalCostPaise, 24000);
  });

  test('receiving the same batch again tops it up; a conflicting MRP is refused', () async {
    await repo.receiveStock(receipt(dolo, packs: 2, freePacks: 1));
    expect(await stock(), 195);
    expect(() => repo.receiveStock(receipt(dolo, mrpPaise: 4000)), throwsA(isA<OperationException>()));
  });

  test('checkout decrements stock, prices from the batch and numbers invoices in sequence', () async {
    final first = await sell(20);
    final second = await sell(15);
    final fy = InvoiceNumber.financialYear(DateTime.now());
    expect(first.invoiceNumber, 'INV/$fy/00001');
    expect(second.invoiceNumber, 'INV/$fy/00002');
    expect(first.grossPaise, 4480);
    expect(first.payablePaise, 4500);
    expect(first.costPaise, 3200);
    expect(first.storeId, storeId);
    expect(await stock(), 115);
    final sales = await repo.watchRecentSales().first;
    expect(sales.map((s) => s.invoiceNumber), containsAll([first.invoiceNumber, second.invoiceNumber]));
  });

  test('overselling is rejected and leaves stock untouched (Rule 3)', () async {
    await expectLater(sell(151), throwsA(isA<CheckoutException>()));
    expect(await stock(), 150);
    expect(await repo.watchRecentSales().first, isEmpty);
  });

  test('Schedule H1 sale needs the prescription record (Rule 9)', () async {
    await repo.receiveStock(receipt(alprax, batchNumber: 'AX1', packs: 2, mrpPaise: 4000, costPaise: 2500));
    final line = CheckoutLineRequest(medicineId: 'alprax', batchId: receipt(alprax, batchNumber: 'AX1').batchId, quantity: 10);
    await expectLater(
      repo.checkout(CheckoutRequest(lines: [line], paymentMode: PaymentMode.cash)),
      throwsA(isA<CheckoutException>()),
    );
    final sale = await repo.checkout(CheckoutRequest(
      lines: [line],
      paymentMode: PaymentMode.cash,
      prescription: const PrescriptionRecord(
          patientName: 'Ramesh', patientPhone: '9826000000', doctorName: 'Dr Jain', doctorRegistrationNumber: 'MP-1'),
    ));
    expect(sale.prescription!.doctorRegistrationNumber, 'MP-1');
  });

  test('cancelling restores stock, keeps the sale and is managers-only (Rule 10)', () async {
    final sale = await sell(30);
    expect(await stock(), 120);

    final asCounter = as(counter);
    await expectLater(asCounter.cancelSale(sale.id, 'wrong item'), throwsA(isA<NotPermittedException>()));
    final asOwner = as(owner);
    await expectLater(asOwner.cancelSale(sale.id, '  '), throwsA(isA<OperationException>()));

    await asOwner.cancelSale(sale.id, 'Customer returned unopened');
    expect(await stock(), 150);
    final kept = (await asOwner.watchRecentSales().first).single;
    expect(kept.isCancelled, isTrue);
    expect(kept.cancellationReason, 'Customer returned unopened');
    await expectLater(asOwner.cancelSale(sale.id, 'again'), throwsA(isA<OperationException>()));
  });

  test('counter staff can sell but cannot receive stock or edit medicines', () async {
    final asCounter = as(counter);
    await asCounter.checkout(CheckoutRequest(
      lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 1)],
      paymentMode: PaymentMode.upi,
    ));
    await expectLater(asCounter.receiveStock(receipt(dolo)), throwsA(isA<NotPermittedException>()));
    await expectLater(asCounter.saveMedicine(dolo), throwsA(isA<NotPermittedException>()));
    await expectLater(asCounter.setBatchBlocked(doloBatchId, true), throwsA(isA<NotPermittedException>()));
    await expectLater(
      asCounter.updateStore(const StoreProfile(storeId: storeId, name: 'X')),
      throwsA(isA<NotPermittedException>()),
    );
  });

  test('udhaar: credit sale, limit, payment and cancellation keep the ledger balanced', () async {
    final customer = await repo.createCustomer(name: 'Sunita Verma', phone: '9826012345', creditLimitPaise: 10000);
    final sale = await sell(30, mode: PaymentMode.credit, customerId: customer.id); // ₹67.20 → ₹67
    Future<CustomerCredit> current() async =>
        (await repo.watchCustomers().first).firstWhere((c) => c.id == customer.id);
    expect((await current()).outstandingBalancePaise, 6700);

    // ₹67 + ₹45 would cross the ₹100 limit.
    await expectLater(sell(20, mode: PaymentMode.credit, customerId: customer.id), throwsA(isA<CheckoutException>()));

    await expectLater(repo.receiveCreditPayment(customerId: customer.id, amountPaise: 6701),
        throwsA(isA<OperationException>()));
    await repo.receiveCreditPayment(customerId: customer.id, amountPaise: 2000, notes: 'cash');
    expect((await current()).outstandingBalancePaise, 4700);

    await repo.cancelSale(sale.id, 'returned');
    expect((await current()).outstandingBalancePaise, -2000); // advance held for the customer

    final ledger = await repo.watchLedger(customer.id).first;
    expect(ledger.map((e) => e.type).toSet(), {
      CreditEntryType.creditSale,
      CreditEntryType.paymentReceived,
      CreditEntryType.saleCancelled,
    });
  });

  test('Cash + UPI: the cash part and the UPI rest are saved; the cash must be less than the bill', () async {
    // 20 tablets = ₹44.80 → ₹45 payable.
    final sale = await repo.checkout(CheckoutRequest(
      lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 20)],
      paymentMode: PaymentMode.split,
      cashPaise: 2000,
    ));
    expect((sale.cashPaise, sale.upiPaise), (2000, 2500));
    expect(sale.paidBy(PaymentMode.cash), 2000);
    expect(sale.paidBy(PaymentMode.upi), 2500);
    expect(sale.paymentLabel, 'Cash ₹20.00 + UPI ₹25.00');
    final saved = (await repo.watchRecentSales().first).single;
    expect((saved.paymentMode, saved.cashPaise, saved.upiPaise), (PaymentMode.split, 2000, 2500));

    for (final cash in [0, 4500, 9000]) {
      await expectLater(
        repo.checkout(CheckoutRequest(
          lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 20)],
          paymentMode: PaymentMode.split,
          cashPaise: cash,
        )),
        throwsA(isA<CheckoutException>()),
        reason: 'cash ₹${cash / 100} of a ₹45 bill',
      );
    }
    expect(await stock(), 130, reason: 'refused bills take no stock');
  });

  test('editing a bill: same number and date, stock moved, old copy kept; managers only', () async {
    final sale = await sell(30); // 2 strips
    expect(await stock(), 120);
    final edited = await repo.editSale(
      sale.id,
      CheckoutRequest(
        lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 45)], // 3 strips
        paymentMode: PaymentMode.split,
        cashPaise: 5000,
        customerName: 'Ramesh',
      ),
    );
    expect(await stock(), 105, reason: '30 back, 45 out');
    expect(edited.id, isNot(sale.id));
    expect(edited.invoiceNumber, sale.invoiceNumber);
    expect(edited.createdAt, sale.createdAt);
    expect(edited.payablePaise, 10100); // ₹100.80 → ₹101
    expect((edited.cashPaise, edited.upiPaise), (5000, 5100));
    expect(edited.customerName, 'Ramesh');
    expect(edited.revisionOf, sale.id);
    expect(edited.isEdited, isTrue);
    expect(edited.editedByName, owner.name);

    final all = await repo.watchRecentSales().first;
    expect(all, hasLength(2));
    final old = all.firstWhere((s) => s.id == sale.id);
    expect(old.isReplaced, isTrue, reason: 'the old copy stays on record');
    expect(old.lines.single.quantity, 30);
    expect(all.firstWhere((s) => s.id == edited.id).isCancelled, isFalse);

    // An edited bill can be edited again, and lines removed down to fewer units.
    final again = await repo.editSale(
      edited.id,
      CheckoutRequest(
        lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 15)],
        paymentMode: PaymentMode.cash,
      ),
    );
    expect(await stock(), 135);
    expect(again.invoiceNumber, sale.invoiceNumber);

    await expectLater(
      as(counter).editSale(again.id, const CheckoutRequest(lines: [], paymentMode: PaymentMode.cash)),
      throwsA(isA<NotPermittedException>()),
    );
    // Editing a bill can't sell more than there is (its own units count as available).
    await expectLater(
      as(owner).editSale(
          again.id,
          CheckoutRequest(
            lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 151)],
            paymentMode: PaymentMode.cash,
          )),
      throwsA(isA<CheckoutException>()),
    );
    expect(await stock(), 135, reason: 'a refused edit changes nothing');
    final next = await sell(1);
    expect(next.invoiceNumber, isNot(sale.invoiceNumber), reason: 'edits do not use up invoice numbers');
  });

  test('editing an udhaar bill moves what the customer owes; a returned or cancelled bill cannot be edited', () async {
    final customer = await repo.createCustomer(name: 'Sunita Verma', phone: '9826012345');
    final sale = await sell(30, mode: PaymentMode.credit, customerId: customer.id); // ₹67
    Future<int> owes() async =>
        (await repo.watchCustomers().first).firstWhere((c) => c.id == customer.id).outstandingBalancePaise;
    expect(await owes(), 6700);

    final edited = await repo.editSale(
      sale.id,
      CheckoutRequest(
        lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 15)],
        paymentMode: PaymentMode.credit,
        customerId: customer.id,
      ),
    );
    expect(await owes(), 3400, reason: '₹67 off, ₹34 on');
    final paidNow = await repo.editSale(
      edited.id,
      CheckoutRequest(
        lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 15)],
        paymentMode: PaymentMode.cash,
      ),
    );
    expect(await owes(), 0, reason: 'paid in cash after all');
    expect(paidNow.customerId, isNull);

    await repo.returnSaleItems(saleId: paidNow.id, units: {0: 5}, refundMode: RefundMode.cash, reason: 'extra');
    await expectLater(
      repo.editSale(paidNow.id, const CheckoutRequest(lines: [], paymentMode: PaymentMode.cash)),
      throwsA(isA<OperationException>()),
    );
    final other = await sell(1);
    await repo.cancelSale(other.id, 'mistake');
    await expectLater(
      repo.editSale(other.id, const CheckoutRequest(lines: [], paymentMode: PaymentMode.cash)),
      throwsA(isA<OperationException>()),
    );
  });

  test('a line sold below MRP and a bill discount are saved on the bill; never above MRP', () async {
    // 30 tablets = 2 strips at MRP ₹33.60 = ₹67.20; sold at ₹30/strip = ₹60, then ₹5 off the bill.
    final sale = await repo.checkout(CheckoutRequest(
      lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 30, ratePaise: 3000)],
      paymentMode: PaymentMode.cash,
      billDiscountPaise: 500,
    ));
    final line = sale.lines.single;
    expect(line.mrpLinePaise, 6720);
    expect(line.ratePaise, 3000);
    expect(line.lineTotalPaise, 5500);
    expect(sale.grossPaise, 5500);
    expect(sale.payablePaise, 5500);
    expect(sale.mrpTotalPaise, 6720);
    expect(sale.discountPaise, 1220);
    expect(sale.billDiscountPaise, 500);
    expect(sale.taxablePaise + sale.gstPaise, 5500, reason: 'GST comes out of what was charged');
    final stored = (await repo.watchRecentSales().first).single;
    expect(stored.discountPaise, 1220);
    expect(stored.lines.single.lineTotalPaise, 5500);

    await expectLater(
      repo.checkout(CheckoutRequest(
        lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 15, ratePaise: 3400)],
        paymentMode: PaymentMode.cash,
      )),
      throwsA(isA<CheckoutException>().having((e) => e.toString(), 'message', contains('above MRP'))),
    );
    await expectLater(
      repo.checkout(CheckoutRequest(
        lines: [CheckoutLineRequest(medicineId: 'dolo', batchId: doloBatchId, quantity: 15)],
        paymentMode: PaymentMode.cash,
        billDiscountPaise: 3360,
      )),
      throwsA(isA<CheckoutException>()),
    );
    expect(await stock(), 120, reason: 'refused bills take no stock');
  });

  test('a return puts stock back, refunds what the customer paid, and the bill cannot then be cancelled', () async {
    final sale = await sell(30); // ₹67.20 charged
    expect(await stock(), 120);
    final asCounter = as(counter);
    await expectLater(
      asCounter.returnSaleItems(saleId: sale.id, units: {0: 15}, refundMode: RefundMode.cash),
      throwsA(isA<NotPermittedException>()),
    );
    final asOwner = as(owner);
    final first = await asOwner.returnSaleItems(saleId: sale.id, units: {0: 10}, refundMode: RefundMode.cash, reason: 'Not needed');
    expect(first.refundPaise, 2240); // 10 of 30 tablets of ₹67.20
    expect(await stock(), 130);
    await expectLater(
      asOwner.returnSaleItems(saleId: sale.id, units: {0: 21}, refundMode: RefundMode.cash),
      throwsA(isA<OperationException>()),
    );
    final rest = await asOwner.returnSaleItems(saleId: sale.id, units: {0: 20}, refundMode: RefundMode.upi);
    expect(first.refundPaise + rest.refundPaise, 6720, reason: 'never more than the line cost');
    expect(await stock(), 150);
    final updated = (await asOwner.watchRecentSales().first).single;
    expect(updated.returnedUnits, [30]);
    expect(updated.refundedPaise, 6720);
    expect(updated.fullyReturned, isTrue);
    await expectLater(asOwner.cancelSale(sale.id, 'oops'), throwsA(isA<OperationException>()));

    final today = DateTime.now();
    final returns = await asOwner.returnsBetween(DateTime(today.year, today.month, today.day), today.add(const Duration(days: 1)));
    expect(returns.map((r) => r.refundPaise).toList()..sort(), [2240, 4480]);
    expect((await asOwner.watchReturnsFor(sale.id).first), hasLength(2));
  });

  test('a return on an udhaar bill lowers what the customer owes', () async {
    final customer = await repo.createCustomer(name: 'Ravi', phone: '98260');
    final sale = await sell(15, mode: PaymentMode.credit, customerId: customer.id); // ₹33.60 → ₹34
    await expectLater(
      repo.returnSaleItems(saleId: (await sell(1)).id, units: {0: 1}, refundMode: RefundMode.udhaar),
      throwsA(isA<OperationException>()),
      reason: 'a cash bill has no udhaar to reduce',
    );
    await repo.returnSaleItems(saleId: sale.id, units: {0: 15}, refundMode: RefundMode.udhaar);
    final c = (await repo.watchCustomers().first).single;
    expect(c.outstandingBalancePaise, 3400 - 3360);
  });

  test('stock can be set to a counted figure, emptied, by managers only', () async {
    await expectLater(
      as(counter).adjustBatchStock(doloBatchId, const StockAdjustment(newQuantity: 200, reason: AdjustReason.count)),
      throwsA(isA<NotPermittedException>()),
    );
    final asOwner = as(owner);
    await asOwner.adjustBatchStock(doloBatchId, const StockAdjustment(newQuantity: 23 * 15, reason: AdjustReason.count));
    expect(await stock(), 345);
    await asOwner.adjustBatchStock(doloBatchId, const StockAdjustment(newQuantity: 0, reason: AdjustReason.damaged));
    expect(await stock(), 0);
    await expectLater(
      asOwner.adjustBatchStock(doloBatchId, const StockAdjustment(newQuantity: -1, reason: AdjustReason.count)),
      throwsA(isA<OperationException>()),
    );
    await expectLater(
      asOwner.adjustBatchStock(doloBatchId, const StockAdjustment(newQuantity: 5, reason: AdjustReason.other)),
      throwsA(isA<OperationException>()),
      reason: '"Other" needs a reason written',
    );
  });

  Future<SupplierLedger> ledger() async => SupplierLedger.build(
        distributors: await repo.watchDistributors().first,
        bills: await repo.watchSupplierBills().first,
        payments: await repo.watchSupplierPayments().first,
      );

  test('stock received from a distributor goes on their bill; credit is owed until paid', () async {
    // setUp received 10 strips at ₹24 on bill SD/101, on credit.
    await repo.receiveStock(receipt(alprax, batchNumber: 'AX1', packs: 2, mrpPaise: 4000, costPaise: 2500,
        supplierName: '  shree   distributors ', supplierInvoiceNumber: 'SD/101'));
    final distributors = await repo.watchDistributors().first;
    expect(distributors.map((d) => d.name), ['Shree Distributors'], reason: 'one distributor, however it is typed');
    final bills = await repo.watchSupplierBills().first;
    expect(bills, hasLength(1));
    expect(bills.single.itemsPaise, 24000 + 5000);
    expect(bills.single.isCredit, isTrue);
    var l = await ledger();
    expect(l.totalOutstandingPaise, 29000);

    final now = DateTime.now();
    await repo.saveSupplierPayment(SupplierPayment(
      id: repo.newId(),
      storeId: storeId,
      distributorId: bills.single.distributorId,
      distributorName: 'Shree Distributors',
      amountPaise: 10000,
      via: PaidVia.upi,
      billNumber: 'SD/101',
      paidOn: now,
      createdAt: now,
      createdBy: owner.uid,
      createdByName: owner.name,
    ));
    l = await ledger();
    expect(l.totalOutstandingPaise, 19000);
    expect(l.accounts.values.single.creditBills.single.isPartlyPaid, isTrue);

    // The printed bill total (with the supplier's GST) is typed in: it is what is owed.
    await repo.saveSupplierBill(bills.single.copyWith(amountPaise: 30450));
    l = await ledger();
    expect(l.totalOutstandingPaise, 20450);

    // A cash purchase is paid there and then: nothing owed.
    await repo.receiveStock(receipt(dolo, batchNumber: 'C1', packs: 1, supplierName: 'Local Medico',
        supplierInvoiceNumber: '', payment: PurchasePayment.cash));
    l = await ledger();
    expect(l.accounts[Distributor.idFor('Local Medico')]!.outstandingPaise, 0);
    expect(l.accounts[Distributor.idFor('Local Medico')]!.cashBilledPaise, 2400);
  });

  test('an old bill can be entered as opening dues, edited and removed (never deleted)', () async {
    final now = DateTime.now();
    final id = Distributor.idFor('Mahaveer Agencies');
    final old = SupplierBill(
      id: SupplierBill.idFor(id, 'MA-77', now),
      storeId: storeId,
      distributorId: id,
      distributorName: 'Mahaveer Agencies',
      billNumber: 'MA-77',
      billDate: DateTime(now.year, now.month, now.day).subtract(const Duration(days: 45)),
      amountPaise: 1250000,
      payment: PurchasePayment.credit,
      isOpening: true,
      createdAt: now,
      createdBy: owner.uid,
      createdByName: owner.name,
    );
    await expectLater(as(counter).saveSupplierBill(old), throwsA(isA<NotPermittedException>()));
    final asOwner = as(owner);
    await asOwner.saveSupplierBill(old);
    var l = await ledger();
    expect(l.accounts[id]!.outstandingPaise, 1250000);
    expect(l.remindersAt(now).map((r) => r.bill.bill.billNumber), contains('MA-77'), reason: '45 days old: overdue');

    await asOwner.saveSupplierBill(old.copyWith(amountPaise: 1200000));
    l = await ledger();
    expect(l.accounts[id]!.outstandingPaise, 1200000);
    await asOwner.saveSupplierBill(old.copyWith(cancelled: true));
    l = await ledger();
    expect(l.accounts[id]!.outstandingPaise, 0);
    expect((await asOwner.watchSupplierBills().first).where((b) => b.id == old.id), hasLength(1),
        reason: 'kept on record');
    await expectLater(
      asOwner.saveSupplierBill(old.copyWith(amountPaise: 0, cancelled: false)),
      throwsA(isA<OperationException>()),
    );
  });

  test('a syrup stored as 60 per bottle is corrected to 1; old bills return bottles, not 60s', () async {
    final syrup = medicine('syr', name: 'Calpol Syrup', unitsPerPack: 60, gstRate: 5).copyWith(packSizeLabel: 'Bottle of 60 ml Syrup', minStock: 120);
    await repo.receiveStock(receipt(syrup, batchNumber: 'CS1', packs: 5, mrpPaise: 4500, costPaise: 3200)); // 300 "units"
    final batchId = receipt(syrup, batchNumber: 'CS1').batchId;
    Future<int> syrupStock() async => (await repo.watchBatches().first).firstWhere((b) => b.id == batchId).quantity;
    final oldSale = await repo.checkout(CheckoutRequest(
      lines: [CheckoutLineRequest(medicineId: 'syr', batchId: batchId, quantity: 120)], // 2 bottles
      paymentMode: PaymentMode.cash,
    ));
    final toCancel = await repo.checkout(CheckoutRequest(
      lines: [CheckoutLineRequest(medicineId: 'syr', batchId: batchId, quantity: 60)], // 1 bottle
      paymentMode: PaymentMode.cash,
    ));
    expect(await syrupStock(), 120); // 2 bottles left

    await expectLater(as(counter).changeUnitsPerPack('syr', 1), throwsA(isA<NotPermittedException>()));
    final asOwner = as(owner);
    await asOwner.changeUnitsPerPack('syr', 1);
    expect(await syrupStock(), 2, reason: 'still 2 bottles');
    final fixed = (await asOwner.watchMedicines().first).firstWhere((m) => m.id == 'syr');
    expect(fixed.unitsPerPack, 1);
    expect(fixed.minStock, 2);

    await asOwner.returnSaleItems(saleId: oldSale.id, units: {0: 60}, refundMode: RefundMode.cash); // 1 bottle back
    expect(await syrupStock(), 3);
    await asOwner.cancelSale(toCancel.id, 'wrong item');
    expect(await syrupStock(), 4);

    // New bills sell bottles.
    await asOwner.checkout(CheckoutRequest(
      lines: [CheckoutLineRequest(medicineId: 'syr', batchId: batchId, quantity: 1)],
      paymentMode: PaymentMode.cash,
    ));
    expect(await syrupStock(), 3);
    expect((await asOwner.watchRecentSales().first).first.lines.single.lineTotalPaise, 4500);
  });

  test('blocked batches cannot be sold until unblocked', () async {
    await repo.setBatchBlocked(doloBatchId, true);
    await expectLater(sell(1), throwsA(isA<CheckoutException>()));
    await repo.setBatchBlocked(doloBatchId, false);
    expect((await sell(1)).lines.single.quantity, 1);
  });

  test('a wrong expiry, received date or price on a batch can be corrected without touching stock or old bills', () async {
    final before = (await repo.watchBatches().first).firstWhere((b) => b.id == doloBatchId);
    final soldBill = await sell(2); // billed at the old price, from this batch
    final stockAfterSale = (await repo.watchBatches().first).firstWhere((b) => b.id == doloBatchId).quantity;

    final received = DateTime(2026, 9, 14);
    await repo.correctBatch(
      doloBatchId,
      BatchCorrection(
        expiryDate: DateTime(2028, 3, 31),
        receivedAt: received,
        mrpPaise: 3500,
        purchasePricePaise: 2500,
      ),
    );

    final after = (await repo.watchBatches().first).firstWhere((b) => b.id == doloBatchId);
    expect(after.expiryDate, DateTime(2028, 3, 31));
    expect(after.createdAt, received);
    expect(after.mrpPaise, 3500);
    expect(after.purchasePricePaise, 2500);
    expect(after.quantity, stockAfterSale, reason: 'a correction never changes the stock');
    expect(after.batchNumber, before.batchNumber);
    expect(after.isBlocked, before.isBlocked);

    // The bill already made keeps the price it was billed at.
    final bills = await repo.salesBetween(DateTime(2000), DateTime.now().add(const Duration(days: 1)));
    final old = bills.firstWhere((b) => b.id == soldBill.id).lines.single;
    expect(old.mrpPaise, 3360, reason: 'billed at the MRP it had then');
    expect(old.lineTotalPaise, soldBill.lines.single.lineTotalPaise);
    expect(old.costPaise, soldBill.lines.single.costPaise);

    // Nonsense is refused, with reasons.
    await expectLater(
      repo.correctBatch(
        doloBatchId,
        BatchCorrection(expiryDate: DateTime(2028, 3, 31), receivedAt: DateTime(2026, 9, 14), mrpPaise: 0, purchasePricePaise: 0),
      ),
      throwsA(isA<OperationException>()),
    );
    await expectLater(
      repo.correctBatch(
        doloBatchId,
        BatchCorrection(
          expiryDate: DateTime(2028, 3, 31),
          receivedAt: DateTime.now().add(const Duration(days: 30)),
          mrpPaise: 3500,
          purchasePricePaise: 2500,
        ),
      ),
      throwsA(isA<OperationException>()),
    );
    await expectLater(repo.correctBatch('no_such_batch', BatchCorrection(expiryDate: DateTime(2028, 3, 31), receivedAt: received, mrpPaise: 3500, purchasePricePaise: 2500)), throwsA(isA<OperationException>()));
  });

  test('only the owner or pharmacist can correct a batch', () async {
    final asCounter = as(counter);
    await expectLater(
      asCounter.correctBatch(
        doloBatchId,
        BatchCorrection(expiryDate: DateTime(2028, 3, 31), receivedAt: DateTime(2026, 9, 14), mrpPaise: 3500, purchasePricePaise: 2500),
      ),
      throwsA(isA<NotPermittedException>()),
    );
  });

  test('salesBetween returns only sales inside the range', () async {
    await sell(1);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    expect(await repo.salesBetween(today, today.add(const Duration(days: 1))), hasLength(1));
    expect(await repo.salesBetween(today.subtract(const Duration(days: 1)), today), isEmpty);
  });

  test('a photographed bill keeps its picture, is corrected, received once and never deleted', () async {
    final jpeg = Uint8List.fromList(List<int>.generate(2048, (i) => i % 251));
    final asCounter = as(counter);
    final scan = await asCounter.createBillScan(
      draft: const BillDraft(supplierName: 'Shree Sai Pharma', invoiceNumber: 'SSP/1', lines: [
        BillDraftLine(rawText: 'DOLO 650 ...', medicineId: 'dolo', batchNumber: 'DL2401', expiryMonth: 12, packs: 4),
      ]),
      ocrText: 'SHREE SAI PHARMA',
      jpeg: jpeg,
    );
    expect(scan.status, BillScanStatus.draft);
    expect(await asCounter.billScanImage(scan.id), jpeg);
    await expectLater(asCounter.setBillScanStatus(scan.id, BillScanStatus.received), throwsA(isA<NotPermittedException>()));

    final asOwner = as(owner);
    final draft = (await asOwner.watchBillScans().first).single.draft;
    await asOwner.updateBillScanDraft(scan.id, draft.copyWith(invoiceNumber: 'SSP/0001'));
    await asOwner.setBillScanStatus(scan.id, BillScanStatus.received, receivedLines: 1);
    final saved = (await asOwner.watchBillScans().first).single;
    expect(saved.draft.invoiceNumber, 'SSP/0001');
    expect(saved.status, BillScanStatus.received);
    expect(saved.receivedLines, 1);
    expect(saved.receivedByName, 'Owner');
  });

  test('an oversized bill photo is refused', () async {
    await expectLater(
      repo.createBillScan(draft: const BillDraft(), ocrText: '', jpeg: Uint8List(950 * 1024)),
      throwsA(isA<OperationException>()),
    );
  });

  test('stock received from a scanned bill is linked to it', () async {
    await repo.receiveStock(StockReceipt(
      medicine: dolo,
      batchNumber: 'NEW1',
      expiryMonth: 6,
      expiryYear: DateTime.now().year + 2,
      packs: 2,
      purchasePricePaise: 2400,
      mrpPaise: 3360,
      billScanId: 'scan123',
    ));
    final purchase = (await repo.watchRecentPurchases().first).firstWhere((p) => p.batchNumber == 'NEW1');
    expect(purchase.billScanId, 'scan123');
  });

  test('a phone sends scans to a counter, which marks them done', () async {
    final station = ScanStation(
        id: repo.newId(), storeId: storeId, name: 'Counter 1', active: true, uid: owner.uid, updatedAt: DateTime.now());
    await repo.saveStation(station);
    expect((await repo.watchStations().first).single.isAvailableAt(DateTime.now()), isTrue);

    final phone = as(counter);
    final event = ScanEvent(
      id: phone.newId(),
      storeId: storeId,
      stationId: station.id,
      rawBarcode: '8901234567890',
      medicineId: 'dolo',
      deviceLabel: 'iPhone',
      createdBy: counter.uid,
      createdByName: counter.name,
      scannedAt: DateTime.now(),
    );
    await phone.sendScan(event);
    var received = await repo.watchScansFor(station.id).first;
    expect(received.single.medicineId, 'dolo');
    expect(received.single.done, isFalse);
    expect(await repo.watchScansFor('other-counter').first, isEmpty);

    await repo.markScanDone(event.id);
    received = await repo.watchScansFor(station.id).first;
    expect(received.single.done, isTrue);
  });
}
