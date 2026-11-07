import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../domain/services/ocr_text.dart';
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

Future<({Uint8List? jpeg, OcrPage? page})> prepareBillPhoto(Uint8List bytes) async {
  final upright = await compute(_upright, (bytes, 0));
  if (upright == null) return (jpeg: null, page: null);
  if (!DeviceFeatures.textReading) return (jpeg: await compressPhoto(upright), page: null);

  var best = upright;
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
      }
    }
  }
  return (jpeg: await compressPhoto(best), page: page);
}
