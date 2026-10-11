import '../domain/services/ocr_text.dart';
import 'text_reader_stub.dart' if (dart.library.io) 'text_reader_native.dart' as impl;

/// Reads printed text from a photo, on the device (nothing is uploaded).
/// Returns null where on-device reading isn't available.
Future<OcrPage?> readTextFromPhoto(String path) => impl.readTextFromPhoto(path);
