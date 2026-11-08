import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/presentation/scan/scan_billing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The phone's Smart Scan is one full-screen camera: a close button, the
/// "where scans go" chip and the torch on top, one live instruction and the
/// round shutter at the bottom — nothing else, at every common Android size.
void main() {
  const sizes = {
    'small Android (360×640)': Size(360, 640),
    'common Android (393×851)': Size(393, 851),
    'large Android (412×915)': Size(412, 915),
  };
  for (final entry in sizes.entries) {
    testWidgets('one full-screen camera frame on a ${entry.key}', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = entry.value * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => Center(
                  child: FilledButton(onPressed: () => openSmartScanner(context, ref), child: const Text('open')),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byType(SmartScanChip), findsOneWidget); // where scans go
        expect(find.byTooltip('Close'), findsOneWidget);
        expect(find.byTooltip('Torch'), findsOneWidget);
        expect(find.bySemanticsLabel('Photograph a pack or a bill'), findsOneWidget); // the one shutter
        expect(find.byTooltip('Done'), findsNothing, reason: 'Close is enough');
        expect(find.text('Point the camera at the bill or the medicine pack'), findsOneWidget);
        // No settings panel under the picture any more.
        expect(find.byType(SegmentedButton<ScanMode>), findsNothing);
        expect(tester.takeException(), isNull); // no overflow

        // The chip opens the choices (Selling / Receiving and the counter).
        await tester.tap(find.byType(SmartScanChip));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600)); // sheet slides up
        expect(find.byType(SegmentedButton<ScanMode>), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
