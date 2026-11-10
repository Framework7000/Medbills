import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/services/supplier_ledger.dart';
import 'package:nuskha_pms/presentation/app.dart';
import 'package:nuskha_pms/presentation/home_shell.dart' show paymentsLabel;
import 'package:nuskha_pms/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What Yash bhaiya asked for, done the way he would do it, on the counter
/// computer and on the phone: sell cheaper with a discount, take a return,
/// fix a stock count, enter an old supplier bill and pay it, see the P&L.
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

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester, String label) async {
  // A phone page opened from "More" sits over the bar: go back to it first.
  while (find.byType(NavigationBar).hitTestable().evaluate().isEmpty &&
      find.byType(NavigationRail).hitTestable().evaluate().isEmpty) {
    await tester.pageBack();
    await tester.pumpAndSettle();
  }
  final rail = find.byType(NavigationRail);
  if (rail.evaluate().isNotEmpty) {
    await tester.tap(find.descendant(of: rail, matching: find.text(label == paymentsLabel ? 'Payments' : label)));
  } else {
    final bar = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
    if (bar.evaluate().isNotEmpty) {
      await tester.tap(bar);
    } else {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, label));
    }
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  for (final size in const [Size(1440, 900), Size(412, 915)]) {
    final w = size.width.toInt();

    Future<ProviderContainer> start(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size * 2;
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
      await tester.pumpAndSettle();
      return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    }

    testWidgets('sell below MRP with a bill discount, then take a return ($w wide)', (tester) async {
      final container = await start(tester);
      final repo = container.read(repositoryProvider)!;
      final stock = container.read(stockIndexProvider).value!;
      final item = stock.values.firstWhere((s) => s.sellableUnits >= s.medicine.unitsPerPack * 2 && s.medicine.scheduleType.isSellable && !s.medicine.scheduleType.requiresRegisterEntry);
      final perPack = item.medicine.unitsPerPack;
      container.read(cartProvider.notifier).addMedicine(item.medicine, item.batches, perPack * 2);
      await tester.pumpAndSettle();
      final mrp = container.read(cartProvider).lines.single.mrpPaise;

      // −10% on the line.
      await tester.tap(find.byKey(const ValueKey('price-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('−10%'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      final rate = container.read(cartProvider).lines.single.ratePaise!;
      expect(rate, (mrp * 90 * 2 + 100) ~/ 200);
      expect(tester.takeException(), isNull);

      // Phone: the totals live in the checkout sheet.
      if (find.byKey(const ValueKey('bill-discount-row')).evaluate().isEmpty) {
        await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('bill-discount-row')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('bill-discount')), '2');
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(container.read(cartProvider).appliedBillDiscountPaise, 200);
      expect(find.text('Discount'), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'checkout panel with discount rows');

      await tester.tap(find.widgetWithText(FilledButton, 'Complete sale'));
      await _settle(tester);
      expect(find.text('Sale complete'), findsOneWidget);
      final sale = (await tester.runAsync(() => repo.watchRecentSales().first))!.first;
      expect(sale.discountPaise, sale.mrpTotalPaise - sale.grossPaise);
      expect(sale.grossPaise, sale.lines.single.lineTotalPaise);
      expect(sale.lines.single.lineTotalPaise, rate * 2 - 200);
      expect(find.text('Discount'), findsWidgets, reason: 'the bill shows it');
      expect(tester.takeException(), isNull, reason: 'invoice with discount');

      // The customer brings one pack back.
      await tester.tap(find.byKey(const ValueKey('return-items')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('return-more-0')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'return dialog');
      await tester.tap(find.widgetWithText(FilledButton, 'Return'));
      await _settle(tester);
      final after = (await tester.runAsync(() => repo.watchRecentSales().first))!.first;
      expect(after.returnedUnits, [perPack]);
      expect(after.refundedPaise, (after.lines.single.lineTotalPaise / 2).round());
      expect(find.text('Net after returns'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bill is edited later (more strips, Cash + UPI), same number, stock moved ($w wide)', (tester) async {
      final container = await start(tester);
      final repo = container.read(repositoryProvider)!;
      final stock = container.read(stockIndexProvider).value!;
      final item = stock.values.firstWhere((s) =>
          s.sellableBatches.any((b) => b.quantity >= s.medicine.unitsPerPack * 4) &&
          s.medicine.scheduleType.isSellable &&
          !s.medicine.scheduleType.requiresRegisterEntry);
      final perPack = item.medicine.unitsPerPack;
      final batch = item.sellableBatches.firstWhere((b) => b.quantity >= perPack * 4);
      container.read(cartProvider.notifier).addMedicine(item.medicine, [batch], perPack);
      await tester.pumpAndSettle();
      if (find.widgetWithText(FilledButton, 'Complete sale').hitTestable().evaluate().isEmpty) {
        await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.widgetWithText(FilledButton, 'Complete sale'));
      await _settle(tester);
      final sale = (await tester.runAsync(() => repo.watchRecentSales().first))!.first;
      Future<int> left() async =>
          (await tester.runAsync(() => repo.watchBatches().first))!.firstWhere((b) => b.id == batch.id).quantity;
      final before = await left();

      // Edit: the bill opens on its own cart, with its line.
      await tester.tap(find.byKey(const ValueKey('edit-bill')));
      await _settle(tester);
      expect(find.text('Edit bill ${sale.invoiceNumber}'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'bill editor');
      // One more strip, twice: the bill's own strip counts as available.
      final more = perPack > 1 ? 'One pack more' : 'One more';
      await tester.tap(find.byTooltip(more).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(more).first);
      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey('pay-split')).hitTestable().evaluate().isEmpty) {
        await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byKey(const ValueKey('pay-split')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('split-cash')), '10');
      await tester.pumpAndSettle();
      expect(find.textContaining('UPI: ₹'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Cash + UPI fields');
      await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
      await _settle(tester);

      final sales = (await tester.runAsync(() => repo.watchRecentSales().first))!;
      final edited = sales.firstWhere((s) => s.revisionOf == sale.id);
      expect(edited.invoiceNumber, sale.invoiceNumber);
      expect(edited.lines.single.quantity, perPack * 3);
      expect((edited.paymentMode.name, edited.cashPaise, edited.upiPaise), ('split', 1000, edited.payablePaise - 1000));
      expect(await left(), before - perPack * 2);
      expect(sales.firstWhere((s) => s.id == sale.id).isReplaced, isTrue);
      expect(find.byKey(const ValueKey('edited-note')), findsOneWidget, reason: 'the corrected bill is shown');
      expect(find.textContaining('Cash ₹10.00 + UPI'), findsWidgets);
      expect(container.read(cartProvider).isEmpty, isTrue, reason: 'the counter cart was never touched');
      expect(tester.takeException(), isNull);
    });

    testWidgets('change a batch\'s stock count right on the stock screen ($w wide)', (tester) async {
      final container = await start(tester);
      final repo = container.read(repositoryProvider)!;
      await _open(tester, 'Stock');
      expect(find.byKey(const ValueKey('stock-value')), findsOneWidget);
      expect(find.text('Stock value (cost)'), findsOneWidget);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      final chip = find.byWidgetPredicate((w) => w is ActionChip && w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('stock-'));
      await tester.tap(chip.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'stock dialog');
      await tester.enterText(find.byKey(const ValueKey('adjust-packs')), '23');
      if (find.byKey(const ValueKey('adjust-loose')).evaluate().isNotEmpty) {
        await tester.enterText(find.byKey(const ValueKey('adjust-loose')), '0');
      }
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _settle(tester);
      final id = '${((chip.evaluate().isEmpty ? null : chip.evaluate().first.widget.key) as ValueKey?)?.value ?? ''}';
      final batches = (await tester.runAsync(() => repo.watchBatches().first))!;
      final medicines = (await tester.runAsync(() => repo.watchMedicines().first))!;
      final b = batches.firstWhere((x) => 'stock-${x.id}' == id);
      final perPack = medicines.firstWhere((m) => m.id == b.medicineId).unitsPerPack;
      expect(b.quantity, 23 * perPack);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an old udhaar bill is entered, reminded and paid; P&L shows it ($w wide)', (tester) async {
      final container = await start(tester);
      final repo = container.read(repositoryProvider)!;
      await _open(tester, paymentsLabel);
      expect(find.text('Udhaar owed'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'empty Purchase & Payment');

      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Old bill (udhaar)'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Distributor / MR'), 'Mahaveer Agencies');
      await tester.enterText(find.widgetWithText(TextField, 'Bill no.'), 'MA-77');
      await tester.enterText(find.byKey(const ValueKey('bill-amount')), '12500');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'bill dialog');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _settle(tester);

      SupplierLedger ledger() => container.read(supplierLedgerProvider).value!;
      expect(ledger().totalOutstandingPaise, 1250000);
      // Entered today with no due date: due in 30 days, not yet a reminder.
      expect(find.byKey(const ValueKey('payment-reminders')), findsNothing);

      await tester.tap(find.byTooltip('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(PopupMenuItem<String>), matching: find.text('Payment')));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextFormField, 'Paid to'), 'Mahaveer Agencies');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('payment-amount')), '5000');
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('UPI')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'payment dialog');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await _settle(tester);
      expect(ledger().totalOutstandingPaise, 750000);
      final pays = (await tester.runAsync(() => repo.watchSupplierPayments().first))!;
      expect(pays.single.amountPaise, 500000);
      expect(tester.takeException(), isNull);

      await _open(tester, 'Reports');
      expect(find.text('Plus / minus'), findsWidgets);
      expect(find.text('2 · Purchase & Payment'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'the P&L statement');
    });
  }
}
