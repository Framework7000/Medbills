import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/scan_link.dart';
import 'package:nuskha_pms/presentation/app.dart';
import 'package:nuskha_pms/state/providers.dart';

void main() {
  testWidgets('sending the phone\'s bill to a counter transfers exact quantities and clears it here', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    final repo = container.read(repositoryProvider)!;

    // A counter is online — created directly, the way a Mac/Windows counter
    // registers itself (not through this phone-mode widget tree).
    final station = ScanStation(
      id: repo.newId(),
      storeId: repo.storeId,
      name: 'Counter 1',
      active: true,
      uid: 'counter-uid',
      updatedAt: DateTime.now(),
    );
    await tester.runAsync(() => repo.saveStation(station));
    await tester.pump();

    // Build a bill on the phone the normal way: search, pick, confirm 2 packs.
    final searchField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search medicine, generic or scan barcode',
    );
    await tester.enterText(searchField, 'Dolo 650');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dolo 650 Tablet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Packs (×15)'), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    final sentLine = container.read(cartProvider).lines.single;
    expect(sentLine.quantity, 2 * 15);

    await tester.tap(find.byTooltip('Send this bill to a counter'));
    await tester.pumpAndSettle();

    // Gone from this phone's own bill — it's the counter's now.
    expect(container.read(cartProvider).lines, isEmpty);
    expect(find.textContaining('Sent 1 line to Counter 1'), findsOneWidget);

    final events = (await tester.runAsync(() => repo.watchScansFor(station.id).first))!;
    final event = events.single;
    expect(event.medicineId, sentLine.medicineId);
    expect(event.batchNumber, sentLine.batchNumber);
    expect(event.units, sentLine.quantity);
  });
}
