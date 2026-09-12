import 'package:flutter_riverpod/flutter_riverpod.dart';

class PurchaseRecord {
  final String medicineId;
  final String medicineName;
  final String batchNumber;
  final DateTime expiryDate;
  final int purchasePricePaise;
  final int mrpPaise;
  final int quantity;
  final DateTime receivedAt;

  const PurchaseRecord({
    required this.medicineId,
    required this.medicineName,
    required this.batchNumber,
    required this.expiryDate,
    required this.purchasePricePaise,
    required this.mrpPaise,
    required this.quantity,
    required this.receivedAt,
  });

  int get totalCostPaise => purchasePricePaise * quantity;
}

class PurchaseHistoryNotifier extends StateNotifier<List<PurchaseRecord>> {
  PurchaseHistoryNotifier() : super(const []);

  void addPurchase(PurchaseRecord record) {
    state = [record, ...state];
  }
}

final purchaseHistoryProvider =
    StateNotifierProvider<PurchaseHistoryNotifier, List<PurchaseRecord>>((ref) {
  return PurchaseHistoryNotifier();
});
