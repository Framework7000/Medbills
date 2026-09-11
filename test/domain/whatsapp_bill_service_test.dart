import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/sale_invoice.dart';
import 'package:nuskha_pms/domain/services/whatsapp_bill_service.dart';

SaleInvoice _invoice({required String phone}) {
  return SaleInvoice(
    invoiceNumber: 'INV-2026-1051',
    storeId: 'store_primary',
    timestamp: DateTime(2026, 9, 12, 10, 30),
    customerName: 'Test Customer',
    customerPhone: phone,
    paymentMode: 'Cash',
    grandTotalPaise: 11200,
    gstTotalPaise: 1200,
    items: const [
      InvoiceItemRecord(
        medicineId: 'med_001',
        name: 'Paracetamol',
        batchNumber: 'B1',
        expiry: '12/2027',
        quantity: 1,
        mrpPaise: 11200,
        gstRate: 12.0,
      ),
    ],
  );
}

void main() {
  group('WhatsAppBillService', () {
    test('message includes invoice number and grand total', () {
      final message = WhatsAppBillService.formatWhatsAppMessage(_invoice(phone: '9752408128'));
      expect(message, contains('INV-2026-1051'));
      expect(message, contains('112.00'));
    });

    test('normalizes 10-digit phone by prepending 91', () {
      expect(WhatsAppBillService.normalizePhone('9752408128'), '919752408128');
    });

    test('encodes message into the wa.me URI', () {
      final uri = WhatsAppBillService.buildWhatsAppUri(_invoice(phone: '9752408128'));
      expect(uri.host, 'wa.me');
      expect(uri.path, '/919752408128');
      expect(uri.queryParameters['text'], contains('INV-2026-1051'));
    });
  });
}
