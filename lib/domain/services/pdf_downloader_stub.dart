import 'dart:typed_data';

import 'package:printing/printing.dart';

/// Desktop/mobile implementation: share the PDF via the platform share
/// sheet, falling back to the system print dialog.
Future<bool> downloadOrPrintPdfBytes(
  Uint8List bytes,
  String filename, {
  String? htmlContent,
}) async {
  try {
    final success = await Printing.sharePdf(bytes: bytes, filename: filename);
    if (!success) {
      await Printing.layoutPdf(onLayout: (format) async => bytes, name: filename);
    }
    return true;
  } catch (_) {
    try {
      await Printing.layoutPdf(onLayout: (format) async => bytes, name: filename);
      return true;
    } catch (_) {
      return false;
    }
  }
}
