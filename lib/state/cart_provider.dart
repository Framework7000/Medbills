import 'package:flutter_riverpod/flutter_riverpod.dart';

class CartItem {
  final String medicineId;
  final String name;
  final String batchNumber;
  final String expiry;
  final int quantity;
  final int mrpPaise;
  final double gstRate;

  const CartItem({
    required this.medicineId,
    required this.name,
    required this.batchNumber,
    required this.expiry,
    required this.quantity,
    required this.mrpPaise,
    required this.gstRate,
  });

  double get lineTotalRupees => (mrpPaise * quantity) / 100.0;

  /// Rule 4: MRP is GST-inclusive in India — the taxable amount is derived
  /// by dividing out the rate, never by adding GST on top of MRP.
  double get lineTaxableRupees => lineTotalRupees / (1.0 + (gstRate / 100.0));

  double get lineGstRupees => lineTotalRupees - lineTaxableRupees;

  CartItem copyWith({int? quantity}) {
    return CartItem(
      medicineId: medicineId,
      name: name,
      batchNumber: batchNumber,
      expiry: expiry,
      quantity: quantity ?? this.quantity,
      mrpPaise: mrpPaise,
      gstRate: gstRate,
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super(_seedItems);

  static final List<CartItem> _seedItems = [
    const CartItem(
      medicineId: 'med_001',
      name: 'Paracetamol 500mg',
      batchNumber: 'B0001',
      expiry: '12/2027',
      quantity: 2,
      mrpPaise: 3500,
      gstRate: 5.0,
    ),
    const CartItem(
      medicineId: 'med_006',
      name: 'Amoxicillin 500mg',
      batchNumber: 'B0006',
      expiry: '06/2027',
      quantity: 1,
      mrpPaise: 8500,
      gstRate: 12.0,
    ),
    const CartItem(
      medicineId: 'med_008',
      name: 'Pantoprazole 40mg',
      batchNumber: 'B0008',
      expiry: '09/2027',
      quantity: 1,
      mrpPaise: 6200,
      gstRate: 12.0,
    ),
  ];

  void addItem(CartItem newItem) {
    final existingIndex = state.indexWhere((item) =>
        item.medicineId == newItem.medicineId && item.batchNumber == newItem.batchNumber);
    if (existingIndex != -1) {
      final existing = state[existingIndex];
      final updated = existing.copyWith(quantity: existing.quantity + newItem.quantity);
      state = [
        for (var i = 0; i < state.length; i++) i == existingIndex ? updated : state[i],
      ];
      return;
    }
    state = [...state, newItem];
  }

  void updateQuantity(int index, int newQty) {
    if (index < 0 || index >= state.length) return;
    if (newQty <= 0) {
      removeItem(index);
      return;
    }
    state = [
      for (var i = 0; i < state.length; i++)
        i == index ? state[i].copyWith(quantity: newQty) : state[i],
    ];
  }

  void removeItem(int index) {
    if (index < 0 || index >= state.length) return;
    state = [
      for (var i = 0; i < state.length; i++) if (i != index) state[i],
    ];
  }

  void clearCart() {
    state = [];
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

final cartSubtotalProvider = Provider<double>((ref) {
  final items = ref.watch(cartProvider);
  return items.fold(0.0, (sum, item) => sum + item.lineTaxableRupees);
});

final cartGstTotalProvider = Provider<double>((ref) {
  final items = ref.watch(cartProvider);
  return items.fold(0.0, (sum, item) => sum + item.lineGstRupees);
});

final cartGrandTotalProvider = Provider<double>((ref) {
  final items = ref.watch(cartProvider);
  return items.fold(0.0, (sum, item) => sum + item.lineTotalRupees);
});

final selectedPaymentModeProvider = StateProvider<String>((ref) => 'Cash');
final customerPhoneProvider = StateProvider<String>((ref) => '9752408128');
final customerNameProvider = StateProvider<String>((ref) => 'Walk-in Customer');
