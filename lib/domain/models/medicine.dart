import '../services/pack_units.dart';
import 'date_value.dart';
import 'schedule_type.dart';

/// Product master record. Rule 1: batch data (expiry, purchase price, MRP,
/// quantity) lives in separate batch documents, never on the medicine.
class Medicine {
  final String id;
  final String storeId; // Rule 8
  final String? catalogueId; // master-catalogue id this was stocked from, if any
  final String name;
  final String genericName;
  final String manufacturer;
  final String type; // category, e.g. "Analgesics"
  final String packSizeLabel; // e.g. "Strip of 15"
  final int unitsPerPack; // Rule 2: base units per pack the MRP is printed on
  final String hsnCode;
  final double gstRate; // percent: 0, 5, 12, 18
  final ScheduleType scheduleType; // Rule 11
  final String? barcode;
  final int minStock; // base units
  final String shelfLocation;
  final DateTime updatedAt;

  const Medicine({
    required this.id,
    required this.storeId,
    this.catalogueId,
    required this.name,
    required this.genericName,
    required this.manufacturer,
    required this.type,
    required this.packSizeLabel,
    required this.unitsPerPack,
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
    String? catalogueId,
    String? name,
    String? genericName,
    String? manufacturer,
    String? type,
    String? packSizeLabel,
    int? unitsPerPack,
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
      catalogueId: catalogueId ?? this.catalogueId,
      name: name ?? this.name,
      genericName: genericName ?? this.genericName,
      manufacturer: manufacturer ?? this.manufacturer,
      type: type ?? this.type,
      packSizeLabel: packSizeLabel ?? this.packSizeLabel,
      unitsPerPack: unitsPerPack ?? this.unitsPerPack,
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
      'catalogueId': catalogueId,
      'name': name,
      'genericName': genericName,
      'manufacturer': manufacturer,
      'type': type,
      'packSizeLabel': packSizeLabel,
      'unitsPerPack': unitsPerPack,
      'hsnCode': hsnCode,
      'gstRate': gstRate,
      'scheduleType': scheduleType.code,
      'barcode': barcode,
      'minStock': minStock,
      'shelfLocation': shelfLocation,
      'updatedAt': updatedAt,
    };
  }

  factory Medicine.fromMap(Map<String, dynamic> map) {
    final packLabel = readString(map['packSizeLabel']);
    final storedUnits = readInt(map['unitsPerPack']);
    return Medicine(
      id: readString(map['id']),
      storeId: readString(map['storeId'], 'store_primary'),
      catalogueId: map['catalogueId'] as String?,
      name: readString(map['name']),
      genericName: readString(map['genericName']),
      manufacturer: readString(map['manufacturer']),
      type: readString(map['type']),
      packSizeLabel: packLabel,
      unitsPerPack: storedUnits > 0 ? storedUnits : PackUnits.fromLabel(packLabel),
      hsnCode: readString(map['hsnCode']),
      gstRate: readDouble(map['gstRate'], 12.0),
      scheduleType: ScheduleType.fromString(map['scheduleType'] as String?),
      barcode: (map['barcode'] as String?)?.trim().isEmpty ?? true ? null : map['barcode'] as String,
      minStock: readInt(map['minStock']),
      shelfLocation: readString(map['shelfLocation']),
      updatedAt: readDate(map['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
