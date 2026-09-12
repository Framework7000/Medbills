import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/batch_repository.dart';
import '../data/repositories/customer_credit_repository.dart';
import '../data/repositories/global_catalogue_repository.dart';
import '../data/repositories/medicine_repository.dart';

class DatabaseStatus {
  final bool isConnected;
  final DateTime lastRefreshed;

  const DatabaseStatus({required this.isConnected, required this.lastRefreshed});

  DatabaseStatus copyWith({bool? isConnected, DateTime? lastRefreshed}) {
    return DatabaseStatus(
      isConnected: isConnected ?? this.isConnected,
      lastRefreshed: lastRefreshed ?? this.lastRefreshed,
    );
  }
}

class DatabaseStatusNotifier extends StateNotifier<DatabaseStatus> {
  DatabaseStatusNotifier({bool initiallyConnected = true})
      : super(DatabaseStatus(isConnected: initiallyConnected, lastRefreshed: DateTime.now()));

  void refresh() {
    state = state.copyWith(lastRefreshed: DateTime.now());
  }
}

final databaseStatusProvider =
    StateNotifierProvider<DatabaseStatusNotifier, DatabaseStatus>((ref) {
  return DatabaseStatusNotifier();
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final medicineRepositoryProvider = Provider<MedicineRepository>((ref) {
  return MedicineRepository(ref.watch(firestoreProvider));
});

final batchRepositoryProvider = Provider<BatchRepository>((ref) {
  return BatchRepository(ref.watch(firestoreProvider));
});

final customerCreditRepositoryProvider = Provider<CustomerCreditRepository>((ref) {
  return CustomerCreditRepository(ref.watch(firestoreProvider));
});

final globalCatalogueRepositoryProvider = Provider<GlobalCatalogueRepository>((ref) {
  return GlobalCatalogueRepository();
});
