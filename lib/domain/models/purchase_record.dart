import 'date_value.dart';

/// A stock-in entry against a supplier invoice. Append-only.
class PurchaseRecord {
  final String id;
  final String storeId;
  final String medicineId;
  final String medicineName;
  final String batchId;
  final String batchNumber;
  final DateTime expiryDate;
  final int unitsPerPack;
  final int quantity; // base units received (paid + free)
  final int freeQuantity; // base units received free (scheme)
  final int purchasePricePaise; // per pack
  final int mrpPaise; // per pack
  final String supplierName;
  final String supplierInvoiceNumber;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  const PurchaseRecord({
    required this.id,
    required this.storeId,
    required this.medicineId,
    required this.medicineName,
    required this.batchId,
    required this.batchNumber,
    required this.expiryDate,
    required this.unitsPerPack,
    required this.quantity,
    this.freeQuantity = 0,
    required this.purchasePricePaise,
    required this.mrpPaise,
    required this.supplierName,
    required this.supplierInvoiceNumber,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
  });

  /// What was actually paid: only the non-free units, at the pack price.
  int get totalCostPaise {
    final paidUnits = quantity - freeQuantity;
    final perPack = unitsPerPack < 1 ? 1 : unitsPerPack;
    return (purchasePricePaise * paidUnits * 2 + perPack) ~/ (perPack * 2);
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'medicineId': medicineId,
        'medicineName': medicineName,
        'batchId': batchId,
        'batchNumber': batchNumber,
        'expiryDate': expiryDate,
        'unitsPerPack': unitsPerPack,
        'quantity': quantity,
        'freeQuantity': freeQuantity,
        'purchasePricePaise': purchasePricePaise,
        'mrpPaise': mrpPaise,
        'totalCostPaise': totalCostPaise,
        'supplierName': supplierName,
        'supplierInvoiceNumber': supplierInvoiceNumber,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'createdByName': createdByName,
      };

  factory PurchaseRecord.fromMap(Map<String, dynamic> map) => PurchaseRecord(
        id: readString(map['id']),
        storeId: readString(map['storeId'], 'store_primary'),
        medicineId: readString(map['medicineId']),
        medicineName: readString(map['medicineName']),
        batchId: readString(map['batchId']),
        batchNumber: readString(map['batchNumber']),
        expiryDate: readDate(map['expiryDate']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        unitsPerPack: readInt(map['unitsPerPack'], 1),
        quantity: readInt(map['quantity']),
        freeQuantity: readInt(map['freeQuantity']),
        purchasePricePaise: readInt(map['purchasePricePaise']),
        mrpPaise: readInt(map['mrpPaise']),
        supplierName: readString(map['supplierName']),
        supplierInvoiceNumber: readString(map['supplierInvoiceNumber']),
        createdAt: readDate(map['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        createdBy: readString(map['createdBy']),
        createdByName: readString(map['createdByName']),
      );
}
