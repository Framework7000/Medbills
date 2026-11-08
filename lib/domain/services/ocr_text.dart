import 'dart:math' as math;

/// Text read from a photo (on-device OCR), independent of the OCR engine.
class OcrLine {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  /// How far the line is turned from level, in degrees (0 = straight).
  final double angle;

  const OcrLine(this.text, {this.left = 0, this.top = 0, this.right = 0, this.bottom = 0, this.angle = 0});

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

  /// Lines that run left to right (wider than tall) minus lines that run up
  /// or down. Negative: the photo is lying on its side and should be turned.
  int get uprightScore {
    var score = 0;
    for (final l in lines) {
      if (l.text.trim().length < 3) continue;
      final w = l.right - l.left;
      if (w > l.height * 1.2) score++;
      if (l.height > w * 1.2) score--;
    }
    return score;
  }

  /// The same reading with every box turned a quarter turn: [clockwise]
  /// true turns the page right. Used when a bill was read lying on its side,
  /// so its table rows line up again.
  OcrPage turned({required bool clockwise}) {
    if (lines.isEmpty) return this;
    final maxX = lines.map((l) => l.right).reduce((a, b) => a > b ? a : b);
    final maxY = lines.map((l) => l.bottom).reduce((a, b) => a > b ? a : b);
    return OcrPage([
      for (final l in lines)
        clockwise
            ? OcrLine(l.text, left: maxY - l.bottom, right: maxY - l.top, top: l.left, bottom: l.right)
            : OcrLine(l.text, left: l.top, right: l.bottom, top: maxX - l.right, bottom: maxX - l.left),
    ]);
  }

  /// How much readable text there is (letters and digits), to compare two
  /// readings of the same photo turned different ways.
  int get readableChars => lines.fold(0, (s, l) => s + l.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length);

  String get text => lines.map((l) => l.text).join('\n');

  /// Lines regrouped into visual rows (a bill's table row is often read as
  /// several separate pieces), each row's pieces ordered left to right.
  List<String> rows() {
    // A bill photographed a little turned has its table rows running
    // uphill: straighten the pieces first, or a medicine's name ends up on
    // the row of the prices below it.
    final slope = _slope();
    final textHeight = _textHeight();
    final placed = slope == 0
        ? lines
        : [
            for (final l in lines)
              () {
                final cy = l.centerY - (l.left + l.right) / 2 * slope;
                // A turned line's box is taller than its print; never below
                // half a line of print (or the box itself, if smaller).
                final floor = math.min(textHeight * 0.5, l.height);
                final h = (l.height - (l.right - l.left) * slope.abs()).clamp(floor, l.height);
                return OcrLine(l.text, left: l.left, right: l.right, top: cy - h / 2, bottom: cy + h / 2);
              }(),
          ];
    final sorted = [...placed]..sort((a, b) => a.centerY.compareTo(b.centerY));
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

  /// Height of one line of print: the boxes of short pieces (figures,
  /// codes), which a slight turn hardly makes taller.
  double _textHeight() {
    final short = [for (final l in lines) if (l.height > 0 && l.right - l.left < l.height * 6) l.height]..sort();
    final all = [for (final l in lines) if (l.height > 0) l.height]..sort();
    final pick = short.length >= 3 ? short : all;
    return pick.isEmpty ? 0 : pick[pick.length ~/ 2];
  }

  /// How steeply the rows run (rise per unit across), found by trying
  /// angles up to 12° either way and keeping the one that lines up the most
  /// pieces side by side. 0 when the page is level or there is too little
  /// to tell.
  double _slope() {
    if (lines.length < 6) return 0;
    final h = _textHeight();
    if (h <= 0) return 0;
    int aligned(double slope) {
      final ys = [for (final l in lines) l.centerY - (l.left + l.right) / 2 * slope];
      var count = 0;
      for (var i = 0; i < lines.length; i++) {
        for (var j = 0; j < lines.length; j++) {
          // Pieces side by side (not overlapping across) at the same height.
          if (i == j || lines[i].right > lines[j].left) continue;
          if ((ys[i] - ys[j]).abs() < h * 0.4) count++;
        }
      }
      return count;
    }

    final level = aligned(0);
    var best = 0.0, bestCount = level;
    for (var tenths = -120; tenths <= 120; tenths += 5) {
      if (tenths == 0) continue;
      final slope = math.tan(tenths / 10 * math.pi / 180);
      final count = aligned(slope);
      if (count > bestCount) {
        best = slope;
        bestCount = count;
      }
    }
    return bestCount >= level * 1.15 + 2 ? best : 0;
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
