import '../models/sale_invoice.dart';

class ProfitLossReport {
  final int invoiceCount;
  final int cancelledCount;
  final int salesPaise; // amount billed at MRP, GST-inclusive (before round-off)
  final int gstPaise;
  final int costPaise; // purchase cost of the goods sold
  final Map<PaymentMode, int> byPaymentMode; // payable amounts
  final Map<double, int> gstBySlab;

  const ProfitLossReport({
    required this.invoiceCount,
    required this.cancelledCount,
    required this.salesPaise,
    required this.gstPaise,
    required this.costPaise,
    required this.byPaymentMode,
    required this.gstBySlab,
  });

  int get grossProfitPaise => salesPaise - costPaise;

  double get marginPercent => salesPaise == 0 ? 0 : grossProfitPaise * 100 / salesPaise;
}

/// All calculations in integer paise. Cancelled invoices are excluded from
/// every total and only counted.
class ProfitLossService {
  static ProfitLossReport calculate(Iterable<SaleInvoice> invoices) {
    var count = 0;
    var cancelled = 0;
    var sales = 0;
    var gst = 0;
    var cost = 0;
    final byMode = <PaymentMode, int>{};
    final bySlab = <double, int>{};

    for (final invoice in invoices) {
      if (invoice.isCancelled) {
        cancelled++;
        continue;
      }
      count++;
      sales += invoice.grossPaise;
      gst += invoice.gstPaise;
      cost += invoice.costPaise;
      byMode.update(invoice.paymentMode, (v) => v + invoice.payablePaise,
          ifAbsent: () => invoice.payablePaise);
      for (final slab in invoice.slabs) {
        bySlab.update(slab.rate, (v) => v + slab.gstPaise, ifAbsent: () => slab.gstPaise);
      }
    }

    return ProfitLossReport(
      invoiceCount: count,
      cancelledCount: cancelled,
      salesPaise: sales,
      gstPaise: gst,
      costPaise: cost,
      byPaymentMode: byMode,
      gstBySlab: bySlab,
    );
  }
}
