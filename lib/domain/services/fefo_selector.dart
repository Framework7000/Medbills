import '../models/batch.dart';

class InsufficientStockException implements Exception {
  final int requested;
  final int available;
  InsufficientStockException({required this.requested, required this.available});

  @override
  String toString() => 'Only $available available, $requested requested';
}

class BatchAllocation {
  final Batch batch;
  final int quantity;
  const BatchAllocation({required this.batch, required this.quantity});
}

/// First-Expiry-First-Out batch allocation for dispensing.
class FefoSelector {
  /// Allocates [requestedQty] base units from the nearest-expiry sellable
  /// batches. [reserved] holds units of each batch already committed
  /// elsewhere (e.g. other lines of the same cart) and treated as
  /// unavailable.
  static List<BatchAllocation> selectBatches({
    required List<Batch> batches,
    required int requestedQty,
    Map<String, int> reserved = const {},
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final eligible = batches
        .where((b) => !b.isBlocked && !b.isExpiredAt(at))
        .map((b) => (batch: b, free: b.quantity - (reserved[b.id] ?? 0)))
        .where((e) => e.free > 0)
        .toList()
      ..sort((a, b) {
        final byExpiry = a.batch.expiryDate.compareTo(b.batch.expiryDate);
        return byExpiry != 0 ? byExpiry : a.batch.batchNumber.compareTo(b.batch.batchNumber);
      });

    final totalAvailable = eligible.fold<int>(0, (sum, e) => sum + e.free);
    if (requestedQty <= 0 || totalAvailable < requestedQty) {
      throw InsufficientStockException(requested: requestedQty, available: totalAvailable);
    }

    final allocations = <BatchAllocation>[];
    var remaining = requestedQty;
    for (final entry in eligible) {
      if (remaining <= 0) break;
      final take = remaining < entry.free ? remaining : entry.free;
      allocations.add(BatchAllocation(batch: entry.batch, quantity: take));
      remaining -= take;
    }
    return allocations;
  }

  static int sellableUnits(Iterable<Batch> batches, DateTime now) =>
      batches.where((b) => b.isSellableAt(now)).fold(0, (sum, b) => sum + b.quantity);
}
