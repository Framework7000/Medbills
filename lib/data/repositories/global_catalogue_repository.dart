import '../../domain/models/medicine.dart';
import '../../domain/models/schedule_type.dart';
import '../../domain/services/pack_units.dart';

/// A master-catalogue medicine plus the reference MRP (per pack) it is
/// typically sold at, used to pre-fill the stock-in form. The real price
/// always comes from the batch received.
class CatalogueEntry {
  final Medicine medicine;
  final int referenceMrpPaise;

  const CatalogueEntry({required this.medicine, required this.referenceMrpPaise});
}

class GlobalCatalogueRepository {
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
        'Gastro', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 19900),
    _m('med_071', 'Pan 40 Tablet', 'Pantoprazole 40mg', 'Alkem Laboratories', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 15500),
    _m('med_072', 'Pantop-D Capsule', 'Pantoprazole 40mg + Domperidone 30mg',
        'Aristo Pharmaceuticals', 'Gastro', _hsnGeneral, 12.0, ScheduleType.scheduleH,
        'Strip of 15', 19000),
    _m('med_008', 'Pantoprazole 40mg', 'Pantoprazole', 'Sun Pharma', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 9000),
    _m('med_018', 'Omez 20 Capsule', 'Omeprazole 20mg', 'Dr. Reddy\'s Laboratories', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 20', 6500),
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
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 3000),

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
        'Allergy', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 18500),
    _m('med_076', 'Telekast-L Tablet', 'Montelukast 10mg + Levocetirizine 5mg', 'Lupin Ltd',
        'Allergy', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 17900),
    _m('med_055', 'Montek LC', 'Montelukast + Levocetirizine', 'Sun Pharma', 'Allergy',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 16500),
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
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '30g Tube', 4800),

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
        'Women\'s Health', _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 4800),
    _m('med_044', 'I-Pill', 'Levonorgestrel', 'Mankind Pharma', 'Women\'s Health',
        _hsnGeneral, 12.0, ScheduleType.otc, '1 Tablet', 10000),

    // ---------------------------------------------------------------
    // Neuro/Psychiatry — Schedule H / H1
    // ---------------------------------------------------------------
    _m('med_046', 'Escitalopram 10mg', 'Escitalopram Oxalate', 'Sun Pharma', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 9500),
    _m('med_047', 'Clonazepam 0.5mg', 'Clonazepam', 'Mankind Pharma', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH1, '10 Tablets Strip', 2800),
    _m('med_048', 'Gabapentin 300mg', 'Gabapentin', 'Sun Pharma', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Capsules Strip', 11000),
    _m('med_092', 'Alprazolam 0.5mg (Restyl)', 'Alprazolam 0.5mg', 'Cipla', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH1, 'Strip of 15', 4200),
    _m('med_093', 'Zolpidem 10mg (Zolfresh)', 'Zolpidem Tartrate 10mg', 'Abbott India',
        'Neuro/Psychiatry', _hsnGeneral, 12.0, ScheduleType.scheduleH1, 'Strip of 10', 9800),
    _m('med_094', 'Ultracet Tablet', 'Tramadol 37.5mg + Paracetamol 325mg',
        'Janssen (Johnson & Johnson)', 'Neuro/Psychiatry', _hsnGeneral, 12.0,
        ScheduleType.scheduleH1, 'Strip of 15', 21500),

    // ---------------------------------------------------------------
    // More analgesics
    // ---------------------------------------------------------------
    _m('med_095', 'Aceclofenac 100mg', 'Aceclofenac', 'Ipca Laboratories', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 3200),
    _m('med_096', 'Nise Tablet', 'Nimesulide 100mg', 'Dr. Reddy\'s Laboratories', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 3100),
    _m('med_097', 'Flexon Tablet', 'Ibuprofen 400mg + Paracetamol 325mg', 'Reckitt Benckiser',
        'Analgesics', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 20', 4600),
    _m('med_098', 'Voveran 50mg', 'Diclofenac Sodium 50mg', 'Novartis India', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 20', 5600),
    _m('med_099', 'Saridon Tablet', 'Paracetamol + Propyphenazone + Caffeine',
        'Piramal Enterprises', 'Analgesics', _hsnGeneral, 12.0, ScheduleType.otc,
        'Strip of 10', 2800),
    _m('med_100', 'Tramadol 50mg', 'Tramadol Hydrochloride', 'Sun Pharma', 'Analgesics',
        _hsnGeneral, 12.0, ScheduleType.scheduleH1, '10 Capsules Strip', 4200),

    // ---------------------------------------------------------------
    // More antibiotics
    // ---------------------------------------------------------------
    _m('med_101', 'Cifran 500 Tablet', 'Ciprofloxacin 500mg', 'Sun Pharma', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 10', 8400),
    _m('med_102', 'Levoflox 500 Tablet', 'Levofloxacin 500mg', 'Cipla', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 5', 9500),
    _m('med_103', 'Norflox-TZ Tablet', 'Norfloxacin 400mg + Tinidazole 600mg', 'Cipla',
        'Antibiotics', _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 10', 9800),
    _m('med_104', 'O2 Tablet', 'Ofloxacin 200mg + Ornidazole 500mg', 'Alkem Laboratories',
        'Antibiotics', _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 10', 8200),
    _m('med_105', 'Zifi 200 Tablet', 'Cefixime 200mg', 'FDC Limited', 'Antibiotics',
        _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 10', 10600),

    // ---------------------------------------------------------------
    // More gastro
    // ---------------------------------------------------------------
    _m('med_106', 'Sucralfate 1g Tablet', 'Sucralfate', 'Cipla', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 3600),
    _m('med_107', 'Domperidone 10mg', 'Domperidone', 'Sun Pharma', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 2200),
    _m('med_108', 'Esomeprazole 40mg', 'Esomeprazole', 'Dr. Reddy\'s Laboratories', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 8600),
    _m('med_109', 'Dulcolax Tablet', 'Bisacodyl 5mg', 'Sanofi India', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 10', 2100),
    _m('med_110', 'Isabgol Husk', 'Psyllium Husk', 'Dabur India', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.otc, '100g Jar', 9000),

    // ---------------------------------------------------------------
    // More diabetes
    // ---------------------------------------------------------------
    _m('med_111', 'Voglibose 0.2mg', 'Voglibose', 'USV Private Limited', 'Diabetes',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 4800),
    _m('med_112', 'Pioglitazone 15mg', 'Pioglitazone', 'Sun Pharma', 'Diabetes',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 3900),
    _m('med_113', 'Human Actrapid Insulin', 'Human Insulin (Soluble)', 'Novo Nordisk India',
        'Diabetes', _hsnGeneral, 5.0, ScheduleType.scheduleH, '10ml Vial', 18200),
    _m('med_114', 'Glucerna Powder', 'Diabetes-Specific Nutrition', 'Abbott India', 'Diabetes',
        _hsnGeneral, 12.0, ScheduleType.otc, '400g Tin', 65000),

    // ---------------------------------------------------------------
    // More cardiac
    // ---------------------------------------------------------------
    _m('med_115', 'Metoprolol 50mg', 'Metoprolol Succinate', 'Sun Pharma', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 4200),
    _m('med_116', 'Losartan 50mg', 'Losartan Potassium', 'Cipla', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 3800),
    _m('med_117', 'Ramipril 5mg', 'Ramipril', 'Sanofi India', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 4500),
    _m('med_118', 'Nitrocontin 2.6mg', 'Nitroglycerin', 'USV Private Limited', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 3200),
    _m('med_119', 'Digoxin 0.25mg', 'Digoxin', 'GSK Pharmaceuticals', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 1800),
    _m('med_120', 'Ecosprin AV 75', 'Aspirin 75mg + Atorvastatin 10mg', 'USV Private Limited',
        'Cardiac', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 8700),

    // ---------------------------------------------------------------
    // More allergy
    // ---------------------------------------------------------------
    _m('med_121', 'Montek 10 Tablet', 'Montelukast 10mg', 'Sun Pharma', 'Allergy',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 11500),
    _m('med_122', 'Atarax 25mg', 'Hydroxyzine', 'Pfizer Limited', 'Allergy',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 3200),
    _m('med_123', 'Rhinocort Nasal Spray', 'Budesonide Nasal Spray', 'AstraZeneca Pharma India',
        'Allergy', _hsnGeneral, 12.0, ScheduleType.scheduleH, '10ml Bottle', 18500),

    // ---------------------------------------------------------------
    // More supplements
    // ---------------------------------------------------------------
    _m('med_124', 'Neurobion Forte', 'Vitamin B1 + B6 + B12', 'Procter & Gamble Health',
        'Supplements', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 30', 2600),
    _m('med_125', 'Revital H Capsule', 'Multivitamin + Ginseng', 'Sun Pharma Consumer',
        'Supplements', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 20', 24500),
    _m('med_126', 'Zincovit Tablet', 'Zinc + Multivitamins', 'Apex Laboratories',
        'Supplements', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 15', 3900),
    _m('med_127', 'Evion 400 Capsule', 'Vitamin E 400mg', 'Merck Limited', 'Supplements',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 10', 3500),
    _m('med_128', 'Dexorange Syrup', 'Iron + Folic Acid + Vitamin B12',
        'Franco-Indian Pharmaceuticals', 'Supplements', _hsnGeneral, 12.0, ScheduleType.otc,
        '200ml Bottle', 13500),

    // ---------------------------------------------------------------
    // More respiratory
    // ---------------------------------------------------------------
    _m('med_129', 'Grilinctus Syrup', 'Dextromethorphan + Chlorpheniramine',
        'Franco-Indian Pharmaceuticals', 'Respiratory', _hsnGeneral, 12.0, ScheduleType.otc,
        '100ml Bottle', 8500),
    _m('med_130', 'Alex Syrup', 'Dextromethorphan + Phenylephrine + Chlorpheniramine',
        'Glenmark Pharmaceuticals', 'Respiratory', _hsnGeneral, 12.0, ScheduleType.otc,
        '100ml Bottle', 8900),
    _m('med_131', 'Montair-FX Tablet', 'Montelukast + Fexofenadine', 'Cipla', 'Respiratory',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 16800),
    _m('med_132', 'Budecort Respules', 'Budesonide 0.5mg', 'Cipla', 'Respiratory',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Box of 5', 32500),

    // ---------------------------------------------------------------
    // More dermatology / topical
    // ---------------------------------------------------------------
    _m('med_133', 'Fucidin Cream', 'Fusidic Acid', 'Leo Pharma', 'Dermatology',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Tube 5g', 2600),
    _m('med_134', 'Panderm Plus Cream', 'Betamethasone + Clotrimazole + Neomycin',
        'Johnson & Johnson', 'Dermatology', _hsnGeneral, 12.0, ScheduleType.scheduleH,
        'Tube 15g', 4800),
    _m('med_135', 'Cetaphil Gentle Cleanser', 'Moisturizing Cleanser', 'Galderma India',
        'Dermatology', _hsnGeneral, 12.0, ScheduleType.otc, '125ml Bottle', 42500),
    _m('med_136', 'Itch Guard Cream', 'Clotrimazole + Beclomethasone', 'Reckitt Benckiser',
        'Dermatology', _hsnGeneral, 12.0, ScheduleType.otc, 'Tube 15g', 6500),
    _m('med_137', 'T-Bact Ointment', 'Mupirocin 2%', 'GSK Pharmaceuticals', 'Dermatology',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Tube 5g', 9500),

    // ---------------------------------------------------------------
    // More antifungal
    // ---------------------------------------------------------------
    _m('med_138', 'Terbinafine 250mg', 'Terbinafine Hydrochloride', 'Novartis India',
        'Antifungal', _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 7', 8500),
    _m('med_139', 'Ketoconazole Shampoo', 'Ketoconazole 2%', 'Johnson & Johnson',
        'Antifungal', _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, '60ml Bottle', 16500),

    // ---------------------------------------------------------------
    // More ophthalmology
    // ---------------------------------------------------------------
    _m('med_140', 'Ciplox Eye Drops', 'Ciprofloxacin 0.3%', 'Cipla', 'Ophthalmology',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10ml Bottle', 2800),
    _m('med_141', 'Genteal Eye Gel', 'Hypromellose', 'Alcon India', 'Ophthalmology',
        _hsnGeneral, 12.0, ScheduleType.otc, '10g Tube', 15500),
    _m('med_142', 'Combigan Eye Drops', 'Brimonidine + Timolol', 'Allergan India',
        'Ophthalmology', _hsnGeneral, 12.0, ScheduleType.scheduleH, '5ml Bottle', 42500),

    // ---------------------------------------------------------------
    // ENT
    // ---------------------------------------------------------------
    _m('med_143', 'Otrivin Nasal Drops', 'Xylometazoline', 'GSK Pharmaceuticals', 'ENT',
        _hsnGeneral, 12.0, ScheduleType.otc, '10ml Bottle', 7500),
    _m('med_144', 'Candibiotic Ear Drops',
        'Clotrimazole + Lidocaine + Beclomethasone + Chloramphenicol', 'Wockhardt', 'ENT',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '6ml Bottle', 8900),
    _m('med_145', 'Waxolve Ear Drops', 'Turpentine Oil + Chlorobutanol',
        'Wallace Pharmaceuticals', 'ENT', _hsnGeneral, 12.0, ScheduleType.otc,
        '10ml Bottle', 6200),

    // ---------------------------------------------------------------
    // More pediatric
    // ---------------------------------------------------------------
    _m('med_146', 'T-Minic Drops', 'Phenylephrine + Chlorpheniramine', 'Pfizer Limited',
        'Pediatric', _hsnGeneral, 12.0, ScheduleType.otc, '15ml Bottle', 5800),
    _m('med_147', 'Polybion Syrup', 'Vitamin B Complex', 'Merck Limited', 'Pediatric',
        _hsnGeneral, 12.0, ScheduleType.otc, '200ml Bottle', 8900),
    _m('med_148', 'Crocin Infant Drops', 'Paracetamol 100mg/ml', 'GSK Pharmaceuticals',
        'Pediatric', _hsnGeneral, 12.0, ScheduleType.otc, '15ml Bottle', 3800),

    // ---------------------------------------------------------------
    // More women's health
    // ---------------------------------------------------------------
    _m('med_149', 'Susten 200 Capsule', 'Progesterone 200mg', 'Sun Pharma', 'Women\'s Health',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 9800),
    _m('med_150', 'Folinine Tablet', 'Folic Acid 5mg', 'Alkem Laboratories', 'Women\'s Health',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 20', 1800),
    _m('med_151', 'Fertab-M Tablet', 'Folic Acid + Methylcobalamin', 'Mankind Pharma',
        'Women\'s Health', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 15', 4600),

    // ---------------------------------------------------------------
    // More neuro/psychiatry — Schedule H / H1
    // ---------------------------------------------------------------
    _m('med_152', 'Amitriptyline 25mg', 'Amitriptyline Hydrochloride', 'Sun Pharma',
        'Neuro/Psychiatry', _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 1900),
    _m('med_153', 'Pregabalin 75mg', 'Pregabalin', 'Pfizer Limited', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH1, 'Strip of 10', 11800),
    _m('med_154', 'Risperidone 2mg', 'Risperidone', 'Sun Pharma', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 4800),
    _m('med_155', 'Divalproex 500mg (Encorate)', 'Sodium Valproate', 'Sun Pharma',
        'Neuro/Psychiatry', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 8500),

    // ---------------------------------------------------------------
    // Urology
    // ---------------------------------------------------------------
    _m('med_156', 'Tamsulosin 0.4mg', 'Tamsulosin Hydrochloride', 'Cipla', 'Urology',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Capsules Strip', 5200),
    _m('med_157', 'Veltam Plus Tablet', 'Tamsulosin + Dutasteride', 'Mankind Pharma', 'Urology',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 18500),
    _m('med_158', 'Cital Syrup', 'Potassium Citrate', 'Blue Cross Laboratories', 'Urology',
        _hsnGeneral, 12.0, ScheduleType.otc, '200ml Bottle', 8900),

    // ---------------------------------------------------------------
    // Muscle relaxant / orthopedic
    // ---------------------------------------------------------------
    _m('med_159', 'Myospaz Tablet', 'Thiocolchicoside 4mg + Aceclofenac 100mg',
        'Blue Cross Laboratories', 'Orthopedic', _hsnGeneral, 12.0, ScheduleType.scheduleH,
        'Strip of 10', 7500),
    _m('med_160', 'Flexura-MR Tablet', 'Chlorzoxazone + Diclofenac + Paracetamol',
        'Mankind Pharma', 'Orthopedic', _hsnGeneral, 12.0, ScheduleType.scheduleH,
        'Strip of 10', 6800),
    _m('med_161', 'Calcirol Sachet', 'Cholecalciferol 60000 IU', 'Cadila Pharmaceuticals',
        'Orthopedic', _hsnGeneral, 12.0, ScheduleType.otc, '4 Sachets Box', 9200),

    // ---------------------------------------------------------------
    // Antiparasitic
    // ---------------------------------------------------------------
    _m('med_162', 'Albendazole 400mg', 'Albendazole', 'GSK Pharmaceuticals', 'Antiparasitic',
        _hsnGeneral, 12.0, ScheduleType.otc, '1 Tablet', 1500),
    _m('med_163', 'Ivermectin 12mg', 'Ivermectin', 'Mankind Pharma', 'Antiparasitic',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 4', 4200),

    // ---------------------------------------------------------------
    // Antiemetic
    // ---------------------------------------------------------------
    _m('med_164', 'Ondansetron 4mg', 'Ondansetron', 'Sun Pharma', 'Antiemetic',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Tablets Strip', 3600),
    _m('med_165', 'Emeset MD 4 Tablet', 'Ondansetron 4mg', 'Cipla', 'Antiemetic',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 3900),

    // ---------------------------------------------------------------
    // First aid / antiseptic
    // ---------------------------------------------------------------
    _m('med_166', 'Dettol Antiseptic Liquid', 'Chloroxylenol', 'Reckitt Benckiser', 'First Aid',
        _hsnGeneral, 18.0, ScheduleType.otc, '100ml Bottle', 7500),
    _m('med_167', 'Betadine Ointment', 'Povidone Iodine 5%', 'Win-Medicare', 'First Aid',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Tube 20g', 9500),
    _m('med_168', 'Savlon Antiseptic Liquid', 'Chlorhexidine + Cetrimide', 'Johnson & Johnson',
        'First Aid', _hsnGeneral, 18.0, ScheduleType.otc, '100ml Bottle', 8200),
    _m('med_169', 'Burnol Cream', 'Povidone Iodine', 'Dr. Reddy\'s Laboratories', 'First Aid',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Tube 20g', 4500),
    _m('med_170', 'Band-Aid Strips', 'Adhesive Bandages', 'Johnson & Johnson', 'First Aid',
        _hsnGeneral, 12.0, ScheduleType.otc, 'Box of 20', 5500),

    // ---------------------------------------------------------------
    // More cold & flu
    // ---------------------------------------------------------------
    _m('med_171', 'Sinarest Tablet', 'Paracetamol + Phenylephrine + Chlorpheniramine',
        'Centaur Pharmaceuticals', 'Respiratory', _hsnGeneral, 12.0, ScheduleType.otc,
        'Strip of 10', 2600),
    _m('med_172', 'Cheston Cold Tablet', 'Cetirizine + Phenylephrine + Paracetamol',
        'Cipla', 'Respiratory', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 10', 2800),
    _m('med_173', 'D Cold Total Tablet', 'Paracetamol + Phenylephrine + Chlorpheniramine + Caffeine',
        'Reckitt Benckiser', 'Respiratory', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 10', 2900),
    _m('med_174', 'Vicks Action 500 Tablet', 'Paracetamol + Phenylephrine + Caffeine',
        'Procter & Gamble Health', 'Respiratory', _hsnGeneral, 12.0, ScheduleType.otc,
        'Strip of 10', 2700),

    // ---------------------------------------------------------------
    // More gastro / antacid
    // ---------------------------------------------------------------
    _m('med_175', 'Gelusil Tablet', 'Magnesium Hydroxide + Aluminium Hydroxide + Simethicone',
        'Sun Pharma', 'Gastro', _hsnGeneral, 12.0, ScheduleType.otc, 'Strip of 15', 3200),
    _m('med_176', 'Gaviscon Suspension', 'Sodium Alginate + Sodium Bicarbonate', 'Reckitt Benckiser',
        'Gastro', _hsnGeneral, 12.0, ScheduleType.otc, '200ml Bottle', 14500),
    _m('med_177', 'Sompraz 40 Tablet', 'Esomeprazole 40mg', 'Sun Pharma', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 15800),
    _m('med_178', 'Loperamide 2mg', 'Loperamide Hydrochloride', 'Cipla', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '10 Capsules Strip', 2100),
    _m('med_179', 'Econorm Sachet', 'Saccharomyces Boulardii', 'Biocodex India', 'Gastro',
        _hsnGeneral, 12.0, ScheduleType.otc, '6 Sachets Box', 10500),

    // ---------------------------------------------------------------
    // More women's health / contraceptives
    // ---------------------------------------------------------------
    _m('med_180', 'Unwanted-72', 'Levonorgestrel 1.5mg', 'Mankind Pharma', 'Women\'s Health',
        _hsnGeneral, 12.0, ScheduleType.otc, '1 Tablet', 9200),
    _m('med_181', 'Mala-D Tablet', 'Ethinylestradiol + Levonorgestrel', 'Government of India (HLL)',
        'Women\'s Health', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 28', 500),
    _m('med_182', 'Duphaston Tablet', 'Dydrogesterone 10mg', 'Abbott India', 'Women\'s Health',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 29500),
    _m('med_183', 'Pregnews Kit', 'Urine Pregnancy Test', 'Span Diagnostics', 'Women\'s Health',
        _hsnGeneral, 12.0, ScheduleType.otc, '1 Kit', 4000),

    // ---------------------------------------------------------------
    // More pediatric
    // ---------------------------------------------------------------
    _m('med_184', 'Woodward\'s Gripe Water', 'Dill Oil', 'Pfizer Limited', 'Pediatric',
        _hsnGeneral, 12.0, ScheduleType.otc, '130ml Bottle', 6500),
    _m('med_185', 'Cremaffin Syrup', 'Liquid Paraffin + Milk of Magnesia', 'Abbott India',
        'Pediatric', _hsnGeneral, 12.0, ScheduleType.otc, '225ml Bottle', 12500),
    _m('med_186', 'Ondem MD 4 Syrup', 'Ondansetron 2mg/5ml', 'Alkem Laboratories', 'Pediatric',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '30ml Bottle', 4800),

    // ---------------------------------------------------------------
    // More diabetes
    // ---------------------------------------------------------------
    _m('med_187', 'Istamet Tablet', 'Sitagliptin 50mg + Metformin 500mg', 'MSD Pharmaceuticals',
        'Diabetes', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 24500),
    _m('med_188', 'Januvia 100 Tablet', 'Sitagliptin Phosphate 100mg', 'MSD Pharmaceuticals',
        'Diabetes', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 7', 34500),
    _m('med_189', 'Dapavis 10 Tablet', 'Dapagliflozin 10mg', 'Sun Pharma', 'Diabetes',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 18500),
    _m('med_190', 'Lantus Solostar Injection', 'Insulin Glargine', 'Sanofi India', 'Diabetes',
        _hsnGeneral, 5.0, ScheduleType.scheduleH, '1 Pen', 48500),

    // ---------------------------------------------------------------
    // More cardiac
    // ---------------------------------------------------------------
    _m('med_191', 'Dytor 10 Tablet', 'Torsemide 10mg', 'Cipla', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 7200),
    _m('med_192', 'Cardivas 6.25 Tablet', 'Carvedilol 6.25mg', 'Sun Pharma', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 3800),
    _m('med_193', 'Met XL 25 Tablet', 'Metoprolol Succinate 25mg', 'Alkem Laboratories', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 15', 4500),
    _m('med_194', 'Olmesar 20 Tablet', 'Olmesartan Medoxomil 20mg', 'Micro Labs', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 8200),
    _m('med_195', 'Cilacar 10 Tablet', 'Cilnidipine 10mg', 'Sun Pharma', 'Cardiac',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 9500),

    // ---------------------------------------------------------------
    // More ophthalmology / ENT
    // ---------------------------------------------------------------
    _m('med_196', 'Moxicip Eye Drops', 'Moxifloxacin 0.5%', 'Cipla', 'Ophthalmology',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '5ml Bottle', 7800),
    _m('med_197', 'Tobramycin Eye Drops', 'Tobramycin 0.3%', 'Alcon India', 'Ophthalmology',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, '5ml Bottle', 6500),
    _m('med_198', 'Nasivion Nasal Drops', 'Oxymetazoline', 'Abbott India', 'ENT',
        _hsnGeneral, 12.0, ScheduleType.otc, '10ml Bottle', 6800),
    _m('med_199', 'Sofradex Ear Drops', 'Framycetin + Gramicidin + Dexamethasone', 'Sanofi India',
        'ENT', _hsnGeneral, 12.0, ScheduleType.scheduleH, '8ml Bottle', 9500),

    // ---------------------------------------------------------------
    // More antiparasitic / antibiotic
    // ---------------------------------------------------------------
    _m('med_200', 'Zentel 400 Tablet', 'Albendazole 400mg', 'GSK Pharmaceuticals', 'Antiparasitic',
        _hsnGeneral, 12.0, ScheduleType.otc, '1 Tablet', 1800),
    _m('med_201', 'Zithrox 500 Tablet', 'Azithromycin 500mg', 'Macleods Pharmaceuticals',
        'Antibiotics', _hsnOtherAntibiotic, 12.0, ScheduleType.scheduleH, 'Strip of 3', 8200),
    _m('med_202', 'Augmentin Duo Syrup', 'Amoxicillin + Clavulanic Acid (Paediatric)',
        'GSK Pharmaceuticals', 'Antibiotics', _hsnPenicillin, 12.0, ScheduleType.scheduleH,
        '30ml Bottle', 12500),

    // ---------------------------------------------------------------
    // Pain balm / topical
    // ---------------------------------------------------------------
    _m('med_203', 'Iodex Balm', 'Methyl Salicylate + Menthol', 'Mankind Pharma', 'Topical',
        _hsnGeneral, 12.0, ScheduleType.otc, '40g Jar', 9500),
    _m('med_204', 'Tiger Balm Red', 'Camphor + Menthol + Clove Oil', 'Tiger Balm (Haw Par)',
        'Topical', _hsnGeneral, 12.0, ScheduleType.otc, '19g Jar', 11000),
    _m('med_205', 'Zandu Balm', 'Camphor + Menthol + Eucalyptus Oil', 'Emami Limited', 'Topical',
        _hsnGeneral, 12.0, ScheduleType.otc, '25ml Bottle', 8500),

    // ---------------------------------------------------------------
    // More thyroid / steroid
    // ---------------------------------------------------------------
    _m('med_206', 'Eltroxin 50mcg', 'Thyroxine Sodium 50mcg', 'GSK Pharmaceuticals', 'Supplements',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 100', 16800),
    _m('med_207', 'Omnacortil 10 Tablet', 'Prednisolone 10mg', 'Macleods Pharmaceuticals',
        'Neuro/Psychiatry', _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 10', 2800),
    _m('med_208', 'Wysolone 5 Tablet', 'Prednisolone 5mg', 'Pfizer Limited', 'Neuro/Psychiatry',
        _hsnGeneral, 12.0, ScheduleType.scheduleH, 'Strip of 20', 3200),

    // ---------------------------------------------------------------
    // Nutrition / supplements
    // ---------------------------------------------------------------
    _m('med_209', 'Ensure Diabetes Care Powder', 'Balanced Nutrition for Diabetics', 'Abbott India',
        'Supplements', _hsnGeneral, 12.0, ScheduleType.otc, '400g Tin', 62000),
    _m('med_210', 'Pediasure Powder', 'Pediatric Nutrition Supplement', 'Abbott India',
        'Pediatric', _hsnGeneral, 12.0, ScheduleType.otc, '400g Tin', 58500),
    _m('med_211', 'Protinex Powder', 'Protein Supplement', 'Danone India', 'Supplements',
        _hsnGeneral, 12.0, ScheduleType.otc, '400g Jar', 42500),
    _m('med_212', 'Horlicks Growth+ Powder', 'Malted Food with Multivitamins', 'HUL',
        'Pediatric', _hsnGeneral, 12.0, ScheduleType.otc, '400g Jar', 25500),
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
      storeId: '',
      catalogueId: id,
      name: name,
      genericName: generic,
      manufacturer: manufacturer,
      type: type,
      packSizeLabel: packSizeLabel,
      unitsPerPack: PackUnits.fromLabel(packSizeLabel),
      hsnCode: hsnCode,
      gstRate: gstRate,
      scheduleType: scheduleType,
      minStock: 2 * PackUnits.fromLabel(packSizeLabel),
      shelfLocation: '',
      updatedAt: DateTime(2026, 9, 1),
    );
  }

  int get length => _seedMedicines.length;

  CatalogueEntry? byId(String id) {
    final m = _seedMedicines.where((m) => m.id == id).firstOrNull;
    return m == null ? null : CatalogueEntry(medicine: m, referenceMrpPaise: referenceMrpFor(id));
  }

  int referenceMrpFor(String catalogueId) {
    // _referenceMrpPaise is filled while _seedMedicines is first built.
    if (_seedMedicines.isEmpty) return 0;
    return _referenceMrpPaise[catalogueId] ?? 0;
  }

  /// Case-insensitive match on brand or generic name. Empty query → all.
  List<CatalogueEntry> search(String query) {
    final q = query.trim().toLowerCase();
    return _seedMedicines
        .where((m) =>
            q.isEmpty ||
            m.name.toLowerCase().contains(q) ||
            m.genericName.toLowerCase().contains(q) ||
            m.manufacturer.toLowerCase().contains(q))
        .map((m) => CatalogueEntry(medicine: m, referenceMrpPaise: referenceMrpFor(m.id)))
        .toList();
  }
}
