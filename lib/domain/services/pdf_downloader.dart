import 'dart:typed_data';

import 'pdf_downloader_stub.dart'
    if (dart.library.html) 'pdf_downloader_web.dart' as downloader;

/// Conditional-import dispatcher: any code touching `dart:html` must live
/// behind this split, or desktop/mobile builds fail to compile (Defect 14.7).
Future<bool> downloadPdfBytes(
  Uint8List bytes,
  String filename, {
  String? htmlContent,
}) {
  return downloader.downloadOrPrintPdfBytes(bytes, filename, htmlContent: htmlContent);
}
