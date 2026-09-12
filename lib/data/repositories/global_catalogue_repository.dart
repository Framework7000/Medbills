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
    // OTC analgesics/antipyretics — HSN 30049099, generally 12% GST in India
    _m('med_001', 'Paracetamol 500mg', 'Paracetamol', 'GSK Pharmaceuticals', 'Analgesics',
        12.0, ScheduleType.otc, '10 Tablets Strip'),
    _m('med_002', 'Dolo 650', 'Paracetamol', 'Micro Labs', 'Analgesics',
        12.0, ScheduleType.otc, '15 Tablets Strip'),
    _m('med_003', 'Crocin Advance', 'Paracetamol', 'GSK Pharmaceuticals', 'Analgesics',
        12.0, ScheduleType.otc, '15 Tablets Strip'),
    _m('med_016', 'Ibuprofen 400mg', 'Ibuprofen', 'Abbott India', 'Analgesics',
        12.0, ScheduleType.otc, '10 Tablets Strip'),
    _m('med_017', 'Diclofenac 50mg', 'Diclofenac Sodium', 'Novartis India', 'Analgesics',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_027', 'Combiflam', 'Ibuprofen + Paracetamol', 'Sanofi India', 'Analgesics',
        12.0, ScheduleType.otc, '20 Tablets Strip'),
    _m('med_030', 'Zerodol-P', 'Aceclofenac + Paracetamol', 'Ipca Laboratories', 'Analgesics',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),

    // Antibiotics — prescription-only (Schedule H)
    _m('med_004', 'Augmentin 625 Duo', 'Amoxicillin + Clavulanic Acid', 'GSK Pharmaceuticals',
        'Antibiotics', 12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_005', 'Azithromycin 500', 'Azithromycin', 'Cipla', 'Antibiotics',
        12.0, ScheduleType.scheduleH, '5 Tablets Strip'),
    _m('med_006', 'Amoxicillin 500mg', 'Amoxicillin', 'Cipla', 'Antibiotics',
        12.0, ScheduleType.scheduleH, '10 Capsules Strip'),
    _m('med_026', 'Azee 500', 'Azithromycin', 'Cipla', 'Antibiotics',
        12.0, ScheduleType.scheduleH, '5 Tablets Strip'),

    // Gastro — Pan-D/Pantoprazole widely OTC-sold in India; Ranitidine restricted post-2020 recall
    _m('med_007', 'Pan-D', 'Pantoprazole + Domperidone', 'Alkem Laboratories', 'Gastro',
        12.0, ScheduleType.otc, '15 Capsules Strip'),
    _m('med_008', 'Pantoprazole 40mg', 'Pantoprazole', 'Sun Pharma', 'Gastro',
        12.0, ScheduleType.otc, '10 Tablets Strip'),
    _m('med_018', 'Omeprazole 20mg', 'Omeprazole', 'Dr. Reddy\'s Laboratories', 'Gastro',
        12.0, ScheduleType.otc, '10 Capsules Strip'),
    _m('med_019', 'Ranitidine 150mg', 'Ranitidine', 'GSK Pharmaceuticals', 'Gastro',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_020', 'ORS Powder', 'Oral Rehydration Salts', 'FDC Limited', 'Gastro',
        5.0, ScheduleType.otc, '1 Sachet'),
    _m('med_029', 'Rantac 150', 'Ranitidine', 'J.B. Chemicals & Pharmaceuticals', 'Gastro',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),

    // Diabetes — prescription-only
    _m('med_009', 'Metformin 500mg', 'Metformin Hydrochloride', 'USV Private Limited',
        'Diabetes', 12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_010', 'Glimepiride 2mg', 'Glimepiride', 'Sanofi India', 'Diabetes',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),

    // Cardiac — prescription-only
    _m('med_011', 'Telmisartan 40mg', 'Telmisartan', 'Glenmark Pharmaceuticals', 'Cardiac',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_012', 'Amlodipine 5mg', 'Amlodipine Besylate', 'Zydus Lifesciences', 'Cardiac',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_013', 'Atorvastatin 10mg', 'Atorvastatin Calcium', 'Sun Pharma', 'Cardiac',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),

    // Allergy — OTC antihistamines
    _m('med_014', 'Cetirizine 10mg', 'Cetirizine Hydrochloride', 'Cipla', 'Allergy',
        12.0, ScheduleType.otc, '10 Tablets Strip'),
    _m('med_015', 'Montair LC', 'Montelukast + Levocetirizine', 'Cipla', 'Allergy',
        12.0, ScheduleType.otc, '10 Tablets Strip'),
    _m('med_025', 'Levocetirizine 5mg', 'Levocetirizine Dihydrochloride', 'Torrent Pharmaceuticals',
        'Allergy', 12.0, ScheduleType.otc, '10 Tablets Strip'),

    // Supplements — OTC, 5% GST slab (life-saving/essential nutrition category)
    _m('med_021', 'Vitamin D3 60K', 'Cholecalciferol', 'Mankind Pharma', 'Supplements',
        5.0, ScheduleType.otc, '4 Sachets Box'),
    _m('med_022', 'B-Complex Forte', 'Vitamin B Complex', 'Mankind Pharma', 'Supplements',
        5.0, ScheduleType.otc, '15 Tablets Strip'),
    _m('med_023', 'Calcium + D3', 'Calcium Carbonate + Cholecalciferol', 'Alkem Laboratories',
        'Supplements', 5.0, ScheduleType.otc, '15 Tablets Strip'),
    _m('med_028', 'Shelcal 500', 'Calcium Carbonate + Vitamin D3', 'Torrent Pharmaceuticals',
        'Supplements', 5.0, ScheduleType.otc, '15 Tablets Strip'),

    // Respiratory — prescription-only combination syrup
    _m('med_024', 'Ascoril LS Syrup', 'Ambroxol + Levosalbutamol', 'Glenmark Pharmaceuticals',
        'Respiratory', 12.0, ScheduleType.scheduleH, '100ml Bottle'),

    // Topical — OTC pain-relief gel, 18% GST slab (cosmetic/topical category)
    _m('med_031', 'Volini Gel', 'Diclofenac Diethylamine', 'Sun Pharma', 'Topical',
        18.0, ScheduleType.otc, '30g Tube'),
    _m('med_032', 'Moov Pain Relief Cream', 'Diclofenac Diethylamine', 'Reckitt Benckiser',
        'Topical', 18.0, ScheduleType.otc, '50g Tube'),
    _m('med_033', 'Betnovate-N Cream', 'Betamethasone + Neomycin', 'GSK Pharmaceuticals',
        'Dermatology', 12.0, ScheduleType.scheduleH, '20g Tube'),
    _m('med_034', 'Candid-B Cream', 'Clotrimazole + Beclomethasone', 'Glenmark Pharmaceuticals',
        'Dermatology', 12.0, ScheduleType.scheduleH, '20g Tube'),
    _m('med_035', 'Soframycin Skin Cream', 'Framycetin Sulphate', 'Sanofi India', 'Dermatology',
        12.0, ScheduleType.otc, '30g Tube'),

    // Antifungal — prescription-only
    _m('med_036', 'Fluconazole 150mg', 'Fluconazole', 'Pfizer India', 'Antifungal',
        12.0, ScheduleType.scheduleH, '1 Capsule'),
    _m('med_037', 'Itraconazole 100mg', 'Itraconazole', 'Cipla', 'Antifungal',
        12.0, ScheduleType.scheduleH, '10 Capsules Strip'),

    // Antiviral — prescription-only
    _m('med_038', 'Acyclovir 400mg', 'Acyclovir', 'GSK Pharmaceuticals', 'Antiviral',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),

    // Ophthalmology — prescription for antibiotic drops, OTC for lubricants
    _m('med_039', 'Moxifloxacin Eye Drops', 'Moxifloxacin Hydrochloride', 'Sun Pharma',
        'Ophthalmology', 12.0, ScheduleType.scheduleH, '5ml Bottle'),
    _m('med_040', 'Refresh Tears Eye Drops', 'Carboxymethylcellulose Sodium', 'Allergan India',
        'Ophthalmology', 12.0, ScheduleType.otc, '10ml Bottle'),

    // Pediatric — OTC syrups
    _m('med_041', 'Calpol Paediatric Syrup', 'Paracetamol', 'GSK Pharmaceuticals', 'Pediatric',
        12.0, ScheduleType.otc, '60ml Bottle'),
    _m('med_042', 'Zincovit Syrup', 'Zinc + Multivitamins', 'Apex Laboratories', 'Pediatric',
        5.0, ScheduleType.otc, '200ml Bottle'),

    // Women's health — mixed OTC/prescription
    _m('med_043', 'Meftal Spas', 'Mefenamic Acid + Dicyclomine', 'Blue Cross Laboratories',
        'Women\'s Health', 12.0, ScheduleType.otc, '10 Tablets Strip'),
    _m('med_044', 'I-Pill', 'Levonorgestrel', 'Mankind Pharma', 'Women\'s Health',
        12.0, ScheduleType.otc, '1 Tablet'),
    _m('med_045', 'Folvite 5mg', 'Folic Acid', 'Sun Pharma', 'Women\'s Health',
        5.0, ScheduleType.otc, '10 Tablets Strip'),

    // Neuro/Psychiatry — prescription-only
    _m('med_046', 'Escitalopram 10mg', 'Escitalopram Oxalate', 'Sun Pharma', 'Neuro/Psychiatry',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_047', 'Clonazepam 0.5mg', 'Clonazepam', 'Mankind Pharma', 'Neuro/Psychiatry',
        12.0, ScheduleType.scheduleX, '10 Tablets Strip'),
    _m('med_048', 'Gabapentin 300mg', 'Gabapentin', 'Sun Pharma', 'Neuro/Psychiatry',
        12.0, ScheduleType.scheduleH, '10 Capsules Strip'),

    // More cardiac / cholesterol
    _m('med_049', 'Rosuvastatin 10mg', 'Rosuvastatin Calcium', 'Cipla', 'Cardiac',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_050', 'Clopidogrel 75mg', 'Clopidogrel Bisulfate', 'Sun Pharma', 'Cardiac',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_051', 'Ecosprin 75', 'Aspirin', 'USV Private Limited', 'Cardiac',
        12.0, ScheduleType.scheduleH, '14 Tablets Strip'),

    // More diabetes — insulin at concessional GST slab
    _m('med_052', 'Human Mixtard Insulin', 'Human Insulin', 'Novo Nordisk India', 'Diabetes',
        5.0, ScheduleType.scheduleH, '10ml Vial'),
    _m('med_053', 'Sitagliptin 100mg', 'Sitagliptin Phosphate', 'MSD Pharmaceuticals', 'Diabetes',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),

    // More respiratory
    _m('med_054', 'Asthalin Inhaler', 'Salbutamol Sulphate', 'Cipla', 'Respiratory',
        12.0, ScheduleType.scheduleH, '200 Metered Doses'),
    _m('med_055', 'Montek LC', 'Montelukast + Levocetirizine', 'Sun Pharma', 'Respiratory',
        12.0, ScheduleType.otc, '10 Tablets Strip'),
    _m('med_056', 'Benadryl Cough Syrup', 'Diphenhydramine + Ammonium Chloride',
        'Johnson & Johnson', 'Respiratory', 12.0, ScheduleType.otc, '100ml Bottle'),

    // More antibiotics
    _m('med_057', 'Ciprofloxacin 500mg', 'Ciprofloxacin Hydrochloride', 'Cipla', 'Antibiotics',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),
    _m('med_058', 'Doxycycline 100mg', 'Doxycycline Hyclate', 'Sun Pharma', 'Antibiotics',
        12.0, ScheduleType.scheduleH, '10 Capsules Strip'),
    _m('med_059', 'Metronidazole 400mg', 'Metronidazole', 'Alkem Laboratories', 'Antibiotics',
        12.0, ScheduleType.scheduleH, '10 Tablets Strip'),

    // More gastro
    _m('med_060', 'Digene Gel', 'Magaldrate + Simethicone', 'Abbott India', 'Gastro',
        12.0, ScheduleType.otc, '200ml Bottle'),
    _m('med_061', 'Eno Fruit Salt', 'Sodium Bicarbonate + Citric Acid', 'GSK Pharmaceuticals',
        'Gastro', 12.0, ScheduleType.otc, '100g Bottle'),
    _m('med_062', 'Cyclopam', 'Dicyclomine + Paracetamol', 'Sun Pharma', 'Gastro',
        12.0, ScheduleType.otc, '10 Tablets Strip'),
  ];

  static Medicine _m(
    String id,
    String name,
    String generic,
    String manufacturer,
    String type,
    double gstRate,
    ScheduleType scheduleType,
    String packSizeLabel,
  ) {
    return Medicine(
      id: id,
      storeId: 'store_primary',
      name: name,
      genericName: generic,
      manufacturer: manufacturer,
      type: type,
      packSizeLabel: packSizeLabel,
      hsnCode: '30049099',
      gstRate: gstRate,
      scheduleType: scheduleType,
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
