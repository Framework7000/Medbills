import 'billing_calculator.dart';
import 'ocr_text.dart';

/// What a pack's printed text says about the strip in hand.
class PackLabelInfo {
  final String? batchNumber;
  final int? expiryMonth;
  final int? expiryYear;
  final int? mrpPaise; // per pack, as printed

  const PackLabelInfo({this.batchNumber, this.expiryMonth, this.expiryYear, this.mrpPaise});

  bool get hasExpiry => expiryMonth != null && expiryYear != null;
  bool get isEmpty => batchNumber == null && !hasExpiry && mrpPaise == null;
}

/// Reads batch number, expiry and MRP from OCR text of a medicine pack, e.g.
///   "B.No. DL24061  MFG. 06/2024  EXP. 05/2027  M.R.P. ₹ 33.60 incl. of all taxes"
/// The manufacturing date is recognised so it is never taken as the expiry.
class PackLabelParser {
  static PackLabelInfo parse(String ocrText) {
    final text = ocrText.toUpperCase().replaceAll('\n', '  ');

    String? batch;
    final batchMatch = RegExp(
      r'(?:B\.?\s*NO|BATCH(?:\s*NO)?|LOT(?:\s*NO)?|B\.?\s*N)\s*[.:#]?\s*([A-Z0-9][A-Z0-9\-/]{2,15})',
    ).firstMatch(text);
    if (batchMatch != null) {
      final value = batchMatch.group(1)!.replaceAll(RegExp(r'[\-/]+$'), '');
      if (RegExp(r'\d').hasMatch(value)) batch = value;
    }

    ({int month, int year})? expiry;
    final expiryMatch = RegExp(
      '(?:EXP(?:IRY)?(?:\\s*DATE)?|USE\\s*BEFORE|EXP\\.?\\s*DT)\\s*[.:]?\\s*($monthYearPattern)',
    ).firstMatch(text);
    if (expiryMatch != null) expiry = parseMonthYear(expiryMatch.group(1)!);
    if (expiry == null) {
      // No "EXP" label read: take the later of two month-year dates (MFG is earlier).
      final dates = RegExp(monthYearPattern)
          .allMatches(text)
          .map((m) => parseMonthYear(m.group(0)!))
          .whereType<({int month, int year})>()
          .toList();
      if (dates.length >= 2) {
        dates.sort((a, b) => (a.year * 12 + a.month).compareTo(b.year * 12 + b.month));
        expiry = dates.last;
      }
    }

    int? mrp;
    final mrpMatch = RegExp(r'M\.?\s*R\.?\s*P\.?[^0-9]{0,24}?(\d{1,5}(?:[.,]\d{1,2})?)').firstMatch(text);
    if (mrpMatch != null) {
      final paise = parseRupeesToPaise(mrpMatch.group(1)!.replaceAll(',', '.'));
      if (paise != null && paise > 0) mrp = paise;
    }

    return PackLabelInfo(
      batchNumber: batch,
      expiryMonth: expiry?.month,
      expiryYear: expiry?.year,
      mrpPaise: mrp,
    );
  }
}
