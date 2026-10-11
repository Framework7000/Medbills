import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/batch.dart';
import 'package:nuskha_pms/domain/services/stock_summary.dart';

import '../support/fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 11);
  final dolo = medicine('dolo');

  group('StockReceipt.validate', () {
    test('accepts a normal delivery and counts free packs as stock', () {
      final r = receipt(dolo, packs: 10, freePacks: 1, expiryYear: 2028);
      expect(r.validate(now: now), isEmpty);
      expect(r.totalUnits, 165);
      expect(r.freeUnits, 15);
      expect(r.expiryDate, DateTime(2028, 12, 31));
      expect(r.batchId, Batch.idFor('dolo', 'dl2401'));
    });

    test('rejects missing or impossible values', () {
      final problems = receipt(dolo, batchNumber: ' ', packs: 0, mrpPaise: 0, expiryMonth: 13, expiryYear: 2028)
          .validate(now: now);
      expect(problems.join(' '), allOf(contains('batch number'), contains('month'), contains('1 pack'), contains('MRP')));
    });

    test('rejects already-expired stock and a rate above MRP', () {
      expect(receipt(dolo, expiryYear: 2026, expiryMonth: 9).validate(now: now).join(), contains('expired'));
      expect(receipt(dolo, costPaise: 5000, mrpPaise: 3000, expiryYear: 2028).validate(now: now).join(),
          contains('higher than MRP'));
    });

    test('a top-up of an existing batch must match its MRP and expiry', () {
      final existing = batch('dolo', 'DL2401', expiry: DateTime(2028, 12, 31), mrpPaise: 3360);
      expect(receipt(dolo, expiryYear: 2028).validate(now: now, existing: existing), isEmpty);
      expect(receipt(dolo, expiryYear: 2028, mrpPaise: 3500).validate(now: now, existing: existing).join(),
          contains('different MRP'));
      expect(receipt(dolo, expiryYear: 2029).validate(now: now, existing: existing).join(),
          contains('different expiry'));
    });
  });

  group('StockSummary', () {
    test('counts only sellable units and flags low, expiring and expired stock', () {
      final m = medicine('dolo', minStock: 30);
      final batches = [
        batch('dolo', 'FAR', expiry: DateTime(2028, 1, 31), quantity: 20),
        batch('dolo', 'NEAR', expiry: DateTime(2026, 12, 31), quantity: 5),
        batch('dolo', 'GONE', expiry: DateTime(2026, 8, 31), quantity: 15),
        batch('dolo', 'HOLD', expiry: DateTime(2028, 1, 31), quantity: 50, blocked: true),
      ];
      final s = StockSummary.index([m], batches, now)['dolo']!;
      expect(s.sellableUnits, 25);
      expect(s.expiredUnits, 15);
      expect(s.nextBatch!.batchNumber, 'NEAR');
      expect(s.isLowStock, isTrue);
      expect(s.hasExpiringSoon, isTrue);
      expect(s.hasExpiredStock, isTrue);
      expect(s.isOutOfStock, isFalse);
    });

    test('a medicine with no batches is out of stock, not low', () {
      final s = StockSummary.index([medicine('x')], const [], now)['x']!;
      expect(s.isOutOfStock, isTrue);
      expect(s.isLowStock, isFalse);
    });

    test('expiry is month-precision: usable through the last day of the month', () {
      final b = batch('dolo', 'B', expiry: Batch.endOfMonth(2026, 10));
      expect(b.isExpiredAt(DateTime(2026, 10, 31, 23, 59)), isFalse);
      expect(b.isExpiredAt(DateTime(2026, 11, 1)), isTrue);
    });
  });
}
