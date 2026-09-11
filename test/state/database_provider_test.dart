import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/state/database_provider.dart';

void main() {
  group('DatabaseStatusNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('defaults to connected', () {
      expect(container.read(databaseStatusProvider).isConnected, isTrue);
    });

    test('refresh updates lastRefreshed timestamp', () async {
      final before = container.read(databaseStatusProvider).lastRefreshed;
      await Future.delayed(const Duration(milliseconds: 5));
      container.read(databaseStatusProvider.notifier).refresh();
      final after = container.read(databaseStatusProvider).lastRefreshed;
      expect(after.isAfter(before), isTrue);
    });
  });
}
