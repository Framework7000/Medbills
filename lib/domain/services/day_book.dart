import '../models/sale_invoice.dart';
import '../models/sale_return.dart';
import '../models/supplier_account.dart';

/// One day's (or one period's) money in and out, all in integer paise.
class BookFigures {
  int bills = 0;
  int cancelledBills = 0;
  int salesPaise = 0; // charged on bills, after discounts, before round-off
  int collectedPaise = 0; // payable on bills (after round-off)
  int discountPaise = 0;
  int gstPaise = 0;
  int costPaise = 0; // purchase cost of goods sold
  final Map<PaymentMode, int> salesByMode = {};

  int returnsCount = 0;
  int refundPaise = 0;
  int returnCostPaise = 0;
  int returnGstPaise = 0;
  final Map<RefundMode, int> refundByMode = {};

  int cashPurchasePaise = 0;
  int creditPurchasePaise = 0;
  int paymentsPaise = 0;
  final Map<PaidVia, int> paymentsByVia = {};

  /// Sales less returns.
  int get netSalesPaise => salesPaise - refundPaise;
  int get netCostPaise => costPaise - returnCostPaise;
  int get netGstPaise => gstPaise - returnGstPaise;

  /// Sales minus the purchase cost of what was sold (returns taken out).
  int get grossProfitPaise => netSalesPaise - netCostPaise;
  double get marginPercent => netSalesPaise == 0 ? 0 : grossProfitPaise * 100 / netSalesPaise;

  int get purchasePaise => cashPurchasePaise + creditPurchasePaise;

  /// Money that went out: cash purchases plus payments of old bills.
  int get paidOutPaise => cashPurchasePaise + paymentsPaise;

  int _mode(PaymentMode m) => salesByMode[m] ?? 0;
  int _refund(RefundMode m) => refundByMode[m] ?? 0;

  /// Money that came in from sales (cash, UPI, card), less refunds paid out.
  int get cashInPaise =>
      _mode(PaymentMode.cash) + _mode(PaymentMode.upi) + _mode(PaymentMode.card) -
      _refund(RefundMode.cash) - _refund(RefundMode.upi);

  /// Cash sales less cash refunds.
  int get cashSalesPaise => _mode(PaymentMode.cash) - _refund(RefundMode.cash);
  int get upiSalesPaise => _mode(PaymentMode.upi) - _refund(RefundMode.upi);
  int get cardSalesPaise => _mode(PaymentMode.card);
  int get udhaarSalesPaise => _mode(PaymentMode.credit) - _refund(RefundMode.udhaar);

  /// Plus or minus for the period: money in less money paid out.
  int get netCashPaise => cashInPaise - paidOutPaise;
}

class DayBook {
  final DateTime from;
  final DateTime to; // exclusive
  final BookFigures total;
  final Map<DateTime, BookFigures> byDay; // midnight → that day's figures
  final List<SupplierBill> purchases; // in the period, newest first
  final List<SupplierPayment> payments; // in the period, newest first
  final List<SaleReturn> returns;

  const DayBook({
    required this.from,
    required this.to,
    required this.total,
    required this.byDay,
    required this.purchases,
    required this.payments,
    required this.returns,
  });

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static bool _within(DateTime t, DateTime from, DateTime to) => !t.isBefore(from) && t.isBefore(to);

  /// [sales] and [returns] may include records outside [from, to); only those
  /// inside count. Old bills entered as opening dues are not purchases of
  /// the period (they only add to what is owed).
  static DayBook build({
    required DateTime from,
    required DateTime to,
    required Iterable<SaleInvoice> sales,
    Iterable<SaleReturn> returns = const [],
    Iterable<SupplierBill> bills = const [],
    Iterable<SupplierPayment> payments = const [],
  }) {
    final total = BookFigures();
    final byDay = <DateTime, BookFigures>{};
    BookFigures day(DateTime t) => byDay.putIfAbsent(_day(t), BookFigures.new);
    for (var d = _day(from); d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
      day(d);
    }

    for (final s in sales) {
      if (!_within(s.createdAt, from, to)) continue;
      for (final f in [total, day(s.createdAt)]) {
        if (s.isCancelled) {
          f.cancelledBills++;
          continue;
        }
        f.bills++;
        f.salesPaise += s.grossPaise;
        f.collectedPaise += s.payablePaise;
        f.discountPaise += s.discountPaise;
        f.gstPaise += s.gstPaise;
        f.costPaise += s.costPaise;
        f.salesByMode.update(s.paymentMode, (v) => v + s.payablePaise, ifAbsent: () => s.payablePaise);
      }
    }
    final periodReturns = returns.where((r) => _within(r.createdAt, from, to)).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final r in periodReturns) {
      for (final f in [total, day(r.createdAt)]) {
        f.returnsCount++;
        f.refundPaise += r.refundPaise;
        f.returnCostPaise += r.costPaise;
        f.returnGstPaise += r.gstPaise;
        f.refundByMode.update(r.refundMode, (v) => v + r.refundPaise, ifAbsent: () => r.refundPaise);
      }
    }
    final periodBills = bills
        .where((b) => !b.cancelled && !b.isOpening && _within(b.billDate, from, to))
        .toList()
      ..sort((a, b) => b.billDate.compareTo(a.billDate));
    for (final b in periodBills) {
      for (final f in [total, day(b.billDate)]) {
        if (b.isCredit) {
          f.creditPurchasePaise += b.totalPaise;
        } else {
          f.cashPurchasePaise += b.totalPaise;
        }
      }
    }
    final periodPayments = payments.where((p) => !p.cancelled && _within(p.paidOn, from, to)).toList()
      ..sort((a, b) => b.paidOn.compareTo(a.paidOn));
    for (final p in periodPayments) {
      for (final f in [total, day(p.paidOn)]) {
        f.paymentsPaise += p.amountPaise;
        f.paymentsByVia.update(p.via, (v) => v + p.amountPaise, ifAbsent: () => p.amountPaise);
      }
    }
    return DayBook(
      from: from,
      to: to,
      total: total,
      byDay: byDay,
      purchases: periodBills,
      payments: periodPayments,
      returns: periodReturns,
    );
  }
}
