import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/presentation/app.dart';
import 'package:nuskha_pms/presentation/purchases/purchases_screen.dart';

/// desktop_drop's own OS drag source can't be driven from a widget test, so
/// these call the DropTarget's callbacks directly — exactly what the plugin
/// does internally once a real drag event arrives — to check the screen's
/// own wiring (hover feedback, unsupported-file rejection).
void main() {
  testWidgets('a bill photo can be dropped onto the Purchases window on desktop, with hover feedback', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      tester.view.physicalSize = const Size(1440, 900) * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Purchases'));
      await tester.pumpAndSettle();
      expect(find.byType(PurchasesScreen), findsOneWidget);

      final dropTarget = tester.widget<DropTarget>(find.byType(DropTarget));
      expect(find.text('Drop to add as a supplier bill'), findsNothing);

      dropTarget.onDragEntered!(DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero));
      await tester.pump();
      expect(find.text('Drop to add as a supplier bill'), findsOneWidget);

      dropTarget.onDragExited!(DropEventDetails(localPosition: Offset.zero, globalPosition: Offset.zero));
      await tester.pump();
      expect(find.text('Drop to add as a supplier bill'), findsNothing);

      // A non-image file is rejected before any attempt to read it.
      dropTarget.onDragDone!(DropDoneDetails(
        files: [DropItemFile('/tmp/not-an-image.pdf')],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('isn\'t one'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a phone has no drop target — Purchases renders its usual content directly', (tester) async {
    // Default test platform is already mobile (DeviceFeatures.isPhone) —
    // just widen the window so "Purchases" is a direct rail tap, same as
    // the desktop test above, rather than behind phone-layout's "More".
    tester.view.physicalSize = const Size(1440, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Purchases'));
    await tester.pumpAndSettle();
    expect(find.byType(PurchasesScreen), findsOneWidget);
    expect(find.byType(DropTarget), findsNothing);
  });
}
