import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/state/cart_provider.dart';

void main() {
  group('CartNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
      addTearDown(container.dispose);
    });

    test('addItem dedups by medicineId + batchNumber', () {
      final notifier = container.read(cartProvider.notifier);
      final before = container.read(cartProvider).length;
      notifier.addItem(const CartItem(
        medicineId: 'med_001',
        name: 'Paracetamol 500mg',
        batchNumber: 'B0001',
        expiry: '12/2027',
        quantity: 3,
        mrpPaise: 3500,
        gstRate: 5.0,
      ));
      final cart = container.read(cartProvider);
      expect(cart.length, before);
      expect(cart.firstWhere((i) => i.batchNumber == 'B0001').quantity, 5);
    });

    test('updateQuantity removes item when new quantity is zero', () {
      final notifier = container.read(cartProvider.notifier);
      final before = container.read(cartProvider).length;
      notifier.updateQuantity(0, 0);
      expect(container.read(cartProvider).length, before - 1);
    });

    test('clearCart empties state', () {
      container.read(cartProvider.notifier).clearCart();
      expect(container.read(cartProvider), isEmpty);
    });

    test('line tax extraction: MRP inclusive of GST', () {
      const item = CartItem(
        medicineId: 'med_x',
        name: 'Test',
        batchNumber: 'B1',
        expiry: '01/2028',
        quantity: 1,
        mrpPaise: 11200,
        gstRate: 12.0,
      );
      expect(item.lineTaxableRupees, closeTo(100.0, 0.01));
      expect(item.lineGstRupees, closeTo(12.0, 0.01));
    });
  });
}
