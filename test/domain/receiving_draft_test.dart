import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/presentation/scan/scan_billing.dart';

void main() {
  group('ReceivingDraftNotifier', () {
    test('a second pack of the same medicine and batch merges into one line', () {
      final notifier = ReceivingDraftNotifier();
      notifier.addPack(
          medicineId: 'med_002', medicineName: 'Dolo 650 Tablet', batchNumber: 'DOBS3975', mrpPaise: 3360);
      notifier.addPack(
          medicineId: 'med_002', medicineName: 'Dolo 650 Tablet', batchNumber: 'DOBS3975', mrpPaise: 3360);
      expect(notifier.state.lines, hasLength(1));
      expect(notifier.state.lines.single.packs, 2);
    });

    test('a different batch of the same medicine is its own line', () {
      final notifier = ReceivingDraftNotifier();
      notifier.addPack(medicineId: 'med_002', medicineName: 'Dolo 650 Tablet', batchNumber: 'DOBS3975');
      notifier.addPack(medicineId: 'med_002', medicineName: 'Dolo 650 Tablet', batchNumber: 'DOBS9999');
      expect(notifier.state.lines, hasLength(2));
      expect(notifier.state.lines.every((l) => l.packs == 1), isTrue);
    });

    test('a different medicine is its own line even with no batch read', () {
      final notifier = ReceivingDraftNotifier();
      notifier.addPack(medicineId: 'med_002', medicineName: 'Dolo 650 Tablet');
      notifier.addPack(medicineId: 'med_003', medicineName: 'Crocin Advance');
      expect(notifier.state.lines, hasLength(2));
    });

    test('clear empties the draft', () {
      final notifier = ReceivingDraftNotifier();
      notifier.addPack(medicineId: 'med_002', medicineName: 'Dolo 650 Tablet');
      notifier.clear();
      expect(notifier.state.lines, isEmpty);
    });
  });
}
