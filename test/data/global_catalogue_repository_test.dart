import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/data/repositories/global_catalogue_repository.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';

void main() {
  final repo = GlobalCatalogueRepository();
  final all = repo.search('');

  test('search matches brand, generic name or manufacturer', () {
    final results = repo.search('paracetamol');
    expect(results, isNotEmpty);
    expect(
      results.every((e) =>
          e.medicine.name.toLowerCase().contains('paracetamol') ||
          e.medicine.genericName.toLowerCase().contains('paracetamol') ||
          e.medicine.manufacturer.toLowerCase().contains('paracetamol')),
      isTrue,
    );
  });

  test('every catalogue entry is complete and sellable data is consistent', () {
    expect(all.length, repo.length);
    final ids = <String>{};
    for (final e in all) {
      final m = e.medicine;
      expect(ids.add(m.id), isTrue, reason: 'duplicate id ${m.id}');
      expect(m.catalogueId, m.id);
      expect(m.name.trim(), isNotEmpty);
      expect(m.unitsPerPack, greaterThanOrEqualTo(1), reason: m.name);
      // The 12% slab was removed on 22-09-2025; medicines are 5% (or 0%).
      expect([0.0, 5.0, 18.0], contains(m.gstRate), reason: m.name);
      expect(m.hsnCode, matches(RegExp(r'^\d{4,8}$')), reason: m.name);
      expect(e.referenceMrpPaise, greaterThan(0), reason: m.name);
    }
  });

  test('known restricted drugs are classified, never OTC (Rule 11)', () {
    for (final name in ['alprax', 'azithral', 'augmentin']) {
      final hits = repo.search(name);
      for (final e in hits) {
        expect(e.medicine.scheduleType, isNot(ScheduleType.otc), reason: e.medicine.name);
      }
    }
  });

  test('every Schedule H1 salt (GSR 588(E)) is marked H1, never plain H', () {
    const h1Salts = [
      'cefixime', 'ceftriaxone', 'cefpodoxime', 'cefotaxime', 'cefdinir', 'cefepime',
      'cefoperazone', 'ceftazidime', 'levofloxacin', 'moxifloxacin', 'alprazolam',
      'zolpidem', 'tramadol', 'diazepam', 'codeine', 'isoniazid', 'rifampicin',
      'meropenem', 'imipenem', 'pentazocine', 'buprenorphine',
    ];
    for (final e in all) {
      final generic = e.medicine.genericName.toLowerCase();
      for (final salt in h1Salts) {
        if (generic.contains(salt)) {
          expect(e.medicine.scheduleType, anyOf(ScheduleType.scheduleH1, ScheduleType.scheduleX),
              reason: '${e.medicine.name} contains $salt');
        }
      }
    }
  });
}
