import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/data/firestore_pharmacy_repository.dart';
import 'package:nuskha_pms/data/local_pharmacy_repository.dart';
import 'package:nuskha_pms/data/pharmacy_repository.dart';
import 'package:nuskha_pms/domain/models/app_user.dart';
import 'package:nuskha_pms/domain/models/customer_credit.dart';
import 'package:nuskha_pms/domain/models/sale_invoice.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';
import 'package:nuskha_pms/domain/models/store_profile.dart';
import 'package:nuskha_pms/domain/services/checkout_engine.dart';
import 'package:nuskha_pms/domain/services/invoice_number.dart';

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

  test('blocked batches cannot be sold until unblocked', () async {
    await repo.setBatchBlocked(doloBatchId, true);
    await expectLater(sell(1), throwsA(isA<CheckoutException>()));
    await repo.setBatchBlocked(doloBatchId, false);
    expect((await sell(1)).lines.single.quantity, 1);
  });

  test('salesBetween returns only sales inside the range', () async {
    await sell(1);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    expect(await repo.salesBetween(today, today.add(const Duration(days: 1))), hasLength(1));
    expect(await repo.salesBetween(today.subtract(const Duration(days: 1)), today), isEmpty);
  });
}
