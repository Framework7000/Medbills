import 'dart:convert';

import 'ocr_text.dart' show parseMonthYear;

/// What a scanned barcode / QR / DataMatrix actually says, decoded on the
/// device so the phone can show it plainly:
///
/// - [EInvoiceCode]: the signed GST e-invoice QR printed on supplier bills
///   (IRN QR): supplier and buyer GSTIN, invoice number and date, total,
///   item count, main HSN, IRN.
/// - [PackCode]: what a medicine pack's code carries: a plain EAN/UPC, GS1
///   (GTIN, batch, expiry, mfg date, serial), a GS1 Digital Link URL, or
///   the labelled text of a Schedule H2 QR (brand, generic name, maker,
///   batch, dates, licence, MRP).
/// - [TextCode]: anything else, kept as-is (shown, never guessed at).
sealed class ScannedCode {
  const ScannedCode(this.raw);
  final String raw;

  static ScannedCode decode(String raw) {
    final text = _stripSymbologyId(raw.trim());
    if (text.isEmpty) return TextCode(raw);
    return _eInvoice(text) ?? _pack(text) ?? TextCode(text);
  }
}

class EInvoiceCode extends ScannedCode {
  const EInvoiceCode(
    super.raw, {
    required this.sellerGstin,
    required this.buyerGstin,
    required this.docNo,
    required this.docType,
    required this.docDate,
    required this.totalPaise,
    required this.itemCount,
    required this.mainHsn,
    required this.irn,
    required this.irnDate,
  });

  final String sellerGstin;
  final String buyerGstin;
  final String docNo;
  final String docType; // INV, CRN (credit note), DBN (debit note)
  final DateTime? docDate;
  final int? totalPaise; // Rule 12: integer paise
  final int? itemCount;
  final String mainHsn;
  final String irn;
  final String irnDate;

  String get docTypeLabel => switch (docType.toUpperCase()) {
        'CRN' => 'Credit note',
        'DBN' => 'Debit note',
        _ => 'Tax invoice',
      };
}

class PackCode extends ScannedCode {
  const PackCode(
    super.raw, {
    this.gtin,
    this.batch,
    this.expiry,
    this.manufactured,
    this.serial,
    this.brand,
    this.genericName,
    this.manufacturer,
    this.licence,
    this.mrpPaise,
    this.url,
  });

  final String? gtin;
  final String? batch;
  final DateTime? expiry; // last day of the expiry month when only MM/YY is given
  final DateTime? manufactured;
  final String? serial;
  final String? brand;
  final String? genericName;
  final String? manufacturer;
  final String? licence;
  final int? mrpPaise;
  final String? url;

  /// Only a bare product number, nothing else (an ordinary retail barcode).
  bool get isPlainBarcode =>
      gtin != null && batch == null && expiry == null && brand == null && genericName == null && url == null;

  bool isExpiredAt(DateTime now) => expiry != null && expiry!.isBefore(DateTime(now.year, now.month, now.day));
}

class TextCode extends ScannedCode {
  const TextCode(super.raw);
  bool get isUrl => RegExp(r'^https?://', caseSensitive: false).hasMatch(raw);
}

// ---------------------------------------------------------------------------
// GST e-invoice QR: a signed JWT whose payload's "data" holds the invoice.

EInvoiceCode? _eInvoice(String text) {
  final parts = text.split('.');
  if (parts.length != 3 || parts[1].length < 40) return null;
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts[0]) || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(parts[1])) {
    return null;
  }
  try {
    final payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
    if (payload is! Map) return null;
    var data = payload['data'];
    if (data is String) data = jsonDecode(data);
    if (data is! Map) return null;
    String s(String key) => (data[key] ?? '').toString().trim();
    if (s('SellerGstin').isEmpty && s('Irn').isEmpty) return null;
    return EInvoiceCode(
      text,
      sellerGstin: s('SellerGstin').toUpperCase(),
      buyerGstin: s('BuyerGstin').toUpperCase(),
      docNo: s('DocNo'),
      docType: s('DocTyp').isEmpty ? 'INV' : s('DocTyp'),
      docDate: _dayMonthYear(s('DocDt')),
      totalPaise: _paise(data['TotInvVal']),
      itemCount: int.tryParse(s('ItemCnt')),
      mainHsn: s('MainHsnCode'),
      irn: s('Irn'),
      irnDate: s('IrnDt'),
    );
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Medicine pack codes.

PackCode? _pack(String text) {
  if (RegExp(r'^\d{8,14}$').hasMatch(text)) return PackCode(text, gtin: text);
  final url = RegExp(r'^https?://\S+$', caseSensitive: false).hasMatch(text) ? text : null;
  if (url != null) return _digitalLink(url);
  final gs1 = _gs1(text);
  if (gs1 != null) return gs1;
  return _labelled(text);
}

const _gs = '\u001d'; // FNC1 / group separator between variable-length fields

/// Fixed lengths of the GS1 application identifiers seen on medicine packs.
const _fixedAi = {'00': 18, '01': 14, '02': 14, '11': 6, '12': 6, '13': 6, '15': 6, '16': 6, '17': 6, '20': 2};
const _variableAi = {'10', '21', '22', '30', '37', '90', '91', '92', '93', '94', '95', '96', '97', '98', '99'};
const _variableAi3 = {'240', '241', '250', '251', '400', '710', '711', '712', '713', '714'};

PackCode? _gs1(String text) {
  final fields = <String, String>{};
  if (text.startsWith('(')) {
    final matches = RegExp(r'\((\d{2,4})\)([^(]*)').allMatches(text).toList();
    if (matches.isEmpty) return null;
    for (final m in matches) {
      fields[m.group(1)!] = m.group(2)!.replaceAll(_gs, '').trim();
    }
  } else if (RegExp(r'^(01\d{14}|0[02]\d|1[0-7]\d|21)').hasMatch(text) && (text.startsWith('01') || text.contains(_gs))) {
    var i = 0;
    while (i < text.length) {
      if (text[i] == _gs) {
        i++;
        continue;
      }
      if (i + 2 > text.length) break;
      final ai2 = text.substring(i, i + 2);
      final ai3 = i + 3 <= text.length ? text.substring(i, i + 3) : '';
      if (_fixedAi.containsKey(ai2)) {
        final end = i + 2 + _fixedAi[ai2]!;
        if (end > text.length) break;
        fields[ai2] = text.substring(i + 2, end);
        i = end;
      } else if (_variableAi.contains(ai2) || _variableAi3.contains(ai3)) {
        final ai = _variableAi3.contains(ai3) ? ai3 : ai2;
        final start = i + ai.length;
        var end = text.indexOf(_gs, start);
        if (end < 0) end = text.length;
        fields[ai] = text.substring(start, end).trim();
        i = end;
      } else {
        break;
      }
    }
  } else {
    return null;
  }
  if (!fields.containsKey('01') && !fields.containsKey('10') && !fields.containsKey('17')) return null;
  return PackCode(
    text,
    gtin: fields['01'],
    batch: _clean(fields['10']),
    expiry: _gs1Date(fields['17']),
    manufactured: _gs1Date(fields['11'], expiry: false),
    serial: _clean(fields['21']),
  );
}

/// GS1 Digital Link (`https://id.gs1.org/01/GTIN/10/BATCH?17=YYMMDD`) or
/// a maker's verification link carrying the details as query parameters.
PackCode? _digitalLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return PackCode(url, url: url);
  final seg = uri.pathSegments;
  final fields = <String, String>{};
  for (var i = 0; i + 1 < seg.length; i++) {
    if (RegExp(r'^\d{2,3}$').hasMatch(seg[i]) && (seg[i] == '01' || seg[i] == '10' || seg[i] == '21' || seg[i] == '17')) {
      fields[seg[i]] = Uri.decodeComponent(seg[i + 1]);
    }
  }
  final q = {for (final e in uri.queryParameters.entries) e.key.toLowerCase(): e.value};
  String? pick(List<String> keys) {
    for (final k in keys) {
      final v = q[k];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  return PackCode(
    url,
    url: url,
    gtin: fields['01'] ?? pick(['gtin', '01', 'upic', 'productcode']),
    batch: _clean(fields['10'] ?? pick(['batch', 'batchno', 'bn', 'lot', '10'])),
    expiry: _gs1Date(fields['17'] ?? q['17']) ?? _textDate(pick(['exp', 'expiry', 'expdate', 'expirydate']), endOfMonth: true),
    manufactured: _gs1Date(q['11'], expiry: false) ?? _textDate(pick(['mfg', 'mfgdate', 'mfd']), endOfMonth: false),
    serial: _clean(fields['21'] ?? pick(['serial', 'sn', '21'])),
  );
}

/// Labelled text, as most Schedule H2 QR codes print it:
/// "Brand Name: Dolo 650 | Generic Name: Paracetamol Tablets IP | Batch No: DOBS3975 | Mfg: 06/2024 | Exp: 05/2027 ..."
PackCode? _labelled(String text) {
  final parts = text
      .split(RegExp(r'[\n\r|;]+|,\s+(?=[A-Za-z .]{2,30}\s*[:=])'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty);
  final found = <String, String>{};
  for (final part in parts) {
    final m = RegExp(r'^([A-Za-z][A-Za-z .()/]{1,40}?)\s*[:=\-]\s*(.+)$').firstMatch(part);
    if (m == null) continue;
    final key = _labelKey(m.group(1)!);
    if (key != null) found.putIfAbsent(key, () => m.group(2)!.trim());
  }
  if (found.length < 2) return null;
  return PackCode(
    text,
    gtin: found['gtin'],
    brand: found['brand'],
    genericName: found['generic'],
    manufacturer: found['maker'],
    batch: _clean(found['batch']),
    expiry: _textDate(found['exp'], endOfMonth: true),
    manufactured: _textDate(found['mfg'], endOfMonth: false),
    licence: found['licence'],
    mrpPaise: _paise(RegExp(r'\d[\d,]*(?:\.\d+)?').firstMatch(found['mrp'] ?? '')?.group(0)),
    serial: found['serial'],
  );
}

String? _labelKey(String label) {
  final l = label.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (RegExp(r'^(brand|brand name|product name|trade name|name of (the )?product)$').hasMatch(l)) return 'brand';
  if (RegExp(r'(generic|proper|salt|composition)').hasMatch(l)) return 'generic';
  if (RegExp(r'(lic|licen[cs]e)').hasMatch(l)) return 'licence';
  if (RegExp(r'^(mfr|mfd by|manufacturer|manufactured by|marketed by|mkt by|name of (the )?manufacturer|manufacturer name( and address)?)').hasMatch(l)) {
    return 'maker';
  }
  if (RegExp(r'^(batch|batch no|b no|bno|lot|lot no)$').hasMatch(l)) return 'batch';
  if (RegExp(r'^(exp|expiry|exp date|expiry date|date of expiry|use before)$').hasMatch(l)) return 'exp';
  if (RegExp(r'^(mfg|mfd|mfg date|date of mfg|date of manufacture|manufacturing date|date of manufacturing)$').hasMatch(l)) {
    return 'mfg';
  }
  if (RegExp(r'^(mrp|m r p|price)$').hasMatch(l)) return 'mrp';
  if (RegExp(r'^(upic|unique product identification code|gtin|product code)$').hasMatch(l)) return 'gtin';
  if (RegExp(r'^(serial|serial no|sr no|sn)$').hasMatch(l)) return 'serial';
  return null;
}

// ---------------------------------------------------------------------------

String _stripSymbologyId(String s) => s.replaceFirst(RegExp(r'^\][A-Za-z]\d'), '');

String? _clean(String? s) {
  final v = s?.trim();
  return (v == null || v.isEmpty) ? null : v.toUpperCase();
}

/// GS1 YYMMDD. DD=00 means "month only": the last day for an expiry,
/// the first day for a manufacturing date.
DateTime? _gs1Date(String? v, {bool expiry = true}) {
  if (v == null || !RegExp(r'^\d{6}$').hasMatch(v)) return null;
  final y = 2000 + int.parse(v.substring(0, 2));
  final m = int.parse(v.substring(2, 4));
  final d = int.parse(v.substring(4, 6));
  if (m < 1 || m > 12) return null;
  if (d == 0) return expiry ? DateTime(y, m + 1, 0) : DateTime(y, m, 1);
  return DateTime(y, m, d);
}

/// "05/2027", "MAY 2027", "05/27" → that month (its last day for expiry);
/// "31/05/2027" → that day.
DateTime? _textDate(String? v, {required bool endOfMonth}) {
  if (v == null || v.trim().isEmpty) return null;
  final full = _dayMonthYear(v.trim());
  if (full != null) return full;
  final my = parseMonthYear(v.trim());
  if (my == null) return null;
  return endOfMonth ? DateTime(my.year, my.month + 1, 0) : DateTime(my.year, my.month, 1);
}

DateTime? _dayMonthYear(String v) {
  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})$').firstMatch(v.trim());
  if (m == null) return null;
  final d = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), y = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  return DateTime(y, mo, d);
}

/// Rupees (number or "1,234.50") → integer paise, without floating-point
/// drift (Rule 12).
int? _paise(Object? value) {
  if (value == null) return null;
  final s = value.toString().replaceAll(',', '').trim();
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2})\d*)?$').firstMatch(s);
  if (m == null) return null;
  final frac = (m.group(2) ?? '').padRight(2, '0');
  return int.parse(m.group(1)!) * 100 + int.parse(frac);
}
