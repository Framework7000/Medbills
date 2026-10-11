import '../models/schedule_type.dart';

/// Rule 9 / Rule 11 checks the counter runs *before* asking the backend to
/// complete a sale, so the pharmacist is prompted for what's missing up front.
/// The backend re-checks the same rules authoritatively (CheckoutEngine).
class ScheduleCompliance {
  /// Schedule H1 and X sales need the patient + prescriber register entry.
  static bool requiresPrescriptionRecord(Iterable<ScheduleType> schedules) =>
      schedules.any((s) => s.requiresRegisterEntry);

  /// Unclassified medicines may not be sold until a pharmacist classifies them.
  static bool hasUnclassified(Iterable<ScheduleType> schedules) =>
      schedules.any((s) => !s.isSellable);
}
