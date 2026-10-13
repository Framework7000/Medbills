import '../models/medicine.dart';
import 'ocr_text.dart';
import 'supplier_bill_parser.dart';

enum CaptureKind { pack, supplierBill }

/// Smart Scan takes one photo and has to decide, on its own, whether it is
/// looking at a single medicine pack or a multi-line supplier bill — the
/// owner shouldn't have to pick a mode first. A supplier bill reliably
/// parses into several item lines (name, batch, qty, rate…); a single pack's
/// label never does. A long, dense page with only one or zero parsed lines
/// (a bill the line-parser failed on, rather than a pack) still counts as a
/// bill by its sheer amount of text.
CaptureKind classifyCapture(OcrPage page, Iterable<Medicine> medicines, {String ownGstin = ''}) {
  final draft = SupplierBillParser.parse(page, medicines, ownGstin: ownGstin);
  if (draft.lines.length >= 2) return CaptureKind.supplierBill;
  if (page.rows().length > 10) return CaptureKind.supplierBill;
  return CaptureKind.pack;
}
