import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/batch.dart';
import '../domain/models/medicine.dart';
import 'database_provider.dart';

const defaultStoreId = 'store_primary';

final medicinesStreamProvider = StreamProvider<List<Medicine>>((ref) {
  final repo = ref.watch(medicineRepositoryProvider);
  return repo.watchMedicines(storeId: defaultStoreId);
});

final batchesForMedicineProvider =
    StreamProvider.family<List<Batch>, String>((ref, medicineId) {
  final repo = ref.watch(batchRepositoryProvider);
  return repo.watchBatchesForMedicine(medicineId);
});

/// Total eligible (non-expired, non-blocked) stock for a medicine, derived
/// from the live Firestore batch stream — the Cloud-mode counterpart to
/// InventoryBatchesNotifier.totalStockFor() in inventory_batches_provider.dart.
final firestoreStockForMedicineProvider = Provider.family<AsyncValue<int>, String>((ref, medicineId) {
  final batches = ref.watch(batchesForMedicineProvider(medicineId));
  return batches.whenData((list) =>
      list.where((b) => !b.isBlocked && !b.isExpired).fold(0, (sum, b) => sum + b.quantity));
});
