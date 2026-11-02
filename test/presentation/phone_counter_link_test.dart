import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/models/scan_link.dart';
import 'package:nuskha_pms/platform/scan_target_memory.dart';
import 'package:nuskha_pms/presentation/scan/scan_billing.dart';
import 'package:nuskha_pms/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScanStation _counter(String id, String name) => ScanStation(
    id: id, storeId: 's', name: name, active: true, uid: 'u', updatedAt: DateTime.now());

Future<ProviderContainer> _pumpChip(WidgetTester tester, List<ScanStation> online) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [stationsProvider.overrideWith((ref) => Stream.value(online))],
    child: const MaterialApp(home: Scaffold(body: Center(child: SmartScanChip()))),
  ));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(SmartScanChip)));
}

void main() {
  testWidgets('a new phone sends to the shop computer by itself when it is the only one online', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = await _pumpChip(tester, [_counter('c1', 'Shop laptop')]);
    expect(container.read(scanTargetProvider)?.id, 'c1');
    expect(find.text('To Shop laptop'), findsOneWidget);
    expect(await tester.runAsync(ScanTargetMemory.load), ('c1', 'Shop laptop'));
  });

  testWidgets('with two computers online and no earlier choice, nothing is guessed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = await _pumpChip(tester, [_counter('c1', 'Counter 1'), _counter('c2', 'Counter 2')]);
    expect(container.read(scanTargetProvider), isNull);
    expect(find.text('To this phone'), findsOneWidget);
  });

  testWidgets('a phone that chose "this phone" earlier is not switched to a counter', (tester) async {
    SharedPreferences.setMockInitialValues({'lastScanTargetId': '', 'lastScanTargetName': ''});
    final container = await _pumpChip(tester, [_counter('c1', 'Shop laptop')]);
    expect(container.read(scanTargetProvider), isNull);
  });

  testWidgets('the remembered counter is picked again after a restart', (tester) async {
    SharedPreferences.setMockInitialValues({'lastScanTargetId': 'c2', 'lastScanTargetName': 'Counter 2'});
    final container = await _pumpChip(tester, [_counter('c1', 'Counter 1'), _counter('c2', 'Counter 2')]);
    expect(container.read(scanTargetProvider)?.id, 'c2');
  });

  test('a computer keeps its counter id and name between launches; switching off is remembered', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await CounterMemory.load(), isNull);
    await CounterMemory.save('station-1', 'Shop laptop');
    expect(await CounterMemory.load(), ('station-1', 'Shop laptop'));
    expect(await CounterMemory.isOff(), isFalse);
    await CounterMemory.setOff(true);
    expect(await CounterMemory.isOff(), isTrue);
    await CounterMemory.save('station-1', 'Shop laptop'); // switched on again by hand
    expect(await CounterMemory.isOff(), isFalse);
  });
}
