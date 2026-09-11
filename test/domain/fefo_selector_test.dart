import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/batch.dart';
import 'package:nuskha_pms/domain/services/fefo_selector.dart';

Batch _batch(String id, DateTime expiry, int qty, {bool blocked = false}) {
  return Batch(
    id: id,
    medicineId: 'med_001',
    batchNumber: id,
    expiryDate: expiry,
    purchasePricePaise: 1000,
    mrpPaise: 1500,
    quantity: qty,
    isBlocked: blocked,
    createdAt: DateTime.now(),
  );
}

void main() {
  group('FefoSelector', () {
    test('allocates from nearest-expiry batch first', () {
      final batches = [
        _batch('B1', DateTime.now().add(const Duration(days: 300)), 10),
        _batch('B2', DateTime.now().add(const Duration(days: 30)), 5),
      ];
      final allocations = FefoSelector.selectBatches(batches: batches, requestedQty: 5);
      expect(allocations.length, 1);
      expect(allocations.first.batch.id, 'B2');
    });

    test('skips expired and blocked batches', () {
      final batches = [
        _batch('EXPIRED', DateTime.now().subtract(const Duration(days: 5)), 10),
        _batch('BLOCKED', DateTime.now().add(const Duration(days: 30)), 10, blocked: true),
        _batch('GOOD', DateTime.now().add(const Duration(days: 60)), 8),
      ];
      final allocations = FefoSelector.selectBatches(batches: batches, requestedQty: 5);
      expect(allocations.length, 1);
      expect(allocations.first.batch.id, 'GOOD');
    });

    test('throws InsufficientStockException when not enough stock', () {
      final batches = [_batch('B1', DateTime.now().add(const Duration(days: 30)), 3)];
      expect(
        () => FefoSelector.selectBatches(batches: batches, requestedQty: 10),
        throwsA(isA<InsufficientStockException>()),
      );
    });
  });
}
