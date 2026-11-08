import 'dart:math' as math;
import 'dart:typed_data';

/// A cleaned copy of a bill photo for a second reading: shadows, a dim
/// corner, a yellow page or uneven lamp light are evened out so the paper
/// is white everywhere, and faint print (a tired printer ribbon, a faded
/// thermal bill) is darkened.
///
/// [gray] is one brightness byte per pixel, row by row ([width] × [height]).
/// Returns a new buffer of the same size.
Uint8List flattenLighting(Uint8List gray, int width, int height) {
  if (width < 4 || height < 4 || gray.length < width * height) return Uint8List.fromList(gray);

  // The paper's brightness everywhere, worked out at half size: the
  // brightest value nearby (print is thinner than the window, so it drops
  // out), then softened.
  final hw = width ~/ 2, hh = height ~/ 2;
  var paper = Uint8List(hw * hh);
  for (var y = 0; y < hh; y++) {
    final a = 2 * y * width, b = a + width;
    for (var x = 0; x < hw; x++) {
      paper[y * hw + x] = (gray[a + 2 * x] + gray[a + 2 * x + 1] + gray[b + 2 * x] + gray[b + 2 * x + 1]) >> 2;
    }
  }
  const reach = 6; // half-size pixels: print strokes up to ~20 px wide at full size drop out
  paper = _slide(paper, hw, hh, reach, horizontal: true, max: true);
  paper = _slide(paper, hw, hh, reach, horizontal: false, max: true);
  paper = _slide(paper, hw, hh, 3, horizontal: true, max: false);
  paper = _slide(paper, hw, hh, 3, horizontal: false, max: false);

  // Divide each pixel by the paper's brightness there, so paper becomes
  // white and print keeps its contrast.
  final flat = Uint8List(width * height);
  final counts = Int32List(256);
  for (var y = 0; y < height; y++) {
    final py = ((y + 0.5) / 2 - 0.5).clamp(0.0, hh - 1.0);
    final y0 = py.floor(), y1 = math.min(y0 + 1, hh - 1);
    final fy = py - y0;
    for (var x = 0; x < width; x++) {
      final px = ((x + 0.5) / 2 - 0.5).clamp(0.0, hw - 1.0);
      final x0 = px.floor(), x1 = math.min(x0 + 1, hw - 1);
      final fx = px - x0;
      final top = paper[y0 * hw + x0] * (1 - fx) + paper[y0 * hw + x1] * fx;
      final bottom = paper[y1 * hw + x0] * (1 - fx) + paper[y1 * hw + x1] * fx;
      final background = math.max(top * (1 - fy) + bottom * fy, 16.0);
      final v = (gray[y * width + x] * 255 / background).round().clamp(0, 255);
      flat[y * width + x] = v;
      counts[v]++;
    }
  }

  // Stretch: the darkest print goes to black, ordinary paper (most of the
  // page) to white, and a gamma darkens faint grey print.
  final total = width * height;
  int level(double share) {
    var seen = 0;
    for (var v = 0; v < 256; v++) {
      seen += counts[v];
      if (seen >= total * share) return v;
    }
    return 255;
  }

  final lo = level(0.01);
  final hi = math.max(level(0.6), lo + 32);
  final table = Uint8List(256);
  for (var v = 0; v < 256; v++) {
    final t = ((v - lo) / (hi - lo)).clamp(0.0, 1.0);
    table[v] = (255 * math.pow(t, 1.3)).round();
  }
  for (var i = 0; i < flat.length; i++) {
    flat[i] = table[flat[i]];
  }
  return flat;
}

/// Running maximum (or mean) over a window of `2 × reach + 1` pixels along
/// each row or column.
Uint8List _slide(Uint8List src, int w, int h, int reach, {required bool horizontal, required bool max}) {
  final out = Uint8List(src.length);
  final length = horizontal ? w : h, lines = horizontal ? h : w;
  final step = horizontal ? 1 : w;
  final window = Int32List(length);
  for (var line = 0; line < lines; line++) {
    final start = horizontal ? line * w : line;
    for (var i = 0; i < length; i++) {
      window[i] = src[start + i * step];
    }
    if (max) {
      for (var i = 0; i < length; i++) {
        var best = 0;
        final from = math.max(0, i - reach), to = math.min(length - 1, i + reach);
        for (var k = from; k <= to; k++) {
          if (window[k] > best) best = window[k];
        }
        out[start + i * step] = best;
      }
    } else {
      var sum = 0, n = 0;
      for (var k = 0; k <= math.min(reach, length - 1); k++) {
        sum += window[k];
        n++;
      }
      for (var i = 0; i < length; i++) {
        out[start + i * step] = sum ~/ n;
        final add = i + reach + 1, drop = i - reach;
        if (add < length) {
          sum += window[add];
          n++;
        }
        if (drop >= 0) {
          sum -= window[drop];
          n--;
        }
      }
    }
  }
  return out;
}
