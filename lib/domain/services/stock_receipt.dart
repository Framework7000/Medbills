import '../models/batch.dart';
import '../models/medicine.dart';

/// A supplier delivery of one batch of one medicine.
class StockReceipt {
  /// The store medicine being stocked. If it doesn't exist in the store yet
  /// (e.g. promoted from the master catalogue), the backend creates it.
  final Medicine medicine;
  final String batchNumber;
  final int expiryMonth;
  final int expiryYear;
  final int packs; // paid packs
  final int freePacks; // scheme / free packs
  final int purchasePricePaise; // per pack
  final int mrpPaise; // per pack
  final String supplierName;
  final String supplierInvoiceNumber;

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
  });

  String get normalisedBatchNumber => Batch.normaliseBatchNumber(batchNumber);
  DateTime get expiryDate => Batch.endOfMonth(expiryYear, expiryMonth);
  int get totalUnits => (packs + freePacks) * medicine.unitsPerPack;
  int get freeUnits => freePacks * medicine.unitsPerPack;
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
    if (packs <= 0) problems.add('Paid quantity must be at least 1 pack.');
    if (freePacks < 0) problems.add('Free quantity cannot be negative.');
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
