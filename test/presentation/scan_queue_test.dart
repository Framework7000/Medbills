import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/scan_link.dart';
import 'package:nuskha_pms/presentation/app.dart';
import 'package:nuskha_pms/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A counter (Mac/Windows) opens a quantity dialog while a phone's scan
/// arrives for the same bill — the scan must still land on the cart, not
/// be dropped or delayed until the dialog closes.
void main() {
  testWidgets('a remote scan is applied to the cart while a quantity dialog is open', (tester) async {
    // Reset synchronously before the test body's Future resolves: the
    // binding checks this is back to null right after, before package:test
    // gets a chance to run any addTearDown/tearDown callback.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      SharedPreferences.setMockInitialValues({});

      tester.view.physicalSize = const Size(1440, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final repo = container.read(repositoryProvider)!;

      // Register this counter to receive phone scans.
      await tester.tap(find.widgetWithText(FilledButton, 'Scan (F3)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use a phone as the scanner'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Start'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Receiving phone scans as'), findsOneWidget);
      final station = (await tester.runAsync(() => repo.watchStations().first))!.single;

      // Open a quantity dialog by picking a medicine from search, and leave it open.
      final searchField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Search medicine, generic or scan barcode',
      );
      await tester.enterText(searchField, 'Dolo');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dolo 650 Tablet'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget); // the quantity dialog is up, unresolved

      // A scan arrives from a phone for this counter while that dialog is still open.
      await tester.runAsync(() => repo.sendScan(ScanEvent(
            id: repo.newId(),
            storeId: repo.storeId,
            stationId: station.id,
            rawBarcode: 'test-remote-scan',
            medicineId: 'med_002',
            deviceLabel: 'iPhone',
            createdBy: 'test-phone-uid',
            createdByName: 'Counter Staff',
            scannedAt: DateTime.now(),
          )));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // It reached the cart immediately — the open dialog neither dropped nor delayed it.
      expect(container.read(cartProvider).lines.any((l) => l.medicineId == 'med_002'), isTrue);

      // Close the still-open dialog without picking a quantity for it.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
