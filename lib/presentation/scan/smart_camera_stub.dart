import 'package:flutter/widgets.dart';

import 'smart_camera.dart';

bool get smartCameraAvailable => false;

Widget buildSmartCamera({
  required void Function(String code) onCode,
  required void Function(SmartCameraHandle handle) onReady,
  required Widget Function(String message) onError,
}) =>
    onError('Camera not available here.');
