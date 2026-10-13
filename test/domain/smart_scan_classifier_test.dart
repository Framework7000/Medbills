import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/data/repositories/global_catalogue_repository.dart';
import 'package:nuskha_pms/domain/services/ocr_text.dart';
import 'package:nuskha_pms/domain/services/smart_scan_classifier.dart';
import 'package:nuskha_pms/domain/services/supplier_bill_parser.dart';

void main() {
  final medicines = GlobalCatalogueRepository().search('').map((e) => e.medicine).toList();

  group('classifyCapture', () {
    test('a single medicine pack label is never mistaken for a bill', () {
      final page = OcrPage.fromText('''
Dolo-650
Paracetamol Tablets IP 650 mg
B.No. DOBS3975  Mfg. 06/2024
Exp. 05/2027
M.R.P. ₹ 33.60 Per Strip of 15 Tablets (Incl. of all taxes)
MICRO LABS LIMITED''');
      expect(classifyCapture(page, medicines), CaptureKind.pack);
    });

    test('a bill with several parseable medicine lines is a supplier bill', () {
      final page = OcrPage.fromText('''
SHREE SAI PHARMA DISTRIBUTORS
GSTIN: 23AAKFS1234C1Z9
Invoice No: SSP/2627/0456  Date: 08/10/2026
1  DOLO 650 TAB  15S  DOBS3975  05/27  20  2  33.60  24.19  483.80
2  PAN 40 TAB  15S  PNT24117  11/27  10  155.00  111.60  1116.00
Grand Total 1,599.80''');
      expect(classifyCapture(page, medicines), CaptureKind.supplierBill);
    });

    test('a long dense page still counts as a bill even if no line parses', () {
      // A bill the line-parser fails on entirely (no recognisable medicine
      // columns) is still a bill by its sheer amount of printed text, not a
      // pack — a pack label is always short.
      final page = OcrPage.fromText(List.generate(14, (i) => 'Unreadable printed line ${i + 1}').join('\n'));
      final draft = SupplierBillParser.parse(page, medicines);
      expect(draft.lines.length, lessThan(2));
      expect(classifyCapture(page, medicines), CaptureKind.supplierBill);
    });

    test('an empty capture is treated as a pack, not a bill', () {
      expect(classifyCapture(const OcrPage([]), medicines), CaptureKind.pack);
    });
  });
}
