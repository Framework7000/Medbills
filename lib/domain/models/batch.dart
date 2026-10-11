import 'date_value.dart';

/// One received lot of a medicine. Rule 12: money is integer paise.
/// [mrpPaise] and [purchasePricePaise] are per pack, exactly as printed on
/// the strip/box and the supplier invoice; [quantity] is in base units
/// (Rule 2), converted with the medicine's unitsPerPack.
class Batch {
  final String id;
  final String storeId;
  final String medicineId;
  final String batchNumber;
  final DateTime expiryDate;
  final int purchasePricePaise;
  final int mrpPaise; // Rule 4: GST-inclusive
  final int quantity;
  final bool isBlocked;
  final DateTime createdAt;

  const Batch({
    required this.id,
    required this.storeId,
    required this.medicineId,
    required this.batchNumber,
    required this.expiryDate,
    required this.purchasePricePaise,
    required this.mrpPaise,
    required this.quantity,
    this.isBlocked = false,
    required this.createdAt,
  });

  /// Pharmacy expiry is month-precision: a strip marked 03/2027 is usable
  /// through 31 March 2027, so [expiryDate] holds the last day of that month.
  bool isExpiredAt(DateTime now) => !now.isBefore(expiryDate.add(const Duration(days: 1)));

  bool get isExpired => isExpiredAt(DateTime.now());

  int daysToExpiry(DateTime now) => expiryDate.difference(now).inDays;

  bool isSellableAt(DateTime now) => !isBlocked && quantity > 0 && !isExpiredAt(now);

  Batch copyWith({int? quantity, bool? isBlocked}) {
    return Batch(
      id: id,
      storeId: storeId,
      medicineId: medicineId,
      batchNumber: batchNumber,
      expiryDate: expiryDate,
      purchasePricePaise: purchasePricePaise,
      mrpPaise: mrpPaise,
      quantity: quantity ?? this.quantity,
      isBlocked: isBlocked ?? this.isBlocked,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeId': storeId,
      'medicineId': medicineId,
      'batchNumber': batchNumber,
      'expiryDate': expiryDate,
      'purchasePricePaise': purchasePricePaise,
      'mrpPaise': mrpPaise,
      'quantity': quantity,
      'isBlocked': isBlocked,
      'createdAt': createdAt,
    };
  }

  factory Batch.fromMap(Map<String, dynamic> map) {
    return Batch(
      id: readString(map['id']),
      storeId: readString(map['storeId'], 'store_primary'),
      medicineId: readString(map['medicineId']),
      batchNumber: readString(map['batchNumber']),
      expiryDate: readDate(map['expiryDate']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      purchasePricePaise: readInt(map['purchasePricePaise']),
      mrpPaise: readInt(map['mrpPaise']),
      quantity: readInt(map['quantity']),
      isBlocked: map['isBlocked'] == true,
      createdAt: readDate(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  /// Deterministic document id so receiving the same batch twice tops up
  /// one record instead of creating a duplicate.
  static String idFor(String medicineId, String batchNumber) =>
      '${medicineId}__${normaliseBatchNumber(batchNumber).replaceAll(RegExp(r'[^A-Z0-9-]'), '_')}';

  static String normaliseBatchNumber(String raw) => raw.trim().toUpperCase();

  /// Last calendar day of [month]/[year] — how printed expiry is read.
  static DateTime endOfMonth(int year, int month) => DateTime(year, month + 1, 0);
}
