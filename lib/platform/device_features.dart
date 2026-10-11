import 'package:flutter/foundation.dart';

/// What this device can do. Every device can scan: a USB/Bluetooth scanner
/// or typed code works everywhere; the camera works on iPhone, Android, Mac
/// and in a browser; reading printed text (packs, bills) runs on iPhone and
/// Android. A Windows/Mac counter can also receive scans sent from a phone.
class DeviceFeatures {
  static bool get _mobile =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);

  /// iPhone/iPad or Android phone.
  static bool get isPhone => _mobile;

  static bool get cameraScanning =>
      kIsWeb || _mobile || defaultTargetPlatform == TargetPlatform.macOS;
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
