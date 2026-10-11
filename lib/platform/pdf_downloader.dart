import 'dart:typed_data';

import 'pdf_downloader_stub.dart'
    if (dart.library.js_interop) 'pdf_downloader_web.dart' as downloader;

/// Saves/shares a PDF. Web triggers a browser download (Blob URL + anchor —
/// the only approach that isn't blocked by pop-up blockers); iOS, Android,
/// macOS and Windows open the platform share sheet / save dialog.
Future<bool> savePdf(Uint8List bytes, String filename) {
  return downloader.downloadOrSharePdfBytes(bytes, filename);
}
