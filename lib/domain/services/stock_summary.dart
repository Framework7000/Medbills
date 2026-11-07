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

/// What the stock on the shelves is worth, in paise.
class InventoryValue {
  final int costPaise; // at purchase rate — the money tied up in stock
  final int mrpPaise; // at MRP — what it sells for
  final int expiredCostPaise; // expired stock, at purchase rate (not counted above)
  final int batches; // batches with stock

  const InventoryValue({
    required this.costPaise,
    required this.mrpPaise,
    required this.expiredCostPaise,
    required this.batches,
  });

  int get marginPaise => mrpPaise - costPaise;

  static int _value(int perPackPaise, int units, int unitsPerPack) {
    final perPack = unitsPerPack < 1 ? 1 : unitsPerPack;
    return (perPackPaise * units * 2 + perPack) ~/ (perPack * 2);
  }

  /// Every batch with stock, at its own rate and MRP. Expired stock is kept
  /// apart because it can't be sold; blocked stock still counts (it is
  /// held, not gone).
  static InventoryValue of(Iterable<StockSummary> stock) {
    var cost = 0, mrp = 0, expired = 0, count = 0;
    for (final s in stock) {
      for (final b in s.batches) {
        if (b.quantity <= 0) continue;
        count++;
        final c = _value(b.purchasePricePaise, b.quantity, s.medicine.unitsPerPack);
        if (b.isExpiredAt(s.asOf)) {
          expired += c;
        } else {
          cost += c;
          mrp += _value(b.mrpPaise, b.quantity, s.medicine.unitsPerPack);
        }
      }
    }
    return InventoryValue(costPaise: cost, mrpPaise: mrp, expiredCostPaise: expired, batches: count);
  }
}
