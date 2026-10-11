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
Future<void> openContinuousScanner(
  BuildContext context, {
  required String title,
  required Future<ScanFeedback> Function(String raw) onScan,
  Widget? header,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _ScannerScreen(title: title, onScan: onScan, header: header),
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
  const _ScannerScreen({required this.title, this.onScan, this.header, this.single = false});
  final String title;
  final Future<ScanFeedback> Function(String raw)? onScan;
  final Widget? header;
  final bool single;

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
        if (feedback.ok) _count++;
      });
    } catch (e) {
      if (mounted) setState(() => _feedback = ScanFeedback('$e', ok: false));
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
                  Text(widget.single ? 'Hold the barcode inside the frame.' : 'Scan packs one after another.',
                      style: text.bodyMedium?.copyWith(color: AppColors.muted))
                else
                  Row(children: [
                    Icon(feedback.ok ? Icons.check_circle : Icons.error_outline,
                        color: feedback.ok ? AppColors.accent : AppColors.danger),
                    const SizedBox(width: Space.s),
                    Expanded(child: Text(feedback.message, maxLines: 3, overflow: TextOverflow.ellipsis)),
                    if (feedback.onAction != null)
                      TextButton(onPressed: feedback.onAction, child: Text(feedback.actionLabel ?? 'Fix')),
                  ]),
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
