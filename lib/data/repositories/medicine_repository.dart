import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/medicine.dart';

/// Only layer allowed to touch Firestore for medicines. Always returns
/// domain models, never raw [DocumentSnapshot]s.
class MedicineRepository {
  MedicineRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('medicines');

  Stream<List<Medicine>> watchMedicines({required String storeId}) {
    return _collection
        .where('storeId', isEqualTo: storeId)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Medicine.fromMap(d.data())).toList());
  }

  Future<Medicine?> getMedicineById(String id) async {
    final doc = await _collection.doc(id).get();
    if (!doc.exists) return null;
    return Medicine.fromMap(doc.data()!);
  }

  Future<Medicine?> getMedicineByBarcode({
    required String storeId,
    required String barcode,
  }) async {
    final query = await _collection
        .where('storeId', isEqualTo: storeId)
        .where('barcode', isEqualTo: barcode)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return Medicine.fromMap(query.docs.first.data());
  }

  Future<void> saveMedicine(Medicine medicine) {
    return _collection.doc(medicine.id).set(medicine.toMap());
  }
}
