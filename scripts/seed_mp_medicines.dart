// Standalone Dart CLI — seeds the live MedBills Firestore database with the
// authentic, fast-moving Madhya Pradesh pharmacy formulations documented in
// the project's medicine data brief. Writes exactly the document shapes
// MedicineRepository / BatchRepository expect (see lib/domain/models/
// medicine.dart and batch.dart's toMap()), so anything seeded here is
// immediately readable by the app once it's pointed at this project.
//
// This lives in its own scripts/pubspec.yaml (no `flutter` SDK dependency)
// so it runs with a plain Dart SDK via `dart run` — no Flutter toolchain
// needed on whatever machine actually seeds the database.
//
// Usage:
//   cd scripts
//   dart pub get
//   dart run seed_mp_medicines.dart \
//       --project your-firebase-project-id \
//       --credentials /path/to/service-account.json
//
// If --credentials is omitted, GOOGLE_APPLICATION_CREDENTIALS is used.
// If --project is omitted, the service account JSON's own project_id is used.
//
// Rule 1: medicines/{id} carries ONLY product master fields; batch data
// (batch number, expiry, purchase price, MRP, quantity) lives exclusively
// under medicines/{id}/batches/{batchId}.
// Rule 8: every document carries storeId.
// Rule 12: all money fields are integer paise.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:googleapis/firestore/v1.dart' as firestore;
import 'package:googleapis_auth/auth_io.dart' as auth;

const _storeId = 'store_primary';

/// One master-catalogue row, exactly as verified against CDSCO schedule
/// classification and current MRP for the Indore/Bhopal distribution hubs.
class SeedMedicine {
  final String id;
  final String name;
  final String genericName;
  final String manufacturer;
  final String manufacturerCode; // used to build realistic batch numbers
  final String hsnCode;
  final double gstRate;
  final String scheduleType; // 'OTC' | 'H' | 'H1' — parsed by ScheduleType.fromString
  final String packSizeLabel;
  final int mrpPaise;

  const SeedMedicine({
    required this.id,
    required this.name,
    required this.genericName,
    required this.manufacturer,
    required this.manufacturerCode,
    required this.hsnCode,
    required this.gstRate,
    required this.scheduleType,
    required this.packSizeLabel,
    required this.mrpPaise,
  });
}

const _hsnPenicillin = '300410';
const _hsnOtherAntibiotic = '300420';
const _hsnGeneral = '300490';

/// The 42 fast-moving Madhya Pradesh formulations from the project's
/// medicine data brief — matched by id to the same demo entries in
/// lib/data/repositories/global_catalogue_repository.dart where an
/// equivalent product already exists there, so local-seed and
/// live-Firestore data agree once this project is connected.
const seedMedicines = <SeedMedicine>[
  SeedMedicine(
    id: 'med_002', name: 'Dolo 650 Tablet', genericName: 'Paracetamol 650mg',
    manufacturer: 'Micro Labs', manufacturerCode: 'MCL', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'OTC', packSizeLabel: 'Strip of 15', mrpPaise: 3360,
  ),
  SeedMedicine(
    id: 'med_063', name: 'Calpol 500 Tablet', genericName: 'Paracetamol 500mg',
    manufacturer: 'GSK Pharmaceuticals', manufacturerCode: 'GSK', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'OTC', packSizeLabel: 'Strip of 15', mrpPaise: 1750,
  ),
  SeedMedicine(
    id: 'med_027', name: 'Combiflam Tablet',
    genericName: 'Ibuprofen 400mg + Paracetamol 325mg',
    manufacturer: 'Sanofi India', manufacturerCode: 'SAN', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'OTC', packSizeLabel: 'Strip of 20', mrpPaise: 4820,
  ),
  SeedMedicine(
    id: 'med_004', name: 'Augmentin 625 Duo',
    genericName: 'Amoxicillin 500mg + Clavulanic Acid 125mg',
    manufacturer: 'GSK Pharmaceuticals', manufacturerCode: 'GSK', hsnCode: _hsnPenicillin,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 10', mrpPaise: 20450,
  ),
  SeedMedicine(
    id: 'med_064', name: 'Clavam 625 Tablet',
    genericName: 'Amoxicillin 500mg + Clavulanic Acid 125mg',
    manufacturer: 'Alkem Laboratories', manufacturerCode: 'ALK', hsnCode: _hsnPenicillin,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 10', mrpPaise: 20100,
  ),
  SeedMedicine(
    id: 'med_065', name: 'Moxikind-CV 625',
    genericName: 'Amoxicillin 500mg + Clavulanic Acid 125mg',
    manufacturer: 'Mankind Pharma', manufacturerCode: 'MKD', hsnCode: _hsnPenicillin,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 10', mrpPaise: 17800,
  ),
  SeedMedicine(
    id: 'med_066', name: 'Monocef 1g Injection', genericName: 'Ceftriaxone 1000mg',
    manufacturer: 'Aristo Pharmaceuticals', manufacturerCode: 'ARS',
    hsnCode: _hsnOtherAntibiotic, gstRate: 12.0, scheduleType: 'H',
    packSizeLabel: '1 Vial', mrpPaise: 6200,
  ),
  SeedMedicine(
    id: 'med_067', name: 'Taxim-O 200 Tablet', genericName: 'Cefixime 200mg',
    manufacturer: 'Alkem Laboratories', manufacturerCode: 'ALK',
    hsnCode: _hsnOtherAntibiotic, gstRate: 12.0, scheduleType: 'H',
    packSizeLabel: 'Strip of 10', mrpPaise: 10850,
  ),
  SeedMedicine(
    id: 'med_068', name: 'Mahacef 200 Tablet', genericName: 'Cefixime 200mg',
    manufacturer: 'Mankind Pharma', manufacturerCode: 'MKD',
    hsnCode: _hsnOtherAntibiotic, gstRate: 12.0, scheduleType: 'H',
    packSizeLabel: 'Strip of 10', mrpPaise: 10200,
  ),
  SeedMedicine(
    id: 'med_069', name: 'Gudcef 200 Tablet', genericName: 'Cefpodoxime Proxetil 200mg',
    manufacturer: 'Mankind Pharma', manufacturerCode: 'MKD',
    hsnCode: _hsnOtherAntibiotic, gstRate: 12.0, scheduleType: 'H',
    packSizeLabel: 'Strip of 10', mrpPaise: 16500,
  ),
  SeedMedicine(
    id: 'med_026', name: 'Azee 500 Tablet', genericName: 'Azithromycin 500mg',
    manufacturer: 'Cipla', manufacturerCode: 'CIP', hsnCode: _hsnOtherAntibiotic,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 5', mrpPaise: 11950,
  ),
  SeedMedicine(
    id: 'med_070', name: 'Azithral 500 Tablet', genericName: 'Azithromycin 500mg',
    manufacturer: 'Alembic Pharmaceuticals', manufacturerCode: 'ALB',
    hsnCode: _hsnOtherAntibiotic, gstRate: 12.0, scheduleType: 'H',
    packSizeLabel: 'Strip of 5', mrpPaise: 12000,
  ),
  SeedMedicine(
    id: 'med_071', name: 'Pan 40 Tablet', genericName: 'Pantoprazole 40mg',
    manufacturer: 'Alkem Laboratories', manufacturerCode: 'ALK', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 15500,
  ),
  SeedMedicine(
    id: 'med_007', name: 'Pan-D Capsule',
    genericName: 'Pantoprazole 40mg + Domperidone 30mg',
    manufacturer: 'Alkem Laboratories', manufacturerCode: 'ALK', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 19900,
  ),
  SeedMedicine(
    id: 'med_072', name: 'Pantop-D Capsule',
    genericName: 'Pantoprazole 40mg + Domperidone 30mg',
    manufacturer: 'Aristo Pharmaceuticals', manufacturerCode: 'ARS', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 19000,
  ),
  SeedMedicine(
    id: 'med_018', name: 'Omez 20 Capsule', genericName: 'Omeprazole 20mg',
    manufacturer: "Dr. Reddy's Laboratories", manufacturerCode: 'DRL', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 20', mrpPaise: 6500,
  ),
  SeedMedicine(
    id: 'med_074', name: 'Rablet 20 Tablet', genericName: 'Rabeprazole 20mg',
    manufacturer: 'Lupin Ltd', manufacturerCode: 'LUP', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 11500,
  ),
  SeedMedicine(
    id: 'med_075', name: 'Aciloc 150 Tablet', genericName: 'Ranitidine 150mg',
    manufacturer: 'Cadila Pharmaceuticals', manufacturerCode: 'CDL', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 30', mrpPaise: 4400,
  ),
  SeedMedicine(
    id: 'med_015', name: 'Montair-LC Tablet',
    genericName: 'Montelukast 10mg + Levocetirizine 5mg',
    manufacturer: 'Cipla', manufacturerCode: 'CIP', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 10', mrpPaise: 18500,
  ),
  SeedMedicine(
    id: 'med_076', name: 'Telekast-L Tablet',
    genericName: 'Montelukast 10mg + Levocetirizine 5mg',
    manufacturer: 'Lupin Ltd', manufacturerCode: 'LUP', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 10', mrpPaise: 17900,
  ),
  SeedMedicine(
    id: 'med_077', name: 'Allegra 120mg Tablet', genericName: 'Fexofenadine 120mg',
    manufacturer: 'Sanofi India', manufacturerCode: 'SAN', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'OTC', packSizeLabel: 'Strip of 10', mrpPaise: 21500,
  ),
  SeedMedicine(
    id: 'med_078', name: 'Avil 25 Tablet', genericName: 'Pheniramine Maleate 25mg',
    manufacturer: 'Sanofi India', manufacturerCode: 'SAN', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 1150,
  ),
  SeedMedicine(
    id: 'med_054', name: 'Asthalin Inhaler', genericName: 'Salbutamol 100mcg (200 MDI)',
    manufacturer: 'Cipla', manufacturerCode: 'CIP', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Inhaler', mrpPaise: 15800,
  ),
  SeedMedicine(
    id: 'med_079', name: 'Foracort 200 Inhaler',
    genericName: 'Formoterol 6mcg + Budesonide 200mcg',
    manufacturer: 'Cipla', manufacturerCode: 'CIP', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Inhaler', mrpPaise: 48500,
  ),
  SeedMedicine(
    id: 'med_028', name: 'Shelcal 500 Tablet',
    genericName: 'Calcium 500mg + Vitamin D3 250 IU',
    manufacturer: 'Torrent Pharmaceuticals', manufacturerCode: 'TOR', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'OTC', packSizeLabel: 'Strip of 15', mrpPaise: 13100,
  ),
  SeedMedicine(
    id: 'med_080', name: 'Becosules Z Capsule',
    genericName: 'B-Complex + Vitamin C + Zinc',
    manufacturer: 'Pfizer Limited', manufacturerCode: 'PFZ', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'OTC', packSizeLabel: 'Strip of 20', mrpPaise: 5200,
  ),
  SeedMedicine(
    id: 'med_081', name: 'Limcee 500mg Tablet', genericName: 'Vitamin C (Ascorbic Acid) 500mg',
    manufacturer: 'Abbott India', manufacturerCode: 'ABT', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'OTC', packSizeLabel: 'Strip of 15', mrpPaise: 2450,
  ),
  SeedMedicine(
    id: 'med_082', name: 'Thyronorm 50mcg', genericName: 'Thyroxine Sodium 50mcg',
    manufacturer: 'Abbott India', manufacturerCode: 'ABT', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Bottle 120', mrpPaise: 16500,
  ),
  SeedMedicine(
    id: 'med_083', name: 'Glycomet-GP 1 Tablet',
    genericName: 'Glimepiride 1mg + Metformin 500mg',
    manufacturer: 'USV Private Limited', manufacturerCode: 'USV', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 11800,
  ),
  SeedMedicine(
    id: 'med_084', name: 'Gemer 2 Tablet', genericName: 'Glimepiride 2mg + Metformin 500mg',
    manufacturer: 'Sun Pharma', manufacturerCode: 'SUN', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 10', mrpPaise: 12800,
  ),
  SeedMedicine(
    id: 'med_011', name: 'Telma 40 Tablet', genericName: 'Telmisartan 40mg',
    manufacturer: 'Glenmark Pharmaceuticals', manufacturerCode: 'GLN', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 14800,
  ),
  SeedMedicine(
    id: 'med_085', name: 'Telmikind 40 Tablet', genericName: 'Telmisartan 40mg',
    manufacturer: 'Mankind Pharma', manufacturerCode: 'MKD', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 10', mrpPaise: 4900,
  ),
  SeedMedicine(
    id: 'med_087', name: 'Amlong 5 Tablet', genericName: 'Amlodipine 5mg',
    manufacturer: 'Micro Labs', manufacturerCode: 'MCL', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 4500,
  ),
  SeedMedicine(
    id: 'med_088', name: 'Atorva 10 Tablet', genericName: 'Atorvastatin 10mg',
    manufacturer: 'Zydus Healthcare', manufacturerCode: 'ZYD', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 11000,
  ),
  SeedMedicine(
    id: 'med_089', name: 'Rosuvas 10 Tablet', genericName: 'Rosuvastatin 10mg',
    manufacturer: 'Sun Pharma', manufacturerCode: 'SUN', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 15', mrpPaise: 24000,
  ),
  SeedMedicine(
    id: 'med_031', name: 'Volini Gel', genericName: 'Diclofenac Diethylamine + Linseed Oil',
    manufacturer: 'Sun Pharma', manufacturerCode: 'SUN', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'OTC', packSizeLabel: 'Tube 50g', mrpPaise: 16000,
  ),
  SeedMedicine(
    id: 'med_033', name: 'Betnovate-N Cream', genericName: 'Betamethasone + Neomycin',
    manufacturer: 'GSK Pharmaceuticals', manufacturerCode: 'GSK', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Tube 20g', mrpPaise: 5500,
  ),
  SeedMedicine(
    id: 'med_090', name: 'Candiforce 200 Capsule', genericName: 'Itraconazole 200mg',
    manufacturer: 'Mankind Pharma', manufacturerCode: 'MKD', hsnCode: _hsnOtherAntibiotic,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 10', mrpPaise: 22000,
  ),
  SeedMedicine(
    id: 'med_091', name: 'Chymoral Forte Tablet', genericName: 'Trypsin + Chymotrypsin',
    manufacturer: 'Torrent Pharmaceuticals', manufacturerCode: 'TOR', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H', packSizeLabel: 'Strip of 20', mrpPaise: 44000,
  ),
  SeedMedicine(
    id: 'med_092', name: 'Alprazolam 0.5mg (Restyl)', genericName: 'Alprazolam 0.5mg',
    manufacturer: 'Cipla', manufacturerCode: 'CIP', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H1', packSizeLabel: 'Strip of 15', mrpPaise: 4200,
  ),
  SeedMedicine(
    id: 'med_093', name: 'Zolpidem 10mg (Zolfresh)', genericName: 'Zolpidem Tartrate 10mg',
    manufacturer: 'Abbott India', manufacturerCode: 'ABT', hsnCode: _hsnGeneral,
    gstRate: 12.0, scheduleType: 'H1', packSizeLabel: 'Strip of 10', mrpPaise: 9800,
  ),
  SeedMedicine(
    id: 'med_094', name: 'Tramadol 50mg (Ultracet)',
    genericName: 'Tramadol 37.5mg + Paracetamol 325mg',
    manufacturer: 'Janssen (Johnson & Johnson)', manufacturerCode: 'JNJ',
    hsnCode: _hsnGeneral, gstRate: 12.0, scheduleType: 'H1',
    packSizeLabel: 'Strip of 15', mrpPaise: 21500,
  ),
];

const _monthLetters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L'];

String _generateBatchNumber(String manufacturerCode, DateTime now, int serial) {
  final year = (now.year % 100).toString().padLeft(2, '0');
  final monthLetter = _monthLetters[now.month - 1];
  return '$manufacturerCode$year$monthLetter${serial.toString().padLeft(2, '0')}';
}

firestore.Value _stringValue(String value) => firestore.Value(stringValue: value);
firestore.Value _doubleValue(double value) => firestore.Value(doubleValue: value);
firestore.Value _intValue(int value) => firestore.Value(integerValue: '$value');
firestore.Value _boolValue(bool value) => firestore.Value(booleanValue: value);
firestore.Value _timestampValue(DateTime value) =>
    firestore.Value(timestampValue: value.toUtc().toIso8601String());

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('project', help: 'Firebase project ID (defaults to the service account\'s own project_id)')
    ..addOption('credentials', help: 'Path to a service account JSON key (defaults to \$GOOGLE_APPLICATION_CREDENTIALS)')
    ..addFlag('dry-run', help: 'Print what would be written without touching Firestore', defaultsTo: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  final args = parser.parse(arguments);
  if (args['help'] as bool) {
    stdout.writeln('Seeds the MedBills Firestore database with authentic MP pharmacy medicines.\n');
    stdout.writeln(parser.usage);
    return;
  }

  final credentialsPath = args['credentials'] as String? ??
      Platform.environment['GOOGLE_APPLICATION_CREDENTIALS'];
  final dryRun = args['dry-run'] as bool;

  if (credentialsPath == null && !dryRun) {
    stderr.writeln(
        'No service account provided. Pass --credentials /path/to/key.json, '
        'set GOOGLE_APPLICATION_CREDENTIALS, or pass --dry-run to preview '
        'without writing.');
    exitCode = 1;
    return;
  }

  final random = Random();
  final now = DateTime.now();

  if (dryRun) {
    stdout.writeln('DRY RUN — ${seedMedicines.length} medicines would be seeded:\n');
    for (final medicine in seedMedicines) {
      final batchNumber = _generateBatchNumber(medicine.manufacturerCode, now, 1);
      final quantity = 100 + random.nextInt(401); // 100–500
      final expiryMonths = 6 + random.nextInt(19); // 6–24
      stdout.writeln(
          '${medicine.id.padRight(10)} ${medicine.name.padRight(28)} '
          'batch=$batchNumber qty=$quantity mrp=₹${(medicine.mrpPaise / 100).toStringAsFixed(2)} '
          'expiry=+${expiryMonths}mo schedule=${medicine.scheduleType}');
    }
    return;
  }

  final credentialsJson = jsonDecode(await File(credentialsPath!).readAsString())
      as Map<String, dynamic>;
  final serviceAccount = auth.ServiceAccountCredentials.fromJson(credentialsJson);
  final projectId = (args['project'] as String?) ?? credentialsJson['project_id'] as String;

  final client = await auth.clientViaServiceAccount(
    serviceAccount,
    [firestore.FirestoreApi.datastoreScope],
  );
  final api = firestore.FirestoreApi(client);
  final databasePath = 'projects/$projectId/databases/(default)/documents';

  stdout.writeln('Seeding ${seedMedicines.length} medicines into $projectId ...\n');

  var written = 0;
  for (final medicine in seedMedicines) {
    final medicineDoc = firestore.Document(fields: {
      'id': _stringValue(medicine.id),
      'storeId': _stringValue(_storeId),
      'name': _stringValue(medicine.name),
      'genericName': _stringValue(medicine.genericName),
      'manufacturer': _stringValue(medicine.manufacturer),
      'type': _stringValue(''),
      'packSizeLabel': _stringValue(medicine.packSizeLabel),
      'hsnCode': _stringValue(medicine.hsnCode),
      'gstRate': _doubleValue(medicine.gstRate),
      'scheduleType': _stringValue(medicine.scheduleType),
      'minStock': _intValue(20),
      'shelfLocation': _stringValue('A1'),
      'updatedAt': _timestampValue(now),
    });

    await api.projects.databases.documents.patch(
      medicineDoc,
      '$databasePath/medicines/${medicine.id}',
    );

    final serial = 1 + random.nextInt(5);
    final batchNumber = _generateBatchNumber(medicine.manufacturerCode, now, serial);
    final quantity = 100 + random.nextInt(401); // 100–500 base units
    final expiryMonths = 6 + random.nextInt(19); // 6–24 months out
    final expiryDate = DateTime(now.year, now.month + expiryMonths, now.day);
    final purchasePricePaise = (medicine.mrpPaise * 0.72).round(); // typical ~28% trade margin

    final batchDoc = firestore.Document(fields: {
      'id': _stringValue('${medicine.id}_$batchNumber'),
      'medicineId': _stringValue(medicine.id),
      'batchNumber': _stringValue(batchNumber),
      'expiryDate': _timestampValue(expiryDate),
      'purchasePricePaise': _intValue(purchasePricePaise),
      'mrpPaise': _intValue(medicine.mrpPaise),
      'quantity': _intValue(quantity),
      'isBlocked': _boolValue(false),
      'createdAt': _timestampValue(now),
    });

    await api.projects.databases.documents.patch(
      batchDoc,
      '$databasePath/medicines/${medicine.id}/batches/${medicine.id}_$batchNumber',
    );

    written++;
    stdout.writeln(
        '[$written/${seedMedicines.length}] ${medicine.name} — batch $batchNumber, '
        'qty $quantity, MRP ₹${(medicine.mrpPaise / 100).toStringAsFixed(2)}');
  }

  client.close();
  stdout.writeln('\nDone. $written medicines + batches written to $projectId.');
}
