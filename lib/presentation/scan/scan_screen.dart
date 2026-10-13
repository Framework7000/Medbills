import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/billing_calculator.dart';
import '../../platform/device_features.dart';
import '../../state/providers.dart';
import '../theme.dart';
import 'barcode_scanner_screen.dart';
import 'scan_billing.dart';

/// Everything that starts with a scan, in one place. On the phone this is a
/// main tab: the phone is the store's scanner — into its own bill or a
/// counter's, reading packs, and photographing supplier bills.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _code = TextEditingController();
  ScanFeedback? _feedback;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submitCode() async {
    final raw = _code.text.trim();
    if (raw.isEmpty) return;
    final feedback = await handleScannedCode(context, ref, raw, toCounter: false);
    if (!mounted) return;
    setState(() {
      _feedback = feedback;
      _code.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cart = ref.watch(cartProvider);
    final target = ref.watch(scanTargetProvider);
    final phone = DeviceFeatures.isPhone;
    final mode = phone ? ref.watch(scanModeProvider) : ScanMode.selling;

    Widget action({
      required IconData icon,
      required String title,
      required String subtitle,
      VoidCallback? onTap,
      Widget? extra,
    }) {
      return Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: onTap == null ? AppColors.infoContainer : AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: onTap == null ? AppColors.muted : AppColors.primary),
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: text.titleMedium?.copyWith(color: onTap == null ? AppColors.muted : null)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: text.bodySmall?.copyWith(color: AppColors.muted)),
                  ]),
                ),
                if (onTap != null) const Icon(PhosphorIconsRegular.caretRight),
              ]),
              if (extra != null) ...[const SizedBox(height: Space.m), extra],
            ]),
          ),
        ),
      );
    }

    final cards = <Widget>[
      if (DeviceFeatures.cameraScanning)
        action(
          icon: PhosphorIconsRegular.scanSmiley,
          title: 'Smart Scan',
          subtitle: mode == ScanMode.receiving
              ? 'Photograph each pack — they build into one bill to review.'
              : target == null
                  ? 'Barcode adds it; camera reads a pack or a bill.'
                  : 'Scans go to ${target.name}\'s bill.',
          onTap: () => openSmartScanner(context, ref),
          extra: const SmartScanHeader(),
        ),
      if (!phone)
        action(
          icon: PhosphorIconsRegular.barcode,
          title: 'USB / Bluetooth scanner',
          subtitle: 'Scan or type a code, then Enter — goes onto the Billing bill.',
          extra: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _code,
              decoration: const InputDecoration(hintText: 'Barcode', prefixIcon: Icon(PhosphorIconsRegular.qrCode)),
              onSubmitted: (_) => _submitCode(),
            ),
            if (_feedback != null) ...[
              const SizedBox(height: Space.s),
              Text(_feedback!.message,
                  style: text.bodyMedium?.copyWith(color: _feedback!.ok ? AppColors.accent : AppColors.danger)),
              if (_feedback!.onAction != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: _feedback!.onAction, child: Text(_feedback!.actionLabel ?? 'Fix')),
                ),
            ],
          ]),
        ),
      if (!DeviceFeatures.cameraScanning)
        action(
          icon: PhosphorIconsRegular.fileText,
          title: 'Read a medicine pack',
          subtitle: 'Works in the iPhone / Android app.',
          onTap: null,
        ),
      if (!phone)
        Text(
          'To use an iPhone as this counter\'s scanner: Billing → Scan (F3) → "Use a phone as the scanner".',
          style: text.bodySmall?.copyWith(color: AppColors.muted),
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(Space.l),
            children: [
              if (!cart.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.m),
                  child: Text(
                    'Bill on this device: ${cart.lines.length} line${cart.lines.length == 1 ? '' : 's'} · '
                    '${formatRupees(cart.summary.payablePaise)} — open Billing to complete it.',
                    style: text.bodyMedium,
                  ),
                ),
              const Padding(padding: EdgeInsets.only(bottom: Space.m), child: NotDeliveredScans()),
              for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: Space.m), child: c),
            ],
          ),
        ),
      ),
    );
  }
}
