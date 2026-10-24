import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/services/scanned_code.dart';

String _b64(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// A GST e-invoice QR as printed on supplier bills: a signed JWT whose
/// payload's "data" is the invoice summary (as a JSON string).
String _eInvoiceQr(Map<String, Object> invoice) =>
    '${_b64({'alg': 'RS256', 'kid': 'ABC', 'typ': 'JWT'})}.'
    '${_b64({'data': jsonEncode(invoice), 'iss': 'NIC'})}.'
    'c2lnbmF0dXJlLW5vdC1jaGVja2VkLWhlcmU';

void main() {
  group('GST e-invoice QR on a supplier bill', () {
    test('reads supplier, buyer, invoice number, date, total, items and HSN', () {
      final code = ScannedCode.decode(_eInvoiceQr({
        'SellerGstin': '23AAKFS1234C1Z9',
        'BuyerGstin': '23ABCDE1234F1Z5',
        'DocNo': 'SSP/2627/0456',
        'DocTyp': 'INV',
        'DocDt': '08/10/2026',
        'TotInvVal': 15998.5,
        'ItemCnt': 12,
        'MainHsnCode': '30049099',
        'Irn': 'a5c12dca80e743321740b001fd70953e8738d109865d28ba4013750f2046f229',
        'IrnDt': '2026-10-08 14:21:00',
      }));
      expect(code, isA<EInvoiceCode>());
      final bill = code as EInvoiceCode;
      expect(bill.sellerGstin, '23AAKFS1234C1Z9');
      expect(bill.buyerGstin, '23ABCDE1234F1Z5');
      expect(bill.docNo, 'SSP/2627/0456');
      expect(bill.docTypeLabel, 'Tax invoice');
      expect(bill.docDate, DateTime(2026, 10, 8));
      expect(bill.totalPaise, 1599850);
      expect(bill.itemCount, 12);
      expect(bill.mainHsn, '30049099');
      expect(bill.irn, startsWith('a5c12dca'));
    });

    test('a credit note is labelled as one', () {
      final code = ScannedCode.decode(_eInvoiceQr({'SellerGstin': '23AAKFS1234C1Z9', 'DocTyp': 'CRN', 'DocNo': 'CN/7'}));
      expect((code as EInvoiceCode).docTypeLabel, 'Credit note');
    });
  });

  group('medicine pack codes', () {
    test('a plain retail barcode is just the product number', () {
      final code = ScannedCode.decode('8901234567890') as PackCode;
      expect(code.gtin, '8901234567890');
      expect(code.isPlainBarcode, isTrue);
    });

    test('GS1 DataMatrix with separators: batch before expiry, plus mfg and serial', () {
      final code = ScannedCode.decode(']d2' '0108901234567890' '10DOBS3975\u001d' '17270531' '11240600' '21ABC123XYZ') as PackCode;
      expect(code.gtin, '08901234567890');
      expect(code.batch, 'DOBS3975');
      expect(code.expiry, DateTime(2027, 5, 31));
      expect(code.manufactured, DateTime(2024, 6, 1));
      expect(code.serial, 'ABC123XYZ');
    });

    test('GS1 in brackets, expiry day 00 means end of month', () {
      final code = ScannedCode.decode('(01)08901234567890(17)270500(10)B4011Z') as PackCode;
      expect(code.expiry, DateTime(2027, 5, 31));
      expect(code.batch, 'B4011Z');
    });

    test('GS1 Digital Link URL', () {
      final code = ScannedCode.decode('https://id.gs1.org/01/08901234567890/10/PNT24117?17=271130') as PackCode;
      expect(code.gtin, '08901234567890');
      expect(code.batch, 'PNT24117');
      expect(code.expiry, DateTime(2027, 11, 30));
      expect(code.url, startsWith('https://'));
    });

    test('Schedule H2 QR with labelled text', () {
      final code = ScannedCode.decode('Brand Name: Dolo 650 | Generic Name: Paracetamol Tablets IP 650 mg | '
          'Manufacturer: Micro Labs Ltd, Bengaluru | Batch No: dobs3975 | Mfg Date: 06/2024 | Exp Date: 05/2027 | '
          'Mfg Lic No: KTK/25/123/2010 | MRP: Rs. 33.60') as PackCode;
      expect(code.brand, 'Dolo 650');
      expect(code.genericName, 'Paracetamol Tablets IP 650 mg');
      expect(code.manufacturer, startsWith('Micro Labs'));
      expect(code.batch, 'DOBS3975');
      expect(code.manufactured, DateTime(2024, 6, 1));
      expect(code.expiry, DateTime(2027, 5, 31));
      expect(code.licence, 'KTK/25/123/2010');
      expect(code.mrpPaise, 3360);
      expect(code.isExpiredAt(DateTime(2027, 6, 1)), isTrue);
      expect(code.isExpiredAt(DateTime(2027, 5, 31)), isFalse);
    });

    test('labelled text on separate lines', () {
      final code = ScannedCode.decode('Product Name: Pan 40\nBatch: PNT24117\nExpiry: NOV 2027') as PackCode;
      expect(code.brand, 'Pan 40');
      expect(code.expiry, DateTime(2027, 11, 30));
    });
  });

  test('anything else is kept as plain text, never guessed at', () {
    expect(ScannedCode.decode('Thank you for shopping'), isA<TextCode>());
    final link = ScannedCode.decode('upi://pay?pa=shop@upi&pn=Shop');
    expect(link, isA<TextCode>());
    expect(ScannedCode.decode('https://example.com/about'), isA<PackCode>()); // a link is shown as-is
    expect(ScannedCode.decode('abc.def.ghi'), isA<TextCode>()); // not a real e-invoice
  });
}
