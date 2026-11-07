import 'dart:typed_data';

import '../domain/services/ocr_text.dart';
import 'bill_photo_stub.dart' if (dart.library.io) 'bill_photo_native.dart' as impl;

/// A supplier-bill photo made ready: turned upright (the phone's rotation
/// flag applied, and turned again if the text reads sideways), read on the
/// device, and shrunk for keeping. [page] is null where reading isn't
/// available (the picture is still kept).
Future<({Uint8List? jpeg, OcrPage? page})> prepareBillPhoto(Uint8List bytes) => impl.prepareBillPhoto(bytes);
