import '../../domain/models/medicine.dart';
import '../../domain/models/schedule_type.dart';

/// One row of the in-memory seed catalogue, along with the batch-shaped
/// pricing fields a cart line needs. The full 253,973-row Indian medicine
/// dataset ships as a bundled read-only SQLite file in production; this
/// seed covers ~95 authentic, fast-moving Indian medicines — including the
/// top formulations distributed through the Indore/Bhopal pharmaceutical
/// hubs that supply Madhya Pradesh retail pharmacies — for demo and
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

  /// HSN chapter-30 headings (Rule 4): 300410 for penicillin-type
  /// antibiotic combinations, 300420 for other antibiotic/antifungal
  /// formulations, 300490 for general formulations. 6-digit headings are
  /// GST-compliant for filers below the 8-digit e-invoicing threshold.
  static const _hsnPenicillin = '300410';
  static const _hsnOtherAntibiotic = '300420';
  static const _hsnGeneral = '300490';

  /// Reference MRP in paise per medicine id (Rule 12: integer paise, never
  /// a double), populated as a side effect of building [_seedMedicines]
  /// below. MRP itself belongs on the Batch, not the Medicine master
  /// (Rule 1) — this is only a seed-data convenience for demo pricing.
  static final Map<String, int> _referenceMrpPaise = {};

  static final List<Medicine> _seedMedicines = [
    // ---------------------------------------------------------------
    // Analgesics / antipyretics — OTC
    // ---------------------------------------------------------------
    _m('med_001', 'Paracetamol 500mg', 'Paracetamol', 'GSK Pharmaceuticals', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.otc, '10 Tablets Strip', 2000),
    _m('med_002', 'Dolo 650 Tablet', 'Paracetamol 650mg', 'Micro Labs', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 15', 3360),
    _m('med_003', 'Crocin Advance', 'Paracetamol', 'GSK Pharmaceuticals', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.otc, '15 Tablets Strip', 3000),
    _m('med_063', 'Calpol 500 Tablet', 'Paracetamol 500mg', 'GSK Pharmaceuticals', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 15', 1750),
    _m('med_016', 'Ibuprofen 400mg', 'Ibuprofen', 'Abbott India', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.otc, '10 Tablets Strip', 2500),
    _m('med_017', 'Diclofenac 50mg', 'Diclofenac Sodium', 'Novartis India', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 2800),
    _m('med_027', 'Combiflam Tablet', 'Ibuprofen 400mg + Paracetamol 325mg', 'Sanofi India',
        'Analgesics', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 20', 4820),
    _m('med_030', 'Zerodol-P', 'Aceclofenac + Paracetamol', 'Ipca Laboratories', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 5800),
    _m('med_091', 'Chymoral Forte Tablet', 'Trypsin + Chymotrypsin', 'Torrent Pharmaceuticals',
        'Analgesics', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 20', 44000),

    // ---------------------------------------------------------------
    // Antibiotics — Schedule H (prescription-only)
    // ---------------------------------------------------------------
    _m('med_004', 'Augmentin 625 Duo', 'Amoxicillin 500mg + Clavulanic Acid 125mg',
        'GSK Pharmaceuticals', 'Antibiotics', _hsnPenicillin, 12.0, ScheduleType.scheduleH,
        'Strip of 10', 20450),
    _m('med_064', 'Clavam 625 Tablet', 'Amoxicillin 500mg + Clavulanic Acid 125mg',
        'Alkem Laboratories', 'Antibiotics', _hsnPenicillin, 12.0, ScheduleType.scheduleH,
        'Strip of 10', 20100),
    _m('med_065', 'Moxikind-CV 625', 'Amoxicillin 500mg + Clavulanic Acid 125mg',
        'Mankind Pharma', 'Antibiotics', _hsnPenicillin, 12.0, ScheduleType.scheduleH,
        'Strip of 10', 17800),
    _m('med_005', 'Azithromycin 500', 'Azithromycin', 'Cipla', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, '5 Tablets Strip', 11000),
    _m('med_026', 'Azee 500 Tablet', 'Azithromycin 500mg', 'Cipla', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 5', 11950),
    _m('med_070', 'Azithral 500 Tablet', 'Azithromycin 500mg', 'Alembic Pharmaceuticals',
        'Antibiotics', _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 5', 12000),
    _m('med_006', 'Amoxicillin 500mg', 'Amoxicillin', 'Cipla', 'Antibiotics',
        _hsnPenicillin, 12.0, ScheduleType.scheduleH, '10 Capsules Strip', 6500),
    _m('med_066', 'Monocef 1g Injection', 'Ceftriaxone 1000mg', 'Aristo Pharmaceuticals',
        'Antibiotics', _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, '1 Vial', 6200),
    _m('med_067', 'Taxim-O 200 Tablet', 'Cefixime 200mg', 'Alkem Laboratories', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 10', 10850),
    _m('med_068', 'Mahacef 200 Tablet', 'Cefixime 200mg', 'Mankind Pharma', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 10', 10200),
    _m('med_069', 'Gudcef 200 Tablet', 'Cefpodoxime Proxetil 200mg', 'Mankind Pharma',
        'Antibiotics', _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 10', 16500),
    _m('med_057', 'Ciprofloxacin 500mg', 'Ciprofloxacin Hydrochloride', 'Cipla', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 8000),
    _m('med_058', 'Doxycycline 100mg', 'Doxycycline Hyclate', 'Sun Pharma', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, '10 Capsules Strip', 6000),
    _m('med_059', 'Metronidazole 400mg', 'Metronidazole', 'Alkem Laboratories', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 3500),

    // ---------------------------------------------------------------
    // Gastro — mostly OTC-sold in India, Ranitidine restricted (Schedule H)
    // ---------------------------------------------------------------
    _m('med_007', 'Pan-D', 'Pantoprazole 40mg + Domperidone 30mg', 'Alkem Laboratories',
        'Gastro', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 15', 19900),
    _m('med_071', 'Pan 40 Tablet', 'Pantoprazole 40mg', 'Alkem Laboratories', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 15500),
    _m('med_072', 'Pantop-D Capsule', 'Pantoprazole 40mg + Domperidone 30mg',
        'Aristo Pharmaceuticals', 'Gastro', _hsnGeneral, 12.0, ScheduleType.scheduleH,
        'Strip of 15', 19000),
    _m('med_008', 'Pantoprazole 40mg', 'Pantoprazole', 'Sun Pharma', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.otc, '10 Tablets Strip', 9000),
    _m('med_018', 'Omez 20 Capsule', 'Omeprazole 20mg', 'Dr. Reddy\'s Laboratories', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 20', 6500),
    _m('med_074', 'Rablet 20 Tablet', 'Rabeprazole 20mg', 'Lupin Ltd', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 11500),
    _m('med_019', 'Ranitidine 150mg', 'Ranitidine', 'GSK Pharmaceuticals', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 4000),
    _m('med_075', 'Aciloc 150 Tablet', 'Ranitidine 150mg', 'Cadila Pharmaceuticals', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 30', 4400),
    _m('med_029', 'Rantac 150', 'Ranitidine', 'J.B. Chemicals & Pharmaceuticals', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 3800),
    _m('med_020', 'ORS Powder', 'Oral Rehydration Salts', 'FDC Limited', 'Gastro',
        _hsnGeneral, 5.0, ScheduleType.otc, '1 Sachet', 2200),
    _m('med_060', 'Digene Gel', 'Magaldrate + Simethicone', 'Abbott India', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.otc, '200ml Bottle', 9500),
    _m('med_061', 'Eno Fruit Salt', 'Sodium Bicarbonate + Citric Acid', 'GSK Pharmaceuticals',
        'Gastro', _hsnGeneral, 12.0, ScheduleType.otc, '100g Bottle', 7500),
    _m('med_062', 'Cyclopam', 'Dicyclomine + Paracetamol', 'Sun Pharma', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.otc, '10 Tablets Strip', 3000),

    // ---------------------------------------------------------------
    // Diabetes — Schedule H
    // ---------------------------------------------------------------
    _m('med_009', 'Metformin 500mg', 'Metformin Hydrochloride', 'USV Private Limited',
        'Diabetes', _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 3500),
    _m('med_010', 'Glimepiride 2mg', 'Glimepiride', 'Sanofi India', 'Diabetes',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 4500),
    _m('med_083', 'Glycomet-GP 1 Tablet', 'Glimepiride 1mg + Metformin 500mg',
        'USV Private Limited', 'Diabetes', _hsnGeneral, 12.0, ScheduleType.scheduleH,
        'Strip of 15', 11800),
    _m('med_084', 'Gemer 2 Tablet', 'Glimepiride 2mg + Metformin 500mg', 'Sun Pharma',
        'Diabetes', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 12800),
    _m('med_052', 'Human Mixtard Insulin', 'Human Insulin', 'Novo Nordisk India', 'Diabetes',
        _hsnGeneral, 5.0, ScheduleType.scheduleH, '10ml Vial', 18500),
    _m('med_053', 'Sitagliptin 100mg', 'Sitagliptin Phosphate', 'MSD Pharmaceuticals',
        'Diabetes', _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 32000),

    // ---------------------------------------------------------------
    // Cardiac — Schedule H
    // ---------------------------------------------------------------
    _m('med_011', 'Telma 40 Tablet', 'Telmisartan 40mg', 'Glenmark Pharmaceuticals', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 14800),
    _m('med_085', 'Telmikind 40 Tablet', 'Telmisartan 40mg', 'Mankind Pharma', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 4900),
    _m('med_012', 'Amlodipine 5mg', 'Amlodipine Besylate', 'Zydus Lifesciences', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 4000),
    _m('med_087', 'Amlong 5 Tablet', 'Amlodipine Besylate 5mg', 'Micro Labs', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 4500),
    _m('med_013', 'Atorvastatin 10mg', 'Atorvastatin Calcium', 'Sun Pharma', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 9500),
    _m('med_088', 'Atorva 10 Tablet', 'Atorvastatin Calcium 10mg', 'Zydus Healthcare',
        'Cardiac', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 11000),
    _m('med_049', 'Rosuvastatin 10mg', 'Rosuvastatin Calcium', 'Cipla', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 21000),
    _m('med_089', 'Rosuvas 10 Tablet', 'Rosuvastatin Calcium 10mg', 'Sun Pharma', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 24000),
    _m('med_050', 'Clopidogrel 75mg', 'Clopidogrel Bisulfate', 'Sun Pharma', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 8500),
    _m('med_051', 'Ecosprin 75', 'Aspirin', 'USV Private Limited', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '14 Tablets Strip', 1800),

    // ---------------------------------------------------------------
    // Allergy — OTC antihistamines
    // ---------------------------------------------------------------
    _m('med_014', 'Cetirizine 10mg', 'Cetirizine Hydrochloride', 'Cipla', 'Allergy',
        _hsnGeneral, 12.0, ScheduleType.otc, '10 Tablets Strip', 1800),
    _m('med_015', 'Montair-LC Tablet', 'Montelukast 10mg + Levocetirizine 5mg', 'Cipla',
        'Allergy', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 10', 18500),
    _m('med_076', 'Telekast-L Tablet', 'Montelukast 10mg + Levocetirizine 5mg', 'Lupin Ltd',
        'Allergy', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 10', 17900),
    _m('med_055', 'Montek LC', 'Montelukast + Levocetirizine', 'Sun Pharma', 'Allergy',
        _hsnGeneral, 12.0, ScheduleType.otc, '10 Tablets Strip', 16500),
    _m('med_025', 'Levocetirizine 5mg', 'Levocetirizine Dihydrochloride', 'Torrent Pharmaceuticals',
        'Allergy', _hsnGeneral, 12.0, ScheduleType.otc, '10 Tablets Strip', 3200),
    _m('med_077', 'Allegra 120mg Tablet', 'Fexofenadine 120mg', 'Sanofi India', 'Allergy',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 10', 21500),
    _m('med_078', 'Avil 25 Tablet', 'Pheniramine Maleate 25mg', 'Sanofi India', 'Allergy',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 1150),

    // ---------------------------------------------------------------
    // Supplements — OTC
    // ---------------------------------------------------------------
    _m('med_021', 'Vitamin D3 60K', 'Cholecalciferol', 'Mankind Pharma', 'Supplements',
        _hsnGeneral, 12.0, ScheduleType.otc, '4 Sachets Box', 9500),
    _m('med_022', 'B-Complex Forte', 'Vitamin B Complex', 'Mankind Pharma', 'Supplements',
        _hsnGeneral, 12.0, ScheduleType.otc, '15 Tablets Strip', 4200),
    _m('med_080', 'Becosules Z Capsule', 'B-Complex + Vitamin C + Zinc', 'Pfizer Limited',
        'Supplements', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 20', 5200),
    _m('med_023', 'Calcium + D3', 'Calcium Carbonate + Cholecalciferol', 'Alkem Laboratories',
        'Supplements', _hsnGeneral, 12.0, ScheduleType.otc, '15 Tablets Strip', 6800),
    _m('med_028', 'Shelcal 500 Tablet', 'Calcium Carbonate 500mg + Vitamin D3 250 IU',
        'Torrent Pharmaceuticals', 'Supplements', _hsnGeneral, 12.0, ScheduleType.otc,
        'Strip of 15', 13100),
    _m('med_081', 'Limcee 500mg Tablet', 'Vitamin C (Ascorbic Acid) 500mg', 'Abbott India',
        'Supplements', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 15', 2450),
    _m('med_045', 'Folvite 5mg', 'Folic Acid', 'Sun Pharma', 'Supplements',
        _hsnGeneral, 12.0, ScheduleType.otc, '10 Tablets Strip', 2200),
    _m('med_082', 'Thyronorm 50mcg', 'Thyroxine Sodium 50mcg', 'Abbott India', 'Supplements',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Bottle 120', 16500),

    // ---------------------------------------------------------------
    // Respiratory
    // ---------------------------------------------------------------
    _m('med_024', 'Ascoril LS Syrup', 'Ambroxol + Levosalbutamol', 'Glenmark Pharmaceuticals',
        'Respiratory', _hsnGeneral, 12.0, ScheduleType.scheduleH, '100ml Bottle', 11800),
    _m('med_054', 'Asthalin Inhaler', 'Salbutamol 100mcg (200 MDI)', 'Cipla', 'Respiratory',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Inhaler', 15800),
    _m('med_079', 'Foracort 200 Inhaler', 'Formoterol 6mcg + Budesonide 200mcg', 'Cipla',
        'Respiratory', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Inhaler', 48500),
    _m('med_056', 'Benadryl Cough Syrup', 'Diphenhydramine + Ammonium Chloride',
        'Johnson & Johnson', 'Respiratory', _hsnGeneral, 12.0, ScheduleType.otc,
        '100ml Bottle', 11000),

    // ---------------------------------------------------------------
    // Topical / Dermatology
    // ---------------------------------------------------------------
    _m('med_031', 'Volini Gel', 'Diclofenac Diethylamine + Linseed Oil', 'Sun Pharma',
        'Topical', _hsnGeneral, 12.0, ScheduleType.otc, 'Tube 50g', 16000),
    _m('med_032', 'Moov Pain Relief Cream', 'Diclofenac Diethylamine', 'Reckitt Benckiser',
        'Topical', _hsnGeneral, 12.0, ScheduleType.otc, '50g Tube', 11500),
    _m('med_033', 'Betnovate-N Cream', 'Betamethasone + Neomycin', 'GSK Pharmaceuticals',
        'Dermatology', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Tube 20g', 5500),
    _m('med_034', 'Candid-B Cream', 'Clotrimazole + Beclomethasone', 'Glenmark Pharmaceuticals',
        'Dermatology', _hsnGeneral, 12.0, ScheduleType.scheduleH, '20g Tube', 13500),
    _m('med_035', 'Soframycin Skin Cream', 'Framycetin Sulphate', 'Sanofi India', 'Dermatology',
        _hsnGeneral, 12.0, ScheduleType.otc, '30g Tube', 4800),

    // ---------------------------------------------------------------
    // Antifungal — Schedule H, HSN 300420 per CDSCO antimicrobial grouping
    // ---------------------------------------------------------------
    _m('med_036', 'Fluconazole 150mg', 'Fluconazole', 'Pfizer India', 'Antifungal',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, '1 Capsule', 3500),
    _m('med_037', 'Itraconazole 100mg', 'Itraconazole', 'Cipla', 'Antifungal',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, '10 Capsules Strip', 18500),
    _m('med_090', 'Candiforce 200 Capsule', 'Itraconazole 200mg', 'Mankind Pharma',
        'Antifungal', _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 10', 22000),

    // ---------------------------------------------------------------
    // Antiviral — Schedule H
    // ---------------------------------------------------------------
    _m('med_038', 'Acyclovir 400mg', 'Acyclovir', 'GSK Pharmaceuticals', 'Antiviral',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 9500),

    // ---------------------------------------------------------------
    // Ophthalmology
    // ---------------------------------------------------------------
    _m('med_039', 'Moxifloxacin Eye Drops', 'Moxifloxacin Hydrochloride', 'Sun Pharma',
        'Ophthalmology', _hsnGeneral, 12.0, ScheduleType.scheduleH, '5ml Bottle', 11500),
    _m('med_040', 'Refresh Tears Eye Drops', 'Carboxymethylcellulose Sodium', 'Allergan India',
        'Ophthalmology', _hsnGeneral, 12.0, ScheduleType.otc, '10ml Bottle', 14500),

    // ---------------------------------------------------------------
    // Pediatric
    // ---------------------------------------------------------------
    _m('med_041', 'Calpol Paediatric Syrup', 'Paracetamol', 'GSK Pharmaceuticals', 'Pediatric',
        _hsnGeneral, 12.0, ScheduleType.otc, '60ml Bottle', 4200),
    _m('med_042', 'Zincovit Syrup', 'Zinc + Multivitamins', 'Apex Laboratories', 'Pediatric',
        _hsnGeneral, 12.0, ScheduleType.otc, '200ml Bottle', 11000),

    // ---------------------------------------------------------------
    // Women's Health
    // ---------------------------------------------------------------
    _m('med_043', 'Meftal Spas', 'Mefenamic Acid + Dicyclomine', 'Blue Cross Laboratories',
        'Women\'s Health', _hsnGeneral, 12.0, ScheduleType.otc, '10 Tablets Strip', 4800),
    _m('med_044', 'I-Pill', 'Levonorgestrel', 'Mankind Pharma', 'Women\'s Health',
        _hsnGeneral, 12.0, ScheduleType.otc, '1 Tablet', 10000),

    // ---------------------------------------------------------------
    // Neuro/Psychiatry — Schedule H / H1
    // ---------------------------------------------------------------
    _m('med_046', 'Escitalopram 10mg', 'Escitalopram Oxalate', 'Sun Pharma', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 9500),
    _m('med_047', 'Clonazepam 0.5mg', 'Clonazepam', 'Mankind Pharma', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleX, '10 Tablets Strip', 2800),
    _m('med_048', 'Gabapentin 300mg', 'Gabapentin', 'Sun Pharma', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Capsules Strip', 11000),
    _m('med_092', 'Alprazolam 0.5mg (Restyl)', 'Alprazolam 0.5mg', 'Cipla', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH1, 'Strip of 15', 4200),
    _m('med_093', 'Zolpidem 10mg (Zolfresh)', 'Zolpidem Tartrate 10mg', 'Abbott India',
        'Neuro/Psychiatry', _hsnGeneral, 12.0, ScheduleType.scheduleH1, 'Strip of 10', 9800),
    _m('med_094', 'Tramadol 50mg (Ultracet)', 'Tramadol 37.5mg + Paracetamol 325mg',
        'Janssen (Johnson & Johnson)', 'Neuro/Psychiatry', _hsnGeneral, 12.0,
        ScheduleType.scheduleH1, 'Strip of 15', 21500),
  ];

  static Medicine _m(
    String id,
    String name,
    String generic,
    String manufacturer,
    String type,
    String hsnCode,
    double gstRate,
    ScheduleType scheduleType,
    String packSizeLabel,
    int referenceMrpPaise,
  ) {
    _referenceMrpPaise[id] = referenceMrpPaise;
    return Medicine(
      id: id,
      storeId: 'store_primary',
      name: name,
      genericName: generic,
      manufacturer: manufacturer,
      type: type,
      packSizeLabel: packSizeLabel,
      hsnCode: hsnCode,
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
        mrpPaise: _referenceMrpPaise[m.id] ?? 5000,
        gstRate: m.gstRate,
      );
    }).toList();
  }
}
