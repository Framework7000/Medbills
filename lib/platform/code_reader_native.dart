import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

import 'device_features.dart';

/// The codes printed on Indian medicine packs: retail barcodes, GS1
/// DataMatrix (with batch and expiry) and the Schedule H2 QR codes.
const packCodeFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upca,
  BarcodeFormat.upce,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.dataMatrix,
  BarcodeFormat.qrCode,
];

Future<String?> readCodeFromPhoto(String path) async {
  if (!DeviceFeatures.textReading) return null;
  final scanner = BarcodeScanner(formats: packCodeFormats);
  try {
    final codes = await scanner.processImage(InputImage.fromFilePath(path));
    return codes.map((c) => c.rawValue?.trim()).whereType<String>().where((v) => v.isNotEmpty).firstOrNull;
  } catch (_) {
    return null;
  } finally {
    await scanner.close();
  }
}
