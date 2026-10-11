import 'dart:typed_data';

import 'package:printing/printing.dart';

Future<bool> downloadOrSharePdfBytes(Uint8List bytes, String filename) async {
  try {
    return await Printing.sharePdf(bytes: bytes, filename: filename);
  } catch (_) {
    try {
      return await Printing.layoutPdf(onLayout: (_) async => bytes, name: filename);
    } catch (_) {
      return false;
    }
  }
}
