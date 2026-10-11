import 'date_value.dart';

/// A billing counter (usually a Windows/Mac computer) that accepts scans
/// sent from a phone.
class ScanStation {
  final String id;
  final String storeId;
  final String name;
  final bool active;
  final String uid;
  final DateTime updatedAt;

  const ScanStation({
    required this.id,
    required this.storeId,
    required this.name,
    required this.active,
    required this.uid,
    required this.updatedAt,
  });

  /// Counters that went quiet (closed without switching off) stop showing.
  bool isAvailableAt(DateTime now) => active && now.difference(updatedAt) < const Duration(hours: 12);

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'name': name,
        'active': active,
        'uid': uid,
        'updatedAt': updatedAt,
      };

  factory ScanStation.fromMap(Map<String, dynamic> map) => ScanStation(
        id: readString(map['id']),
        storeId: readString(map['storeId']),
        name: readString(map['name'], 'Counter'),
        active: map['active'] == true,
        uid: readString(map['uid']),
        updatedAt: readDate(map['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      );
}

/// One barcode (or recognised pack) scanned on a phone for a counter's bill.
class ScanEvent {
  final String id;
  final String storeId;
  final String stationId;
  final String rawBarcode;
  final String? medicineId; // set when the phone already identified it
  final String? batchNumber;
  final String deviceLabel;
  final String createdBy;
  final String createdByName;
  final DateTime scannedAt;
  final bool done;

  const ScanEvent({
    required this.id,
    required this.storeId,
    required this.stationId,
    required this.rawBarcode,
    this.medicineId,
    this.batchNumber,
    required this.deviceLabel,
    required this.createdBy,
    required this.createdByName,
    required this.scannedAt,
    this.done = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'stationId': stationId,
        'rawBarcode': rawBarcode,
        'medicineId': medicineId,
        'batchNumber': batchNumber,
        'deviceLabel': deviceLabel,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'scannedAt': scannedAt,
        'status': done ? 'done' : 'pending',
      };

  factory ScanEvent.fromMap(Map<String, dynamic> map) => ScanEvent(
        id: readString(map['id']),
        storeId: readString(map['storeId']),
        stationId: readString(map['stationId']),
        rawBarcode: readString(map['rawBarcode']),
        medicineId: map['medicineId'] as String?,
        batchNumber: map['batchNumber'] as String?,
        deviceLabel: readString(map['deviceLabel']),
        createdBy: readString(map['createdBy']),
        createdByName: readString(map['createdByName']),
        scannedAt: readDate(map['scannedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        done: map['status'] == 'done',
      );
}
