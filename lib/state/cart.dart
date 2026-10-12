import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/batch.dart';
import '../domain/models/customer_credit.dart';
import '../domain/models/medicine.dart';
import '../domain/models/sale_invoice.dart';
import '../domain/models/schedule_type.dart';
import '../domain/services/billing_calculator.dart';
import '../domain/services/checkout_engine.dart';
import '../domain/services/fefo_selector.dart';

/// One bill line on this device's counter: a quantity from one batch.
/// The backend re-prices and re-validates every line at checkout.
class CartLine {
  final String medicineId;
  final String batchId;
  final String name;
  final String batchNumber;
  final DateTime expiryDate;
  final int unitsPerPack;
  final int quantity; // base units
  final int mrpPaise; // per pack
  final double gstRate;
  final ScheduleType scheduleType;

  const CartLine({
    required this.medicineId,
    required this.batchId,
    required this.name,
    required this.batchNumber,
    required this.expiryDate,
    required this.unitsPerPack,
    required this.quantity,
    required this.mrpPaise,
    required this.gstRate,
    required this.scheduleType,
  });

  int get lineTotalPaise => BillingCalculator.linePaise(
        mrpPaisePerPack: mrpPaise,
        unitsPerPack: unitsPerPack,
        quantityUnits: quantity,
      );

  CartLine withQuantity(int units) => CartLine(
        medicineId: medicineId,
        batchId: batchId,
        name: name,
        batchNumber: batchNumber,
        expiryDate: expiryDate,
        unitsPerPack: unitsPerPack,
        quantity: units,
        mrpPaise: mrpPaise,
        gstRate: gstRate,
        scheduleType: scheduleType,
      );
}

class CartState {
  final List<CartLine> lines;
  final PaymentMode paymentMode;
  final String customerName;
  final String customerPhone;
  final CustomerCredit? creditCustomer;

  const CartState({
    this.lines = const [],
    this.paymentMode = PaymentMode.cash,
    this.customerName = '',
    this.customerPhone = '',
    this.creditCustomer,
  });

  bool get isEmpty => lines.isEmpty;

  BillSummary get summary => BillingCalculator.summarise(
        lines.map((l) => BillLine(lineTotalPaise: l.lineTotalPaise, gstRate: l.gstRate)),
      );

  Map<String, int> get unitsByBatch {
    final map = <String, int>{};
    for (final l in lines) {
      map.update(l.batchId, (v) => v + l.quantity, ifAbsent: () => l.quantity);
    }
    return map;
  }

  Set<ScheduleType> get schedules => lines.map((l) => l.scheduleType).toSet();

  CartState copyWith({
    List<CartLine>? lines,
    PaymentMode? paymentMode,
    String? customerName,
    String? customerPhone,
    CustomerCredit? creditCustomer,
    bool clearCreditCustomer = false,
  }) {
    return CartState(
      lines: lines ?? this.lines,
      paymentMode: paymentMode ?? this.paymentMode,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      creditCustomer: clearCreditCustomer ? null : creditCustomer ?? this.creditCustomer,
    );
  }

  CheckoutRequest toRequest({PrescriptionRecord? prescription}) => CheckoutRequest(
        lines: [
          for (final l in lines)
            CheckoutLineRequest(medicineId: l.medicineId, batchId: l.batchId, quantity: l.quantity),
        ],
        paymentMode: paymentMode,
        customerName: customerName,
        customerPhone: customerPhone,
        customerId: paymentMode == PaymentMode.credit ? creditCustomer?.id : null,
        prescription: prescription,
      );
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  /// Adds [units] of [medicine], taking nearest-expiry batches first and
  /// skipping units already on this bill. Throws [InsufficientStockException].
  void addMedicine(Medicine medicine, List<Batch> batches, int units, {DateTime? now}) {
    final allocations = FefoSelector.selectBatches(
      batches: batches,
      requestedQty: units,
      reserved: state.unitsByBatch,
      now: now,
    );
    final lines = [...state.lines];
    for (final a in allocations) {
      final index = lines.indexWhere((l) => l.batchId == a.batch.id);
      if (index >= 0) {
        lines[index] = lines[index].withQuantity(lines[index].quantity + a.quantity);
      } else {
        lines.add(CartLine(
          medicineId: medicine.id,
          batchId: a.batch.id,
          name: medicine.name,
          batchNumber: a.batch.batchNumber,
          expiryDate: a.batch.expiryDate,
          unitsPerPack: medicine.unitsPerPack,
          quantity: a.quantity,
          mrpPaise: a.batch.mrpPaise,
          gstRate: medicine.gstRate,
          scheduleType: medicine.scheduleType,
        ));
      }
    }
    state = state.copyWith(lines: lines);
  }

  /// Sets a line's quantity, capped by what that batch currently holds.
  /// Returns false (and changes nothing) if [units] exceeds [available].
  bool setQuantity(int index, int units, {required int available}) {
    if (index < 0 || index >= state.lines.length) return false;
    if (units <= 0) {
      remove(index);
      return true;
    }
    if (units > available) return false;
    final lines = [...state.lines];
    lines[index] = lines[index].withQuantity(units);
    state = state.copyWith(lines: lines);
    return true;
  }

  void remove(int index) {
    if (index < 0 || index >= state.lines.length) return;
    state = state.copyWith(lines: [...state.lines]..removeAt(index));
  }

  /// Reverses exactly what one earlier scan added to [batchId] — used to
  /// undo a remote scan the sender cancelled, without touching anything
  /// else someone may have added to that same line since.
  void removeUnits(String batchId, int units) {
    final index = state.lines.indexWhere((l) => l.batchId == batchId);
    if (index < 0) return;
    final left = state.lines[index].quantity - units;
    if (left <= 0) {
      remove(index);
    } else {
      final lines = [...state.lines];
      lines[index] = lines[index].withQuantity(left);
      state = state.copyWith(lines: lines);
    }
  }

  void setPaymentMode(PaymentMode mode) {
    state = state.copyWith(paymentMode: mode, clearCreditCustomer: mode != PaymentMode.credit);
  }

  void setCustomer({String? name, String? phone}) {
    state = state.copyWith(customerName: name, customerPhone: phone);
  }

  void setCreditCustomer(CustomerCredit? customer) {
    state = customer == null
        ? state.copyWith(clearCreditCustomer: true)
        : state.copyWith(
            creditCustomer: customer,
            customerName: customer.name,
            customerPhone: customer.phoneNumber,
          );
  }

  void clear() => state = const CartState();
}
