import '../models/batch.dart';
import 'billing_calculator.dart' show formatRupees;

/// A fix to a received batch: a mistyped expiry, received date or price.
/// The quantity is never touched here (stock changes only through
/// receiving, selling and cancelling), and past bills keep the values they
/// were billed with.
class BatchCorrection {
  const BatchCorrection({
    required this.expiryDate,
    required this.receivedAt,
    required this.mrpPaise,
    required this.purchasePricePaise,
  });

  /// Pharmacy expiry is month-precision, so this is the last day of the month.
  final DateTime expiryDate;
  final DateTime receivedAt;
  final int mrpPaise; // GST-inclusive, per pack (Rule 4, Rule 12)
  final int purchasePricePaise; // per pack

  /// What is wrong with this correction, in plain words; empty when fine.
  List<String> problems(DateTime now) => [
        if (expiryDate.year < 2000 || expiryDate.year > 2100) 'Check the expiry year.',
        if (receivedAt.isAfter(DateTime(now.year, now.month, now.day + 1))) 'Received date cannot be in the future.',
        if (receivedAt.year < 2000) 'Check the received date.',
        if (mrpPaise <= 0) 'Enter the MRP.',
        if (purchasePricePaise < 0) 'Enter the purchase price.',
      ];

  bool changes(Batch b) =>
      expiryDate != b.expiryDate ||
      !_sameDay(receivedAt, b.createdAt) ||
      mrpPaise != b.mrpPaise ||
      purchasePricePaise != b.purchasePricePaise;

  /// For the audit log: only what changed, old → new.
  String describeAgainst(Batch b) => [
        if (expiryDate != b.expiryDate) 'expiry ${_my(b.expiryDate)} → ${_my(expiryDate)}',
        if (!_sameDay(receivedAt, b.createdAt)) 'received ${_dmy(b.createdAt)} → ${_dmy(receivedAt)}',
        if (mrpPaise != b.mrpPaise) 'MRP ${formatRupees(b.mrpPaise)} → ${formatRupees(mrpPaise)}',
        if (purchasePricePaise != b.purchasePricePaise)
          'cost ${formatRupees(b.purchasePricePaise)} → ${formatRupees(purchasePricePaise)}',
      ].join(', ');

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  static String _my(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.year}';
  static String _dmy(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
