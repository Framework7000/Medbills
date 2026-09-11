import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/main.dart';

void main() {
  testWidgets('MedBillsApp renders the Billing Counter shell', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
    await tester.pumpAndSettle();

    expect(find.text('Billing Counter'), findsOneWidget);
    expect(find.text('Complete and Print (F9)'), findsOneWidget);
  });

  testWidgets('navigating to Bill History shows seeded invoices', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MedBillsApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bill History'));
    await tester.pumpAndSettle();

    expect(find.text('INV-2026-1050'), findsOneWidget);
  });
}
