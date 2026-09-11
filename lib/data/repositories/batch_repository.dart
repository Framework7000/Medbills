import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/batch.dart';

/// Rule 1: batches live under `medicines/{id}/batches/{id}` as a
/// subcollection, never flattened onto the medicine document.
class BatchRepository {
  BatchRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _batchesOf(String medicineId) {
    return _firestore
        .collection('medicines')
        .doc(medicineId)
        .collection('batches');
  }

  Stream<List<Batch>> watchBatchesForMedicine(String medicineId) {
    return _batchesOf(medicineId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Batch.fromMap(d.data())).toList());
  }

  /// Batches eligible for FEFO allocation: not expired, not blocked, with
  /// remaining quantity.
  Future<List<Batch>> getActiveBatches(String medicineId) async {
    final snap = await _batchesOf(medicineId).get();
    final now = DateTime.now();
    return snap.docs
        .map((d) => Batch.fromMap(d.data()))
        .where((b) => !b.isBlocked && b.quantity > 0 && b.expiryDate.isAfter(now))
        .toList();
  }

  Future<void> saveBatch(Batch batch) {
    return _batchesOf(batch.medicineId).doc(batch.id).set(batch.toMap());
  }
}
