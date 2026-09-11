import 'schedule_type.dart';

/// Product master record. Rule 1: batch data (expiry, purchase price, MRP,
/// quantity) lives in the `batches` subcollection, never flattened here.
class Medicine {
  final String id;
  final String storeId; // Rule 8: always present, even single-store today
  final String name;
  final String genericName;
  final String manufacturer;
  final String type; // category, e.g. "Analgesics", "Antibiotics"
  final String packSizeLabel; // e.g. "10 Tablets Strip"
  final String hsnCode;
  final double gstRate; // percentage: 5.0, 12.0, 18.0
  final ScheduleType scheduleType; // Rule 11
  final String? barcode;
  final int minStock; // Rule 2: base units
  final String shelfLocation;
  final DateTime updatedAt;

  const Medicine({
    required this.id,
    required this.storeId,
    required this.name,
    required this.genericName,
    required this.manufacturer,
    required this.type,
    required this.packSizeLabel,
    required this.hsnCode,
    required this.gstRate,
    required this.scheduleType,
    this.barcode,
    required this.minStock,
    required this.shelfLocation,
    required this.updatedAt,
  });

  Medicine copyWith({
    String? id,
    String? storeId,
    String? name,
    String? genericName,
    String? manufacturer,
    String? type,
    String? packSizeLabel,
    String? hsnCode,
    double? gstRate,
    ScheduleType? scheduleType,
    String? barcode,
    int? minStock,
    String? shelfLocation,
    DateTime? updatedAt,
  }) {
    return Medicine(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      genericName: genericName ?? this.genericName,
      manufacturer: manufacturer ?? this.manufacturer,
      type: type ?? this.type,
      packSizeLabel: packSizeLabel ?? this.packSizeLabel,
      hsnCode: hsnCode ?? this.hsnCode,
      gstRate: gstRate ?? this.gstRate,
      scheduleType: scheduleType ?? this.scheduleType,
      barcode: barcode ?? this.barcode,
      minStock: minStock ?? this.minStock,
      shelfLocation: shelfLocation ?? this.shelfLocation,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'storeId': storeId,
      'name': name,
      'genericName': genericName,
      'manufacturer': manufacturer,
      'type': type,
      'packSizeLabel': packSizeLabel,
      'hsnCode': hsnCode,
      'gstRate': gstRate,
      'scheduleType': scheduleType.name,
      'barcode': barcode,
      'minStock': minStock,
      'shelfLocation': shelfLocation,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory Medicine.fromMap(Map<String, dynamic> map) {
    return Medicine(
      id: map['id'] as String,
      storeId: map['storeId'] as String? ?? 'store_primary',
      name: map['name'] as String,
      genericName: map['genericName'] as String? ?? '',
      manufacturer: map['manufacturer'] as String? ?? '',
      type: map['type'] as String? ?? '',
      packSizeLabel: map['packSizeLabel'] as String? ?? '',
      hsnCode: map['hsnCode'] as String? ?? '',
      gstRate: (map['gstRate'] as num?)?.toDouble() ?? 12.0,
      scheduleType: ScheduleType.fromString(map['scheduleType'] as String?),
      barcode: map['barcode'] as String?,
      minStock: (map['minStock'] as num?)?.toInt() ?? 0,
      shelfLocation: map['shelfLocation'] as String? ?? '',
      updatedAt: map['updatedAt'] != null
          ? DateTime.parse(map['updatedAt'] as String)
          : DateTime.now(),
    );
  }
}
