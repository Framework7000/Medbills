import '../models/batch.dart';
import '../models/medicine.dart';

/// Everything the screens need to know about one medicine's stock.
class StockSummary {
  final Medicine medicine;
  final List<Batch> batches; // FEFO order: nearest expiry first
  final DateTime asOf;

  StockSummary({required this.medicine, required List<Batch> batches, required this.asOf})
      : batches = List.unmodifiable(batches.toList()
          ..sort((a, b) {
            final c = a.expiryDate.compareTo(b.expiryDate);
            return c != 0 ? c : a.batchNumber.compareTo(b.batchNumber);
          }));

  static const expiringSoonDays = 90;

  List<Batch> get sellableBatches => batches.where((b) => b.isSellableAt(asOf)).toList();

  int get sellableUnits => sellableBatches.fold(0, (sum, b) => sum + b.quantity);

  int get expiredUnits =>
      batches.where((b) => b.isExpiredAt(asOf) && b.quantity > 0).fold(0, (sum, b) => sum + b.quantity);

  /// The batch FEFO would sell next.
  Batch? get nextBatch {
    final sellable = sellableBatches;
    return sellable.isEmpty ? null : sellable.first;
  }

  bool get isOutOfStock => sellableUnits == 0;

  bool get isLowStock => !isOutOfStock && sellableUnits <= medicine.minStock;

  bool get hasExpiringSoon => sellableBatches.any((b) => b.daysToExpiry(asOf) <= expiringSoonDays);

  bool get hasExpiredStock => expiredUnits > 0;

  /// Builds a summary for every medicine, including those with no batches.
  static Map<String, StockSummary> index(List<Medicine> medicines, List<Batch> batches, DateTime now) {
    final byMedicine = <String, List<Batch>>{};
    for (final b in batches) {
      (byMedicine[b.medicineId] ??= []).add(b);
    }
    return {
      for (final m in medicines)
        m.id: StockSummary(medicine: m, batches: byMedicine[m.id] ?? const [], asOf: now),
    };
  }
}
