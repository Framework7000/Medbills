import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/batch.dart';
import '../domain/services/fefo_selector.dart';

/// Local, offline-first batch ledger keyed by medicine id. Stands in for
/// the Firestore `medicines/{id}/batches` subcollection (Rule 1) until a
/// live Firebase project is wired up — the shape mirrors [BatchRepository]
/// exactly so swapping the data source later is a one-line change in
/// [database_provider.dart].
class InventoryBatchesNotifier extends StateNotifier<Map<String, List<Batch>>> {
  InventoryBatchesNotifier() : super(_seedBatches());

  static Map<String, List<Batch>> _seedBatches() {
    final now = DateTime.now();
    Batch seed(String medicineId, String batchNumber, int daysToExpiry, int mrpPaise, int qty) {
      return Batch(
        id: '${medicineId}_$batchNumber',
        medicineId: medicineId,
        batchNumber: batchNumber,
        expiryDate: now.add(Duration(days: daysToExpiry)),
        purchasePricePaise: (mrpPaise * 0.65).round(),
        mrpPaise: mrpPaise,
        quantity: qty,
        createdAt: now,
      );
    }

    return {
      'med_001': [seed('med_001', 'B0001', 540, 3500, 120)],
      'med_006': [seed('med_006', 'B0006', 380, 8500, 60)],
      'med_008': [seed('med_008', 'B0008', 460, 6200, 45)],
      'med_004': [seed('med_004', 'B0004', 300, 14500, 30)],
      'med_009': [seed('med_009', 'B0009', 620, 4200, 90)],
      'med_013': [seed('med_013', 'B0013', 700, 8800, 40)],
    };
  }

  /// Adds a newly purchased batch (or increments an existing one with the
  /// same batch number) for a medicine.
  void receiveBatch(Batch batch) {
    final existing = List<Batch>.from(state[batch.medicineId] ?? const []);
    final dupIndex = existing.indexWhere((b) => b.batchNumber == batch.batchNumber);
    if (dupIndex != -1) {
      existing[dupIndex] = existing[dupIndex].copyWith(
        quantity: existing[dupIndex].quantity + batch.quantity,
      );
    } else {
      existing.add(batch);
    }
    state = {...state, batch.medicineId: existing};
  }

  bool hasStock(String medicineId, int quantity) {
    return totalStockFor(medicineId) >= quantity;
  }

  int totalStockFor(String medicineId) {
    final batches = state[medicineId] ?? const [];
    return batches
        .where((b) => !b.isBlocked && !b.isExpired)
        .fold(0, (sum, b) => sum + b.quantity);
  }

  /// Decrements stock FEFO-style (Rule 3: allocate nearest-expiry batches
  /// first) after a sale. Throws [InsufficientStockException] if the
  /// medicine doesn't have enough eligible stock.
  void dispense(String medicineId, int quantity) {
    final batches = state[medicineId] ?? const [];
    final allocations = FefoSelector.selectBatches(batches: batches, requestedQty: quantity);

    final updated = List<Batch>.from(batches);
    for (final allocation in allocations) {
      final index = updated.indexWhere((b) => b.id == allocation.batch.id);
      if (index != -1) {
        updated[index] =
            updated[index].copyWith(quantity: updated[index].quantity - allocation.quantity);
      }
    }
    state = {...state, medicineId: updated};
  }
}

final inventoryBatchesProvider =
    StateNotifierProvider<InventoryBatchesNotifier, Map<String, List<Batch>>>((ref) {
  return InventoryBatchesNotifier();
});

final totalStockProvider = Provider.family<int, String>((ref, medicineId) {
  final batches = ref.watch(inventoryBatchesProvider)[medicineId] ?? const [];
  return batches
      .where((b) => !b.isBlocked && !b.isExpired)
      .fold(0, (sum, b) => sum + b.quantity);
});
