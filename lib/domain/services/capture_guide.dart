import 'ocr_text.dart';

/// What the live camera tells the person holding it, one plain instruction
/// at a time, until the bill is close, whole, level, lit and steady.
enum CaptureHint {
  pointAtBill('Point the camera at the bill or the medicine pack'),
  stillLooking('Hold the bill flat, 20–30 cm away, in good light'),
  moreLight('Too dark — turn on the torch'),
  tooBright('Too much glare — tilt the bill away from the light'),
  packSeen('Pack found — show its barcode, or tap the white button'),
  billFound('Bill found — bring the camera closer'),
  moveCloser('Move closer — the print is too small'),
  moveBack('Move back — fit the whole bill in the picture'),
  centre('Move the bill to the middle of the screen'),
  straighten('Hold the phone straight over the bill'),
  holdSteady('Hold steady…'),
  ready('Capturing the bill…'),
  captured('Bill captured — reading it');

  const CaptureHint(this.message);
  final String message;

  /// Shown in amber: something to fix before the photo can be taken.
  bool get isProblem => !{holdSteady, ready, captured, billFound}.contains(this);
}

/// One live frame's reading: the text found, in the coordinates of the
/// upright frame ([width] × [height]), and its average brightness (0–255).
class FrameText {
  final double width;
  final double height;
  final List<OcrLine> lines;
  final double meanLuma;

  const FrameText({required this.width, required this.height, required this.lines, required this.meanLuma});
}

/// A rectangle in 0..1 of the frame (left, top, right, bottom).
class NormRect {
  final double left, top, right, bottom;
  const NormRect(this.left, this.top, this.right, this.bottom);

  double get width => right - left;
  double get height => bottom - top;
  double get area => width * height;
  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
}

class CaptureAdvice {
  final CaptureHint hint;
  /// Where the text is, for drawing a box around it (null: nothing seen).
  final NormRect? area;
  /// True once per bill: take the photo now.
  final bool capture;
  /// The frame looks like a supplier bill.
  final bool isBill;
  /// 0..1: how close the bill is to being captured (for a progress ring).
  final double progress;

  const CaptureAdvice(this.hint, {this.area, this.capture = false, this.isBill = false, this.progress = 0});
}

/// Turns live frame readings into one plain instruction and decides when a
/// supplier bill is close enough, whole, level, lit and steady enough to
/// photograph by itself. Packs are read from their codes (or the shutter),
/// so only bills are captured automatically.
class CaptureGuide {
  /// Darker than this (average 0–255) is too dark to read small print.
  static const minLuma = 70.0;

  /// Brighter than this is washed out (glare on glossy paper).
  static const maxLuma = 235.0;

  /// The bill's text should fill at least this much of the picture.
  static const minArea = 0.28;

  /// Typical line height (of the frame's longer side) below which print is
  /// too small to read reliably.
  static const minLineHeight = 0.010;

  /// Text this close to the top or bottom edge means part of the bill is cut off.
  static const edge = 0.012;

  /// The middle of the text further than this from the middle of the picture.
  static const offCentre = 0.18;

  /// Lines turned more than this many degrees: the phone is not level.
  static const maxTilt = 12.0;

  /// Steady = the text area moved less than this between frames.
  static const steadyShift = 0.035;

  /// Good, steady frames in a row before taking the photo.
  static const steadyFramesNeeded = 2;

  /// Frames with nothing readable before the "how to hold it" tip.
  static const tipAfterEmptyFrames = 4;

  static const _billWords = [
    'INVOICE', 'GSTIN', 'GST', 'BATCH', 'EXP', 'QTY', 'RATE', 'MRP', 'AMOUNT', 'TOTAL', 'HSN', 'BILL', 'D.L', 'DL NO',
    'CGST', 'SGST', 'TAXABLE', 'PACK', 'DISC', 'FREE', 'NET', 'CASH', 'CREDIT', 'M/S',
  ];

  NormRect? _last;
  int _steady = 0;
  int _empty = 0;
  bool _captured = false;

  /// Starts over (the camera came back, or a new bill is wanted).
  void reset() {
    _last = null;
    _steady = 0;
    _empty = 0;
    _captured = false;
  }

  /// Bill words or many lines of text: a supplier bill rather than a pack.
  static bool looksLikeBill(List<OcrLine> lines) {
    if (lines.length < 5) return false;
    final text = lines.map((l) => l.text.toUpperCase()).join(' ');
    final words = _billWords.where(text.contains).length;
    return words >= 3 || (words >= 2 && lines.length >= 8) || lines.length >= 18;
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    return sorted[sorted.length ~/ 2];
  }

  CaptureAdvice update(FrameText f) {
    final lines = f.lines.where((l) => l.text.trim().length >= 2 && l.right > l.left && l.bottom > l.top).toList();
    if (lines.isEmpty || f.width <= 0 || f.height <= 0) {
      _last = null;
      _steady = 0;
      _empty++;
      // A bill that left the picture may be photographed again.
      _captured = false;
      if (f.meanLuma > 0 && f.meanLuma < minLuma) return const CaptureAdvice(CaptureHint.moreLight);
      return CaptureAdvice(_empty >= tipAfterEmptyFrames ? CaptureHint.stillLooking : CaptureHint.pointAtBill);
    }
    _empty = 0;

    var l = double.infinity, t = double.infinity, r = 0.0, b = 0.0;
    for (final line in lines) {
      if (line.left < l) l = line.left;
      if (line.top < t) t = line.top;
      if (line.right > r) r = line.right;
      if (line.bottom > b) b = line.bottom;
    }
    final area = NormRect(
      (l / f.width).clamp(0.0, 1.0),
      (t / f.height).clamp(0.0, 1.0),
      (r / f.width).clamp(0.0, 1.0),
      (b / f.height).clamp(0.0, 1.0),
    );

    if (!looksLikeBill(lines)) {
      // A pack, a label, a few words: its code reads by itself, or the
      // shutter. A handful of lines spread wide may be a bill too far away.
      _last = area;
      _steady = 0;
      final CaptureHint hint;
      if (f.meanLuma < minLuma) {
        hint = CaptureHint.moreLight;
      } else if (lines.length >= 3 && area.area < 0.12) {
        hint = CaptureHint.billFound;
      } else {
        hint = CaptureHint.packSeen;
      }
      return CaptureAdvice(hint, area: area);
    }

    // Line height: the smaller side of each line's box (a bill read on its
    // side has tall, thin lines), median over the lines, against the frame.
    final lineHeight = _median([
      for (final line in lines)
        (line.right - line.left) < (line.bottom - line.top) ? (line.right - line.left) : (line.bottom - line.top),
    ]) / (f.width > f.height ? f.width : f.height);
    // Tilt: how far lines are from level or from upright (a bill photographed
    // on its side is fine — it is turned afterwards).
    final tilt = _median([
      for (final line in lines.where((x) => x.text.trim().length >= 6))
        () {
          final a = line.angle.abs() % 90;
          return a > 45 ? 90 - a : a;
        }(),
      0,
    ]);

    final last = _last;
    CaptureHint hint;
    var progress = 0.25;
    if (f.meanLuma < minLuma) {
      hint = CaptureHint.moreLight;
    } else if (f.meanLuma > maxLuma) {
      hint = CaptureHint.tooBright;
    } else if (area.top < edge || area.bottom > 1 - edge || (area.left < edge && area.right > 1 - edge)) {
      hint = CaptureHint.moveBack;
      progress = 0.5;
    } else if (area.area < minArea || lineHeight < minLineHeight) {
      hint = CaptureHint.moveCloser;
      progress = 0.4;
    } else if ((area.cx - 0.5).abs() > offCentre || (area.cy - 0.5).abs() > offCentre) {
      hint = CaptureHint.centre;
      progress = 0.6;
    } else if (tilt > maxTilt) {
      hint = CaptureHint.straighten;
      progress = 0.6;
    } else {
      final steady = last != null &&
          (area.cx - last.cx).abs() < steadyShift &&
          (area.cy - last.cy).abs() < steadyShift &&
          (area.width - last.width).abs() < steadyShift * 2 &&
          (area.height - last.height).abs() < steadyShift * 2;
      _steady = steady ? _steady + 1 : 0;
      hint = _steady >= steadyFramesNeeded ? CaptureHint.ready : CaptureHint.holdSteady;
      progress = 0.75 + 0.25 * (_steady / steadyFramesNeeded).clamp(0.0, 1.0);
    }
    if (hint != CaptureHint.ready && hint != CaptureHint.holdSteady) _steady = 0;
    _last = area;

    // One photo per bill: after it is taken, nothing more until the bill
    // leaves the picture (see the empty-frame case above) or another bill
    // takes its place (the text area jumps).
    final previous = last;
    if (_captured &&
        previous != null &&
        ((area.cx - previous.cx).abs() > 0.25 || (area.width - previous.width).abs() > 0.3)) {
      _captured = false;
    }
    if (_captured) return CaptureAdvice(CaptureHint.captured, area: area, isBill: true, progress: 1);
    final capture = hint == CaptureHint.ready;
    if (capture) _captured = true;
    return CaptureAdvice(hint, area: area, capture: capture, isBill: true, progress: progress);
  }
}
