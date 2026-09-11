/// Drug schedule classification under Indian pharmacy regulation.
///
/// Rule 11: never default an unclassified drug to [otc]. Unclassified
/// medicines must resolve to [unknown] and be force-classified before sale.
enum ScheduleType {
  otc,
  scheduleH,
  scheduleH1,
  scheduleX,
  unknown;

  bool get requiresPrescription =>
      this == scheduleH || this == scheduleH1 || this == scheduleX;

  bool get isScheduleH1 => this == scheduleH1;

  static ScheduleType fromString(String? value) {
    if (value == null) return ScheduleType.unknown;
    switch (value.trim().toUpperCase()) {
      case 'OTC':
        return ScheduleType.otc;
      case 'SCHEDULE_H':
      case 'SCHEDULE H':
      case 'H':
        return ScheduleType.scheduleH;
      case 'SCHEDULE_H1':
      case 'SCHEDULE H1':
      case 'H1':
        return ScheduleType.scheduleH1;
      case 'SCHEDULE_X':
      case 'SCHEDULE X':
      case 'X':
        return ScheduleType.scheduleX;
      default:
        return ScheduleType.unknown;
    }
  }
}
