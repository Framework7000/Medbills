import '../models/medicine.dart';
import '../models/schedule_type.dart';

/// One medicine whose stored GST rate or schedule is out of date.
class MasterCorrection {
  final Medicine current;
  final Medicine corrected;

  const MasterCorrection(this.current, this.corrected);

  bool get gstChanged => current.gstRate != corrected.gstRate;
  bool get scheduleChanged => current.scheduleType != corrected.scheduleType;

  String get summary => [
        if (gstChanged) 'GST ${_pct(current.gstRate)} → ${_pct(corrected.gstRate)}',
        if (scheduleChanged) '${current.scheduleType.label} → ${corrected.scheduleType.label}',
      ].join(' · ');

  static String _pct(double r) => '${r == r.roundToDouble() ? r.toInt() : r}%';
}

/// Finds store medicines that need updating after a rule change:
///
/// - **GST:** the 12% slab was removed on 22-09-2025 and medicines moved to
///   5%. A medicine still at 12% gets its catalogue rate, or 5% if it isn't
///   from the catalogue.
/// - **Schedule:** a catalogue entry that is stricter than the store's copy
///   wins (e.g. cefixime H → H1). A stricter or Unclassified store value is
///   left alone: that was the pharmacist's decision (Rule 11).
///
/// Past sales keep the rate they were billed at; this only changes the
/// master used for new bills.
List<MasterCorrection> findMasterCorrections(
  Iterable<Medicine> storeMedicines,
  Medicine? Function(String catalogueId) catalogueLookup,
) {
  final out = <MasterCorrection>[];
  for (final m in storeMedicines) {
    final master = m.catalogueId == null ? null : catalogueLookup(m.catalogueId!);
    var gst = m.gstRate;
    if (gst == 12.0) gst = (master != null && master.gstRate != 12.0) ? master.gstRate : 5.0;
    var schedule = m.scheduleType;
    if (master != null &&
        schedule != ScheduleType.unknown &&
        _strictness(master.scheduleType) > _strictness(schedule)) {
      schedule = master.scheduleType;
    }
    if (gst != m.gstRate || schedule != m.scheduleType) {
      out.add(MasterCorrection(m, m.copyWith(gstRate: gst, scheduleType: schedule)));
    }
  }
  return out;
}

int _strictness(ScheduleType s) => switch (s) {
      ScheduleType.otc => 0,
      ScheduleType.scheduleH => 1,
      ScheduleType.scheduleH1 => 2,
      ScheduleType.scheduleX => 3,
      ScheduleType.unknown => -1,
    };
