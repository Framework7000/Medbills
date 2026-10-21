import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/medicine.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';
import 'package:nuskha_pms/domain/services/master_corrections.dart';

import '../support/fixtures.dart';

void main() {
  Medicine fromCatalogue(String id, {double gst = 12, ScheduleType schedule = ScheduleType.scheduleH}) =>
      medicine(id, gstRate: gst, schedule: schedule).copyWith(catalogueId: 'cat_$id');

  test('12% becomes the catalogue rate, or 5% when not from the catalogue', () {
    final master = {'cat_a': medicine('a', gstRate: 5)};
    final fixes = findMasterCorrections(
      [fromCatalogue('a'), medicine('custom', gstRate: 12)],
      (id) => master[id],
    );
    expect(fixes.map((f) => f.corrected.gstRate), [5.0, 5.0]);
    expect(fixes.first.summary, 'GST 12% → 5%');
  });

  test('a stricter catalogue schedule wins; the pharmacist\'s stricter or Unclassified choice stays', () {
    final master = {
      'cat_cef': medicine('cef', gstRate: 5, schedule: ScheduleType.scheduleH1),
      'cat_strict': medicine('strict', gstRate: 5, schedule: ScheduleType.scheduleH),
      'cat_unk': medicine('unk', gstRate: 5, schedule: ScheduleType.scheduleH1),
    };
    final fixes = findMasterCorrections([
      fromCatalogue('cef', gst: 5, schedule: ScheduleType.scheduleH),
      fromCatalogue('strict', gst: 5, schedule: ScheduleType.scheduleH1),
      fromCatalogue('unk', gst: 5, schedule: ScheduleType.unknown),
    ], (id) => master[id]);
    expect(fixes, hasLength(1));
    expect(fixes.single.current.id, 'cef');
    expect(fixes.single.corrected.scheduleType, ScheduleType.scheduleH1);
    expect(fixes.single.summary, 'Schedule H → Schedule H1');
  });

  test('up-to-date medicines need nothing; 18% items are left alone', () {
    final fixes = findMasterCorrections(
      [medicine('ok', gstRate: 5), medicine('dettol', gstRate: 18)],
      (_) => null,
    );
    expect(fixes, isEmpty);
  });
}
