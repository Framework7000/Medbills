/// Parsed result from a scanned barcode.
class ParsedBarcode {
  final String? gtin;
  final String? batchNumber;
  final DateTime? expiryDate;

  const ParsedBarcode({this.gtin, this.batchNumber, this.expiryDate});
}

/// Parses GS1 DataMatrix 2D barcodes and plain EAN-13/UPC 1D barcodes off
/// pharmacy packaging.
///
/// Supports:
/// - Plain EAN-13/EAN-8/UPC-A (8-14 digit numeric strings)
/// - Parenthesized GS1: `(01)08901234567890(17)261200(10)BATCH123`
/// - Unparenthesized GS1: `01089012345678901726120010BATCH123`
class Gs1Parser {
  static const _giAi = '01'; // GTIN
  static const _expiryAi = '17'; // Expiry date YYMMDD
  static const _batchAi = '10'; // Batch/lot number (variable length)

  static ParsedBarcode parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const ParsedBarcode();

    if (trimmed.contains('(')) {
      return _parseParenthesized(trimmed);
    }

    if (RegExp(r'^\d{8,14}$').hasMatch(trimmed)) {
      return ParsedBarcode(gtin: trimmed);
    }

    if (RegExp(r'^01\d{14}').hasMatch(trimmed)) {
      return _parseUnparenthesized(trimmed);
    }

    return const ParsedBarcode();
  }

  static ParsedBarcode _parseParenthesized(String input) {
    String? gtin;
    String? batch;
    DateTime? expiry;

    final matches = RegExp(r'\((\d{2})\)([^(]+)').allMatches(input);
    for (final m in matches) {
      final ai = m.group(1);
      final value = m.group(2)?.trim() ?? '';
      if (ai == _giAi) {
        gtin = value;
      } else if (ai == _expiryAi) {
        expiry = _parseYyMmDd(value);
      } else if (ai == _batchAi) {
        batch = value;
      }
    }
    return ParsedBarcode(gtin: gtin, batchNumber: batch, expiryDate: expiry);
  }

  static ParsedBarcode _parseUnparenthesized(String input) {
    var cursor = 0;
    String? gtin;
    String? batch;
    DateTime? expiry;

    while (cursor < input.length - 1) {
      final ai = input.substring(cursor, cursor + 2);
      cursor += 2;
      if (ai == _giAi && cursor + 14 <= input.length) {
        gtin = input.substring(cursor, cursor + 14);
        cursor += 14;
      } else if (ai == _expiryAi && cursor + 6 <= input.length) {
        expiry = _parseYyMmDd(input.substring(cursor, cursor + 6));
        cursor += 6;
      } else if (ai == _batchAi) {
        batch = input.substring(cursor);
        cursor = input.length;
      } else {
        break;
      }
    }
    return ParsedBarcode(gtin: gtin, batchNumber: batch, expiryDate: expiry);
  }

  /// GS1 AI 17 rule: DD=00 means "last day of the given month".
  static DateTime? _parseYyMmDd(String value) {
    if (value.length != 6) return null;
    final yy = int.tryParse(value.substring(0, 2));
    final mm = int.tryParse(value.substring(2, 4));
    final dd = int.tryParse(value.substring(4, 6));
    if (yy == null || mm == null || dd == null) return null;
    final year = 2000 + yy;

    if (dd == 0) {
      final firstOfNextMonth =
          (mm == 12) ? DateTime(year + 1, 1, 1) : DateTime(year, mm + 1, 1);
      return firstOfNextMonth.subtract(const Duration(days: 1));
    }
    return DateTime(year, mm, dd);
  }
}
