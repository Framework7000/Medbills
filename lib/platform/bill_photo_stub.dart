import 'dart:typed_data';

import '../domain/services/ocr_text.dart';
import 'photo_compress.dart';

Future<({Uint8List? jpeg, OcrPage? page})> prepareBillPhoto(Uint8List bytes) async =>
    (jpeg: await compressPhoto(bytes), page: null);
