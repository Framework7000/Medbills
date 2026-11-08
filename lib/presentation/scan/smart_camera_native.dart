import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../domain/services/capture_guide.dart';
import '../../domain/services/ocr_text.dart';
import '../../platform/code_reader_native.dart' show packCodeFormats;
import '../../platform/device_features.dart';
import 'smart_camera.dart';

bool get smartCameraAvailable => DeviceFeatures.isPhone;

Widget buildSmartCamera({
  required void Function(String code) onCode,
  required void Function(SmartCameraHandle handle) onReady,
  required Widget Function(String message) onError,
  void Function(FrameText frame)? onText,
}) =>
    _SmartCameraView(onCode: onCode, onReady: onReady, onError: onError, onText: onText);

class _SmartCameraView extends StatefulWidget {
  const _SmartCameraView({required this.onCode, required this.onReady, required this.onError, this.onText});
  final void Function(String code) onCode;
  final void Function(SmartCameraHandle handle) onReady;
  final Widget Function(String message) onError;
  final void Function(FrameText frame)? onText;

  @override
  State<_SmartCameraView> createState() => _SmartCameraViewState();
}

class _SmartCameraViewState extends State<_SmartCameraView> with WidgetsBindingObserver implements SmartCameraHandle {
  CameraController? _camera;
  final _scanner = BarcodeScanner(formats: packCodeFormats);
  TextRecognizer? _textReader;
  DateTime _lastTextRead = DateTime.fromMillisecondsSinceEpoch(0);

  /// How often a live frame is read for text (guidance only — the photo
  /// itself is read in full afterwards).
  static const _textEvery = Duration(milliseconds: 650);
  String? _error;
  bool _streaming = false;
  bool _reading = false; // one frame at a time; frames arriving meanwhile are dropped
  bool _torch = false;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final camera = _camera;
    _camera = null;
    unawaited(camera?.dispose());
    unawaited(_scanner.close());
    unawaited(_textReader?.close());
    super.dispose();
  }

  // The camera is released while the app is in the background and opened
  // again on return, as iOS and Android expect.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      final camera = _camera;
      _camera = null;
      _streaming = false;
      if (camera != null) {
        unawaited(camera.dispose());
        if (mounted) setState(() {});
      }
    } else if (state == AppLifecycleState.resumed && _camera == null && _error == null) {
      unawaited(_start());
    }
  }

  Future<void> _start() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('NoCamera', 'No camera found on this device.');
      final back = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cameras.first);
      final camera = CameraController(
        back,
        ResolutionPreset.veryHigh, // sharp enough to read small print on a bill
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      try {
        await camera.setFocusMode(FocusMode.auto);
      } catch (_) {}
      setState(() {
        _camera = camera;
        _error = null;
        _torch = false;
      });
      await _startStream();
      widget.onReady(this);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.code) {
            'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' =>
              'Camera permission is off. Allow camera access for MedBills in Settings.',
            _ => 'Camera unavailable: ${e.description ?? e.code}',
          });
    } catch (e) {
      // Anything else (camera busy, plugin missing) shows a message rather
      // than a blank screen; codes can still be typed or sent from a counter.
      if (mounted) setState(() => _error = 'Camera unavailable. Close other camera apps and try again.');
    }
  }

  Future<void> _startStream() async {
    final camera = _camera;
    if (camera == null || _streaming || !camera.value.isInitialized) return;
    await camera.startImageStream(_onFrame);
    _streaming = true;
  }

  Future<void> _stopStream() async {
    final camera = _camera;
    if (camera == null || !_streaming) return;
    _streaming = false;
    await camera.stopImageStream();
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_reading || _capturing) return;
    final input = _toInputImage(image);
    if (input == null) return;
    _reading = true;
    try {
      final codes = await _scanner.processImage(input);
      final raw = codes.map((c) => c.rawValue?.trim()).whereType<String>().where((v) => v.isNotEmpty).firstOrNull;
      if (raw != null && mounted) widget.onCode(raw);
      final onText = widget.onText;
      if (onText != null && !_capturing && DateTime.now().difference(_lastTextRead) >= _textEvery) {
        _lastTextRead = DateTime.now();
        final reader = _textReader ??= TextRecognizer(script: TextRecognitionScript.latin);
        final result = await reader.processImage(input);
        final meta = input.metadata!;
        final sideways = meta.rotation == InputImageRotation.rotation90deg || meta.rotation == InputImageRotation.rotation270deg;
        final light = _light(image);
        if (mounted) {
          onText(FrameText(
            width: sideways ? meta.size.height : meta.size.width,
            height: sideways ? meta.size.width : meta.size.height,
            meanLuma: light.mean,
            glare: light.glare,
            lines: [
              for (final block in result.blocks)
                for (final line in block.lines)
                  OcrLine(line.text,
                      left: line.boundingBox.left,
                      top: line.boundingBox.top,
                      right: line.boundingBox.right,
                      bottom: line.boundingBox.bottom,
                      angle: line.angle ?? 0),
            ],
          ));
        }
      }
    } catch (_) {
      // A frame that can't be read is skipped; the next one is along shortly.
    } finally {
      _reading = false;
    }
  }

  /// Average brightness 0–255 and the share of burnt-out white (glare),
  /// from a sample of the frame's pixels.
  static ({double mean, double glare}) _light(CameraImage image) {
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return (mean: 0, glare: 0);
    var sum = 0, n = 0, burnt = 0;
    void add(int y) {
      sum += y;
      n++;
      if (y >= 250) burnt++;
    }
    if (Platform.isIOS) {
      // BGRA: 4 bytes a pixel.
      for (var i = 0; i + 2 < bytes.length; i += 4 * 97) {
        add((bytes[i] * 29 + bytes[i + 1] * 150 + bytes[i + 2] * 77) >> 8);
      }
    } else {
      // NV21: the first width × height bytes are the brightness (Y) plane.
      final y = image.width * image.height;
      final end = y < bytes.length ? y : bytes.length;
      for (var i = 0; i < end; i += 97) {
        add(bytes[i]);
      }
    }
    return n == 0 ? (mean: 0.0, glare: 0.0) : (mean: sum / n, glare: burnt / n);
  }

  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  /// Camera frame → ML Kit input, per the ML Kit plugin's own example:
  /// BGRA on iOS, NV21 on Android, with the sensor's rotation.
  InputImage? _toInputImage(CameraImage image) {
    final camera = _camera;
    if (camera == null) return null;
    final sensor = camera.description.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensor);
    } else {
      var turn = _orientations[camera.value.deviceOrientation];
      if (turn == null) return null;
      turn = camera.description.lensDirection == CameraLensDirection.front
          ? (sensor + turn) % 360
          : (sensor - turn + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(turn);
    }
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw as int);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  Future<String?> takePhoto() async {
    final camera = _camera;
    if (camera == null || _capturing) return null;
    _capturing = true;
    try {
      await _stopStream();
      final photo = await camera.takePicture();
      return photo.path;
    } catch (_) {
      return null;
    } finally {
      _capturing = false;
      if (mounted && _camera == camera) {
        try {
          await _startStream();
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> toggleTorch() async {
    final camera = _camera;
    if (camera == null) return;
    try {
      await camera.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      _torch = !_torch;
    } catch (_) {}
  }

  Future<void> _focusAt(TapUpDetails details, BoxConstraints box) async {
    final camera = _camera;
    if (camera == null) return;
    final point = Offset(details.localPosition.dx / box.maxWidth, details.localPosition.dy / box.maxHeight);
    try {
      await camera.setFocusPoint(point);
      await camera.setExposurePoint(point);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return widget.onError(_error!);
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    // Fill the space like the system camera does (cover, not letterbox).
    final preview = camera.value.previewSize;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        onTapUp: (d) => _focusAt(d, box),
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              // previewSize is reported landscape; the phone is held upright.
              width: preview?.height ?? box.maxWidth,
              height: preview?.width ?? box.maxHeight,
              child: CameraPreview(camera),
            ),
          ),
        ),
      ),
    );
  }
}
