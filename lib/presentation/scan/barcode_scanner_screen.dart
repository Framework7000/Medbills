import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';

/// What happened to one scan, shown over the camera.
class ScanFeedback {
  const ScanFeedback(this.message, {this.ok = true, this.actionLabel, this.onAction});
  final String message;
  final bool ok;
  final String? actionLabel;
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
/// read and route a photo without leaving this screen. It returns null when
/// the user cancelled (nothing to show).
Future<void> openContinuousScanner(
  BuildContext context, {
  required String title,
  required Future<ScanFeedback> Function(String raw) onScan,
  Widget? header,
  Future<ScanFeedback?> Function()? onCapturePhoto,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _ScannerScreen(title: title, onScan: onScan, header: header, onCapturePhoto: onCapturePhoto),
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
  const _ScannerScreen({required this.title, this.onScan, this.header, this.single = false, this.onCapturePhoto});
  final String title;
  final Future<ScanFeedback> Function(String raw)? onScan;
  final Widget? header;
  final bool single;
  final Future<ScanFeedback?> Function()? onCapturePhoto;

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
  int _count = 0;
  int _burst = 0; // bumped on every success to retrigger the confirm animation
  int _feedbackSeq = 0; // bumped on every feedback to retrigger its entrance

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().where((v) => v.trim().isNotEmpty).firstOrNull;
    if (raw == null || _busy || _done) return;
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
    setState(() => _busy = true);
    try {
      final feedback = await widget.onScan!(raw.trim());
      if (!mounted) return;
      unawaited(feedback.ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact());
      setState(() {
        _feedback = feedback;
        _feedbackSeq++;
        if (feedback.ok) {
          _count++;
          _burst++;
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _feedback = ScanFeedback('$e', ok: false);
          _feedbackSeq++;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The shutter button: takes a photo for anything a barcode can't read.
  Future<void> _onCapture() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final feedback = await widget.onCapturePhoto!();
      if (!mounted) return;
      if (feedback == null) return; // cancelled, or it navigated away itself
      unawaited(feedback.ok ? HapticFeedback.mediumImpact() : HapticFeedback.heavyImpact());
      setState(() {
        _feedback = feedback;
        _feedbackSeq++;
        if (feedback.ok) {
          _count++;
          _burst++;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            icon: const Icon(Icons.flashlight_on_outlined),
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
            if (_busy) const Center(child: CircularProgressIndicator(color: Colors.white)),
            IgnorePointer(child: Center(child: _ConfirmBurst(key: ValueKey(_burst), play: _burst > 0))),
            if (widget.onCapturePhoto != null)
              Positioned(
                right: Space.l,
                bottom: Space.l,
                child: FloatingActionButton(
                  heroTag: null,
                  tooltip: 'Photograph a pack or a bill',
                  onPressed: _busy ? null : _onCapture,
                  child: const Icon(Icons.camera_alt),
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
                if (feedback == null)
                  Text(
                      widget.single
                          ? 'Hold the barcode inside the frame.'
                          : widget.onCapturePhoto != null
                              ? 'Point at a barcode, or tap the camera for a pack or a bill.'
                              : 'Scan packs one after another.',
                      style: text.bodyMedium?.copyWith(color: AppColors.muted))
                else
                  _AnimatedFeedback(
                    key: ValueKey(_feedbackSeq),
                    feedback: feedback,
                  ),
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
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      ),
      child: Row(children: [
        Icon(feedback.ok ? Icons.check_circle : Icons.error_outline,
            color: feedback.ok ? AppColors.accent : AppColors.danger),
        const SizedBox(width: Space.s),
        Expanded(child: Text(feedback.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: text.bodyMedium)),
        if (feedback.onAction != null) TextButton(onPressed: feedback.onAction, child: Text(feedback.actionLabel ?? 'Fix')),
      ]),
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
    if (widget.play) _controller.forward();
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
              child: const Icon(Icons.check, color: Colors.white, size: 56),
            ),
          ),
        );
      },
    );
  }
}
