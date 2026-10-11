import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/batch.dart';
import '../../domain/models/scan_link.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../domain/services/stock_summary.dart';
import '../../platform/device_features.dart';
import '../../state/providers.dart';
import '../purchases/medicine_picker.dart';
import '../widgets/common.dart';
import 'barcode_scanner_screen.dart';
import 'scan_flows.dart';

/// On a phone: the counter that camera scans are sent to (null = this
/// phone's own bill).
final scanTargetProvider = StateProvider<ScanStation?>((ref) => null);

/// Adds one pack of a scanned medicine to this device's bill — the scanned
/// batch when it is on the shelf, otherwise nearest expiry first.
ScanFeedback addScannedToBill(WidgetRef ref, StockSummary stock, {String? batchNumber}) {
  final m = stock.medicine;
  if (!m.scheduleType.isSellable) {
    return ScanFeedback('${m.name} is unclassified — set its schedule in Stock first.', ok: false);
  }
  final now = DateTime.now();
  final cart = ref.read(cartProvider);
  final batches = batchesFor(stock, batchNumber);
  final free = batches
      .where((b) => b.isSellableAt(now))
      .fold<int>(0, (sum, b) => sum + b.quantity - (cart.unitsByBatch[b.id] ?? 0));
  if (free <= 0) {
    return ScanFeedback(
        stock.isOutOfStock ? '${m.name} is out of stock.' : 'All ${m.name} in stock is already on this bill.',
        ok: false);
  }
  final units = free < m.unitsPerPack ? free : m.unitsPerPack;
  try {
    ref.read(cartProvider.notifier).addMedicine(m, batches, units, now: now);
  } catch (e) {
    return ScanFeedback(friendlyError(e), ok: false);
  }
  final wanted = batchNumber == null || batchNumber.isEmpty ? null : Batch.normaliseBatchNumber(batchNumber);
  final usedWanted = wanted != null && batches.length == 1 && batches.first.batchNumber == wanted;
  return ScanFeedback('Added ${PackUnits.describe(units, m.unitsPerPack)} · ${m.name}'
      '${wanted != null && !usedWanted ? ' (batch $wanted not in stock — billed nearest expiry)' : ''}');
}

/// Handles one scanned code: adds it to this device's bill, or sends it to
/// the chosen counter. [toCounter] false always bills here (a counter's own
/// USB scanner).
Future<ScanFeedback> handleScannedCode(BuildContext context, WidgetRef ref, String raw, {bool toCounter = true}) async {
  final index = ref.read(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
  final hit = resolveBarcode(raw, index);
  if (hit.expiry != null && hit.expiry!.isBefore(DateTime.now())) {
    return ScanFeedback('This pack is EXPIRED (${DateFormat('MM/yy').format(hit.expiry!)}). Do not sell it.', ok: false);
  }
  final stock = hit.stock;
  if (stock == null) {
    final manager = ref.read(currentUserProvider)?.role.canManageStock ?? false;
    return ScanFeedback(
      'Barcode $raw isn\'t linked to a medicine yet.',
      ok: false,
      actionLabel: manager ? 'Link' : null,
      onAction: manager ? () => linkBarcode(context, ref, raw) : null,
    );
  }
  final target = toCounter ? ref.read(scanTargetProvider) : null;
  if (target != null) {
    final repo = ref.read(repositoryProvider)!;
    await repo.sendScan(ScanEvent(
      id: repo.newId(),
      storeId: repo.storeId,
      stationId: target.id,
      rawBarcode: raw,
      medicineId: stock.medicine.id,
      batchNumber: hit.batchNumber,
      deviceLabel: DeviceFeatures.label,
      createdBy: repo.actor.uid,
      createdByName: repo.actor.name,
      scannedAt: DateTime.now(),
    ));
    return ScanFeedback('Sent ${stock.medicine.name} to ${target.name}');
  }
  return addScannedToBill(ref, stock, batchNumber: hit.batchNumber);
}

/// Saves an unknown barcode on the medicine it belongs to, so the next scan
/// of that pack — on any device — finds it.
Future<void> linkBarcode(BuildContext context, WidgetRef ref, String raw) async {
  final picked = await pickMedicine(context);
  if (picked == null || !context.mounted) return;
  try {
    await ref.read(repositoryProvider)!.saveMedicine(picked.medicine.copyWith(barcode: raw));
    if (context.mounted) showMessage(context, 'Barcode linked to ${picked.medicine.name}. Scan it again to add it.');
  } catch (e) {
    if (context.mounted) showMessage(context, friendlyError(e), error: true);
  }
}

/// Opens the camera for scanning pack after pack into the bill.
Future<void> openBillScanner(BuildContext context, WidgetRef ref) => openContinuousScanner(
      context,
      title: 'Scan medicines',
      onScan: (raw) => handleScannedCode(context, ref, raw),
      header: const ScanTargetPicker(),
    );

class ScanTargetPicker extends ConsumerWidget {
  const ScanTargetPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final stations = (ref.watch(stationsProvider).valueOrNull ?? const <ScanStation>[])
        .where((s) => s.isAvailableAt(now))
        .toList();
    if (stations.isEmpty) return const SizedBox.shrink();
    final target = ref.watch(scanTargetProvider);
    return DropdownButtonFormField<String>(
      initialValue: stations.any((s) => s.id == target?.id) ? target!.id : '',
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Add scanned items to'),
      items: [
        const DropdownMenuItem(value: '', child: Text('The bill on this device')),
        for (final s in stations) DropdownMenuItem(value: s.id, child: Text('${s.name} (counter)')),
      ],
      onChanged: (id) => ref.read(scanTargetProvider.notifier).state = stations.where((s) => s.id == id).firstOrNull,
    );
  }
}

/// Photographs a pack, identifies it and adds one pack to the bill.
Future<void> readPackIntoBill(BuildContext context, WidgetRef ref) async {
  final index = ref.read(stockIndexProvider).valueOrNull ?? const <String, StockSummary>{};
  final scan = await scanPackPhoto(context, medicines: index.values.map((s) => s.medicine).toList());
  if (scan == null || !context.mounted) return;
  final info = scan.info;
  if (info.hasExpiry && Batch.endOfMonth(info.expiryYear!, info.expiryMonth!).isBefore(DateTime.now())) {
    showMessage(context, 'That pack is expired — not added.', error: true);
    return;
  }
  final stock = index[scan.medicine.id];
  if (stock == null) return;
  final feedback = addScannedToBill(ref, stock, batchNumber: info.batchNumber);
  if (info.mrpPaise != null && feedback.ok) {
    final billed = batchesFor(stock, info.batchNumber).firstOrNull;
    if (billed != null && billed.mrpPaise != info.mrpPaise) {
      showMessage(context,
          '${feedback.message}. Note: pack MRP ${formatRupees(info.mrpPaise!)} differs from stock record ${formatRupees(billed.mrpPaise)}.',
          error: true);
      return;
    }
  }
  showMessage(context, feedback.message, error: !feedback.ok);
}
