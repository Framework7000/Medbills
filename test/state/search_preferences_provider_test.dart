import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/state/search_preferences_provider.dart';

void main() {
  group('SearchPreferencesNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('defaults to seeded pinned medicines', () {
      expect(container.read(searchPreferencesProvider).pinnedMedicineIds, isNotEmpty);
    });

    test('togglePin caps pins at 10', () {
      final notifier = container.read(searchPreferencesProvider.notifier);
      for (var i = 0; i < 15; i++) {
        notifier.togglePin('med_extra_$i');
      }
      expect(container.read(searchPreferencesProvider).pinnedMedicineIds.length, lessThanOrEqualTo(10));
    });

    test('recent searches capped at 10, most recent first', () {
      final notifier = container.read(searchPreferencesProvider.notifier);
      for (var i = 0; i < 15; i++) {
        notifier.addRecentSearch('query_$i');
      }
      final recents = container.read(searchPreferencesProvider).recentSearches;
      expect(recents.length, 10);
      expect(recents.first, 'query_14');
    });
  });
}
