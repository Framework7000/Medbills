import 'package:flutter/widgets.dart';

import '../../domain/services/capture_guide.dart';
import 'smart_camera.dart';

bool get smartCameraAvailable => false;

Widget buildSmartCamera({
  required void Function(String code) onCode,
  required void Function(SmartCameraHandle handle) onReady,
  required Widget Function(String message) onError,
  void Function(FrameText frame)? onText,
}) =>
    onError('Camera not available here.');
