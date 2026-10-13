import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/data/repositories/global_catalogue_repository.dart';
import 'package:nuskha_pms/domain/services/medicine_matcher.dart';
import 'package:nuskha_pms/domain/services/ocr_text.dart';
import 'package:nuskha_pms/domain/services/pack_label_parser.dart';
import 'package:nuskha_pms/domain/services/supplier_bill_parser.dart';

void main() {
  final medicines = GlobalCatalogueRepository().search('').map((e) => e.medicine).toList();

  group('month-year reading', () {
    test('reads the formats printed on Indian packs and bills', () {
      expect(parseMonthYear('05/27'), (month: 5, year: 2027));
      expect(parseMonthYear('5/2027'), (month: 5, year: 2027));
      expect(parseMonthYear('MAR-2027'), (month: 3, year: 2027));
      expect(parseMonthYear('Sept 26'), (month: 9, year: 2026));
      expect(parseMonthYear('05.2027'), (month: 5, year: 2027));
      expect(parseMonthYear('13/27'), isNull);
    });

    test('never mistakes a price, a full date or a word for an expiry', () {
      final p = RegExp(monthYearPattern);
      expect(p.hasMatch('RATE 12.50'), isFalse);
      expect(p.firstMatch('DATE 12/05/2027'), isNull);
      expect(p.hasMatch('MARG ERP 2024'), isFalse);
      expect(p.firstMatch('DL2401 11/27 10')!.group(0), '11/27');
    });
  });

  group('PackLabelParser', () {
    test('reads batch, expiry (not MFG) and MRP from a strip', () {
      final info = PackLabelParser.parse('''
Dolo-650
Paracetamol Tablets IP 650 mg
B.No. DOBS3975  Mfg. 06/2024
Exp. 05/2027
M.R.P. ₹ 33.60 Per Strip of 15 Tablets (Incl. of all taxes)
MICRO LABS LIMITED''');
      expect(info.batchNumber, 'DOBS3975');
      expect((info.expiryMonth, info.expiryYear), (5, 2027));
      expect(info.mrpPaise, 3360);
    });

    test('takes the later date when the EXP label was not read', () {
      final info = PackLabelParser.parse('Batch: AX2210 MFD 10/2025 12/2027 MRP Rs.42.00');
      expect(info.batchNumber, 'AX2210');
      expect((info.expiryMonth, info.expiryYear), (12, 2027));
      expect(info.mrpPaise, 4200);
    });

    test('returns empty when nothing useful is printed', () {
      expect(PackLabelParser.parse('Keep out of reach of children').isEmpty, isTrue);
    });
  });

  group('MedicineMatcher', () {
    test('finds the exact brand and strength', () {
      final result = MedicineMatcher.match('DOLO-650  Paracetamol Tablets IP 650mg  Micro Labs', medicines);
      expect(result.best!.medicine.name, 'Dolo 650 Tablet');
      expect(result.isConfident, isTrue);
    });

    test('does not confuse Pan 40 with Pan-D', () {
      final pan40 = MedicineMatcher.match('PAN 40 Pantoprazole Gastro-resistant Tablets IP 40 mg Alkem', medicines);
      expect(pan40.best!.medicine.name, 'Pan 40 Tablet');
      final panD = MedicineMatcher.match('PAN-D Pantoprazole 40 mg & Domperidone 30 mg Capsules Alkem', medicines);
      expect(panD.best!.medicine.name, 'Pan-D');
    });

    test('tolerates a one-letter OCR slip in a long brand name', () {
      expect(MedicineMatcher.match('AUGMENT1N 625 DUO', medicines).best!.medicine.name, 'Augmentin 625 Duo');
    });

    test('does not invent a match from a generic name alone', () {
      expect(MedicineMatcher.match('Paracetamol 500 mg', medicines.where((m) => m.name.startsWith('Dolo'))).best,
          isNull);
    });
  });

  group('SupplierBillParser', () {
    // A Marg-style stockist bill as OCR returns it: pieces of each table row
    // arrive separately with their positions.
    OcrPage bill() {
      final rows = [
        ['SHREE SAI PHARMA DISTRIBUTORS'],
        ['14, Siyaganj Main Road, Indore (M.P.)  Ph: 0731-2534567'],
        ['GSTIN: 23AAKFS1234C1Z9', 'D.L. No.: 20B/IND/1234, 21B/IND/1235'],
        ['TAX INVOICE'],
        ['Bill To: MEDBILLS PHARMACY  GSTIN: 23ABCDE1234F1Z5'],
        ['Invoice No: SSP/2627/0456', 'Date: 08/10/2026'],
        ['Sr', 'Product', 'Pack', 'Batch', 'Exp', 'Qty', 'Free', 'MRP', 'Rate', 'GST%', 'Amount'],
        ['1', 'DOLO 650 TAB', '15S', 'DOBS3975', '05/27', '20', '2', '33.60', '24.19', '12.00', '483.80'],
        ['2', 'PAN 40 TAB', '15S', 'PNT24117', '11/27', '10', '155.00', '111.60', '12.00', '1116.00'],
        ['3', 'AUGMENTIN 625 DUO TAB', '10S', 'B4011Z', 'MAR-27', '5', '223.40', '160.85', '12.00', '804.25'],
        ['Grand Total', '2,404.05'],
      ];
      final lines = <OcrLine>[];
      for (var r = 0; r < rows.length; r++) {
        for (var c = 0; c < rows[r].length; c++) {
          // Slight vertical jitter, as real OCR gives.
          final top = r * 30.0 + (c.isEven ? 0 : 2);
          lines.add(OcrLine(rows[r][c], left: c * 80.0, right: c * 80.0 + 70, top: top, bottom: top + 18));
        }
      }
      return OcrPage(lines..shuffle());
    }

    test('reads the supplier header and skips the store\'s own GSTIN', () {
      final draft = SupplierBillParser.parse(bill(), medicines, ownGstin: '23ABCDE1234F1Z5');
      expect(draft.supplierName, 'Shree Sai Pharma Distributors');
      expect(draft.supplierGstin, '23AAKFS1234C1Z9');
      expect(draft.supplierDrugLicence, startsWith('20B/IND/1234'));
      expect(draft.invoiceNumber, 'SSP/2627/0456');
      expect(draft.invoiceDate, DateTime(2026, 10, 8));
      expect(draft.billTotalPaise, 240405);
    });

    test('reads each medicine line with batch, expiry, quantity, free, rate and MRP', () {
      final lines = SupplierBillParser.parse(bill(), medicines).lines;
      expect(lines, hasLength(3));

      final dolo = lines[0];
      expect(dolo.medicineName, 'Dolo 650 Tablet');
      expect(dolo.batchNumber, 'DOBS3975');
      expect((dolo.expiryMonth, dolo.expiryYear), (5, 2027));
      expect((dolo.packs, dolo.freePacks), (20, 2));
      expect((dolo.mrpPaise, dolo.ratePaise), (3360, 2419));

      final pan = lines[1];
      expect(pan.medicineName, 'Pan 40 Tablet');
      expect((pan.packs, pan.freePacks), (10, 0));
      expect((pan.mrpPaise, pan.ratePaise), (15500, 11160));

      final aug = lines[2];
      expect(aug.medicineName, 'Augmentin 625 Duo');
      expect(aug.batchNumber, 'B4011Z');
      expect((aug.expiryMonth, aug.expiryYear), (3, 2027));
      expect((aug.mrpPaise, aug.ratePaise), (22340, 16085));
    });

    test('keeps an unknown product line for the pharmacist to match', () {
      final page = OcrPage.fromText('1  XYZOCIN 250 TAB  10S  XZ7781  08/27  6  80.00  58.00  348.00');
      final line = SupplierBillParser.parse(page, medicines).lines.single;
      expect(line.medicineId, isNull);
      expect(line.medicineName, startsWith('XYZOCIN'));
      expect(line.batchNumber, 'XZ7781');
      expect((line.packs, line.mrpPaise, line.ratePaise), (6, 8000, 5800));
    });

    test('a weak, unconfident match is shown as a guess but never auto-trusted', () {
      // "Digene" alone (its generic, "Magaldrate + Simethicone", doesn't
      // appear here, and it has no strength number to confirm against)
      // scores above the matcher's floor but below its confidence bar —
      // the line must still parse, with the guess as a starting point for
      // the pharmacist to confirm or correct, not silently assumed right.
      final page = OcrPage.fromText('1  DIGENE GEL  1  B123  05/27  2  50.00  95.00');
      final line = SupplierBillParser.parse(page, medicines).lines.single;
      expect(line.medicineId, isNull);
      expect(line.medicineName, 'Digene Gel');
      expect(line.batchNumber, 'B123');
      expect((line.packs, line.mrpPaise, line.ratePaise), (2, 9500, 5000));
    });

    test('reads a bill where the batch sits right after the item, not next to the expiry', () {
      // A real cash-memo layout: Item Name, Unit, Batch, Qty+free, MRP,
      // Rate, Amount, Exp — the batch is far from the expiry, with four
      // price/qty columns between them, and "ZTAB 200" has a bare strength
      // number in the name itself (no unit suffix) that must not be read
      // as part of the quantity.
      final page = OcrPage.fromText('''
BHAGWATI PHARMA SALES
SHOP NO-27,28,29,30 SECOND FLOOR DA   GST No. : 23AASFB6139R1Z0
CASH MEMO
Item Name   Unit  Batch   Qty+free  MRP     RATE    AMOUNT  EXP
ZTAB 200    * 30ML L7166  5+1       95.00   72.40   362.00  5/28
DUPHALAC SALUTION * 150ML 883171 2  198.14  150.98  301.96  3/28
GROSS TOTAL : 663.96''');
      final draft = SupplierBillParser.parse(page, medicines);
      expect(draft.supplierName, 'Bhagwati Pharma Sales');
      expect(draft.lines, hasLength(2));

      final ztab = draft.lines[0];
      expect(ztab.batchNumber, 'L7166');
      expect((ztab.expiryMonth, ztab.expiryYear), (5, 2028));
      expect((ztab.packs, ztab.freePacks), (5, 1));
      expect((ztab.mrpPaise, ztab.ratePaise), (9500, 7240));

      final duphalac = draft.lines[1];
      expect(duphalac.batchNumber, '883171');
      expect((duphalac.packs, duphalac.freePacks), (2, 0));
      expect((duphalac.mrpPaise, duphalac.ratePaise), (19814, 15098));

      expect(draft.billTotalPaise, 66396);
    });
  });
}
