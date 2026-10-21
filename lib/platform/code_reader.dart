import 'code_reader_stub.dart' if (dart.library.io) 'code_reader_native.dart' as impl;

/// Finds a barcode, QR code or DataMatrix in a still photo, on the device.
/// Returns its text, or null when there is none or this device can't read
/// codes from photos.
Future<String?> readCodeFromPhoto(String path) => impl.readCodeFromPhoto(path);
