import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/services/fefo_selector.dart';
import 'package:nuskha_pms/state/inventory_batches_provider.dart';

void main() {
  group('InventoryBatchesNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('seeds starting stock for known medicines', () {
      final notifier = container.read(inventoryBatchesProvider.notifier);
      expect(notifier.totalStockFor('med_001'), 120);
    });

    test('hasStock reflects total eligible batch quantity', () {
      final notifier = container.read(inventoryBatchesProvider.notifier);
      expect(notifier.hasStock('med_001', 120), isTrue);
      expect(notifier.hasStock('med_001', 121), isFalse);
    });

    test('dispense decrements stock FEFO-style', () {
      final notifier = container.read(inventoryBatchesProvider.notifier);
      notifier.dispense('med_001', 20);
      expect(notifier.totalStockFor('med_001'), 100);
    });

    test('dispense throws InsufficientStockException when over-requested', () {
      final notifier = container.read(inventoryBatchesProvider.notifier);
      expect(
        () => notifier.dispense('med_001', 1000),
        throwsA(isA<InsufficientStockException>()),
      );
    });

    test('receiveBatch merges quantity into an existing batch number', () {
      final notifier = container.read(inventoryBatchesProvider.notifier);
      final before = notifier.totalStockFor('med_001');
      notifier.receiveBatch(
        container.read(inventoryBatchesProvider)['med_001']!.first.copyWith(quantity: 50),
      );
      expect(notifier.totalStockFor('med_001'), before + 50);
    });

    test('receiveBatch adds a new batch for a medicine with no prior stock', () {
      final notifier = container.read(inventoryBatchesProvider.notifier);
      expect(notifier.totalStockFor('med_099'), 0);
    });
  });
}
