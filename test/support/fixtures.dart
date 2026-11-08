import 'package:nuskha_pms/domain/models/supplier_account.dart';
import 'package:nuskha_pms/domain/models/batch.dart';
import 'package:nuskha_pms/domain/models/medicine.dart';
import 'package:nuskha_pms/domain/models/schedule_type.dart';
import 'package:nuskha_pms/domain/services/stock_receipt.dart';

const storeId = 'store_test';

Medicine medicine(
  String id, {
  String name = 'Dolo 650',
  int unitsPerPack = 15,
  double gstRate = 12,
  ScheduleType schedule = ScheduleType.otc,
  int minStock = 30,
}) {
  return Medicine(
    id: id,
    storeId: storeId,
    name: name,
    genericName: 'Paracetamol 650mg',
    manufacturer: 'Micro Labs',
    type: 'Tablet',
    packSizeLabel: 'Strip of $unitsPerPack',
    unitsPerPack: unitsPerPack,
    hsnCode: '300490',
    gstRate: gstRate,
    scheduleType: schedule,
    minStock: minStock,
    shelfLocation: 'A1',
    updatedAt: DateTime(2026, 1, 1),
  );
}

Batch batch(
  String medicineId,
  String number, {
  required DateTime expiry,
  int quantity = 150,
  int mrpPaise = 3360,
  int costPaise = 2400,
  bool blocked = false,
}) {
  return Batch(
    id: Batch.idFor(medicineId, number),
    storeId: storeId,
    medicineId: medicineId,
    batchNumber: number,
    expiryDate: expiry,
    purchasePricePaise: costPaise,
    mrpPaise: mrpPaise,
    quantity: quantity,
    isBlocked: blocked,
    createdAt: DateTime(2026, 1, 1),
  );
}

StockReceipt receipt(
  Medicine medicine, {
  String batchNumber = 'DL2401',
  num packs = 10,
  num freePacks = 0,
  int mrpPaise = 3360,
  int costPaise = 2400,
  int? expiryYear,
  int expiryMonth = 12,
  String supplierName = 'Shree Distributors',
  String supplierInvoiceNumber = 'SD/101',
  PurchasePayment payment = PurchasePayment.credit,
  DateTime? billDate,
  int? billTotalPaise,
  String? knownDistributorId,
}) {
  return StockReceipt(
    medicine: medicine,
    batchNumber: batchNumber,
    expiryMonth: expiryMonth,
    expiryYear: expiryYear ?? DateTime.now().year + 2,
    packs: packs,
    freePacks: freePacks,
    purchasePricePaise: costPaise,
    mrpPaise: mrpPaise,
    supplierName: supplierName,
    supplierInvoiceNumber: supplierInvoiceNumber,
    payment: payment,
    billDate: billDate,
    billTotalPaise: billTotalPaise,
    knownDistributorId: knownDistributorId,
  );
}
