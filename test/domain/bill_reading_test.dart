import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/bill_scan.dart';
import 'package:nuskha_pms/domain/models/supplier_account.dart';
import 'package:nuskha_pms/domain/services/bill_reading_merge.dart';
import 'package:nuskha_pms/domain/services/distributor_match.dart';
import 'package:nuskha_pms/domain/services/ocr_text.dart';
import 'package:nuskha_pms/domain/services/photo_clean.dart';

/// A bill table read as separate pieces per column, photographed turned by
/// [degrees] (rows run uphill to the right).
OcrPage table(double degrees) {
  final slope = math.tan(degrees * math.pi / 180);
  const rows = [
    ['TELMIKIND BETA 25MG', 'TB7752', '11/27', '4', '136.12', '103.81'],
    ['NEOSPRIN EYE OINT', 'NS4344', '06/28', '2', '149.00', '114.88'],
    ['ACORTIL SYP 100ML', 'AC0310', '03/28', '3', '42.24', '33.80'],
    ['GLYCOMET SR 500MG', 'GL8009', '05/28', '10', '31.40', '23.53'],
    ['FLAGYL 400 TAB', 'FG0048', '08/27', '5', '24.10', '18.27'],
  ];
  const xs = [100.0, 700.0, 950.0, 1150.0, 1350.0, 1600.0];
  const widths = [420.0, 140.0, 110.0, 40.0, 120.0, 120.0];
  return OcrPage([
    for (var r = 0; r < rows.length; r++)
      for (var c = 0; c < xs.length; c++)
        () {
          final cx = xs[c] + widths[c] / 2;
          final cy = 300 + r * 46 - cx * slope; // uphill: further right is higher
          final h = 28 + widths[c] * slope.abs(); // a turned line's box is taller
          return OcrLine(rows[r][c], left: xs[c], right: xs[c] + widths[c], top: cy - h / 2, bottom: cy + h / 2);
        }(),
  ]);
}

BillDraftLine line(String name,
        {String batch = '', int? month, int? year, num packs = 0, int rate = 0, int mrp = 0, String? id}) =>
    BillDraftLine(
        rawText: name,
        medicineName: name,
        medicineId: id,
        batchNumber: batch,
        expiryMonth: month,
        expiryYear: year,
        packs: packs,
        ratePaise: rate,
        mrpPaise: mrp);

void main() {
  group('rows of a turned photo', () {
    for (final degrees in [0.0, 3.0, -5.0, 8.0]) {
      test('$degrees° keeps each medicine with its own figures', () {
        final rows = table(degrees).rows();
        expect(rows, hasLength(5));
        expect(rows[0], startsWith('TELMIKIND BETA 25MG  TB7752  11/27  4  136.12  103.81'));
        expect(rows[4], 'FLAGYL 400 TAB  FG0048  08/27  5  24.10  18.27');
      });
    }

    test('a small piece on a turned page (a dot, a tick) is handled', () {
      final page = OcrPage([
        ...table(6).lines,
        const OcrLine('.', left: 50, right: 54, top: 300, bottom: 304),
      ]);
      expect(page.rows().where((r) => r.contains('FLAGYL')).single, contains('18.27'));
    });

    test('a level page is left exactly as it was read', () {
      const page = OcrPage([
        OcrLine('A', left: 0, right: 10, top: 0, bottom: 10),
        OcrLine('B', left: 20, right: 30, top: 1, bottom: 11),
      ]);
      expect(page.rows(), ['A  B']);
    });
  });

  group('combining two readings of one bill', () {
    test('fills what one reading missed from the other, never inventing', () {
      final plain = BillDraft(supplierName: 'Apna Medical Agency', lines: [
        line('TELMIKIND BETA', batch: 'TB7752', month: 11, year: 2027, packs: 4, rate: 10381),
        line('ACORTIL SYP', batch: 'ACO310', packs: 3, rate: 3380, mrp: 4224),
      ]);
      final cleaned = BillDraft(invoiceNumber: 'GCC010774', billTotalPaise: 132753, lines: [
        line('TELMIKIND BETA', batch: 'TB7752', month: 11, year: 2027, packs: 4, rate: 10381, mrp: 13612),
        line('ACORTIL SYP', batch: 'AC0310', month: 3, year: 2028, packs: 3, rate: 3380, mrp: 4224),
        line('GLYCOMET SR', batch: 'GL8009', month: 5, year: 2028, packs: 10, rate: 2353, mrp: 3140),
      ]);
      final both = combineBillReadings([plain, cleaned]);
      expect(both.supplierName, 'Apna Medical Agency');
      expect(both.invoiceNumber, 'GCC010774');
      expect(both.billTotalPaise, 132753);
      expect(both.lines, hasLength(3), reason: 'ACO310 and AC0310 are the same batch, read two ways');
      final telmi = both.lines.firstWhere((l) => l.medicineName.startsWith('TELMI'));
      expect((telmi.ratePaise, telmi.mrpPaise), (10381, 13612));
      final acortil = both.lines.firstWhere((l) => l.medicineName.startsWith('ACORTIL'));
      expect((acortil.expiryMonth, acortil.expiryYear), (3, 2028));
    });

    test('where the readings disagree, the field is left for the pharmacist', () {
      final a = BillDraft(lines: [line('TELMIKIND', batch: 'TB7752', packs: 4, rate: 10381, mrp: 13612)]);
      final b = BillDraft(lines: [line('TELMIKIND', batch: 'TB7752', packs: 1, rate: 10381, mrp: 18612)]);
      final both = combineBillReadings([a, b]).lines.single;
      expect(both.packs, 0, reason: '4 or 1 — not guessed');
      expect(both.ratePaise, 10381, reason: 'both read the same rate');
      expect(both.mrpPaise, 0, reason: '136.12 or 186.12 — not guessed');
    });

    test('a pair of prices that makes sense beats one that does not', () {
      final a = BillDraft(lines: [line('FLAGYL', batch: 'FG0048', packs: 5, rate: 2410, mrp: 2700)]);
      final b = BillDraft(lines: [line('FLAGYL', batch: 'FG0048', packs: 5, rate: 1827, mrp: 2410)]);
      // 24.10 → 27.00 is under 11%, 18.27 → 24.10 is 24%: both "make sense".
      // Both sensible but different: both left blank rather than picking one.
      final both = combineBillReadings([a, b]).lines.single;
      expect((both.ratePaise, both.mrpPaise), (0, 0));

      final c = BillDraft(lines: [line('ECOSPRIN', batch: 'Z019', packs: 6, rate: 412)]);
      final d = BillDraft(lines: [line('ECOSPRIN', batch: 'Z019', packs: 6, rate: 412, mrp: 2472)]);
      expect(combineBillReadings([c, d]).lines.single.mrpPaise, 0,
          reason: '24.72 is the line amount (6 × 4.12), not an MRP');
    });

    test('a generic bought at a big margin is not mistaken for a misread', () {
      final a = BillDraft(lines: [line('PARACETAMOL 500', batch: 'G1', packs: 10, rate: 600, mrp: 2500)]);
      final b = BillDraft(lines: [line('PARACETAMOL 500', batch: 'G1', packs: 10, rate: 600)]);
      final both = combineBillReadings([a, b]).lines.single;
      expect((both.ratePaise, both.mrpPaise), (600, 2500));
    });

    test('a row only one reading saw is added only when it is clearly an item', () {
      final a = BillDraft(lines: [line('DOLO 650', batch: 'D123', month: 1, year: 2028, packs: 2, rate: 2400, mrp: 3200)]);
      final b = BillDraft(lines: [
        line('DOLO 650', batch: 'D123', month: 1, year: 2028, packs: 2),
        line('PAN 40', batch: 'P77', month: 4, year: 2028, packs: 3),
        line('JUNK ROW'),
      ]);
      expect(combineBillReadings([a, b]).lines.map((l) => l.medicineName), ['DOLO 650', 'PAN 40']);
    });

    test('one reading, or none, comes back as it is', () {
      final a = BillDraft(supplierName: 'X', lines: [line('DOLO 650', batch: 'D1', packs: 1)]);
      expect(combineBillReadings([a]), same(a));
      expect(combineBillReadings([a, const BillDraft()]), same(a));
      expect(combineBillReadings([]).lines, isEmpty);
    });
  });

  test('a shadow across the bill is evened out and print stays dark', () {
    const w = 200, h = 100;
    final gray = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final paper = 60 + (x * 180 ~/ w); // dark on the left, bright on the right
        final ink = (y ~/ 10).isOdd && x % 7 < 3; // stripes of "print"
        gray[y * w + x] = ink ? paper ~/ 3 : paper;
      }
    }
    final out = flattenLighting(gray, w, h);
    int at(int x, int y) => out[y * w + x];
    expect(at(10, 5), greaterThan(225), reason: 'paper in the shadow is white');
    expect(at(190, 5), greaterThan(225), reason: 'paper in the light is white');
    expect(at(14, 15), lessThan(80), reason: 'print in the shadow is dark');
    expect(at(189, 15), lessThan(80), reason: 'print in the light is dark');
  });

  group('which known distributor a bill is from', () {
    Distributor d(String name, {String gstin = ''}) =>
        Distributor(id: Distributor.idFor(name), storeId: 's', name: name, gstin: gstin, createdAt: DateTime(2026));
    final list = [
      d('Apna Medical Agency', gstin: '23ABZPA1234C1Z5'),
      d('Shree Ganesh Pharma'),
      d('Medical Agency'), // says nothing on its own
    ];

    test('by GSTIN, exactly', () {
      expect(matchDistributor(gstin: '23abzpa1234c1z5', supplierName: '', ocrText: '', distributors: list)?.name,
          'Apna Medical Agency');
    });

    test('by the full name anywhere on the bill', () {
      expect(
          matchDistributor(
                  gstin: '', supplierName: 'Tax Invoice', ocrText: 'TAX INVOICE\nSHREE GANESH  PHARMA.\nJABALPUR', distributors: list)
              ?.name,
          'Shree Ganesh Pharma');
    });

    test('by a name read a letter off', () {
      expect(matchDistributor(gstin: '', supplierName: 'Apna Medlcal Agencv', ocrText: '', distributors: list)?.name,
          'Apna Medical Agency');
    });

    test('a new distributor, or a name that only says "Medical Agency", matches nothing', () {
      expect(matchDistributor(gstin: '', supplierName: 'Om Sai Distributors', ocrText: 'OM SAI', distributors: list), isNull);
      expect(
          matchDistributor(gstin: '', supplierName: '', ocrText: 'RAJ MEDICAL AGENCY JABALPUR', distributors: list), isNull);
    });
  });
}
