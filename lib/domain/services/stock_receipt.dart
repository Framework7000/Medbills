import '../models/batch.dart';
import '../models/medicine.dart';
import '../models/supplier_account.dart';

/// A supplier delivery of one batch of one medicine.
class StockReceipt {
  /// The store medicine being stocked. If it doesn't exist in the store yet
  /// (e.g. promoted from the master catalogue), the backend creates it.
  final Medicine medicine;
  final String batchNumber;
  final int expiryMonth;
  final int expiryYear;
  final num packs; // paid packs (4.5 = four and a half strips)
  final num freePacks; // scheme / free packs
  final int purchasePricePaise; // per pack
  final int mrpPaise; // per pack
  final String supplierName;
  final String supplierInvoiceNumber;
  final String? billScanId; // the photographed bill this came from
  /// Cash (paid now) or credit (owed to the supplier).
  final PurchasePayment payment;
  /// The date printed on the supplier's bill; null = today.
  final DateTime? billDate;
  /// The bill's printed grand total, when known (scanned bills).
  final int? billTotalPaise;
  /// The distributor this goes to when already known (a renamed distributor
  /// keeps its id); otherwise worked out from [supplierName].
  final String? knownDistributorId;

  const StockReceipt({
    required this.medicine,
    required this.batchNumber,
    required this.expiryMonth,
    required this.expiryYear,
    required this.packs,
    this.freePacks = 0,
    required this.purchasePricePaise,
    required this.mrpPaise,
    this.supplierName = '',
    this.supplierInvoiceNumber = '',
    this.billScanId,
    this.payment = PurchasePayment.credit,
    this.billDate,
    this.billTotalPaise,
    this.knownDistributorId,
  });

  String get distributorName => Distributor.tidyName(supplierName);
  String get distributorId =>
      Distributor.idFor(supplierName).isEmpty ? '' : (knownDistributorId ?? Distributor.idFor(supplierName));

  String supplierBillId(DateTime now) =>
      SupplierBill.idFor(distributorId, supplierInvoiceNumber.trim(), billDate ?? now);

  /// The supplier bill once this delivery is added to it (created if new),
  /// or null when no supplier was named.
  SupplierBill? billAfter(
    SupplierBill? existing, {
    required String storeId,
    required String uid,
    required String userName,
    required DateTime now,
  }) {
    if (distributorId.isEmpty) return null;
    final base = existing ??
        SupplierBill(
          id: supplierBillId(now),
          storeId: storeId,
          distributorId: distributorId,
          distributorName: distributorName,
          billNumber: supplierInvoiceNumber.trim(),
          billDate: billDate ?? DateTime(now.year, now.month, now.day),
          payment: payment,
          createdAt: now,
          createdBy: uid,
          createdByName: userName,
        );
    return base.copyWith(
      itemsPaise: base.itemsPaise + costPaise,
      payment: payment,
      amountPaise: billTotalPaise,
      cancelled: false,
    );
  }

  String get normalisedBatchNumber => Batch.normaliseBatchNumber(batchNumber);
  DateTime get expiryDate => Batch.endOfMonth(expiryYear, expiryMonth);
  int get paidUnits => (packs * medicine.unitsPerPack).round();
  int get freeUnits => (freePacks * medicine.unitsPerPack).round();
  int get totalUnits => paidUnits + freeUnits;

  /// What the paid units cost at the purchase rate.
  int get costPaise {
    final perPack = medicine.unitsPerPack < 1 ? 1 : medicine.unitsPerPack;
    return (purchasePricePaise * paidUnits * 2 + perPack) ~/ (perPack * 2);
  }

  static bool _whole(num packs, int perPack) => ((packs * perPack) - (packs * perPack).round()).abs() < 1e-6;
  String get batchId => Batch.idFor(medicine.id, batchNumber);

  /// Returns every problem with this entry; empty means it can be saved.
  /// [existing] is the batch already on record under the same batch number,
  /// if any — receiving more of it must not silently change its expiry or MRP.
  List<String> validate({required DateTime now, Batch? existing}) {
    final problems = <String>[];
    if (normalisedBatchNumber.isEmpty) problems.add('Enter the batch number printed on the pack.');
    if (expiryMonth < 1 || expiryMonth > 12) problems.add('Expiry month must be 1–12.');
    if (expiryYear < now.year || expiryYear > now.year + 15) {
      problems.add('Expiry year looks wrong.');
    } else if (!expiryDate.isAfter(now)) {
      problems.add('This batch has already expired — do not stock it.');
    }
    if (packs <= 0 || paidUnits <= 0) problems.add('Paid quantity must be more than zero.');
    if (freePacks < 0) problems.add('Free quantity cannot be negative.');
    final perPack = medicine.unitsPerPack < 1 ? 1 : medicine.unitsPerPack;
    if (!_whole(packs, perPack)) {
      problems.add('$packs packs of $perPack is not a whole number of units. Check the paid quantity.');
    }
    if (!_whole(freePacks, perPack)) {
      problems.add('$freePacks free packs of $perPack is not a whole number of units. Check the free quantity.');
    }
    if (mrpPaise <= 0) problems.add('Enter the MRP printed on the pack.');
    if (purchasePricePaise <= 0) problems.add('Enter the purchase rate per pack.');
    if (purchasePricePaise > mrpPaise && mrpPaise > 0) {
      problems.add('Purchase rate is higher than MRP — check both values.');
    }
    if (medicine.unitsPerPack < 1) problems.add('Units per pack must be at least 1.');
    if (existing != null) {
      if (existing.mrpPaise != mrpPaise) {
        problems.add('Batch $normalisedBatchNumber is already in stock at a different MRP. '
            'Check the batch number, or enter it with the MRP already on record.');
      }
      final sameExpiry = existing.expiryDate.year == expiryDate.year &&
          existing.expiryDate.month == expiryDate.month;
      if (!sameExpiry) {
        problems.add('Batch $normalisedBatchNumber is already in stock with a different expiry. '
            'Check the batch number and expiry.');
      }
    }
    return problems;
  }
}
