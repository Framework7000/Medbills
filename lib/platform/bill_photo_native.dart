import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/services/ocr_text.dart';
import '../domain/services/photo_clean.dart';
import '../domain/services/supplier_bill_parser.dart';
import 'device_features.dart';
import 'photo_compress.dart';
import 'text_reader.dart';

/// Upright JPEG for reading: the camera's rotation flag applied, at a size
/// text reading handles quickly, optionally turned a further [turn] degrees.
Uint8List? _upright((Uint8List, int) args) {
  final (bytes, turn) = args;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var image = img.bakeOrientation(decoded);
  if (turn != 0) image = img.copyRotate(image, angle: turn);
  final longest = image.width > image.height ? image.width : image.height;
  if (longest > 2400) {
    image = image.width >= image.height ? img.copyResize(image, width: 2400) : img.copyResize(image, height: 2400);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

/// The upright photo with its lighting evened out (see [flattenLighting]),
/// as a grey JPEG for a second reading.
Uint8List? _cleaned(Uint8List jpeg) {
  final image = img.decodeImage(jpeg);
  if (image == null) return null;
  final gray = Uint8List(image.width * image.height);
  var i = 0;
  for (final p in image) {
    gray[i++] = ((p.r * 77 + p.g * 150 + p.b * 29) / 256).floor();
  }
  final flat = flattenLighting(gray, image.width, image.height);
  final rgb = Uint8List(flat.length * 3);
  for (var k = 0; k < flat.length; k++) {
    rgb[k * 3] = rgb[k * 3 + 1] = rgb[k * 3 + 2] = flat[k];
  }
  final cleaned = img.Image.fromBytes(width: image.width, height: image.height, bytes: rgb.buffer, numChannels: 3);
  return Uint8List.fromList(img.encodeJpg(cleaned, quality: 90));
}

Future<OcrPage?> _read(Uint8List jpeg, String tag) async {
  final file = File('${Directory.systemTemp.path}${Platform.pathSeparator}medbills_bill_${tag}_${DateTime.now().microsecondsSinceEpoch}.jpg');
  try {
    await file.writeAsBytes(jpeg, flush: true);
    return await readTextFromPhoto(file.path);
  } finally {
    try {
      await file.delete();
    } catch (_) {}
  }
}

Future<({Uint8List? jpeg, OcrPage? page, OcrPage? cleaned})> prepareBillPhoto(Uint8List bytes) async {
  final upright = await compute(_upright, (bytes, 0));
  if (upright == null) return (jpeg: null, page: null, cleaned: null);
  if (!DeviceFeatures.textReading) return (jpeg: await compressPhoto(upright), page: null, cleaned: null);

  var best = upright;
  var turnedBy = 0; // degrees the photo was turned from how the phone saved it
  var page = await _read(upright, '0');
  // Text running up the page: the bill was photographed on its side.
  // Try both quarter turns and keep whichever reads best.
  if (page != null && page.uprightScore < 0) {
    for (final turn in const [90, 270]) {
      final turned = await compute(_upright, (bytes, turn));
      if (turned == null) continue;
      final p = await _read(turned, '$turn');
      if (p != null && p.uprightScore > (page?.uprightScore ?? 0) && p.readableChars >= (page?.readableChars ?? 0) * 0.6) {
        page = p;
        best = turned;
        turnedBy = turn;
      }
    }
  }
  // Upside down (the text reader reports every line at about 180°, or the
  // table's columns read in reverse, the amount first and the batch last):
  // turn the photo half a turn and read it again, so the picture kept with
  // the bill is the right way up too. Kept only if it reads at least as well.
  final first = page;
  if (first != null && !first.isEmpty) {
    final upsideDown = first.looksUpsideDown ||
        SupplierBillParser.readingScore(first, upsideDown: true) > SupplierBillParser.readingScore(first) + 4;
    if (upsideDown) {
      final flipped = await compute(_upright, (bytes, (turnedBy + 180) % 360));
      final p = flipped == null ? null : await _read(flipped, 'flip');
      if (flipped != null &&
          p != null &&
          p.readableChars >= first.readableChars * 0.6 &&
          SupplierBillParser.readingScore(p) >= SupplierBillParser.readingScore(first)) {
        page = p;
        best = flipped;
      }
    }
  }
  // A second reading of the same photo, cleaned up: a shadow, a dim corner
  // or faint print the first reading lost often reads here. A failure only
  // means there is no second reading.
  OcrPage? cleaned;
  try {
    final clean = await compute(_cleaned, best);
    if (clean != null) cleaned = await _read(clean, 'clean');
  } catch (_) {}
  return (jpeg: await compressPhoto(best), page: page, cleaned: cleaned);
}
