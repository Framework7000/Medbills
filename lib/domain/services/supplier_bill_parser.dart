import '../models/bill_scan.dart';
import '../models/medicine.dart';
import 'billing_calculator.dart';
import 'medicine_matcher.dart';
import 'ocr_text.dart';

/// Turns the OCR of a wholesale/stockist bill (Marg, Medica, hand-typed…)
/// into a draft purchase: supplier, GSTIN, drug licence, bill number and
/// date, and one line per medicine with batch, expiry, quantity, free,
/// rate and MRP. Nothing here is trusted blindly — the review screen shows
/// every value next to the row it came from.
class SupplierBillParser {
  static final _gstin = RegExp(r'\b\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]\b');
  static final _invoiceNo = RegExp(
      r'(?:INVOICE|INV|BILL)\s*(?:NO|NUMBER|#)\.?\s*[:.\-]?\s*([A-Z0-9][A-Z0-9\-/]{0,19})');
  static final _labelledDate = RegExp(r'(?:DATE|DATED|DT)\s*[.:]?\s*(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})\b');
  static final _anyDate = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})\b');
  static final _drugLicence = RegExp(r'\bD\.?\s*L\.?\s*(?:NO\.?|NOS\.?)?\s*[.:]\s*([A-Z0-9][A-Z0-9\-/ ,]{4,48})');
  static final _total = RegExp(r'(GRAND\s*TOTAL|NET\s*(?:AMOUNT|AMT|PAYABLE|TOTAL)|BILL\s*AMOUNT|INVOICE\s*TOTAL|TOTAL)');
  static const _supplierWords = [
    'PHARMA', 'MEDICAL', 'MEDICOS', 'MEDICINE', 'DISTRIBUTOR', 'AGENC', 'ENTERPRISE', 'TRADER', 'DRUG',
    'HEALTHCARE', 'SURGICAL', 'CHEMIST', 'STOCKIST', 'WHOLESALE', 'ASSOCIATES', 'CORPORATION', 'SALES',
  ];
  static const _notSupplier = ['INVOICE', 'GSTIN', 'PHONE', 'MOBILE', 'ORIGINAL', 'DUPLICATE', 'CASH MEMO', 'BILL TO'];

  static BillDraft parse(OcrPage page, Iterable<Medicine> medicines, {String ownGstin = ''}) {
    final rows = page.rows().map((r) => r.toUpperCase()).toList();
    final text = rows.join('\n');
    final own = ownGstin.trim().toUpperCase();

    final gstins = _gstin.allMatches(text).map((m) => m.group(0)!).where((g) => g != own).toList();

    String invoiceNumber = '';
    for (final row in rows) {
      final m = _invoiceNo.firstMatch(row);
      if (m != null && RegExp(r'\d').hasMatch(m.group(1)!)) {
        invoiceNumber = m.group(1)!;
        break;
      }
    }

    DateTime? date;
    final dm = _labelledDate.firstMatch(text) ?? _anyDate.firstMatch(text);
    if (dm != null) {
      final d = int.parse(dm.group(1)!), mo = int.parse(dm.group(2)!);
      final y = dm.group(3)!.length == 2 ? 2000 + int.parse(dm.group(3)!) : int.parse(dm.group(3)!);
      if (d >= 1 && d <= 31 && mo >= 1 && mo <= 12) date = DateTime(y, mo, d);
    }

    final dl = _drugLicence.firstMatch(text)?.group(1)?.trim().replaceAll(RegExp(r'[ ,]+$'), '') ?? '';

    final lines = <BillDraftLine>[];
    for (final row in rows) {
      final line = _parseItemRow(row, medicines);
      if (line != null) lines.add(line);
    }

    int? total;
    for (final row in rows) {
      if (_total.hasMatch(row) && !lines.any((l) => l.rawText == row)) {
        final numbers = RegExp(r'\d[\d,]*\.\d{2}').allMatches(row).toList();
        if (numbers.isNotEmpty) total = parseRupeesToPaise(numbers.last.group(0)!);
      }
    }

    return BillDraft(
      supplierName: _supplierName(rows),
      supplierGstin: gstins.isEmpty ? '' : gstins.first,
      supplierDrugLicence: dl,
      invoiceNumber: invoiceNumber,
      invoiceDate: date,
      billTotalPaise: total,
      lines: lines,
    );
  }

  static String _supplierName(List<String> rows) {
    final head = rows.take(8).where((r) {
      final letters = r.replaceAll(RegExp(r'[^A-Z]'), '');
      return letters.length >= 5 && !_notSupplier.any(r.contains) && !_gstin.hasMatch(r);
    }).toList();
    final named = head.where((r) => _supplierWords.any(r.contains)).firstOrNull ?? head.firstOrNull;
    if (named == null) return '';
    // Keep the name part of the row, not trailing columns.
    final name = named.split(RegExp(r'\s{2,}')).first.trim();
    return name.split(' ').map((w) => w.length <= 1 ? w : w[0] + w.substring(1).toLowerCase()).join(' ');
  }

  static BillDraftLine? _parseItemRow(String row, Iterable<Medicine> medicines) {
    final clean = row.replaceAllMapped(RegExp(r'(\d),(\d{3})'), (m) => '${m[1]}${m[2]}');
    final expiryMatch = RegExp(monthYearPattern).firstMatch(clean);
    final expiry = expiryMatch == null ? null : parseMonthYear(expiryMatch.group(0)!);
    final match = MedicineMatcher.match(clean, medicines);
    final medicine = match.best?.medicine;

    final before = expiryMatch == null ? clean : clean.substring(0, expiryMatch.start);
    final after = expiryMatch == null ? clean : clean.substring(expiryMatch.end);

    final nameTokens = medicine == null ? <String>{} : normaliseOcr(medicine.name).split(' ').toSet();
    final beforeTokens = before.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    String batch = '';
    for (final t in beforeTokens.reversed.take(4)) {
      final token = t.replaceAll(RegExp(r'^[^A-Z0-9]+|[^A-Z0-9]+$'), '');
      if (_looksLikeBatch(token) && !nameTokens.contains(token)) {
        batch = token;
        break;
      }
    }

    // Numbers after the expiry (or the whole row, if no expiry was read).
    final numberSource = expiryMatch == null && batch.isNotEmpty
        ? clean.substring(clean.indexOf(batch) + batch.length)
        : after;
    final numbers = RegExp(r'(?<![A-Z0-9.])(\d+(?:\.\d{1,2})?)(%?)(?![A-Z0-9])')
        .allMatches(numberSource)
        .where((m) => m.group(2)!.isEmpty)
        .map((m) => m.group(1)!)
        .toList();

    // An item row needs a medicine (or at least batch + expiry) and a quantity.
    final looksLikeItem = (medicine != null && (expiry != null || batch.isNotEmpty)) ||
        (expiry != null && batch.isNotEmpty);
    if (!looksLikeItem || numbers.isEmpty) return null;

    var index = 0;
    int qty = 0, free = 0;
    if (!numbers[0].contains('.') || numbers[0].endsWith('.00')) {
      qty = double.parse(numbers[0]).round();
      index = 1;
      if (numbers.length > 1 && !numbers[1].contains('.')) {
        final f = int.parse(numbers[1]);
        if (f <= qty) {
          free = f;
          index = 2;
        }
      }
    }
    final money = numbers.skip(index).map((n) => parseRupeesToPaise(n)!).where((p) => p > 0).toList();
    final priced = _pickRateAndMrp(money, qty);

    return BillDraftLine(
      rawText: row,
      medicineId: medicine?.id,
      medicineName: medicine?.name ?? _leadingWords(clean),
      batchNumber: batch,
      expiryMonth: expiry?.month,
      expiryYear: expiry?.year,
      packs: qty,
      freePacks: free,
      ratePaise: priced.rate,
      mrpPaise: priced.mrp,
    );
  }

  static bool _looksLikeBatch(String t) {
    if (t.length < 3 || t.length > 15) return false;
    if (!RegExp(r'^[A-Z0-9][A-Z0-9\-/]*$').hasMatch(t)) return false;
    if (!RegExp(r'\d').hasMatch(t)) return false;
    if (RegExp(r"^\d+'?S$|^\d+[X*]\d+$|^\d+(ML|GM|G|MG|MCG|KG|L|TAB|TABS|CAP|CAPS)$").hasMatch(t)) return false;
    if (RegExp(r'^\d+$').hasMatch(t)) return t.length >= 5 && !t.startsWith('300');
    return true;
  }

  /// Picks purchase rate and MRP (both per pack) from the row's money
  /// columns: MRP is above the rate (but not absurdly), and a column equal to
  /// quantity × rate (with or without GST) confirms the pair.
  static ({int rate, int mrp}) _pickRateAndMrp(List<int> values, int qty) {
    if (values.isEmpty) return (rate: 0, mrp: 0);
    if (values.length == 1) return (rate: 0, mrp: values.first);
    var best = (rate: 0, mrp: 0);
    var bestScore = -1 << 30;
    const percents = {500, 1200, 1800, 250, 600, 900, 2800};
    for (var i = 0; i < values.length; i++) {
      for (var j = 0; j < values.length; j++) {
        if (i == j) continue;
        final mrp = values[i], rate = values[j];
        if (rate <= 0 || mrp < rate || mrp > rate * 4) continue;
        var score = 0;
        if (qty > 0) {
          final amount = qty * rate;
          for (var k = 0; k < values.length; k++) {
            if (k == i || k == j) continue;
            for (final factor in const [1.0, 1.05, 1.12, 1.18]) {
              final expected = amount * factor;
              if ((values[k] - expected).abs() <= expected * 0.03 + 100) score = score < 10 ? 10 : score;
            }
          }
        }
        if (percents.contains(mrp)) score -= 3;
        if (percents.contains(rate)) score -= 3;
        if (i < j) score += 1; // MRP column usually comes first
        final margin = (mrp - rate) / mrp;
        if (margin >= 0.08 && margin <= 0.45) score += 2;
        if (score > bestScore) {
          bestScore = score;
          best = (rate: rate, mrp: mrp);
        }
      }
    }
    return best;
  }

  static String _leadingWords(String row) {
    final m = RegExp(r'[A-Z][A-Z0-9\-]*(?:\s+[A-Z0-9][A-Z0-9\-]*){0,3}').firstMatch(row);
    return m == null ? '' : m.group(0)!.trim();
  }
}
