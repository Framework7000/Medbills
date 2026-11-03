import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/presentation/app.dart';
import 'package:nuskha_pms/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The owner's brother mistyped an expiry and wants to fix it: Stock →
/// medicine → pencil on the batch → new expiry → Save.
/// Real fonts, so text measures as it does on a phone (as app_smoke_test does).
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

void main() {
  setUpAll(_loadFonts);

  for (final size in const [Size(1440, 900), Size(412, 915)]) {
    testWidgets('a batch expiry and price are edited from the stock screen (${size.width.toInt()} wide)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
      await tester.pumpAndSettle();

      final nav = find.byType(NavigationBar).evaluate().isNotEmpty ? find.byType(NavigationBar) : find.byType(NavigationRail);
      await tester.tap(find.descendant(of: nav, matching: find.text('Stock')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Batches'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'stock detail with the new pencil button');

      final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
      final repo = container.read(repositoryProvider)!;
      final before = (await tester.runAsync(() => repo.watchBatches().first))!;

      // The pencil sits on every batch.
      await tester.tap(find.byTooltip('Edit dates and prices').first);
      await tester.pumpAndSettle();
      expect(find.text('Stock quantity is not changed here. Bills already made keep their prices. This change is recorded.'),
          findsOneWidget);

      expect(tester.takeException(), isNull, reason: 'the edit dialog');

      // Nonsense is stopped in the form.
      final expiryField = find.widgetWithText(TextFormField, 'Expiry');
      await tester.enterText(find.widgetWithText(TextFormField, 'Expiry').first, '13/27');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter month and year, like 05/27'), findsOneWidget);

      // A correct fix is saved.
      await tester.enterText(expiryField.first, '03/2029');
      await tester.enterText(find.widgetWithText(TextFormField, 'MRP per pack (₹)'), '41.50');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(find.textContaining('updated'), findsOneWidget);

      final after = (await tester.runAsync(() => repo.watchBatches().first))!;
      final changed = after.where((a) {
        final b = before.firstWhere((x) => x.id == a.id);
        return a.expiryDate != b.expiryDate;
      }).toList();
      expect(changed, hasLength(1), reason: 'exactly one batch was corrected');
      expect(changed.single.expiryDate, DateTime(2029, 3, 31));
      expect(changed.single.mrpPaise, 4150);
      expect(changed.single.quantity, before.firstWhere((x) => x.id == changed.single.id).quantity);
      expect(tester.takeException(), isNull);
    });
  }
}
