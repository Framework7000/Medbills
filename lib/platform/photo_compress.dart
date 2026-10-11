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
