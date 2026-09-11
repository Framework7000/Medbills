import '../../domain/models/medicine.dart';
import '../../domain/models/schedule_type.dart';

/// One row of the in-memory seed catalogue, along with the batch-shaped
/// pricing fields a cart line needs. The full 253,973-row Indian medicine
/// dataset ships as a bundled read-only SQLite file in production; this
/// seed covers the 31 most common OTC/prescription medicines for demo and
/// offline-first search.
class CartItemSeed {
  final String medicineId;
  final String name;
  final String batchNumber;
  final String expiry;
  final int mrpPaise;
  final double gstRate;

  const CartItemSeed({
    required this.medicineId,
    required this.name,
    required this.batchNumber,
    required this.expiry,
    required this.mrpPaise,
    required this.gstRate,
  });
}

class GlobalCatalogueRepository {
  /// Declared total size of the real dataset this seed stands in for.
  static const int totalCatalogueCount = 253973;

  static final List<Medicine> _seedMedicines = [
    _m('med_001', 'Paracetamol 500mg', 'Paracetamol', 'GSK', 'Analgesics', 5.0),
    _m('med_002', 'Dolo 650', 'Paracetamol', 'Micro Labs', 'Analgesics', 5.0),
    _m('med_003', 'Crocin Advance', 'Paracetamol', 'GSK', 'Analgesics', 5.0),
    _m('med_004', 'Augmentin 625 Duo', 'Amoxicillin + Clavulanate', 'GSK', 'Antibiotics', 12.0),
    _m('med_005', 'Azithromycin 500', 'Azithromycin', 'Cipla', 'Antibiotics', 12.0),
    _m('med_006', 'Amoxicillin 500mg', 'Amoxicillin', 'Cipla', 'Antibiotics', 12.0),
    _m('med_007', 'Pan-D', 'Pantoprazole + Domperidone', 'Alkem', 'Gastro', 12.0),
    _m('med_008', 'Pantoprazole 40mg', 'Pantoprazole', 'Sun Pharma', 'Gastro', 12.0),
    _m('med_009', 'Metformin 500mg', 'Metformin', 'USV', 'Diabetes', 12.0),
    _m('med_010', 'Glimepiride 2mg', 'Glimepiride', 'Sanofi', 'Diabetes', 12.0),
    _m('med_011', 'Telmisartan 40mg', 'Telmisartan', 'Glenmark', 'Cardiac', 12.0),
    _m('med_012', 'Amlodipine 5mg', 'Amlodipine', 'Zydus', 'Cardiac', 12.0),
    _m('med_013', 'Atorvastatin 10mg', 'Atorvastatin', 'Ranbaxy', 'Cardiac', 12.0),
    _m('med_014', 'Cetirizine 10mg', 'Cetirizine', 'Cipla', 'Allergy', 5.0),
    _m('med_015', 'Montair LC', 'Montelukast + Levocetirizine', 'Cipla', 'Allergy', 5.0),
    _m('med_016', 'Ibuprofen 400mg', 'Ibuprofen', 'Abbott', 'Analgesics', 12.0),
    _m('med_017', 'Diclofenac 50mg', 'Diclofenac', 'Novartis', 'Analgesics', 12.0),
    _m('med_018', 'Omeprazole 20mg', 'Omeprazole', 'Dr. Reddy\'s', 'Gastro', 12.0),
    _m('med_019', 'Ranitidine 150mg', 'Ranitidine', 'GSK', 'Gastro', 12.0),
    _m('med_020', 'ORS Powder', 'Oral Rehydration Salts', 'FDC', 'Gastro', 5.0),
    _m('med_021', 'Vitamin D3 60K', 'Cholecalciferol', 'Mankind', 'Supplements', 5.0),
    _m('med_022', 'B-Complex Forte', 'Vitamin B Complex', 'Mankind', 'Supplements', 5.0),
    _m('med_023', 'Calcium + D3', 'Calcium Carbonate', 'Alkem', 'Supplements', 5.0),
    _m('med_024', 'Ascoril LS Syrup', 'Ambroxol + Levosalbutamol', 'Glenmark', 'Respiratory', 12.0),
    _m('med_025', 'Levocetirizine 5mg', 'Levocetirizine', 'Torrent', 'Allergy', 5.0),
    _m('med_026', 'Azee 500', 'Azithromycin', 'Cipla', 'Antibiotics', 12.0),
    _m('med_027', 'Combiflam', 'Ibuprofen + Paracetamol', 'Sanofi', 'Analgesics', 12.0),
    _m('med_028', 'Shelcal 500', 'Calcium + Vitamin D3', 'Torrent', 'Supplements', 5.0),
    _m('med_029', 'Rantac 150', 'Ranitidine', 'J.B. Chemicals', 'Gastro', 12.0),
    _m('med_030', 'Zerodol-P', 'Aceclofenac + Paracetamol', 'Ipca', 'Analgesics', 12.0),
    _m('med_031', 'Volini Gel', 'Diclofenac Diethylamine', 'Sun Pharma', 'Topical', 18.0),
  ];

  static Medicine _m(
    String id,
    String name,
    String generic,
    String manufacturer,
    String type,
    double gstRate,
  ) {
    return Medicine(
      id: id,
      storeId: 'store_primary',
      name: name,
      genericName: generic,
      manufacturer: manufacturer,
      type: type,
      packSizeLabel: '10 Tablets Strip',
      hsnCode: '3004',
      gstRate: gstRate,
      scheduleType: ScheduleType.otc,
      minStock: 20,
      shelfLocation: 'A1',
      updatedAt: DateTime.now(),
    );
  }

  List<Medicine> searchCatalogue(String query) {
    if (query.trim().isEmpty) return _seedMedicines;
    final lower = query.toLowerCase();
    return _seedMedicines
        .where((m) =>
            m.name.toLowerCase().contains(lower) ||
            m.genericName.toLowerCase().contains(lower))
        .toList();
  }

  List<CartItemSeed> searchCartItems(String query) {
    return searchCatalogue(query).map((m) {
      return CartItemSeed(
        medicineId: m.id,
        name: m.name,
        batchNumber: 'B${m.id.substring(4)}',
        expiry: '12/2027',
        mrpPaise: 5000 + (int.parse(m.id.substring(4)) * 137) % 20000,
        gstRate: m.gstRate,
      );
    }).toList();
  }
}
