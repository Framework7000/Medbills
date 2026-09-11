import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/sale_invoice.dart';
import 'package:nuskha_pms/domain/services/profit_loss_service.dart';

void main() {
  test('calculates revenue, cost, and margin in paise', () {
    final invoice = SaleInvoice(
      invoiceNumber: 'INV-1',
      storeId: 'store_primary',
      timestamp: DateTime.now(),
      customerName: 'Test',
      customerPhone: '9999999999',
      paymentMode: 'Cash',
      grandTotalPaise: 20000,
      gstTotalPaise: 2143,
      items: const [
        InvoiceItemRecord(
          medicineId: 'med_001',
          name: 'Paracetamol',
          batchNumber: 'B1',
          expiry: '12/2027',
          quantity: 2,
          mrpPaise: 10000,
          gstRate: 12.0,
        ),
      ],
    );

    final report = ProfitLossService.calculate(
      invoices: [invoice],
      costLookup: {ProfitLossService.costLookupKey('med_001', 'B1'): 6000},
    );

    expect(report.totalSalesPaise, 20000);
    expect(report.totalCostPaise, 12000);
    expect(report.grossProfitPaise, 8000);
    expect(report.profitMarginPercentage, 40.0);
  });

  test('excludes cancelled invoices', () {
    final cancelled = SaleInvoice(
      invoiceNumber: 'INV-2',
      storeId: 'store_primary',
      timestamp: DateTime.now(),
      customerName: 'Test',
      customerPhone: '9999999999',
      paymentMode: 'Cash',
      grandTotalPaise: 5000,
      gstTotalPaise: 500,
      items: const [],
      isCancelled: true,
    );

    final report = ProfitLossService.calculate(invoices: [cancelled], costLookup: const {});
    expect(report.totalSalesPaise, 0);
  });
}
