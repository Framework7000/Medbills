import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/services/fefo_selector.dart';

import '../support/fixtures.dart';

void main() {
  final now = DateTime(2026, 10, 11);

  group('FefoSelector', () {
    test('allocates from the nearest-expiry batch first and spills over', () {
      final batches = [
        batch('m', 'LATE', expiry: DateTime(2027, 12, 31), quantity: 10),
        batch('m', 'SOON', expiry: DateTime(2026, 12, 31), quantity: 5),
      ];
      final allocations = FefoSelector.selectBatches(batches: batches, requestedQty: 8, now: now);
      expect(allocations.map((a) => (a.batch.batchNumber, a.quantity)), [('SOON', 5), ('LATE', 3)]);
    });

    test('skips expired, blocked and reserved stock', () {
      final batches = [
        batch('m', 'EXPIRED', expiry: DateTime(2026, 9, 30), quantity: 10),
        batch('m', 'BLOCKED', expiry: DateTime(2026, 11, 30), quantity: 10, blocked: true),
        batch('m', 'GOOD', expiry: DateTime(2027, 1, 31), quantity: 8),
      ];
      final reserved = {batches[2].id: 3};
      final allocations =
          FefoSelector.selectBatches(batches: batches, requestedQty: 5, reserved: reserved, now: now);
      expect(allocations.single.batch.batchNumber, 'GOOD');
      expect(allocations.single.quantity, 5);
      expect(
        () => FefoSelector.selectBatches(batches: batches, requestedQty: 6, reserved: reserved, now: now),
        throwsA(isA<InsufficientStockException>().having((e) => e.available, 'available', 5)),
      );
    });

    test('rejects zero or negative requests', () {
      final batches = [batch('m', 'B', expiry: DateTime(2027, 1, 31), quantity: 8)];
      expect(() => FefoSelector.selectBatches(batches: batches, requestedQty: 0, now: now),
          throwsA(isA<InsufficientStockException>()));
    });
  });
}
