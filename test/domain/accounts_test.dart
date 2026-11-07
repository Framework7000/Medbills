import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/sale_invoice.dart';
import 'package:nuskha_pms/domain/models/sale_return.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';
import 'package:nuskha_pms/domain/models/supplier_account.dart';
import 'package:nuskha_pms/domain/services/billing_calculator.dart';
import 'package:nuskha_pms/domain/services/checkout_engine.dart';
import 'package:nuskha_pms/domain/services/day_book.dart';
import 'package:nuskha_pms/domain/services/stock_summary.dart';
import 'package:nuskha_pms/domain/services/supplier_ledger.dart';
import 'package:nuskha_pms/state/cart.dart';

import '../support/fixtures.dart';

void main() {
  final now = DateTime(2026, 11, 7, 12);

  group('discounts', () {
    test('spread shares a discount exactly, in proportion', () {
      expect(BillingCalculator.spread(100, [100, 100, 100]), [34, 33, 33]);
      expect(BillingCalculator.spread(1000, [6720, 3360]), [667, 333]);
      for (final amount in [1, 7, 99, 1234]) {
        final shares = BillingCalculator.spread(amount, [3361, 17, 999, 4]);
        expect(shares.fold<int>(0, (s, v) => s + v), amount);
      }
      expect(BillingCalculator.spread(5, [0, 0]), [0, 0]);
    });

    test('the counter shows exactly what checkout will charge', () {
      final dolo = medicine('dolo');
      final h = medicine('h', name: 'Pantop', unitsPerPack: 10, gstRate: 5);
      final b1 = batch('dolo', 'D1', expiry: DateTime(2028, 1, 31));
      final b2 = batch('h', 'H1', expiry: DateTime(2028, 1, 31), mrpPaise: 15500, costPaise: 9000, quantity: 100);
      final cart = CartNotifier()
        ..addMedicine(dolo, [b1], 22, now: now)
        ..addMedicine(h, [b2], 7, now: now);
      cart.setLineRate(0, 3000);
      cart.setBillDiscount(1999);
      final state = cart.state;
      final plan = CheckoutEngine.plan(
        request: state.toRequest(),
        medicines: {'dolo': dolo, 'h': h},
        batches: {b1.id: b1, b2.id: b2},
        now: now,
      );
      expect(plan.lines.map((l) => l.lineTotalPaise).toList(), state.netLineTotals);
      expect(plan.summary.payablePaise, state.summary.payablePaise);
      expect(plan.summary.gstPaise, state.summary.gstPaise);
      expect(state.mrpTotalPaise - plan.summary.grossPaise, state.totalDiscountPaise);
    });

    test('a price at or above MRP is just MRP', () {
      final line = CartNotifier()..addMedicine(medicine('dolo'), [batch('dolo', 'D1', expiry: DateTime(2028, 1, 31))], 15, now: now);
      line.setLineRate(0, 9999);
      expect(line.state.lines.single.ratePaise, isNull);
      line.setLineRate(0, 3000);
      expect(line.state.lines.single.lineTotalPaise, 3000);
      line.setQuantity(0, 30, available: 150);
      expect(line.state.lines.single.lineTotalPaise, 6000, reason: 'the price per strip stays');
    });
  });

  SaleInvoice sale({int qty = 30, int total = 6720, int cost = 4800, PaymentMode mode = PaymentMode.cash, DateTime? at}) =>
      SaleInvoice(
        id: 's1',
        storeId: storeId,
        invoiceNumber: 'INV-1',
        createdAt: at ?? now,
        createdBy: 'u',
        createdByName: 'U',
        customerName: 'A',
        customerPhone: '',
        paymentMode: mode,
        lines: [
          SaleLine(
            medicineId: 'dolo',
            batchId: 'b',
            name: 'Dolo',
            batchNumber: 'D1',
            expiryDate: DateTime(2028),
            hsnCode: '3004',
            gstRate: 5,
            scheduleType: ScheduleType.otc,
            unitsPerPack: 15,
            quantity: qty,
            mrpPaise: 3360,
            lineTotalPaise: total,
            costPaise: cost,
          ),
        ],
        slabs: BillingCalculator.summarise([BillLine(lineTotalPaise: total, gstRate: 5)]).slabs,
        grossPaise: total,
        payablePaise: (total + 50) ~/ 100 * 100,
      );

  test('returning a line bit by bit refunds exactly the line, never more', () {
    var s = sale(qty: 7, total: 1000, cost: 701);
    var refunded = 0, cost = 0;
    for (final u in [1, 2, 3, 1]) {
      final plan = SaleReturnPlanner.plan(sale: s, units: {0: u}, mode: RefundMode.cash);
      refunded += plan.refundPaise;
      cost += plan.lines.single.costPaise;
      s = SaleInvoice.fromMap({...s.toMap(), 'returnedUnits': plan.newReturnedUnits, 'refundedPaise': refunded});
    }
    expect(refunded, 1000);
    expect(cost, 701);
    expect(() => SaleReturnPlanner.plan(sale: s, units: {0: 1}, mode: RefundMode.cash), throwsA(isA<ReturnException>()));
    expect(() => SaleReturnPlanner.plan(sale: sale(), units: {0: 1}, mode: RefundMode.udhaar), throwsA(isA<ReturnException>()));
  });

  SupplierBill bill(String no, int paise, {PurchasePayment pay = PurchasePayment.credit, DateTime? date, bool opening = false}) =>
      SupplierBill(
        id: no,
        storeId: storeId,
        distributorId: 'd_a',
        distributorName: 'A Pharma',
        billNumber: no,
        billDate: date ?? now,
        amountPaise: paise,
        payment: pay,
        isOpening: opening,
        createdAt: date ?? now,
        createdBy: 'u',
        createdByName: 'U',
      );
  SupplierPayment pay(int paise, {String billNo = '', DateTime? on}) => SupplierPayment(
        id: 'p$paise$billNo',
        storeId: storeId,
        distributorId: 'd_a',
        distributorName: 'A Pharma',
        amountPaise: paise,
        via: PaidVia.cash,
        billNumber: billNo,
        paidOn: on ?? now,
        createdAt: now,
        createdBy: 'u',
        createdByName: 'U',
      );

  test('payments clear the named bill first, then the oldest; reminders show late bills', () {
    final l = SupplierLedger.build(
      distributors: const [],
      bills: [
        bill('OLD', 50000, date: now.subtract(const Duration(days: 60)), opening: true),
        bill('NEW', 30000, date: now.subtract(const Duration(days: 2))),
        bill('CASH', 9999, pay: PurchasePayment.cash),
      ],
      payments: [pay(30000, billNo: 'new'), pay(20000)],
    );
    final a = l.accounts['d_a']!;
    expect(a.outstandingPaise, 30000);
    final byNo = {for (final b in a.creditBills) b.bill.billNumber: b};
    expect(byNo['NEW']!.isPaid, isTrue);
    expect(byNo['OLD']!.balancePaise, 30000);
    expect(l.remindersAt(now).map((r) => r.bill.bill.billNumber), ['OLD']);
    expect(byNo['OLD']!.daysOverdue(now), 30);
  });

  test('the day book: sales by mode, returns, cash and credit purchases, payments, plus or minus', () {
    final today = DateTime(now.year, now.month, now.day);
    final r = SaleReturn(
      id: 'r',
      storeId: storeId,
      saleId: 's1',
      invoiceNumber: 'INV-1',
      customerName: 'A',
      lines: const [
        ReturnLine(lineIndex: 0, medicineId: 'dolo', batchId: 'b', name: 'Dolo', batchNumber: 'D1', unitsPerPack: 15,
            quantity: 15, refundPaise: 3360, costPaise: 2400, gstRate: 5),
      ],
      refundMode: RefundMode.cash,
      reason: '',
      createdAt: now,
      createdBy: 'u',
      createdByName: 'U',
    );
    final book = DayBook.build(
      from: today,
      to: today.add(const Duration(days: 1)),
      sales: [sale(), sale(mode: PaymentMode.upi), sale(at: now.subtract(const Duration(days: 3)))],
      returns: [r],
      bills: [
        bill('C', 10000, pay: PurchasePayment.cash),
        bill('K', 50000),
        bill('OLD', 99999, opening: true),
      ],
      payments: [pay(20000)],
    );
    final t = book.total;
    expect(t.bills, 2);
    expect(t.salesPaise, 13440);
    expect(t.netSalesPaise, 13440 - 3360);
    expect(t.grossProfitPaise, (13440 - 3360) - (9600 - 2400));
    expect(t.cashSalesPaise, 6700 - 3360);
    expect(t.upiSalesPaise, 6700);
    expect(t.cashPurchasePaise, 10000);
    expect(t.creditPurchasePaise, 50000, reason: 'the old bill is not a purchase of today');
    expect(t.paymentsPaise, 20000);
    expect(t.paidOutPaise, 30000);
    expect(t.netCashPaise, (6700 - 3360 + 6700) - 30000);
    expect(book.byDay.keys.single, today);
  });

  test('stock value counts every batch at its own rate; expired kept apart', () {
    final s = StockSummary(
      medicine: medicine('dolo'),
      batches: [
        batch('dolo', 'A', expiry: DateTime(2028, 1, 31), quantity: 23 * 15),
        batch('dolo', 'B', expiry: DateTime(2028, 1, 31), quantity: 7), // 7 loose tablets
        batch('dolo', 'X', expiry: DateTime(2026, 1, 31), quantity: 15),
      ],
      asOf: now,
    );
    final v = InventoryValue.of([s]);
    expect(v.costPaise, 23 * 2400 + (2400 * 7 * 2 + 15) ~/ 30);
    expect(v.mrpPaise, 23 * 3360 + 3360 * 7 ~/ 15);
    expect(v.expiredCostPaise, 2400);
  });
}
