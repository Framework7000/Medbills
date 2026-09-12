import '../models/schedule_type.dart';

/// Patient and prescriber details captured for a Schedule H1 sale.
///
/// Rule 9: Schedule H1 sales are hard-blocked until this is captured — not
/// a dismissible warning. India's CDSCO H1 amendment (2014) requires
/// retail pharmacies to log the patient and the prescribing doctor's name
/// and registration number for every H1 dispense, retained for 3 years
/// (mirrored in state pharmacy-council rules, e.g. the Madhya Pradesh drug
/// inspectorate register).
class PrescriberDetails {
  final String patientName;
  final String patientPhone;
  final String doctorName;
  final String doctorRegistrationNumber;

  const PrescriberDetails({
    required this.patientName,
    required this.patientPhone,
    required this.doctorName,
    required this.doctorRegistrationNumber,
  });

  bool get isComplete =>
      patientName.trim().isNotEmpty &&
      patientPhone.trim().isNotEmpty &&
      doctorName.trim().isNotEmpty &&
      doctorRegistrationNumber.trim().isNotEmpty;
}

class ScheduleH1Compliance {
  /// True if any of the given schedules requires prescriber capture before
  /// the sale can complete.
  static bool requiresPrescriberCapture(Iterable<ScheduleType> scheduleTypes) {
    return scheduleTypes.any((s) => s.isScheduleH1);
  }

  /// A sale is blocked if H1 capture is required but the details provided
  /// (if any) are missing or incomplete.
  static bool blocksSale({
    required Iterable<ScheduleType> scheduleTypes,
    required PrescriberDetails? details,
  }) {
    if (!requiresPrescriberCapture(scheduleTypes)) return false;
    return details == null || !details.isComplete;
  }
}
