import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Shrinks a photo to a readable JPEG under [maxBytes] (bill photos are kept
/// in the database, whose documents are limited to 1 MB).
Future<Uint8List?> compressPhoto(Uint8List bytes, {int maxBytes = 880 * 1024}) =>
    compute(_compress, (bytes, maxBytes));

Uint8List? _compress((Uint8List, int) args) {
  final (bytes, maxBytes) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  for (final (width, quality) in const [(1800, 72), (1500, 65), (1200, 60), (1000, 55), (800, 50)]) {
    final resized = oriented.width > width ? img.copyResize(oriented, width: width) : oriented;
    final jpeg = img.encodeJpg(resized, quality: quality);
    if (jpeg.length <= maxBytes) return Uint8List.fromList(jpeg);
  }
  return null;
}

/// Makes a logo, signature or seal picture small enough to keep with the
/// store (under [maxBytes]), keeping transparency where possible.
Future<Uint8List?> compressStamp(Uint8List bytes, {int maxBytes = 150 * 1024}) =>
    compute(_stamp, (bytes, maxBytes));

Uint8List? _stamp((Uint8List, int) args) {
  final (bytes, maxBytes) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  final oriented = img.bakeOrientation(decoded);
  for (final width in const [600, 450, 320]) {
    final resized = oriented.width > width ? img.copyResize(oriented, width: width) : oriented;
    final png = img.encodePng(resized, level: 9);
    if (png.length <= maxBytes) return Uint8List.fromList(png);
  }
  final small = oriented.width > 450 ? img.copyResize(oriented, width: 450) : oriented;
  final jpg = img.encodeJpg(small, quality: 80);
  return jpg.length <= maxBytes ? Uint8List.fromList(jpg) : null;
}
