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
    'ESTIMATE', 'CREDIT MEMO', 'BILL OF SUPPLY', 'CHALLAN', 'SUBJECT TO', 'JURISDICTION',
  ];

  /// [ownGstin] and [ownName] are the shop's own: a bill names the shop it
  /// is made out to, and that is never the supplier.
  static BillDraft parse(OcrPage page, Iterable<Medicine> medicines, {String ownGstin = '', String ownName = ''}) {
    // Read lying on its side (text running up or down the photo): every line
    // overlaps every other, so the whole bill would come out as one row. Turn
    // the boxes both ways and keep the reading that finds the most.
    if (page.uprightScore < 0) {
      final a = _parse(page.turned(clockwise: true), medicines, ownGstin, ownName);
      final b = _parse(page.turned(clockwise: false), medicines, ownGstin, ownName);
      return _score(a) >= _score(b) ? a : b;
    }
    return _parse(page, medicines, ownGstin, ownName);
  }

  static int _score(BillDraft d) =>
      d.lines.length * 10 +
      d.lines.where((l) => l.expiryMonth != null && l.batchNumber.isNotEmpty && l.packs > 0).length * 5 +
      (d.invoiceNumber.isEmpty ? 0 : 3) +
      (d.billTotalPaise == null ? 0 : 3);

  static BillDraft _parse(OcrPage page, Iterable<Medicine> medicines, String ownGstin, String ownName) {
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

    // A table header naming a GST % column.
    final gstColumn = rows.any((r) =>
        RegExp(r'GST\s*%|GST\s*RATE|\bGST\b').hasMatch(r) && (r.contains('RATE') || r.contains('MRP')) && r.contains('QTY'));
    // Which comes first in the table header, MRP or the rate (null: no header seen).
    bool? mrpBeforeRate;
    for (final r in rows) {
      final mrpAt = RegExp(r'\bMRP\b').firstMatch(r)?.start;
      final rateAt = RegExp(r'\b(?:RATE|PTR)\b').firstMatch(r)?.start;
      if (mrpAt != null && rateAt != null && r.contains('QTY')) {
        mrpBeforeRate = mrpAt < rateAt;
        break;
      }
    }
    final lines = <BillDraftLine>[];
    for (final row in rows) {
      final line = _parseItemRow(row, medicines, gstColumn: gstColumn, mrpBeforeRate: mrpBeforeRate);
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
      supplierName: _supplierName(rows, page, ownName),
      supplierGstin: gstins.isEmpty ? '' : gstins.first,
      supplierDrugLicence: dl,
      invoiceNumber: invoiceNumber,
      invoiceDate: date,
      billTotalPaise: total,
      lines: lines,
    );
  }

  static String _supplierName(List<String> rows, OcrPage page, String ownName) {
    final own = ownName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    bool usable(String piece) =>
        piece.replaceAll(RegExp(r'[^A-Z]'), '').length >= 5 &&
        !_notSupplier.any(piece.contains) &&
        !_gstin.hasMatch(piece) &&
        !_address.hasMatch(piece) &&
        // The table's header ("Qty Free MRP …") — even two of its words.
        _tableWords.where((w) => RegExp('\\b$w\\b').hasMatch(piece)).length < 2 &&
        // An item row (figures, dates, a batch) is not a name either.
        piece.replaceAll(RegExp(r'[^0-9]'), '').length * 5 <= piece.replaceAll(' ', '').length &&
        // The shop the bill is made out to.
        !(own.length >= 4 && piece.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').contains(own));
    String titled(String name) => name
        .replaceFirst(RegExp(r'^[^A-Za-z0-9]+'), '')
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) => w.length <= 1 ? w : w[0] + w.substring(1).toLowerCase())
        .join(' ');

    // 1. Written out: "Supplier: Om Sai Distributors", "From: …".
    for (final r in rows.take(15)) {
      final m = _labelledSupplier.firstMatch(r);
      if (m == null) continue;
      final piece = m.group(1)!.split(RegExp(r'\s{2,}')).first.trim();
      if (usable(piece)) return titled(piece);
    }

    // 2. The firm's name is printed biggest at the top of its bill.
    final upper = [for (final l in page.lines) l.copyWithText(l.text.toUpperCase())];
    final heights = [
      for (final l in upper)
        if (l.height > 0) l.height,
    ]..sort();
    if (heights.length >= 6) {
      final median = heights[heights.length ~/ 2];
      final top = upper.map((l) => l.top).reduce((a, b) => a < b ? a : b);
      final bottom = upper.map((l) => l.bottom).reduce((a, b) => a > b ? a : b);
      final head = upper.where((l) => l.top <= top + (bottom - top) * 0.3 && usable(l.text.trim())).toList()
        ..sort((a, b) => b.height.compareTo(a.height));
      if (head.isNotEmpty && head.first.height >= median * 1.35) return titled(head.first.text);
    }

    // 3. A bill's top row often carries the name and "TAX INVOICE" side by
    // side, so each column piece of a row is judged on its own.
    final head = [
      for (final r in rows.take(8))
        for (final piece in r.split(RegExp(r'\s{2,}')))
          if (usable(piece)) piece.trim(),
    ];
    final name = head.where((r) => _supplierWords.any(r.contains)).firstOrNull ?? head.firstOrNull;
    return name == null ? '' : titled(name);
  }

  static final _labelledSupplier =
      RegExp(r"(?:^|\s)(?:FROM|SUPPLIER|SOLD\s*BY|SELLER)\s*(?:NAME)?\s*:\s*([A-Z][A-Z0-9&.,' ]{3,60})");

  /// The item table's header row ("Description Pack Batch Exp Qty …") is
  /// never the supplier's name.
  static const _tableWords = ['DESCRIPTION', 'PARTICULARS', 'ITEM', 'PACK', 'BATCH', 'EXP', 'QTY', 'FREE', 'MRP', 'RATE', 'AMOUNT', 'HSN'];

  /// An address piece ("SHOP NO.89, GROUND FLOOR", "14, MAIN ROAD") is not a name.
  static final _address = RegExp(r'\b(SHOP|PLOT|FLOOR|ROAD|MARG|NAGAR|BAZAR|BAZAAR|STREET|COLONY|SECTOR|NEAR|OPP)\b|^\d|,.*,');

  /// A real item row is one line of the table; anything this long is many
  /// rows run together (a misread page), not one medicine.
  static const maxItemRowLength = 220;

  static const _gstRates = {0, 250, 500, 600, 900, 1200, 1400, 1800, 2800};

  static BillDraftLine? _parseItemRow(String row, Iterable<Medicine> medicines,
      {bool gstColumn = false, bool? mrpBeforeRate}) {
    if (row.length > maxItemRowLength) return null;
    // Table borders read as brackets or bars ("[136.12 |5.00") are not part
    // of any figure.
    final clean = row
        .replaceAll(RegExp(r'[\[\]{}|_]'), ' ')
        .replaceAllMapped(RegExp(r'(\d),(\d{3})'), (m) => '${m[1]}${m[2]}');
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
    String? findBatch(Iterable<String> tokens, {required bool mixedOnly}) {
      for (final t in tokens) {
        final token = t.replaceAll(RegExp(r'^[^A-Z0-9]+|[^A-Z0-9]+$'), '');
        if (!_looksLikeBatch(token) || nameTokens.contains(token)) continue;
        // Letters and digits together (TB7752) is far likelier a batch than
        // a bare number, which may be a misread price.
        if (mixedOnly && !RegExp(r'[A-Z]').hasMatch(token)) continue;
        return token;
      }
      return null;
    }
    // Most bills print the batch just before the expiry — check there first;
    // some print it right after the item name/pack, with quantity and
    // price columns between it and the expiry — then scan the whole row.
    final nearExpiry = beforeTokens.reversed.take(4).toList();
    batch = findBatch(nearExpiry, mixedOnly: true) ??
        findBatch(beforeTokens, mixedOnly: true) ??
        findBatch(nearExpiry, mixedOnly: false) ??
        findBatch(beforeTokens, mixedOnly: false) ??
        '';

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
    // A numbered table row with a batch and prices is an item too, even when
    // its expiry was misread — the pharmacist fills that in.
    final numbered = RegExp(r'^\s*\d{1,3}\s+[A-Z]').hasMatch(clean);
    final prices = RegExp(r'\d+\.\d{2}').allMatches(numberSource).length;
    final looksLikeItem = (guess != null && (expiry != null || batch.isNotEmpty)) ||
        (expiry != null && batch.isNotEmpty) ||
        (numbered && batch.isNotEmpty && prices >= 2);
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
    var money = numbers.skip(index).map((n) => parseRupeesToPaise(n)!).where((p) => p > 0).toList();
    // The bill has a GST % column: 5.00 / 12.00 / 18.00 in a row is that
    // rate, not a price (as long as two other figures remain).
    if (gstColumn) {
      final withoutRates = money.where((p) => !_gstRates.contains(p)).toList();
      if (withoutRates.length >= 2) money = withoutRates;
    }
    var priced = _pickRateAndMrp(money, qty, mrpBeforeRate: mrpBeforeRate);

    // Check the quantity against the amount column: quantity × rate is the
    // line amount (with or without GST). A misread quantity (an expiry read
    // as "727") is replaced by the one that adds up; a missing one is worked
    // out from amount ÷ rate when that is a whole number.
    if (priced.rate > 0) {
      bool addsUp(int q) => q > 0 && money.any((m) => const [1.0, 1.05, 1.12, 1.18].any((f) {
            final expected = q * priced.rate * f;
            return (m - expected).abs() <= expected * 0.02 + 50;
          }));
      if (!addsUp(qty)) {
        final ints = [for (final n in numbers) if (!n.contains('.') || n.endsWith('.00')) double.parse(n).round()];
        final found = ints.indexWhere((q) => q <= maxPacksPerLine && addsUp(q));
        if (found >= 0) {
          qty = ints[found];
          free = found + 1 < ints.length && ints[found + 1] <= qty ? ints[found + 1] : 0;
        } else if (qty == 0) {
          for (final m in money.where((m) => m > priced.rate)) {
            final q = m / priced.rate;
            if (q <= maxPacksPerLine && (q - q.round()).abs() < 0.02) {
              qty = q.round();
              break;
            }
          }
        }
        // The rate and MRP were chosen for the old quantity; choose again.
        priced = _pickRateAndMrp(money, qty, mrpBeforeRate: mrpBeforeRate);
      }
    }
    // The pair found sits in the wrong column order for this bill (the real
    // rate was misread, so the MRP was taken as the rate and some other
    // figure as the MRP): the rate is the line amount ÷ quantity, as long as
    // the MRP column then makes sense with it.
    if (qty > 0 && mrpBeforeRate != null && priced.rate > 0 && priced.mrp > 0 &&
        (money.indexOf(priced.mrp) < money.indexOf(priced.rate)) != mrpBeforeRate) {
      final amount = money.last;
      final rate = (amount / qty).round();
      final mrp = money
          .take(money.length - 1)
          .where((m) => m > rate && (m - rate) / m >= 0.08 && (m - rate) / m <= 0.45)
          .firstOrNull;
      if (mrp != null) priced = (rate: rate, mrp: mrp);
    }
    // No rate/MRP pair found, but a figure × quantity is the amount: that
    // figure is the rate (the MRP is left for the pharmacist).
    if (priced.rate == 0 && qty > 0) {
      for (final r in money) {
        if (money.any((m) => m != r && (m - r * qty).abs() <= r * qty * 0.02 + 50)) {
          final mrp = money.where((m) => m > r && m <= r * 4 && (m - r * qty).abs() > r * qty * 0.02 + 50).firstOrNull ?? 0;
          priced = (rate: r, mrp: mrp);
          break;
        }
      }
    }

    return BillDraftLine(
      rawText: row,
      medicineId: medicine?.id,
      medicineName: medicine?.name ?? guess?.name ?? _leadingWords(clean, batch),
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
  static ({int rate, int mrp}) _pickRateAndMrp(List<int> values, int qty, {bool? mrpBeforeRate}) {
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
        // The line amount (quantity × rate) is never the MRP.
        if (qty > 1 && const [1.0, 1.05, 1.12, 1.18].any((f) => (mrp - qty * rate * f).abs() <= qty * rate * f * 0.01 + 5)) {
          continue;
        }
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
        // MRP column usually comes first, unless this bill's header says otherwise.
        if ((mrpBeforeRate ?? true) ? i < j : j < i) score += 1;
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

  /// The item's name when no medicine matched: the first few words, up to
  /// the batch number, without a serial number misread as letters ("1" read
  /// as "IB", "I", "L|").
  static String _leadingWords(String row, [String batch = '']) {
    var text = row;
    final batchAt = batch.isEmpty ? -1 : text.indexOf(batch);
    if (batchAt > 0) text = text.substring(0, batchAt);
    text = text.replaceFirst(RegExp(r'^\s*[IL|!J][A-Z]?[.;:)|]?\s+(?=[A-Z]{3})'), '');
    final m = RegExp(r'[A-Z][A-Z0-9\-]*(?:\s+[A-Z0-9][A-Z0-9\-]*){0,3}').firstMatch(text);
    return m == null ? '' : m.group(0)!.trim();
  }
}
