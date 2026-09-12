import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';
import 'package:nuskha_pms/domain/services/schedule_h1_compliance.dart';

void main() {
  group('ScheduleH1Compliance', () {
    test('requiresPrescriberCapture is false for OTC-only carts', () {
      expect(
        ScheduleH1Compliance.requiresPrescriberCapture([ScheduleType.otc, ScheduleType.scheduleH]),
        isFalse,
      );
    });

    test('requiresPrescriberCapture is true when any item is Schedule H1', () {
      expect(
        ScheduleH1Compliance.requiresPrescriberCapture([ScheduleType.otc, ScheduleType.scheduleH1]),
        isTrue,
      );
    });

    test('blocksSale is false for a non-H1 cart with no details', () {
      expect(
        ScheduleH1Compliance.blocksSale(scheduleTypes: [ScheduleType.otc], details: null),
        isFalse,
      );
    });

    test('blocksSale is true for an H1 cart with no details', () {
      expect(
        ScheduleH1Compliance.blocksSale(scheduleTypes: [ScheduleType.scheduleH1], details: null),
        isTrue,
      );
    });

    test('blocksSale is true for an H1 cart with incomplete details', () {
      const incomplete = PrescriberDetails(
        patientName: 'Ramesh Kumar',
        patientPhone: '',
        doctorName: 'Dr. Sharma',
        doctorRegistrationNumber: 'MP12345',
      );
      expect(
        ScheduleH1Compliance.blocksSale(
          scheduleTypes: [ScheduleType.scheduleH1],
          details: incomplete,
        ),
        isTrue,
      );
    });

    test('blocksSale is false for an H1 cart with complete details', () {
      const complete = PrescriberDetails(
        patientName: 'Ramesh Kumar',
        patientPhone: '9876543210',
        doctorName: 'Dr. Sharma',
        doctorRegistrationNumber: 'MP12345',
      );
      expect(
        ScheduleH1Compliance.blocksSale(
          scheduleTypes: [ScheduleType.scheduleH1],
          details: complete,
        ),
        isFalse,
      );
    });
  });
}
