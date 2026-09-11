import 'package:decimal/decimal.dart';

/// A batch of a [Medicine] product. Rule 12: all money stored as integer
/// paise, never a double. Rule 4: [mrpPaise] is GST-inclusive.
class Batch {
  final String id;
  final String medicineId;
  final String batchNumber;
  final DateTime expiryDate;
  final int purchasePricePaise;
  final int mrpPaise;
  final int quantity; // Rule 2: base units (e.g. tablets)
  final bool isBlocked;
  final DateTime createdAt;

  const Batch({
    required this.id,
    required this.medicineId,
    required this.batchNumber,
    required this.expiryDate,
    required this.purchasePricePaise,
    required this.mrpPaise,
    required this.quantity,
    this.isBlocked = false,
    required this.createdAt,
  });

  Decimal get purchasePriceRupees =>
      (Decimal.fromInt(purchasePricePaise) / Decimal.fromInt(100)).toDecimal();

  Decimal get mrpRupees =>
      (Decimal.fromInt(mrpPaise) / Decimal.fromInt(100)).toDecimal();

  bool get isExpired => DateTime.now().isAfter(expiryDate);

  Batch copyWith({
    String? id,
    String? medicineId,
    String? batchNumber,
    DateTime? expiryDate,
    int? purchasePricePaise,
    int? mrpPaise,
    int? quantity,
    bool? isBlocked,
    DateTime? createdAt,
  }) {
    return Batch(
      id: id ?? this.id,
      medicineId: medicineId ?? this.medicineId,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      purchasePricePaise: purchasePricePaise ?? this.purchasePricePaise,
      mrpPaise: mrpPaise ?? this.mrpPaise,
      quantity: quantity ?? this.quantity,
      isBlocked: isBlocked ?? this.isBlocked,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medicineId': medicineId,
      'batchNumber': batchNumber,
      'expiryDate': expiryDate.toIso8601String(),
      'purchasePricePaise': purchasePricePaise,
      'mrpPaise': mrpPaise,
      'quantity': quantity,
      'isBlocked': isBlocked,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Batch.fromMap(Map<String, dynamic> map) {
    return Batch(
      id: map['id'] as String,
      medicineId: map['medicineId'] as String,
      batchNumber: map['batchNumber'] as String? ?? '',
      expiryDate: map['expiryDate'] != null
          ? DateTime.parse(map['expiryDate'] as String)
          : DateTime.now(),
      purchasePricePaise: (map['purchasePricePaise'] as num?)?.toInt() ?? 0,
      mrpPaise: (map['mrpPaise'] as num?)?.toInt() ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      isBlocked: map['isBlocked'] as bool? ?? false,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : DateTime.now(),
    );
  }
}
