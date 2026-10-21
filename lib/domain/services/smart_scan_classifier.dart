import '../models/medicine.dart';
import 'ocr_text.dart';
import 'supplier_bill_parser.dart';

enum CaptureKind { pack, supplierBill }

/// Smart Scan takes one photo and has to decide, on its own, whether it is
/// looking at a medicine pack or a supplier bill — the owner never picks a
/// mode. It weighs what each kind of paper actually prints:
///
/// - a bill: a supplier GSTIN, "Tax Invoice" / bill number, Qty and
///   Rate/Amount columns, several batch numbers, several parsed item lines;
/// - a pack: "Each tablet contains", "MRP … incl. of all taxes", Mfg + Exp,
///   one batch number, storage and Rx warnings.
///
/// The amount of text alone never decides it — the back panel of a carton
/// is as long as a short bill — it only breaks a tie when neither kind of
/// marking was read.
CaptureKind classifyCapture(OcrPage page, Iterable<Medicine> medicines, {String ownGstin = ''}) {
  if (page.isEmpty) return CaptureKind.pack;
  final rows = page.rows();
  final text = rows.join('\n').toUpperCase();
  final own = ownGstin.trim().toUpperCase();

  var bill = 0;
  var pack = 0;

  final draft = SupplierBillParser.parse(page, medicines, ownGstin: ownGstin);
  if (draft.lines.length >= 2) bill += 3 + (draft.lines.length >= 4 ? 2 : 0);
  if (_gstin.allMatches(text).any((m) => m.group(0) != own)) bill += 3;
  if (_invoice.hasMatch(text)) bill += 2;
  if (_qty.hasMatch(text) && _amount.hasMatch(text)) bill += 2;
  if (_totals.hasMatch(text)) bill += 1;
  final batches = _batchLabel.allMatches(text).length + _batchCode.allMatches(text).length;
  if (batches >= 3) bill += 2;

  if (_eachContains.hasMatch(text)) pack += 3;
  if (_mrpInclusive.hasMatch(text)) pack += 2;
  if (_mfg.hasMatch(text) && _exp.hasMatch(text)) pack += 2;
  if (_packWarnings.hasMatch(text)) pack += 2;
  if (_packOf.hasMatch(text)) pack += 1;

  if (bill > pack) return CaptureKind.supplierBill;
  if (pack > bill) return CaptureKind.pack;
  // Nothing recognisable either way: a long page of print is a bill the
  // parser couldn't read; a few lines are a pack.
  return rows.length > 10 ? CaptureKind.supplierBill : CaptureKind.pack;
}

final _gstin = RegExp(r'\b\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]\b');
final _invoice = RegExp(r'\b(TAX\s+INVOICE|INVOICE\s*(NO|#|NUMBER)|INV\.?\s*NO|BILL\s*(NO|NUMBER)|CASH\s+MEMO|CREDIT\s+MEMO)\b');
final _qty = RegExp(r'\b(QTY|QUANTITY)\b');
final _amount = RegExp(r'\b(RATE|AMOUNT|AMT|P\.?T\.?R|N\.?\s*RATE)\b');
final _totals = RegExp(r'\b(GRAND\s+TOTAL|NET\s+AMOUNT|NET\s+PAYABLE|SUB\s*TOTAL|TAXABLE\s+(VALUE|AMT|AMOUNT)|CGST|SGST|IGST)\b');
final _batchLabel = RegExp(r'\bB\.?\s*NO\.?\b|\bBATCH\s*(NO\.?)?\b');
// A batch-like code: letters and digits mixed, 5-10 long (DOBS3975, B4011Z).
final _batchCode = RegExp(r'\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*\d)[A-Z0-9]{5,10}\b(?=\s+(\d{2}/\d{2}|[A-Z]{3}-\d{2}))');
final _eachContains = RegExp(
    r'\bEACH\s+(\d+\s*ML\s+|\d+\s*G\s+)?((FILM|SUGAR|ENTERIC)[- ]COATED\s+|UNCOATED\s+|(HARD|SOFT)\s+GELATIN\s+|DISPERSIBLE\s+|CHEWABLE\s+)?(TABLET|CAPSULE|CAPSULES|ML|GM|G|SACHET|VIAL|AMPOULE|DOSE|SPRAY|DROP|STRIP)S?\s+CONTAINS\b');
final _mrpInclusive = RegExp(r'INCL\.?(USIVE)?\s+OF\s+ALL\s+TAXES|\bM\.?\s*R\.?\s*P\.?\b.{0,30}\bPER\s+(STRIP|BOTTLE|PACK|TUBE|VIAL)\b');
final _mfg = RegExp(r'\b(MFG|MFD|MANUFACTURED|MFG\.?\s*DT|MFG\.?\s*DATE)\b');
final _exp = RegExp(r'\b(EXP|EXPIRY|USE\s+BEFORE|BEST\s+BEFORE)\b');
final _packWarnings = RegExp(
    r'SCHEDULE\s+H1?\s+(DRUG|PRESCRIPTION)|\bRX\b|STORE\s+(IN\s+A\s+(COOL|DRY)|BELOW|AT)|KEEP\s+(OUT\s+OF|AWAY\s+FROM)\s+(THE\s+)?REACH|DOSAGE\s*:|AS\s+DIRECTED\s+BY|PROTECT\s+FROM\s+(LIGHT|MOISTURE)|TO\s+BE\s+SOLD\s+BY\s+RETAIL');
final _packOf = RegExp(r'\b(STRIP|BLISTER|PACK|BOTTLE)\s+OF\s+\d+\b|\b\d+\s*(TABLETS|CAPSULES)\b');
