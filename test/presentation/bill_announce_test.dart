import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/bill_scan.dart';
import 'package:nuskha_pms/presentation/app.dart';
import 'package:nuskha_pms/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A supplier bill photographed on the phone is announced on the counter
/// computer at once, with a button straight to its review.
void main() {
  testWidgets('a bill saved from the phone pops up on the computer with Review', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1440, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
      await tester.pumpAndSettle();
      expect(find.textContaining('New supplier bill'), findsNothing); // nothing new at start

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final repo = container.read(repositoryProvider)!;
      await tester.runAsync(() => repo.createBillScan(
            draft: const BillDraft(supplierName: 'Shree Sai Pharma', invoiceNumber: 'SSP/0456'),
            ocrText: 'photographed on the phone',
          ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.textContaining('New supplier bill'), findsOneWidget);
      expect(find.textContaining('SSP/0456'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Review'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
