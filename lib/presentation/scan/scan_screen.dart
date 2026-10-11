import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/services/billing_calculator.dart';
import '../../domain/services/stock_summary.dart';
import '../../platform/device_features.dart';
import '../../state/providers.dart';
import '../inventory/inventory_screen.dart';
import '../purchases/bill_scan_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'barcode_scanner_screen.dart';
import 'scan_billing.dart';
import 'scan_flows.dart';

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

  /// Scan (camera) or type a code and open that medicine's stock and batches.
  Future<void> _checkMedicine() async {
    final raw = DeviceFeatures.cameraScanning ? await scanSingleBarcode(context, title: 'Check a medicine') : _code.text.trim();
    if (!mounted || raw == null) return;
    if (raw.isEmpty) {
      showMessage(context, 'Scan or type the barcode in the box above first.');
      return;
    }
    final index = ref.read(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
    final hit = resolveBarcode(raw, index);
    if (hit.stock == null) {
      final manager = ref.read(currentUserProvider)?.role.canManageStock ?? false;
      showMessage(context, 'Barcode $raw isn\'t linked to a medicine yet.${manager ? ' Use "Scan into bill" to link it.' : ''}',
          error: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MedicineDetailScreen(medicineId: hit.stock!.medicine.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cart = ref.watch(cartProvider);
    final target = ref.watch(scanTargetProvider);
    final phone = DeviceFeatures.isPhone;

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
                if (onTap != null) const Icon(Icons.chevron_right),
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
          icon: Icons.qr_code_scanner,
          title: 'Scan into bill',
          subtitle: target == null
              ? 'Point the camera at barcodes one after another — each adds a pack.'
              : 'Scans go to ${target.name}\'s bill.',
          onTap: () => openBillScanner(context, ref),
          extra: const ScanTargetPicker(),
        ),
      if (!phone)
        action(
          icon: Icons.barcode_reader,
          title: 'USB / Bluetooth scanner',
          subtitle: 'Scan into the box below (or type a code and press Enter) — it goes on the bill in Billing.',
          extra: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _code,
              decoration: const InputDecoration(hintText: 'Barcode', prefixIcon: Icon(Icons.qr_code_2)),
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
      action(
        icon: Icons.document_scanner_outlined,
        title: 'Read a medicine pack',
        subtitle: DeviceFeatures.textReading
            ? 'Photo of the strip → exact medicine, batch, expiry and MRP. Warns if expired.'
            : 'Works in the iPhone / Android app.',
        onTap: DeviceFeatures.textReading ? () => readPackIntoBill(context, ref) : null,
      ),
      action(
        icon: Icons.receipt_long_outlined,
        title: 'Scan supplier bill',
        subtitle: DeviceFeatures.textReading
            ? 'Photo of the bill → supplier, GSTIN, bill no. and every line, ready to receive into stock.'
            : 'Attach a bill photo (text is read in the phone app); it shows on every device.',
        onTap: () => captureSupplierBill(context, ref),
      ),
      action(
        icon: Icons.manage_search,
        title: 'Check a medicine',
        subtitle: 'Scan a pack to see its stock, batches and expiry.',
        onTap: _checkMedicine,
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
              for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: Space.m), child: c),
            ],
          ),
        ),
      ),
    );
  }
}
