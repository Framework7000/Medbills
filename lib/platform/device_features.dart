import 'package:flutter/foundation.dart';

/// What this device can do. Camera scanning and on-device text reading run
/// on iPhone/iPad and Android. Windows and Mac counters use a USB/Bluetooth
/// barcode scanner (it types into the search box) and receive scans and
/// bill photos from a phone.
class DeviceFeatures {
  static bool get _mobile =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  static bool get cameraScanning => _mobile;
  static bool get textReading => _mobile;

  /// A short label for scans sent from this device.
  static String get label => switch (defaultTargetPlatform) {
        _ when kIsWeb => 'Browser',
        TargetPlatform.iOS => 'iPhone',
        TargetPlatform.android => 'Android phone',
        TargetPlatform.macOS => 'Mac',
        TargetPlatform.windows => 'Windows PC',
        _ => 'Device',
      };
}
