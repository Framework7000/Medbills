import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/medicine.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';
import 'package:nuskha_pms/data/repositories/medicine_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late MedicineRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = MedicineRepository(firestore);
  });

  Medicine sample({String id = 'med_001', String? barcode}) {
    return Medicine(
      id: id,
      storeId: 'store_primary',
      name: 'Paracetamol 500mg',
      genericName: 'Paracetamol',
      manufacturer: 'GSK',
      type: 'Analgesics',
      packSizeLabel: '10 Tablets Strip',
      hsnCode: '3004',
      gstRate: 5.0,
      scheduleType: ScheduleType.otc,
      barcode: barcode,
      minStock: 20,
      shelfLocation: 'A1',
      updatedAt: DateTime.now(),
    );
  }

  test('saveMedicine then getMedicineById round-trips the model', () async {
    await repository.saveMedicine(sample());
    final fetched = await repository.getMedicineById('med_001');
    expect(fetched, isNotNull);
    expect(fetched!.name, 'Paracetamol 500mg');
    expect(fetched.scheduleType, ScheduleType.otc);
  });

  test('getMedicineByBarcode finds by storeId + barcode', () async {
    await repository.saveMedicine(sample(barcode: '8901234567890'));
    final fetched = await repository.getMedicineByBarcode(
      storeId: 'store_primary',
      barcode: '8901234567890',
    );
    expect(fetched, isNotNull);
    expect(fetched!.id, 'med_001');
  });

  test('watchMedicines streams documents scoped to storeId', () async {
    await repository.saveMedicine(sample());
    final list = await repository.watchMedicines(storeId: 'store_primary').first;
    expect(list.length, 1);
  });
}
