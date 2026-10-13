import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../domain/models/batch.dart';
import '../../domain/models/medicine.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/gs1_parser.dart';
import '../../domain/services/medicine_matcher.dart';
import '../../domain/services/ocr_text.dart';
import '../../domain/services/pack_label_parser.dart';
import '../../domain/services/stock_summary.dart';
import '../../platform/device_features.dart';
import '../../platform/text_reader.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// A scanned code resolved against the store's medicines.
class BarcodeHit {
  const BarcodeHit({required this.raw, this.stock, this.batchNumber, this.expiry});
  final String raw;
  final StockSummary? stock;
  final String? batchNumber; // from GS1 / QR payloads that carry it
  final DateTime? expiry;
}

String _digits(String s) => s.replaceFirst(RegExp(r'^0+'), '');

/// Matches EAN/UPC, GS1 DataMatrix (GTIN + batch + expiry) and the text
/// QR codes printed on Indian packs (brand, batch, expiry in plain text).
BarcodeHit resolveBarcode(String raw, Map<String, StockSummary> index) {
  final parsed = Gs1Parser.parse(raw);
  final gtin = parsed.gtin;
  StockSummary? hit;
  for (final s in index.values) {
    final code = s.medicine.barcode;
    if (code == null || code.isEmpty) continue;
    if (code == raw || (gtin != null && _digits(code) == _digits(gtin))) {
      hit = s;
      break;
    }
  }
  var batch = parsed.batchNumber;
  var expiry = parsed.expiryDate;
  if (hit == null && raw.length > 14) {
    // A text QR code: read it like a pack label.
    final match = MedicineMatcher.match(raw, index.values.map((s) => s.medicine));
    if (match.isConfident) hit = index[match.best!.medicine.id];
    final info = PackLabelParser.parse(raw);
    batch ??= info.batchNumber;
    if (expiry == null && info.hasExpiry) expiry = Batch.endOfMonth(info.expiryYear!, info.expiryMonth!);
  }
  return BarcodeHit(raw: raw, stock: hit, batchNumber: batch, expiry: expiry);
}

/// The batches to bill from: the scanned batch when it is on the shelf and
/// sellable, otherwise nearest expiry first.
List<Batch> batchesFor(StockSummary stock, String? batchNumber) {
  if (batchNumber == null || batchNumber.isEmpty) return stock.batches;
  final wanted = Batch.normaliseBatchNumber(batchNumber);
  final exact = stock.sellableBatches.where((b) => b.batchNumber == wanted).toList();
  return exact.isEmpty ? stock.batches : exact;
}

/// Result of reading a medicine pack from a photo.
class PackScan {
  const PackScan(this.medicine, this.info);
  final Medicine medicine;
  final PackLabelInfo info;
}

/// Photographs a pack, reads its printed text on the device, and identifies
/// the exact medicine (brand + strength) among [medicines], plus the batch,
/// expiry and MRP printed on it. The user confirms before anything is used.
///
/// Smart Scan already has the photo and its OCR by the time it knows this is
/// a pack (not a supplier bill) — pass [photo]/[page] to skip re-reading it.
Future<PackScan?> scanPackPhoto(
  BuildContext context, {
  required List<Medicine> medicines,
  XFile? photo,
  OcrPage? page,
}) async {
  if (!DeviceFeatures.textReading) {
    showMessage(context, 'Reading packs works on the iPhone or Android app.');
    return null;
  }
  final file = photo ?? await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 2200, imageQuality: 92);
  if (file == null || !context.mounted) return null;
  final ocrPage = page ?? await readTextFromPhoto(file.path);
  if (!context.mounted) return null;
  if (ocrPage == null || ocrPage.isEmpty) {
    showMessage(context, 'No printed text found. Hold the pack flat, in good light, and try again.', error: true);
    return null;
  }
  final info = PackLabelParser.parse(ocrPage.text);
  final match = MedicineMatcher.match(ocrPage.text, medicines);
  return showDialog<PackScan>(
    context: context,
    builder: (_) => _PackScanDialog(text: ocrPage.text, info: info, match: match, medicines: medicines),
  );
}

class _PackScanDialog extends StatefulWidget {
  const _PackScanDialog({required this.text, required this.info, required this.match, required this.medicines});
  final String text;
  final PackLabelInfo info;
  final MatchResult match;
  final List<Medicine> medicines;

  @override
  State<_PackScanDialog> createState() => _PackScanDialogState();
}

class _PackScanDialogState extends State<_PackScanDialog> {
  late Medicine? _chosen = widget.match.isConfident ? widget.match.best!.medicine : null;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final info = widget.info;
    final now = DateTime.now();
    final expired = info.hasExpiry && Batch.endOfMonth(info.expiryYear!, info.expiryMonth!).isBefore(now);
    final q = _search.text.trim().toLowerCase();
    final options = q.isEmpty
        ? widget.match.candidates.map((c) => c.medicine).toList()
        : widget.medicines.where((m) => m.name.toLowerCase().contains(q) || m.genericName.toLowerCase().contains(q)).take(8).toList();

    return AlertDialog(
      title: const Text('Read from pack'),
      content: DialogBody(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.match.candidates.isEmpty)
            Text('Couldn\'t match the brand. Search for it below.', style: text.bodyMedium?.copyWith(color: AppColors.warning))
          else if (!widget.match.isConfident)
            Text('More than one medicine could match — pick the exact one.',
                style: text.bodyMedium?.copyWith(color: AppColors.warning)),
          RadioGroup<String>(
            groupValue: _chosen?.id,
            onChanged: (id) => setState(() => _chosen = options.where((m) => m.id == id).firstOrNull),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final m in options)
                RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: m.id,
                  title: Text(m.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${m.manufacturer} · ${m.packSizeLabel}', overflow: TextOverflow.ellipsis),
                ),
            ]),
          ),
          TextField(
            controller: _search,
            decoration: const InputDecoration(hintText: 'Not listed? Search', prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass)),
            onChanged: (_) => setState(() {}),
          ),
          const Divider(height: Space.xl),
          AmountRow('Batch', info.batchNumber ?? 'not read'),
          AmountRow(
            'Expiry',
            info.hasExpiry ? DateFormat('MMM yyyy').format(DateTime(info.expiryYear!, info.expiryMonth!)) : 'not read',
          ),
          AmountRow('MRP', info.mrpPaise == null ? 'not read' : formatRupees(info.mrpPaise!)),
          if (expired)
            Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: Text('This pack is EXPIRED. Do not sell it.',
                  style: text.titleSmall?.copyWith(color: AppColors.danger)),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Text read from the pack', style: text.bodySmall),
            children: [SelectableText(widget.text, style: text.bodySmall)],
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _chosen == null ? null : () => Navigator.pop(context, PackScan(_chosen!, info)),
          child: const Text('Use this'),
        ),
      ],
    );
  }
}
