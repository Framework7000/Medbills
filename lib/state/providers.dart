import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_service.dart';
import '../data/firestore_pharmacy_repository.dart';
import '../data/local_pharmacy_repository.dart';
import '../data/pharmacy_repository.dart';
import '../data/repositories/global_catalogue_repository.dart';
import '../data/repositories/india_catalogue.dart';
import '../domain/models/app_user.dart';
import '../domain/models/batch.dart';
import '../domain/models/bill_scan.dart';
import '../domain/models/customer_credit.dart';
import '../domain/models/medicine.dart';
import '../domain/models/purchase_record.dart';
import '../domain/models/sale_invoice.dart';
import '../domain/models/scan_link.dart';
import '../domain/models/store_profile.dart';
import '../domain/services/stock_summary.dart';
import 'cart.dart';

/// True when Firebase initialised and the app runs against the shared cloud
/// database; false for the demo build (web preview). Overridden in main().
final cloudModeProvider = Provider<bool>((ref) => false);

final authServiceProvider = Provider<AuthService>((ref) {
  if (ref.watch(cloudModeProvider)) {
    return FirebaseAuthService(FirebaseAuth.instance, FirebaseFirestore.instance);
  }
  return DemoAuthService();
});

final sessionProvider = StreamProvider<SessionState>((ref) {
  return ref.watch(authServiceProvider).watchSession();
});

final currentUserProvider = Provider<AppUser?>((ref) {
  final session = ref.watch(sessionProvider).valueOrNull;
  return session is SignedIn ? session.user : null;
});

/// The backend for the signed-in user's store; null while signed out.
final repositoryProvider = Provider<PharmacyRepository?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  final actor = Actor.of(user);
  final PharmacyRepository repo;
  if (ref.watch(cloudModeProvider)) {
    repo = FirestorePharmacyRepository(FirebaseFirestore.instance, storeId: user.storeId, actor: actor);
  } else {
    // Keep one demo store across role switches so the demo data persists.
    final demo = ref.watch(_demoRepositoryProvider);
    demo.actor = actor;
    return demo;
  }
  ref.onDispose(repo.dispose);
  return repo;
});

final _demoRepositoryProvider = Provider<LocalPharmacyRepository>((ref) {
  final repo = LocalPharmacyRepository(
    storeId: DemoAuthService.storeId,
    actor: const Actor(uid: 'demo-owner', name: 'Demo Owner', role: UserRole.owner),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

PharmacyRepository _repo(Ref ref) {
  final repo = ref.watch(repositoryProvider);
  if (repo == null) throw StateError('Not signed in');
  return repo;
}

final storeProvider = StreamProvider<StoreProfile>((ref) => _repo(ref).watchStore());

final medicinesProvider = StreamProvider<List<Medicine>>((ref) => _repo(ref).watchMedicines());

final batchesProvider = StreamProvider<List<Batch>>((ref) => _repo(ref).watchBatches());

final recentSalesProvider = StreamProvider<List<SaleInvoice>>((ref) => _repo(ref).watchRecentSales());

final purchasesProvider = StreamProvider<List<PurchaseRecord>>((ref) => _repo(ref).watchRecentPurchases());

final customersProvider = StreamProvider<List<CustomerCredit>>((ref) => _repo(ref).watchCustomers());

final ledgerProvider = StreamProvider.family<List<CreditLedgerEntry>, String>(
  (ref, customerId) => _repo(ref).watchLedger(customerId),
);

final billScansProvider = StreamProvider<List<BillScan>>((ref) => _repo(ref).watchBillScans());

/// Billing counters currently accepting scans from phones.
final stationsProvider = StreamProvider<List<ScanStation>>((ref) => _repo(ref).watchStations());

/// Every scan this device/user has sent — powers the "not delivered" list.
final sentScansProvider = StreamProvider<List<ScanEvent>>((ref) {
  final repo = _repo(ref);
  return repo.watchSentScans(repo.actor.uid);
});

/// Ticks once a minute so expiry status stays current on a counter that
/// is left open all day.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream<DateTime>.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

/// Stock per medicine id, rebuilt whenever medicines or batches change.
final stockIndexProvider = Provider<AsyncValue<Map<String, StockSummary>>>((ref) {
  final medicines = ref.watch(medicinesProvider);
  final batches = ref.watch(batchesProvider);
  final now = ref.watch(clockProvider).valueOrNull ?? DateTime.now();
  if (medicines.hasError) return AsyncValue.error(medicines.error!, medicines.stackTrace!);
  if (batches.hasError) return AsyncValue.error(batches.error!, batches.stackTrace!);
  if (!medicines.hasValue || !batches.hasValue) return const AsyncValue.loading();
  return AsyncValue.data(StockSummary.index(medicines.value!, batches.value!, now));
});

final catalogueProvider = Provider<GlobalCatalogueRepository>((ref) => GlobalCatalogueRepository());

/// Every medicine in India (≈2.46 lakh, bundled with the app), loaded in the
/// background the first time something needs it. Null if it couldn't load —
/// the store's own medicines and the checked catalogue still work.
final indiaCatalogueProvider = FutureProvider<IndiaCatalogue?>((ref) async {
  try {
    final gz = await rootBundle.load('assets/catalogue/india.tsv.gz');
    final aliases = await rootBundle.loadString('assets/catalogue/aliases.tsv');
    return await compute(IndiaCatalogue.fromAssets, (gz.buffer.asUint8List(gz.offsetInBytes, gz.lengthInBytes), aliases));
  } catch (_) {
    return null;
  }
});

/// This device's bill in progress. Not shared: each counter has its own.
/// Cleared when the signed-in user changes.
final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  ref.watch(currentUserProvider.select((u) => u?.uid));
  return CartNotifier();
});
