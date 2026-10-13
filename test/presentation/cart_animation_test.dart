import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/presentation/app.dart';
import 'package:nuskha_pms/presentation/widgets/common.dart';

void main() {
  testWidgets('a new bill line flies in and the total counts up; an edited line pulses', (tester) async {
    tester.view.physicalSize = const Size(1440, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
    await tester.pumpAndSettle();

    final searchField = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'Search medicine, generic or scan barcode',
    );
    await tester.enterText(searchField, 'Dolo 650');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dolo 650 Tablet'));
    await tester.pumpAndSettle(); // quantity dialog opens with a default quantity

    // The instant the line appears, its entrance and the total's count-up
    // are both actively animating, not an instant jump.
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();

    expect(find.text('Dolo 650 Tablet'), findsWidgets);
    expect(find.byType(CountUpAmount), findsWidgets);

    // Changing an existing line's quantity pulses it rather than silently
    // updating — some animation must be mid-flight right after the tap.
    await tester.tap(find.byTooltip('One pack more'));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.takeException(), isNull);
  });
}
