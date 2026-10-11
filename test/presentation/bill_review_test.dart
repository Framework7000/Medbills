import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/data/repositories/global_catalogue_repository.dart';
import 'package:nuskha_pms/domain/models/bill_scan.dart';
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
  for (final size in const [Size(375, 667), Size(1440, 900)]) {
    testWidgets('a scanned bill is checked and received into stock (${size.width.toInt()} wide)', (tester) async {
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final repo = container.read(repositoryProvider)!;
      final medicines = GlobalCatalogueRepository().search('').map((e) => e.medicine).toList();
      final draft = SupplierBillParser.parse(OcrPage.fromText(_bill), medicines);
      expect(draft.lines, hasLength(2));
      final scan = (await tester.runAsync(() => repo.createBillScan(draft: draft, ocrText: _bill)))!;

      Navigator.of(tester.element(find.byType(Scaffold).first))
          .push(MaterialPageRoute<void>(builder: (_) => BillReviewScreen(scanId: scan.id)));
      await tester.pumpAndSettle();
      expect(find.text('Shree Sai Pharma Distributors'), findsOneWidget);
      expect(find.text('Dolo 650 Tablet'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Receive 2 lines into stock'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Receive'));
      await tester.pumpAndSettle();

      final batches = (await tester.runAsync(() => repo.watchBatches().first))!;
      final dolo = batches.singleWhere((b) => b.batchNumber == 'DOBS3975');
      expect(dolo.medicineId, 'med_002');
      expect(dolo.quantity, 22 * 15); // 20 paid + 2 free strips of 15
      expect(dolo.mrpPaise, 3360);
      final saved = (await tester.runAsync(() => repo.watchBillScans().first))!.single;
      expect(saved.status, BillScanStatus.received);
      expect(saved.receivedLines, 2);
      expect(find.text('Received into stock'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }
}
