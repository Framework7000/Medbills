/// Drug schedule classification under the Drugs and Cosmetics Rules, 1945.
///
/// Rule 11: an unclassified medicine is [unknown], never [otc], and cannot be
/// sold until a pharmacist classifies it.
enum ScheduleType {
  otc('OTC', 'OTC'),
  scheduleH('H', 'Schedule H'),
  scheduleH1('H1', 'Schedule H1'),
  scheduleX('X', 'Schedule X'),
  unknown('UNKNOWN', 'Unclassified');

  const ScheduleType(this.code, this.label);

  /// Stable value persisted in the database.
  final String code;
  final String label;

  bool get requiresPrescription =>
      this == scheduleH || this == scheduleH1 || this == scheduleX;

  /// H1 and X sales must record patient + prescriber (Rule 9).
  bool get requiresRegisterEntry => this == scheduleH1 || this == scheduleX;

  bool get isScheduleH1 => this == scheduleH1;

  bool get isSellable => this != unknown;

  static ScheduleType fromString(String? value) {
    if (value == null) return ScheduleType.unknown;
    final normalised = value.trim().toUpperCase().replaceAll(' ', '_');
    switch (normalised) {
      case 'OTC':
        return ScheduleType.otc;
      case 'H':
      case 'SCHEDULE_H':
      case 'SCHEDULEH':
        return ScheduleType.scheduleH;
      case 'H1':
      case 'SCHEDULE_H1':
      case 'SCHEDULEH1':
        return ScheduleType.scheduleH1;
      case 'X':
      case 'SCHEDULE_X':
      case 'SCHEDULEX':
        return ScheduleType.scheduleX;
      default:
        return ScheduleType.unknown;
    }
  }
}
