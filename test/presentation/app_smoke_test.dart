import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/presentation/app.dart';

/// Real fonts, so text measures as it does on a device and overflow checks
/// mean something (the default test font is far narrower or wider).
Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await loader.load();
  }

  await load('WorkSans', ['assets/fonts/WorkSans-Regular.ttf', 'assets/fonts/WorkSans-Bold.ttf']);
  final outfit = Directory('assets/fonts').listSync().map((e) => e.path).where((p) => p.contains('Outfit')).toList();
  if (outfit.isNotEmpty) await load('Outfit', outfit);
  await load('NotoSansDevanagari', ['assets/fonts/NotoSansDevanagari-Regular.ttf']);
}

const _sizes = {
  'iPhone SE (375×667)': Size(375, 667),
  'iPhone XR / 17 (414×896)': Size(414, 896),
  'iPad portrait (768×1024)': Size(768, 1024),
  'Mac / Windows (1440×900)': Size(1440, 900),
  // A resized/short desktop window — the nav rail must scroll, never overflow.
  'Short Mac window (900×600)': Size(900, 600),
};

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
  await tester.pumpAndSettle();
}

Finder _nav(String label) {
  final bar = find.byType(NavigationBar);
  final rail = find.byType(NavigationRail);
  final scope = bar.evaluate().isNotEmpty ? bar : rail;
  return find.descendant(of: scope, matching: find.text(label));
}

Future<void> _open(WidgetTester tester, String label) async {
  if (_nav(label).evaluate().isNotEmpty) {
    // A short window scrolls the rail — bring the destination into view
    // (a no-op where it's already visible) before tapping it.
    await tester.ensureVisible(_nav(label));
    await tester.pumpAndSettle();
    await tester.tap(_nav(label));
  } else {
    // Phone: the remaining sections live behind "More".
    await tester.tap(_nav('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, label));
  }
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  final back = find.byType(BackButton);
  final close = find.byType(CloseButton);
  if (back.evaluate().isNotEmpty) {
    await tester.tap(back.first);
  } else if (close.evaluate().isNotEmpty) {
    await tester.tap(close.first);
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  for (final entry in _sizes.entries) {
    testWidgets('every section renders without overflow — ${entry.key}', (tester) async {
      await _pumpApp(tester, entry.value);
      expect(find.text('Billing'), findsWidgets);

      for (final section in ['Scan', 'Stock', 'Bills', 'Udhaar', 'Purchases', 'Reports', 'Settings']) {
        await _open(tester, section);
        expect(tester.takeException(), isNull, reason: section);
        if (Navigator.of(tester.element(find.byType(Scaffold).last)).canPop()) await _back(tester);
      }

      // Medicine detail with its batches.
      await _open(tester, 'Stock');
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Batches'), findsOneWidget);
      await _back(tester);
    });

    testWidgets('a complete sale updates stock and bill history — ${entry.key}', (tester) async {
      await _pumpApp(tester, entry.value);
      await _open(tester, 'Billing');

      await tester.enterText(find.byType(TextField).first, 'Dolo');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dolo'), findsWidgets);

      if (find.widgetWithText(FilledButton, 'Complete sale').evaluate().isEmpty) {
        await tester.tap(find.text('Checkout'));
        await tester.pumpAndSettle();
      }
      final complete = find.widgetWithText(FilledButton, 'Complete sale');
      await tester.ensureVisible(complete);
      await tester.tap(complete);
      await tester.pumpAndSettle();
      expect(find.text('Sale complete'), findsOneWidget);
      expect(find.textContaining('INV/'), findsWidgets);
      expect(tester.takeException(), isNull);

      await _back(tester);
      expect(find.byType(BottomSheet), findsNothing);
      await _open(tester, 'Bills');
      expect(find.textContaining('INV/'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
