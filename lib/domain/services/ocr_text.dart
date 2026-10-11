/// Text read from a photo (on-device OCR), independent of the OCR engine.
class OcrLine {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const OcrLine(this.text, {this.left = 0, this.top = 0, this.right = 0, this.bottom = 0});

  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;
}

class OcrPage {
  final List<OcrLine> lines;
  const OcrPage(this.lines);

  factory OcrPage.fromText(String text) {
    final rows = text.split('\n');
    return OcrPage([
      for (var i = 0; i < rows.length; i++)
        if (rows[i].trim().isNotEmpty) OcrLine(rows[i].trim(), top: i * 20.0, bottom: i * 20.0 + 16, right: 1000),
    ]);
  }

  bool get isEmpty => lines.isEmpty;

  String get text => lines.map((l) => l.text).join('\n');

  /// Lines regrouped into visual rows (a bill's table row is often read as
  /// several separate pieces), each row's pieces ordered left to right.
  List<String> rows() {
    final sorted = [...lines]..sort((a, b) => a.centerY.compareTo(b.centerY));
    final rows = <List<OcrLine>>[];
    for (final line in sorted) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null) {
        final top = row.map((l) => l.top).reduce((a, b) => a < b ? a : b);
        final bottom = row.map((l) => l.bottom).reduce((a, b) => a > b ? a : b);
        final overlap = (bottom < line.bottom ? bottom : line.bottom) - (top > line.top ? top : line.top);
        final smaller = line.height < (bottom - top) ? line.height : bottom - top;
        if (smaller > 0 && overlap >= smaller * 0.5) {
          row.add(line);
          continue;
        }
      }
      rows.add([line]);
    }
    return [
      for (final row in rows) (row..sort((a, b) => a.left.compareTo(b.left))).map((l) => l.text).join('  '),
    ];
  }
}

/// Upper-case, punctuation folded to spaces — the form every matcher uses.
String normaliseOcr(String text) =>
    text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9.]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

const _months = {
  'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
  'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
};

/// Month + year as printed on packs and bills: 03/27, 3/2027, 03-2027,
/// MAR 27, MAR.2027, MAR-27.
({int month, int year})? parseMonthYear(String raw) {
  final s = raw.trim().toUpperCase();
  var m = RegExp(r'^(\d{1,2})\s*(?:[/\-]\s*(\d{4}|\d{2})|\.\s*(\d{4}))$').firstMatch(s);
  if (m != null) {
    final month = int.parse(m.group(1)!);
    final year = _year(m.group(2) ?? m.group(3)!);
    if (month >= 1 && month <= 12) return (month: month, year: year);
    return null;
  }
  m = RegExp('^($_monthNames)\\.?\\s*[\\-/.,]?\\s*(\\d{2}|\\d{4})\$').firstMatch(s);
  if (m != null) {
    return (month: _months[m.group(1)!.substring(0, 3)]!, year: _year(m.group(2)!));
  }
  return null;
}

int _year(String digits) => digits.length == 2 ? 2000 + int.parse(digits) : int.parse(digits);

/// Pattern for a month-year token inside longer text (used by the parsers).
/// A dot separator needs a 4-digit year so prices like 12.50 never read as
/// dates, and the tail of a full date (12/05/2027) is not taken as 05/2027.
// ignore: prefer_interpolation_to_compose_strings
const monthYearPattern = r'(?:(?<!\d|\d[/\-.])\d{1,2}\s*(?:[/\-]\s*(?:\d{4}|\d{2})|\.\s*\d{4})(?![/\-.]?\d)'
    r'|(?<![A-Z])' +
    _monthNames +
    r'\.?\s*[\-/.,]?\s*(?:\d{4}|\d{2})(?!\d))';

const _monthNames = r'(?:JAN(?:UARY)?|FEB(?:RUARY)?|MAR(?:CH)?|APR(?:IL)?|MAY|JUNE?|JULY?|AUG(?:UST)?'
    r'|SEPT?(?:EMBER)?|OCT(?:OBER)?|NOV(?:EMBER)?|DEC(?:EMBER)?)(?![A-Z])';
