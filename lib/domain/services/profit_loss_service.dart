import '../models/batch.dart';
import '../models/sale_invoice.dart';

class ProfitLossReport {
  final int totalSalesPaise;
  final int totalCostPaise;
  final int grossProfitPaise;

  const ProfitLossReport({
    required this.totalSalesPaise,
    required this.totalCostPaise,
    required this.grossProfitPaise,
  });

  double get profitMarginPercentage {
    if (totalSalesPaise == 0) return 0.0;
    return (grossProfitPaise / totalSalesPaise) * 100;
  }
}

/// All calculations performed in integer paise (Rule 12).
class ProfitLossService {
  /// [costLookup] maps `medicineId|batchNumber` to purchase price in paise,
  /// derived from the batch used to fulfil that line item.
  static ProfitLossReport calculate({
    required List<SaleInvoice> invoices,
    required Map<String, int> costLookup,
  }) {
    var totalSales = 0;
    var totalCost = 0;

    for (final invoice in invoices) {
      if (invoice.isCancelled) continue;
      for (final item in invoice.items) {
        totalSales += item.totalPaise;
        final key = '${item.medicineId}|${item.batchNumber}';
        final unitCost = costLookup[key] ?? 0;
        totalCost += unitCost * item.quantity;
      }
    }

    return ProfitLossReport(
      totalSalesPaise: totalSales,
      totalCostPaise: totalCost,
      grossProfitPaise: totalSales - totalCost,
    );
  }

  static String costLookupKey(String medicineId, String batchNumber) =>
      '$medicineId|$batchNumber';

  static Map<String, int> buildCostLookup(List<Batch> batches) {
    return {
      for (final b in batches)
        costLookupKey(b.medicineId, b.batchNumber): b.purchasePricePaise,
    };
  }
}
