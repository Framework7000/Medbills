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
