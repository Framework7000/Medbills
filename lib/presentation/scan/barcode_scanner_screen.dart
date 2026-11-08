import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../domain/services/capture_guide.dart';
import '../theme.dart';
import 'smart_camera.dart';
import '../widgets/common.dart' show friendlyError;

/// What happened to one scan, shown over the camera.
class ScanFeedback {
  const ScanFeedback(
    this.message, {
    this.ok = true,
    this.actionLabel,
    this.onAction,
    this.undoToken,
    this.appliedBatchId,
    this.appliedUnits,
  });
  final String message;
  final bool ok;
  final String? actionLabel;
  /// The scan-event id, when this was a send to a counter — lets [onUndo]
  /// cancel exactly this one within its 3-second window.
  final String? undoToken;
  /// What was actually added to a bill, when this added locally — lets a
  /// receiving counter reverse exactly this scan if the sender undoes it.
  final String? appliedBatchId;
  final int? appliedUnits;
  final VoidCallback? onAction;
}

const _formats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.dataMatrix,
  BarcodeFormat.qrCode,
];

/// Keeps the camera open and hands every new code to [onScan] — for billing
/// many packs in a row. The same code is ignored for 2.5 s so one pack held
/// under the camera isn't added twice.
///
/// [onCapturePhoto], when given, adds a shutter button for anything that
/// isn't a barcode (a pack label, a supplier bill) — Smart Scan uses it to
/// read and route a photo without leaving this screen. On a phone the photo
/// is taken from the same live camera and its path is passed in; elsewhere
/// the path is null and the callback picks a photo itself. It returns null
/// when the user cancelled (nothing to show).
///
/// [pendingLabel], when given, is shown while a scan is in flight — e.g.
/// "Sending to Counter 1…" when a remote station is the target.
/// [onUndo], when given alongside a successful send, offers a 3-second
/// undo window after each one.
Future<void> openContinuousScanner(
  BuildContext context, {
  required String title,
  required Future<ScanFeedback> Function(String raw) onScan,
  Widget? header,
  Widget? compactHeader,
  Future<ScanFeedback?> Function(String? photoPath)? onCapturePhoto,
  String Function()? pendingLabel,
  Future<void> Function(ScanFeedback sent)? onUndo,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _ScannerScreen(
      title: title,
      onScan: onScan,
      header: header,
      compactHeader: compactHeader,
      onCapturePhoto: onCapturePhoto,
      pendingLabel: pendingLabel,
      onUndo: onUndo,
    ),
  ));
}

/// Scans one code and returns it (e.g. to save a medicine's barcode).
Future<String?> scanSingleBarcode(BuildContext context, {String title = 'Scan barcode'}) {
  return Navigator.of(context).push(MaterialPageRoute<String>(
    fullscreenDialog: true,
    builder: (_) => _ScannerScreen(title: title, single: true),
  ));
}

class _ScannerScreen extends StatefulWidget {
  const _ScannerScreen({
    required this.title,
    this.onScan,
    this.header,
    this.compactHeader,
    this.single = false,
    this.onCapturePhoto,
    this.pendingLabel,
    this.onUndo,
  });
  final String title;
  final Future<ScanFeedback> Function(String raw)? onScan;
  final Widget? header;
  /// On a phone's full-screen Smart Scan camera, a small control shown over
  /// the top of the picture (where scans go) instead of [header] below it.
  final Widget? compactHeader;
  final bool single;
  final Future<ScanFeedback?> Function(String? photoPath)? onCapturePhoto;
  final String Function()? pendingLabel;
  final Future<void> Function(ScanFeedback sent)? onUndo;

  @override
  State<_ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<_ScannerScreen> {
  final _controller = MobileScannerController(formats: _formats, detectionSpeed: DetectionSpeed.normal);
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _busy = false;
  bool _done = false;
  ScanFeedback? _feedback;
  String? _pendingText;
  bool _waitingForInternet = false;
  Timer? _waitingTimer;
  int _count = 0;
  int _burst = 0; // bumped on every success to retrigger the confirm animation
  int _shake = 0; // bumped on every failure to retrigger the shake
  int _feedbackSeq = 0; // bumped on every feedback to retrigger its entrance

  /// The phone's own live camera (codes + photos in place), when Smart Scan
  /// runs on a phone; otherwise [_controller]'s barcode scanner is used.
  bool get _useSmartCamera => widget.onCapturePhoto != null && smartCameraAvailable;
  SmartCameraHandle? _camera;

  // Live guidance: what the camera sees, and the one instruction it gives.
  final _guide = CaptureGuide();
  CaptureAdvice? _advice;
  Size? _frameSize;

  void _onFrameText(FrameText frame) {
    if (!mounted) return;
    if (_busy) return;
    final advice = _guide.update(frame);
    setState(() {
      _advice = advice;
      _frameSize = Size(frame.width, frame.height);
    });
    // A whole, steady, readable bill: photograph it without a tap.
    if (advice.capture) {
      unawaited(HapticFeedback.lightImpact());
      unawaited(_onCapture());
    }
  }

  // The 3-second undo window after a send.
  ScanFeedback? _undoable;
  int _undoSecondsLeft = 0;
  Timer? _undoTimer;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    _waitingTimer?.cancel();
    _undoTimer?.cancel();
    super.dispose();
  }

  void _startUndoCountdown(ScanFeedback feedback) {
    if (widget.onUndo == null) return;
    _undoTimer?.cancel();
    setState(() {
      _undoable = feedback;
      _undoSecondsLeft = 3;
    });
    _undoTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _undoSecondsLeft--);
      if (_undoSecondsLeft <= 0) {
        t.cancel();
        setState(() => _undoable = null);
      }
    });
  }

  Future<void> _tapUndo() async {
    final feedback = _undoable;
    if (feedback == null) return;
    _undoTimer?.cancel();
    setState(() => _undoable = null);
    try {
      await widget.onUndo!(feedback);
      if (!mounted) return;
      unawaited(HapticFeedback.lightImpact());
      setState(() {
        _feedback = const ScanFeedback('Undone');
        _feedbackSeq++;
        if (_count > 0) _count--;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _feedback = ScanFeedback('Could not undo: ${friendlyError(e)}', ok: false);
          _feedbackSeq++;
          _shake++;
        });
      }
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().where((v) => v.trim().isNotEmpty).firstOrNull;
    if (raw != null) await _onCode(raw);
  }

  Future<void> _onCode(String raw) async {
    if (_busy || _done) return;
    final now = DateTime.now();
    if (raw == _lastCode && now.difference(_lastAt) < const Duration(milliseconds: 2500)) return;
    _lastCode = raw;
    _lastAt = now;

    if (widget.single) {
      _done = true;
      unawaited(HapticFeedback.mediumImpact());
      Navigator.of(context).pop(raw.trim());
      return;
    }
    await _run(() => widget.onScan!(raw.trim()));
  }

  /// The shutter button: takes a photo for anything a barcode can't read.
  Future<void> _onCapture() async {
    if (_busy) return;
    await _run(() async {
      String? path;
      if (_useSmartCamera) {
        path = await _camera?.takePhoto();
        if (path == null) return const ScanFeedback('Could not take the photo — try again.', ok: false);
      }
      return widget.onCapturePhoto!(path);
    }, isCapture: true);
  }

  /// Runs a scan/capture action: shows a "pending" state immediately (and
  /// "Waiting for internet…" if it's taking unusually long — this app's
  /// writes queue locally and send themselves once back online, so a slow
  /// action almost always means no connection yet, not an error), then the
  /// result, with a shake on failure and an undo window on a successful
  /// send to a counter. A null result (the user cancelled, or it navigated
  /// away itself) shows nothing.
  Future<void> _run(Future<ScanFeedback?> Function() action, {bool isCapture = false}) async {
    setState(() {
      _busy = true;
      _pendingText = isCapture ? 'Reading…' : widget.pendingLabel?.call();
      _waitingForInternet = false;
    });
    _waitingTimer?.cancel();
    _waitingTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted && _busy) setState(() => _waitingForInternet = true);
    });
    try {
      final feedback = await action();
      if (!mounted || feedback == null) return;
      unawaited(feedback.ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact());
      setState(() {
        _feedback = feedback;
        _feedbackSeq++;
        if (feedback.ok) {
          _count++;
          _burst++;
        } else {
          _shake++;
        }
      });
      if (feedback.ok && feedback.undoToken != null && widget.onUndo != null && !isCapture) _startUndoCountdown(feedback);
    } catch (e) {
      if (mounted) {
        setState(() {
          _feedback = ScanFeedback(friendlyError(e), ok: false);
          _feedbackSeq++;
          _shake++;
        });
      }
    } finally {
      _waitingTimer?.cancel();
      if (mounted) {
        setState(() {
          _busy = false;
          _waitingForInternet = false;
        });
      }
    }
  }

  /// The phone's Smart Scan: one full-screen camera and nothing else. Codes
  /// are read the moment they're in view; the round button reads a pack or
  /// a bill. Where results go is one small chip at the top; the result of
  /// each scan floats over the bottom of the picture.
  Widget _smartCameraLayout(BuildContext context) {
    final feedback = _feedback;
    Widget roundButton(IconData icon, String tooltip, VoidCallback onPressed) => Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          buildSmartCamera(
            onCode: _onCode,
            onText: _onFrameText,
            onReady: (camera) => _camera = camera,
            onError: (message) => Center(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // The text the camera has found, boxed: green when it's good to go.
          IgnorePointer(
            child: _advice?.area == null || _frameSize == null
                ? const Center(child: _AimFrame())
                : CustomPaint(
                    size: Size.infinite,
                    painter: _DetectedBox(
                      area: _advice!.area!,
                      frame: _frameSize!,
                      good: !_advice!.hint.isProblem,
                    ),
                  ),
          ),
          if (_busy)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: Space.m),
                  Text(
                    _waitingForInternet ? 'Waiting for internet…' : (_pendingText ?? 'Reading…'),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          IgnorePointer(
            child: Center(
              child: _ConfirmBurst(key: ValueKey(_burst), play: _burst > 0),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  roundButton(PhosphorIconsRegular.x, 'Close', () => Navigator.of(context).pop()),
                  const SizedBox(width: Space.s),
                  Expanded(child: Center(child: widget.compactHeader ?? const SizedBox.shrink())),
                  const SizedBox(width: Space.s),
                  roundButton(PhosphorIconsRegular.flashlight, 'Torch', () => _camera?.toggleTorch()),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.m, 0, Space.m, Space.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (feedback != null)
                      Material(
                        color: AppColors.surface,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(16),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(Space.m, Space.s, Space.s, Space.s),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ShakeOnFail(
                                key: ValueKey(_shake),
                                shake: !feedback.ok,
                                child: _AnimatedFeedback(key: ValueKey(_feedbackSeq), feedback: feedback),
                              ),
                              if (_undoable != null)
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: _tapUndo,
                                    icon: const Icon(PhosphorIconsRegular.arrowUUpLeft),
                                    label: Text('Undo ($_undoSecondsLeft s)'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      Center(child: _GuidePill(hint: _advice?.hint ?? CaptureHint.pointAtBill)),
                    const SizedBox(height: Space.l),
                    // One button: photograph a pack (or a bill, if it wasn't
                    // taken by itself). The ring fills as a bill gets ready.
                    Center(
                      child: _ShutterButton(
                        onPressed: _busy ? null : _onCapture,
                        progress: _advice?.isBill == true ? _advice!.progress : 0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_useSmartCamera) return _smartCameraLayout(context);
    final text = Theme.of(context).textTheme;
    final feedback = _feedback;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        titleTextStyle: text.titleLarge?.copyWith(color: Colors.white),
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(PhosphorIconsRegular.flashlight),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Camera permission is off. Allow camera access for MedBills in Settings.'
                        : 'Camera unavailable: ${error.errorDetails?.message ?? error.errorCode.name}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 280,
                  height: 180,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (_busy)
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const CircularProgressIndicator(color: Colors.white),
                  if (_waitingForInternet) ...[
                    const SizedBox(height: Space.m),
                    const Text('Waiting for internet…', style: TextStyle(color: Colors.white)),
                  ],
                ]),
              ),
            IgnorePointer(child: Center(child: _ConfirmBurst(key: ValueKey(_burst), play: _burst > 0))),
            if (widget.onCapturePhoto != null)
              Positioned(
                right: Space.l,
                bottom: Space.l,
                child: FloatingActionButton(
                  heroTag: null,
                  tooltip: 'Photograph a pack or a bill',
                  onPressed: _busy ? null : _onCapture,
                  child: const Icon(PhosphorIconsRegular.camera),
                ),
              ),
          ]),
        ),
        Material(
          color: AppColors.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (widget.header != null) ...[widget.header!, const SizedBox(height: Space.m)],
                if (_busy && _pendingText != null)
                  Text(_waitingForInternet ? 'Waiting for internet…' : _pendingText!,
                      style: text.bodyMedium?.copyWith(color: AppColors.muted))
                else if (feedback == null)
                  Text(
                      widget.single
                          ? 'Hold the barcode inside the frame.'
                          : widget.onCapturePhoto != null
                              ? 'Point at a barcode, or tap the camera for a pack or a bill.'
                              : 'Scan packs one after another.',
                      style: text.bodyMedium?.copyWith(color: AppColors.muted))
                else
                  _ShakeOnFail(
                    key: ValueKey(_shake),
                    shake: !feedback.ok,
                    child: _AnimatedFeedback(key: ValueKey(_feedbackSeq), feedback: feedback),
                  ),
                if (_undoable != null) ...[
                  const SizedBox(height: Space.s),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _tapUndo,
                      icon: const Icon(PhosphorIconsRegular.arrowUUpLeft),
                      label: Text('Undo ($_undoSecondsLeft s)'),
                    ),
                  ),
                ],
                if (!widget.single) ...[
                  const SizedBox(height: Space.m),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_count == 0 ? 'Close' : 'Done · $_count scanned'),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A result slides and fades in so it reads as "just happened", not as
/// static text that was always there.
class _AnimatedFeedback extends StatelessWidget {
  const _AnimatedFeedback({super.key, required this.feedback});
  final ScanFeedback feedback;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      ),
      child: Row(children: [
        Icon(feedback.ok ? PhosphorIconsRegular.checkCircle : PhosphorIconsRegular.warningCircle,
            color: feedback.ok ? AppColors.accent : AppColors.danger),
        const SizedBox(width: Space.s),
        Expanded(child: Text(feedback.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: text.bodyMedium)),
        if (feedback.onAction != null) TextButton(onPressed: feedback.onAction, child: Text(feedback.actionLabel ?? 'Fix')),
      ]),
    );
  }
}

/// Shakes once on a failed scan — a clearer "no" than red text alone.
class _ShakeOnFail extends StatefulWidget {
  const _ShakeOnFail({super.key, required this.shake, required this.child});
  final bool shake;
  final Widget child;

  @override
  State<_ShakeOnFail> createState() => _ShakeOnFailState();
}

class _ShakeOnFailState extends State<_ShakeOnFail> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));

  @override
  void initState() {
    super.initState();
    if (widget.shake && !MediaQuery.of(context).disableAnimations) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.shake) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final offset = sin(t * pi * 4) * (1 - t) * 10;
        return Transform.translate(offset: Offset(offset, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// A green checkmark that pops and fades over the preview on every
/// successful scan — the "yes, got it, sent" confirmation at a glance,
/// without having to read anything.
class _ConfirmBurst extends StatefulWidget {
  const _ConfirmBurst({super.key, required this.play});
  final bool play;

  @override
  State<_ConfirmBurst> createState() => _ConfirmBurstState();
}

class _ConfirmBurstState extends State<_ConfirmBurst> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  @override
  void initState() {
    super.initState();
    if (widget.play && !MediaQuery.of(context).disableAnimations) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.play) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Scale up fast past 1.0 then settle; fade out over the back half.
        final scale = t < 0.4 ? Curves.easeOut.transform(t / 0.4) * 1.15 : 1.15 - Curves.easeIn.transform((t - 0.4) / 0.6) * 0.15;
        final opacity = t < 0.6 ? 1.0 : (1 - (t - 0.6) / 0.4).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(color: Color(0xCC1E8E5A), shape: BoxShape.circle),
              child: const Icon(PhosphorIconsRegular.check, color: Colors.white, size: 56),
            ),
          ),
        );
      },
    );
  }
}

/// The round shutter of the in-app camera, like the system camera's.
class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onPressed, this.progress = 0});
  final VoidCallback? onPressed;
  /// 0..1: a ring around the button fills as a bill gets ready to capture.
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Photograph a pack or a bill',
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: onPressed == null ? 0.4 : 1,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Stack(alignment: Alignment.center, children: [
              if (progress > 0)
                SizedBox(
                  width: 84,
                  height: 84,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: progress),
                    duration: const Duration(milliseconds: 300),
                    builder: (context, v, _) => CircularProgressIndicator(
                      value: v,
                      strokeWidth: 5,
                      color: v >= 0.75 ? AppColors.accent : Colors.amber,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                padding: const EdgeInsets.all(5),
                child: const DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The one instruction for the person holding the phone, in a pill that is
/// amber while something needs fixing and green once it's right.
class _GuidePill extends StatelessWidget {
  const _GuidePill({required this.hint});
  final CaptureHint hint;

  static IconData _icon(CaptureHint h) => switch (h) {
        CaptureHint.pointAtBill || CaptureHint.stillLooking => PhosphorIconsRegular.scan,
        CaptureHint.moreLight => PhosphorIconsRegular.flashlight,
        CaptureHint.tooBright => PhosphorIconsRegular.sun,
        CaptureHint.packSeen => PhosphorIconsRegular.barcode,
        CaptureHint.billFound || CaptureHint.moveCloser => PhosphorIconsRegular.magnifyingGlassPlus,
        CaptureHint.moveBack => PhosphorIconsRegular.arrowsOut,
        CaptureHint.centre => PhosphorIconsRegular.crosshair,
        CaptureHint.straighten => PhosphorIconsRegular.deviceMobile,
        CaptureHint.holdSteady => PhosphorIconsRegular.handPalm,
        CaptureHint.ready || CaptureHint.captured => PhosphorIconsRegular.checkCircle,
      };

  @override
  Widget build(BuildContext context) {
    final good = !hint.isProblem;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: Container(
        key: ValueKey(hint),
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        decoration: BoxDecoration(
          color: good ? AppColors.accent.withValues(alpha: 0.92) : const Color(0xE6333333),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: good ? Colors.white : Colors.amber, width: 1.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_icon(hint), color: good ? Colors.white : Colors.amber, size: 22),
          const SizedBox(width: Space.s),
          Flexible(
            child: Text(
              hint.message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Draws a box around the text the camera found, mapped from the frame onto
/// the preview (which fills the screen like the system camera: cover).
class _DetectedBox extends CustomPainter {
  _DetectedBox({required this.area, required this.frame, required this.good});
  final NormRect area;
  final Size frame;
  final bool good;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.width <= 0 || frame.height <= 0) return;
    final scale = max(size.width / frame.width, size.height / frame.height);
    final shown = Size(frame.width * scale, frame.height * scale);
    final dx = (size.width - shown.width) / 2, dy = (size.height - shown.height) / 2;
    final rect = Rect.fromLTRB(
      dx + area.left * shown.width - 8,
      dy + area.top * shown.height - 8,
      dx + area.right * shown.width + 8,
      dy + area.bottom * shown.height + 8,
    );
    final color = good ? AppColors.accent : Colors.amber;
    canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(12)),
        Paint()..color = color.withValues(alpha: 0.12));
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_DetectedBox old) => old.area != area || old.good != good || old.frame != frame;
}

/// Corner marks showing where to hold a code — light enough not to hide the
/// picture.
class _AimFrame extends StatelessWidget {
  const _AimFrame();

  @override
  Widget build(BuildContext context) {
    const side = BorderSide(color: Colors.white, width: 3);
    Widget corner(Alignment a) => Align(
      alignment: a,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border(
            top: a.y < 0 ? side : BorderSide.none,
            bottom: a.y > 0 ? side : BorderSide.none,
            left: a.x < 0 ? side : BorderSide.none,
            right: a.x > 0 ? side : BorderSide.none,
          ),
        ),
      ),
    );
    return SizedBox(
      width: 260,
      height: 180,
      child: Stack(
        children: [
          corner(Alignment.topLeft),
          corner(Alignment.topRight),
          corner(Alignment.bottomLeft),
          corner(Alignment.bottomRight),
        ],
      ),
    );
  }
}
