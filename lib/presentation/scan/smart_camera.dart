import 'package:flutter/widgets.dart';

import 'smart_camera_stub.dart' if (dart.library.io) 'smart_camera_native.dart' as impl;

/// Controls for the live Smart Scan camera once it is running.
abstract class SmartCameraHandle {
  /// Takes a full-resolution photo from the live view (no separate camera
  /// app) and returns its file path, or null if it failed.
  Future<String?> takePhoto();
  Future<void> toggleTorch();
}

/// Whether this device has the in-app Smart Scan camera (iPhone/Android).
bool get smartCameraAvailable => impl.smartCameraAvailable;

/// One live camera that reports every barcode / QR / DataMatrix it sees
/// through [onCode] and can take a photo in place through the handle given
/// to [onReady]. [onError] builds what shows if the camera can't start.
Widget buildSmartCamera({
  required void Function(String code) onCode,
  required void Function(SmartCameraHandle handle) onReady,
  required Widget Function(String message) onError,
}) =>
    impl.buildSmartCamera(onCode: onCode, onReady: onReady, onError: onError);
