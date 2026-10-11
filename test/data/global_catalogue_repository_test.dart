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
      expect([0.0, 5.0, 12.0, 18.0], contains(m.gstRate), reason: m.name);
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
}
