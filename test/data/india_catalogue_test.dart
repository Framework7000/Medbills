import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/data/repositories/india_catalogue.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';

const _tsv = 'az_1\tAugmentin 625 Duo Tablet\tamoxicillin 500mg + clavulanic acid 125mg\tGlaxo SmithKline Pharmaceuticals Ltd\tstrip of 10 tablets\t10\t22342\t2022-11\tUNKNOWN\t5\t300410\n'
    'az_2\tDolo 650 Tablet\tparacetamol 650mg\tMicro Labs Ltd\tstrip of 15 tablets\t15\t3427\t2022-11\tUNKNOWN\t5\t300490\n'
    'az_3\tTaxim-O 200 Tablet\tcefixime 200mg\tAlkem Laboratories Ltd\tstrip of 10 tablets\t10\t10850\t2022-11\tH1\t5\t300420\n'
    'az_4\tCalpol 650 Tablet\tparacetamol 650mg\tGlaxo SmithKline Pharmaceuticals Ltd\tstrip of 15 tablets\t15\t3000\t2022-11\tUNKNOWN\t5\t300490\n';
const _aliases = 'amoxycillin\tamoxicillin\nacetaminophen\tparacetamol\npcm\tparacetamol\n';

void main() {
  final cat = IndiaCatalogue.fromTsv(_tsv, _aliases);

  test('reads every field into a medicine with its reference MRP', () {
    final e = cat.byId('az_3')!;
    expect(e.medicine.name, 'Taxim-O 200 Tablet');
    expect(e.medicine.genericName, 'Cefixime 200mg');
    expect(e.medicine.scheduleType, ScheduleType.scheduleH1);
    expect(e.medicine.unitsPerPack, 10);
    expect(e.medicine.gstRate, 5.0);
    expect(e.medicine.hsnCode, '300420');
    expect(e.medicine.catalogueId, 'az_3');
    expect(e.referenceMrpPaise, 10850);
  });

  test('finds by brand, ignoring spaces and hyphens, brand-starts first', () {
    expect(cat.search('dolo650').map((e) => e.medicine.name), ['Dolo 650 Tablet']);
    expect(cat.search('taxim o').single.medicine.id, 'az_3');
    expect(cat.search('650').first.medicine.name, isNot(contains('Augmentin')));
  });

  test('finds by salt under any of its names, and by maker', () {
    expect(cat.search('amoxycillin').single.medicine.name, 'Augmentin 625 Duo Tablet');
    expect(cat.search('acetaminophen').map((e) => e.medicine.name), containsAll(['Dolo 650 Tablet', 'Calpol 650 Tablet']));
    expect(cat.search('pcm 650'), hasLength(2));
    expect(cat.search('glaxo').length, 2);
  });

  test('a printed brand finds its medicine; a vague one finds nothing', () {
    expect(cat.byBrand('Dolo 650')!.medicine.id, 'az_2');
    expect(cat.byBrand('Do'), isNull);
    expect(cat.byBrand('Crocin'), isNull);
  });

  test('the bundled file loads and searches quickly', () {
    final file = File('assets/catalogue/india.tsv.gz');
    if (!file.existsSync()) return;
    final load = Stopwatch()..start();
    final real = IndiaCatalogue.fromAssets((file.readAsBytesSync(), File('assets/catalogue/aliases.tsv').readAsStringSync()));
    load.stop();
    expect(real.length, greaterThan(200000));
    final search = Stopwatch()..start();
    final dolo = real.search('dolo 650');
    search.stop();
    expect(dolo.first.medicine.name, startsWith('Dolo 650'));
    expect(real.search('augmentin 625').first.medicine.genericName, contains('Amoxicillin'));
    // ignore: avoid_print
    print('India catalogue: ${real.length} medicines, loaded in ${load.elapsedMilliseconds} ms, '
        'searched in ${search.elapsedMilliseconds} ms');
    expect(search.elapsedMilliseconds, lessThan(1500));
  });
}
