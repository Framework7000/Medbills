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
  // "M/S X" on a cash memo names the party being billed (us), not the
  // seller — and a bare "GST No." label (no number read after it) is worth
  // less as a fallback name than finding nothing.
  static const _notSupplier = [
    'INVOICE', 'GSTIN', 'GST NO', 'PHONE', 'MOBILE', 'ORIGINAL', 'DUPLICATE', 'CASH MEMO', 'BILL TO', 'M/S',
  ];

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
    // A row may carry both the manufacturing and the expiry month (MFG 01/25
    // EXP 12/27). The expiry is the one labelled EXP, else the later one —
    // a medicine always expires after it was made.
    final dateMatches = [
      for (final m in RegExp(monthYearPattern).allMatches(clean))
        if (parseMonthYear(m.group(0)!) != null) m,
    ];
    ({int month, int year})? expiry;
    for (final m in dateMatches) {
      final d = parseMonthYear(m.group(0)!)!;
      final label = clean.substring((m.start - 8).clamp(0, m.start), m.start);
      final isExp = label.contains('EXP') || label.contains('EX.') || label.contains('EXPIRY');
      final isMfg = label.contains('MFG') || label.contains('MFD') || label.contains('MANUF');
      if (isMfg && dateMatches.length > 1) continue;
      if (isExp || expiry == null || d.year * 12 + d.month > expiry.year * 12 + expiry.month) {
        expiry = d;
        if (isExp) break;
      }
    }
    final firstDate = dateMatches.isEmpty ? null : dateMatches.first;
    final match = MedicineMatcher.match(clean, medicines);
    // A weak/ambiguous match is still useful for finding the batch number and
    // as a starting guess, but auto-filling it as THE medicine when the
    // matcher itself isn't sure would silently show the wrong product —
    // only a confident match is trusted; anything else stays unmatched for
    // the pharmacist to confirm, same as a brand-new medicine would be.
    final guess = match.best?.medicine;
    final medicine = match.isConfident ? guess : null;

    final before = firstDate == null ? clean : clean.substring(0, firstDate.start);

    final nameTokens = guess == null ? <String>{} : normaliseOcr(guess.name).split(' ').toSet();
    final beforeTokens = before.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    String batch = '';
    // Most bills print the batch just before the expiry — check there first.
    for (final t in beforeTokens.reversed.take(4)) {
      final token = t.replaceAll(RegExp(r'^[^A-Z0-9]+|[^A-Z0-9]+$'), '');
      if (_looksLikeBatch(token) && !nameTokens.contains(token)) {
        batch = token;
        break;
      }
    }
    // Some print it right after the item name/pack instead, with the
    // quantity, MRP, rate and amount columns between it and the expiry —
    // scan the rest of the row for it.
    if (batch.isEmpty) {
      for (final t in beforeTokens) {
        final token = t.replaceAll(RegExp(r'^[^A-Z0-9]+|[^A-Z0-9]+$'), '');
        if (_looksLikeBatch(token) && !nameTokens.contains(token)) {
          batch = token;
          break;
        }
      }
    }

    // The quantity/price columns start right after the batch — never before
    // it, which matters when the item name itself has a bare number in it
    // (a strength like "ZTAB 200" with no unit attached). Fall back to the
    // whole row when no batch was found at all.
    final batchEnd = batch.isEmpty ? -1 : clean.indexOf(batch) + batch.length;
    var numberSource = batchEnd >= 0 ? clean.substring(batchEnd) : clean;
    // Blank out every date (expiry and manufacturing) so neither is read
    // as a quantity or a price.
    for (final m in dateMatches) {
      final offset = batchEnd >= 0 ? batchEnd : 0;
      final localStart = (m.start - offset).clamp(0, numberSource.length);
      final localEnd = (m.end - offset).clamp(0, numberSource.length);
      if (localEnd > localStart) {
        numberSource = numberSource.replaceRange(localStart, localEnd, ' ' * (localEnd - localStart));
      }
    }
    final numbers = RegExp(r'(?<![A-Z0-9.])(\d+(?:\.\d{1,2})?)(%?)(?![A-Z0-9])')
        .allMatches(numberSource)
        .where((m) => m.group(2)!.isEmpty)
        .map((m) => m.group(1)!)
        // An HSN code (3004, 300490, 30049099) is not a quantity or price.
        .where((n) => !_hsn.hasMatch(n))
        .toList();

    // An item row needs a medicine guess (confident or not — the pharmacist
    // confirms it either way) or at least batch + expiry, and a quantity.
    final looksLikeItem = (guess != null && (expiry != null || batch.isNotEmpty)) ||
        (expiry != null && batch.isNotEmpty);
    if (!looksLikeItem || numbers.isEmpty) return null;

    var index = 0;
    int qty = 0, free = 0;
    if (!numbers[0].contains('.') || numbers[0].endsWith('.00')) {
      qty = double.parse(numbers[0]).round();
      index = 1;
      // No shop orders thousands of packs on one line: that number is
      // something else (a code, an amount) — leave the quantity to fill in.
      if (qty > maxPacksPerLine) qty = 0;
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
      medicineName: medicine?.name ?? guess?.name ?? _leadingWords(clean),
      batchNumber: batch,
      expiryMonth: expiry?.month,
      expiryYear: expiry?.year,
      packs: qty,
      freePacks: free,
      ratePaise: priced.rate,
      mrpPaise: priced.mrp,
    );
  }

  /// HSN headings medicines are billed under (3004 medicaments, 3005
  /// dressings, 3006 pharmacy goods, 3304/3401 cosmetics and soaps, 9018
  /// instruments, 2106/2936 supplements), as 4, 6 or 8 digits.
  static final _hsn = RegExp(r'^(?:3001|3002|3003|3004|3005|3006|3304|3401|9018|9021|2106|2936)(?:\d{2}){0,2}$');

  /// Above this a "quantity" is taken to be a misread.
  static const maxPacksPerLine = 999;

  /// Labels read with their number ("NO-22", "SR.12", "HSN-3004") are not
  /// batch numbers.
  static final _labelToken = RegExp(r'^(?:NO|SR|SL|SNO|PG|PAGE|DT|DATE|HSN|GST|INV|BILL|PH|MOB|DL|FSSAI|EXP|MFG|QTY|PCS|CGST|SGST|IGST)[\-/.]?\d');

  static bool _looksLikeBatch(String t) {
    if (t.length < 3 || t.length > 15) return false;
    if (_labelToken.hasMatch(t)) return false;
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
