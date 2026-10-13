import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/data/repositories/global_catalogue_repository.dart';
import 'package:nuskha_pms/domain/services/ocr_text.dart';
import 'package:nuskha_pms/domain/services/supplier_bill_parser.dart';
import 'package:nuskha_pms/presentation/app.dart';
import 'package:nuskha_pms/presentation/purchases/bill_scan_screen.dart';
import 'package:nuskha_pms/state/providers.dart';

const _bill = '''
SHREE SAI PHARMA DISTRIBUTORS
GSTIN: 23AAKFS1234C1Z9
Invoice No: SSP/2627/0456  Date: 08/10/2026
1  DOLO 650 TAB  15S  DOBS3975  05/27  20  2  33.60  24.19  483.80
2  PAN 40 TAB  15S  PNT24117  11/27  10  155.00  111.60  1116.00
Grand Total 1,599.80''';

void main() {
  testWidgets('receiving the same supplier + bill number twice warns before double-counting stock', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final repo = container.read(repositoryProvider)!;
    final medicines = GlobalCatalogueRepository().search('').map((e) => e.medicine).toList();
    final draft = SupplierBillParser.parse(OcrPage.fromText(_bill), medicines);

    // Receive the bill once, in full.
    final first = (await tester.runAsync(() => repo.createBillScan(draft: draft, ocrText: _bill)))!;
    Navigator.of(tester.element(find.byType(Scaffold).first))
        .push(MaterialPageRoute<void>(builder: (_) => BillReviewScreen(scanId: first.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receive 2 lines into stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Receive'));
    await tester.pumpAndSettle();
    expect(find.text('Already received?'), findsNothing); // nothing to warn about the first time
    Navigator.of(tester.element(find.byType(Scaffold).first)).pop();
    await tester.pumpAndSettle();

    // A second, separate scan of the same supplier + bill number — e.g. the
    // same paper bill photographed again by mistake. One tap of the
    // "Receive into stock" button must show the warning immediately,
    // before the normal confirm dialog.
    final second = (await tester.runAsync(() => repo.createBillScan(draft: draft, ocrText: _bill)))!;
    Navigator.of(tester.element(find.byType(Scaffold).first))
        .push(MaterialPageRoute<void>(builder: (_) => BillReviewScreen(scanId: second.id)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receive 2 lines into stock'));
    await tester.pumpAndSettle();
    expect(find.text('Already received?'), findsOneWidget);

    // Backing out must not receive anything.
    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();
    final purchasesAfterBack = (await tester.runAsync(() => repo.watchRecentPurchases().first))!;
    expect(purchasesAfterBack, hasLength(2)); // only the first scan's two lines

    // Proceeding through the warning does receive it (the pharmacist's call).
    await tester.tap(find.text('Receive 2 lines into stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Receive anyway'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Receive'));
    await tester.pumpAndSettle();
    final purchasesAfterProceed = (await tester.runAsync(() => repo.watchRecentPurchases().first))!;
    expect(purchasesAfterProceed, hasLength(4)); // both scans' lines now recorded
  });
}
