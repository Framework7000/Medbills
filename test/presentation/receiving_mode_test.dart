import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/presentation/app.dart';
import 'package:nuskha_pms/presentation/purchases/bill_scan_screen.dart';
import 'package:nuskha_pms/presentation/scan/scan_billing.dart';
import 'package:nuskha_pms/state/providers.dart';

/// Camera capture itself isn't testable here (ImagePicker/OCR are platform
/// plugins) — these drive the receiving draft directly, the way
/// smartPhotoCapture does once a pack is read, and check the surrounding
/// UI and hand-off to BillReviewScreen.
void main() {
  testWidgets('switching to Receiving builds a draft and hands it to bill review, selling is unaffected', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.byType(ScanModeToggle), findsOneWidget);
    // Selling is the default — no receiving summary, no draft yet.
    expect(find.byType(ReceivingSummary), findsNothing);
    expect(container.read(receivingDraftProvider).lines, isEmpty);

    await tester.tap(find.text('Receiving'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceivingSummary), findsOneWidget);
    expect(find.textContaining('Scan packs from a delivery'), findsOneWidget);

    // Two packs of one medicine/batch, one of another — as smartPhotoCapture
    // would add them while scanning a delivery.
    container.read(receivingDraftProvider.notifier).addPack(
          medicineId: 'med_002',
          medicineName: 'Dolo 650 Tablet',
          batchNumber: 'DOBS3975',
          expiryMonth: 5,
          expiryYear: 2027,
          mrpPaise: 3360,
        );
    container.read(receivingDraftProvider.notifier).addPack(
          medicineId: 'med_002',
          medicineName: 'Dolo 650 Tablet',
          batchNumber: 'DOBS3975',
          expiryMonth: 5,
          expiryYear: 2027,
          mrpPaise: 3360,
        );
    container.read(receivingDraftProvider.notifier).addPack(
          medicineId: 'med_003',
          medicineName: 'Crocin Advance',
          batchNumber: 'CRN2201',
          expiryMonth: 8,
          expiryYear: 2027,
          mrpPaise: 3000,
        );
    await tester.pump();
    expect(find.text('2 medicines · 3 packs scanned'), findsOneWidget);

    await tester.tap(find.text('Review & receive'));
    await tester.pumpAndSettle();

    // Handed off to the normal bill-review screen, and the phone's own
    // draft is cleared so a fresh delivery can start clean.
    expect(find.byType(BillReviewScreen), findsOneWidget);
    expect(find.text('Dolo 650 Tablet'), findsWidgets);
    expect(find.text('Crocin Advance'), findsWidgets);
    expect(container.read(receivingDraftProvider).lines, isEmpty);

    final saved = (await tester.runAsync(() => container.read(repositoryProvider)!.watchBillScans().first))!.single;
    expect(saved.draft.lines, hasLength(2));
    expect(saved.draft.lines.firstWhere((l) => l.medicineId == 'med_002').packs, 2);

    // Selling still works unchanged: back out and flip the switch back.
    Navigator.of(tester.element(find.byType(BillReviewScreen))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selling'));
    await tester.pumpAndSettle();
    expect(find.byType(ReceivingSummary), findsNothing);
  });
}
