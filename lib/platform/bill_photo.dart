import 'dart:typed_data';

import '../domain/services/ocr_text.dart';
import 'bill_photo_stub.dart' if (dart.library.io) 'bill_photo_native.dart' as impl;

/// A supplier-bill photo made ready: turned upright (the phone's rotation
/// flag applied, and turned again if the text reads sideways), read on the
/// device, and shrunk for keeping. [page] is null where reading isn't
/// available (the picture is still kept). [cleaned] is a second reading of
/// the same photo with shadows and faint print evened out, to fill in what
/// the first reading missed.
Future<PreparedBillPhoto> prepareBillPhoto(Uint8List bytes) => impl.prepareBillPhoto(bytes);

typedef PreparedBillPhoto = ({Uint8List? jpeg, OcrPage? page, OcrPage? cleaned});
