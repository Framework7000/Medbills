import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/services/billing_calculator.dart';
import 'package:nuskha_pms/domain/services/invoice_number.dart';
import 'package:nuskha_pms/domain/services/pack_units.dart';

void main() {
  group('BillingCalculator.linePaise', () {
    test('prices loose tablets from the per-strip MRP, rounded to the paisa', () {
      // ₹35.00 per strip of 15, 5 tablets → ₹11.666… → ₹11.67
      expect(BillingCalculator.linePaise(mrpPaisePerPack: 3500, unitsPerPack: 15, quantityUnits: 5), 1167);
    });

    test('whole packs are exact', () {
      expect(BillingCalculator.linePaise(mrpPaisePerPack: 3500, unitsPerPack: 15, quantityUnits: 30), 7000);
      expect(BillingCalculator.linePaise(mrpPaisePerPack: 9950, unitsPerPack: 1, quantityUnits: 3), 29850);
    });
  });

  group('GST extraction (Rule 4/5)', () {
    test('extracts taxable value from a GST-inclusive amount', () {
      expect(BillingCalculator.taxableFromGross(11200, 12), 10000);
      expect(BillingCalculator.taxableFromGross(10500, 5), 10000);
      expect(BillingCalculator.taxableFromGross(5000, 0), 5000);
    });

    test('rounds once per slab, not per line', () {
      // Per line: 107/1.12 = 95.54 → 96 each = 192. Per slab: 214/1.12 = 191.07 → 191.
      final summary = BillingCalculator.summarise(const [
        BillLine(lineTotalPaise: 107, gstRate: 12),
        BillLine(lineTotalPaise: 107, gstRate: 12),
      ]);
      expect(summary.slabs.single.taxablePaise, 191);
      expect(summary.slabs.single.gstPaise, 23);
    });

    test('CGST and SGST always add up to the slab GST', () {
      final slab = BillingCalculator.summarise(const [BillLine(lineTotalPaise: 214, gstRate: 12)]).slabs.single;
      expect(slab.cgstPaise + slab.sgstPaise, slab.gstPaise);
      expect(slab.sgstPaise, 11);
      expect(slab.cgstPaise, 12);
    });

    test('separates slabs and rounds the bill to the nearest rupee', () {
      final summary = BillingCalculator.summarise(const [
        BillLine(lineTotalPaise: 11200, gstRate: 12),
        BillLine(lineTotalPaise: 10500, gstRate: 5),
        BillLine(lineTotalPaise: 33, gstRate: 12),
      ]);
      expect(summary.slabs.map((s) => s.rate), [5, 12]);
      expect(summary.grossPaise, 21733);
      expect(summary.payablePaise, 21700);
      expect(summary.roundOffPaise, -33);
      expect(summary.taxablePaise + summary.gstPaise, summary.grossPaise);
    });

    test('50 paise rounds up', () {
      final summary = BillingCalculator.summarise(const [BillLine(lineTotalPaise: 1050, gstRate: 0)]);
      expect(summary.payablePaise, 1100);
    });
  });

  group('rupee text', () {
    test('formats with Indian digit grouping', () {
      expect(formatRupees(12345678), '₹1,23,456.78');
      expect(formatRupees(5), '₹0.05');
      expect(formatRupees(-1250), '-₹12.50');
      expect(formatRupees(100000, symbol: false), '1,000.00');
    });

    test('parses user input to paise without floating point', () {
      expect(parseRupeesToPaise('1,234.5'), 123450);
      expect(parseRupeesToPaise('₹ 99'), 9900);
      expect(parseRupeesToPaise('0.1'), 10);
      expect(parseRupeesToPaise('12.345'), isNull);
      expect(parseRupeesToPaise('abc'), isNull);
      expect(parseRupeesToPaise(''), isNull);
    });
  });

  group('InvoiceNumber (Rule 6 format)', () {
    test('financial year runs April to March', () {
      expect(InvoiceNumber.financialYear(DateTime(2026, 3, 31)), '25-26');
      expect(InvoiceNumber.financialYear(DateTime(2026, 4, 1)), '26-27');
      expect(InvoiceNumber.financialYear(DateTime(2099, 12, 1)), '99-00');
    });

    test('serial is zero padded and fits the 16-character GST limit', () {
      final number = InvoiceNumber.format(DateTime(2026, 10, 11), 42);
      expect(number, 'INV/26-27/00042');
      expect(number.length, lessThanOrEqualTo(16));
    });
  });

  group('PackUnits (Rule 2)', () {
    test('reads units per pack from common labels', () {
      expect(PackUnits.fromLabel('Strip of 15'), 15);
      expect(PackUnits.fromLabel('10 Capsules Strip'), 10);
      expect(PackUnits.fromLabel('100ml Bottle'), 1);
      expect(PackUnits.fromLabel('Inhaler'), 1);
      expect(PackUnits.fromLabel('Tube 20g'), 1);
    });

    test('describes stock in packs plus loose units', () {
      expect(PackUnits.describe(32, 15), '2 × 15 + 2');
      expect(PackUnits.describe(30, 15), '2 × 15');
      expect(PackUnits.describe(5, 15), '5 loose');
      expect(PackUnits.describe(7, 1), '7');
      expect(PackUnits.split(32, 15), (2, 2));
    });
  });
}
