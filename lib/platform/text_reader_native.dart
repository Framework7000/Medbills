import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/services/ocr_text.dart';
import 'device_features.dart';

Future<OcrPage?> readTextFromPhoto(String path) async {
  if (!DeviceFeatures.textReading) return null;
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFilePath(path));
    return OcrPage([
      for (final block in result.blocks)
        for (final line in block.lines)
          OcrLine(
            line.text,
            left: line.boundingBox.left,
            top: line.boundingBox.top,
            right: line.boundingBox.right,
            bottom: line.boundingBox.bottom,
          ),
    ]);
  } finally {
    await recognizer.close();
  }
}
