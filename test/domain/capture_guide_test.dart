import 'package:flutter_test/flutter_test.dart';
import 'package:nuskha_pms/domain/services/capture_guide.dart';
import 'package:nuskha_pms/domain/services/ocr_text.dart';

/// A supplier bill as the live camera reads it, in a 1080 × 1920 frame.
FrameText bill({
  double left = 140,
  double top = 300,
  double width = 800,
  double lineHeight = 28,
  int rows = 20,
  double gap = 60,
  double luma = 140,
  double angle = 0,
  double dx = 0,
  double dy = 0,
}) {
  const words = ['TAX INVOICE', 'GSTIN 23AAKFS1234C1Z9', 'Batch Exp Qty Rate MRP Amount', 'TOTAL', 'CGST SGST'];
  return FrameText(
    width: 1080,
    height: 1920,
    meanLuma: luma,
    lines: [
      for (var i = 0; i < rows; i++)
        OcrLine(
          i < words.length ? words[i] : 'DOLO 650 TAB DL2401 05/27 20 33.60 24.19',
          left: left + dx,
          right: left + dx + width,
          top: top + dy + i * gap,
          bottom: top + dy + i * gap + lineHeight,
          angle: angle,
        ),
    ],
  );
}

void main() {
  test('nothing in view: point at it, then a tip on how to hold it', () {
    final g = CaptureGuide();
    const empty = FrameText(width: 1080, height: 1920, lines: [], meanLuma: 140);
    expect(g.update(empty).hint, CaptureHint.pointAtBill);
    for (var i = 0; i < CaptureGuide.tipAfterEmptyFrames; i++) {
      g.update(empty);
    }
    expect(g.update(empty).hint, CaptureHint.stillLooking);
    expect(g.update(const FrameText(width: 1080, height: 1920, lines: [], meanLuma: 30)).hint, CaptureHint.moreLight);
  });

  test('a whole, close, level, steady bill is captured by itself, once', () {
    final g = CaptureGuide();
    final first = g.update(bill());
    expect(first.isBill, isTrue);
    expect(first.hint, CaptureHint.holdSteady);
    expect(first.capture, isFalse);
    expect(g.update(bill(dx: 4)).hint, CaptureHint.holdSteady);
    final ready = g.update(bill(dx: 2));
    expect(ready.hint, CaptureHint.ready);
    expect(ready.capture, isTrue);
    expect(ready.progress, 1);
    // Still in view afterwards: not taken again.
    final after = g.update(bill());
    expect(after.capture, isFalse);
    expect(after.hint, CaptureHint.captured);
    // It leaves the picture, then a bill comes back: it can be taken again.
    g.update(const FrameText(width: 1080, height: 1920, lines: [], meanLuma: 140));
    g.update(bill());
    g.update(bill());
    expect(g.update(bill()).capture, isTrue);
  });

  test('moving phone: hold steady, never captured', () {
    final g = CaptureGuide();
    for (final shift in [0.0, 120.0, 0.0, 120.0, 0.0]) {
      final a = g.update(bill(dy: shift));
      expect(a.capture, isFalse);
      expect(a.hint, CaptureHint.holdSteady);
    }
  });

  test('each problem gets its own instruction', () {
    // Small print / far away.
    expect(CaptureGuide().update(bill(width: 300, lineHeight: 12, gap: 20)).hint, CaptureHint.moveCloser);
    // Running off the top of the picture.
    expect(CaptureGuide().update(bill(top: 5)).hint, CaptureHint.moveBack);
    // Running off the bottom.
    expect(CaptureGuide().update(bill(top: 600, gap: 70)).hint, CaptureHint.moveBack);
    // Off to one side.
    expect(CaptureGuide().update(bill(left: 20, width: 600, top: 100, gap: 50, rows: 24)).hint, CaptureHint.centre);
    // Turned.
    expect(CaptureGuide().update(bill(angle: 20)).hint, CaptureHint.straighten);
    expect(CaptureGuide().update(bill(angle: 88)).hint, isNot(CaptureHint.straighten),
        reason: 'a bill on its side is fine — it is turned afterwards');
    // Light.
    expect(CaptureGuide().update(bill(luma: 40)).hint, CaptureHint.moreLight);
    expect(CaptureGuide().update(bill(luma: 245)).hint, CaptureHint.tooBright);
  });

  test('a pack or a far-away bill is told apart from a bill up close', () {
    const pack = FrameText(width: 1080, height: 1920, meanLuma: 140, lines: [
      OcrLine('DOLO 650', left: 300, right: 700, top: 800, bottom: 860),
      OcrLine('Paracetamol Tablets IP', left: 300, right: 760, top: 880, bottom: 920),
    ]);
    final a = CaptureGuide().update(pack);
    expect(a.hint, CaptureHint.packSeen);
    expect(a.isBill, isFalse);
    expect(a.capture, isFalse);
    final far = FrameText(width: 1080, height: 1920, meanLuma: 140, lines: [
      for (var i = 0; i < 4; i++) OcrLine('SOME TEXT $i', left: 480, right: 600, top: 900.0 + i * 12, bottom: 908.0 + i * 12),
    ]);
    expect(CaptureGuide().update(far).hint, CaptureHint.billFound);
  });

  test('every instruction is plain English', () {
    for (final h in CaptureHint.values) {
      expect(h.message, matches(RegExp(r'^[A-Za-z0-9 ,.–—…\-]+$')), reason: h.name);
    }
  });
}
