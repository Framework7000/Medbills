import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/sale_invoice.dart';

const _retentionDays = 180;

class BillHistoryNotifier extends StateNotifier<List<SaleInvoice>> {
  BillHistoryNotifier() : super(_seedInvoices);

  static final List<SaleInvoice> _seedInvoices = [
    SaleInvoice(
      invoiceNumber: 'INV-2026-1050',
      storeId: 'store_primary',
      timestamp: DateTime.now().subtract(const Duration(days: 2)),
      customerName: 'Walk-in Customer',
      customerPhone: '9752408128',
      paymentMode: 'Cash',
      grandTotalPaise: 18500,
      gstTotalPaise: 1980,
      items: const [
        InvoiceItemRecord(
          medicineId: 'med_001',
          name: 'Paracetamol 500mg',
          batchNumber: 'B0001',
          expiry: '12/2027',
          quantity: 2,
          mrpPaise: 3500,
          gstRate: 5.0,
        ),
        InvoiceItemRecord(
          medicineId: 'med_006',
          name: 'Amoxicillin 500mg',
          batchNumber: 'B0006',
          expiry: '06/2027',
          quantity: 1,
          mrpPaise: 8500,
          gstRate: 12.0,
        ),
      ],
    ),
    SaleInvoice(
      invoiceNumber: 'INV-2026-1049',
      storeId: 'store_primary',
      timestamp: DateTime.now().subtract(const Duration(days: 5)),
      customerName: 'Ramesh Kumar',
      customerPhone: '9812345678',
      paymentMode: 'UPI',
      grandTotalPaise: 6200,
      gstTotalPaise: 664,
      items: const [
        InvoiceItemRecord(
          medicineId: 'med_008',
          name: 'Pantoprazole 40mg',
          batchNumber: 'B0008',
          expiry: '09/2027',
          quantity: 1,
          mrpPaise: 6200,
          gstRate: 12.0,
        ),
      ],
    ),
  ];

  void addInvoice(SaleInvoice invoice) {
    state = [invoice, ...state];
    purgeOldRecords();
  }

  void purgeOldRecords() {
    final cutoff = DateTime.now().subtract(const Duration(days: _retentionDays));
    state = state.where((invoice) => invoice.timestamp.isAfter(cutoff)).toList();
  }
}

final billHistoryProvider =
    StateNotifierProvider<BillHistoryNotifier, List<SaleInvoice>>((ref) {
  return BillHistoryNotifier();
});
