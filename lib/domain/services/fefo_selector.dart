import '../models/batch.dart';

class InsufficientStockException implements Exception {
  final int requested;
  final int available;
  InsufficientStockException({required this.requested, required this.available});

  @override
  String toString() =>
      'InsufficientStockException: requested $requested, only $available available';
}

class BatchAllocation {
  final Batch batch;
  final int quantity;
  const BatchAllocation({required this.batch, required this.quantity});
}

/// First-Expiry-First-Out batch allocation for dispensing (Rule 3: all
/// stock decrements happen atomically inside a Firestore transaction that
/// reads batches before writing).
class FefoSelector {
  static List<BatchAllocation> selectBatches({
    required List<Batch> batches,
    required int requestedQty,
  }) {
    final eligible = batches
        .where((b) => !b.isExpired && !b.isBlocked && b.quantity > 0)
        .toList()
      ..sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

    final totalAvailable = eligible.fold<int>(0, (sum, b) => sum + b.quantity);
    if (totalAvailable < requestedQty) {
      throw InsufficientStockException(
        requested: requestedQty,
        available: totalAvailable,
      );
    }

    final allocations = <BatchAllocation>[];
    var remaining = requestedQty;
    for (final batch in eligible) {
      if (remaining <= 0) break;
      final take = remaining < batch.quantity ? remaining : batch.quantity;
      allocations.add(BatchAllocation(batch: batch, quantity: take));
      remaining -= take;
    }
    return allocations;
  }
}
