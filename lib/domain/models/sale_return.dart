import '../services/billing_calculator.dart';
import 'date_value.dart';
import 'sale_invoice.dart';

/// How money went back to the customer for a return.
enum RefundMode {
  cash('Cash'),
  upi('UPI'),
  udhaar('Udhaar reduced');

  const RefundMode(this.label);
  final String label;

  static RefundMode fromString(String? v) =>
      RefundMode.values.firstWhere((m) => m.name == v, orElse: () => RefundMode.cash);
}

/// One returned line: some units of one line of the original bill.
class ReturnLine {
  final int lineIndex; // position in the sale's lines
  final String medicineId;
  final String batchId;
  final String name;
  final String batchNumber;
  final int unitsPerPack;
  final int quantity; // base units back on the shelf
  final int refundPaise; // what the customer paid for these units
  final int costPaise; // their purchase cost (comes back into stock)
  final double gstRate;

  const ReturnLine({
    required this.lineIndex,
    required this.medicineId,
    required this.batchId,
    required this.name,
    required this.batchNumber,
    required this.unitsPerPack,
    required this.quantity,
    required this.refundPaise,
    required this.costPaise,
    required this.gstRate,
  });

  Map<String, dynamic> toMap() => {
        'lineIndex': lineIndex,
        'medicineId': medicineId,
        'batchId': batchId,
        'name': name,
        'batchNumber': batchNumber,
        'unitsPerPack': unitsPerPack,
        'quantity': quantity,
        'refundPaise': refundPaise,
        'costPaise': costPaise,
        'gstRate': gstRate,
      };

  factory ReturnLine.fromMap(Map<String, dynamic> m) => ReturnLine(
        lineIndex: readInt(m['lineIndex']),
        medicineId: readString(m['medicineId']),
        batchId: readString(m['batchId']),
        name: readString(m['name']),
        batchNumber: readString(m['batchNumber']),
        unitsPerPack: readInt(m['unitsPerPack'], 1),
        quantity: readInt(m['quantity']),
        refundPaise: readInt(m['refundPaise']),
        costPaise: readInt(m['costPaise']),
        gstRate: readDouble(m['gstRate']),
      );
}

/// A customer bringing medicines back (a sales return / credit note).
/// Append-only: recorded on the day it happens, so that day's figures show it.
class SaleReturn {
  final String id;
  final String storeId;
  final String saleId;
  final String invoiceNumber;
  final String customerName;
  final List<ReturnLine> lines;
  final RefundMode refundMode;
  final String reason;
  final DateTime createdAt;
  final String createdBy;
  final String createdByName;

  const SaleReturn({
    required this.id,
    required this.storeId,
    required this.saleId,
    required this.invoiceNumber,
    required this.customerName,
    required this.lines,
    required this.refundMode,
    required this.reason,
    required this.createdAt,
    required this.createdBy,
    required this.createdByName,
  });

  int get refundPaise => lines.fold(0, (s, l) => s + l.refundPaise);
  int get costPaise => lines.fold(0, (s, l) => s + l.costPaise);

  /// GST inside the refund, worked out per slab like a bill.
  int get gstPaise => BillingCalculator.summarise(
        lines.map((l) => BillLine(lineTotalPaise: l.refundPaise, gstRate: l.gstRate)),
      ).gstPaise;

  Map<String, dynamic> toMap() => {
        'id': id,
        'storeId': storeId,
        'saleId': saleId,
        'invoiceNumber': invoiceNumber,
        'customerName': customerName,
        'lines': lines.map((l) => l.toMap()).toList(),
        'refundMode': refundMode.name,
        'refundPaise': refundPaise,
        'reason': reason,
        'createdAt': createdAt,
        'createdBy': createdBy,
        'createdByName': createdByName,
      };

  factory SaleReturn.fromMap(Map<String, dynamic> m) => SaleReturn(
        id: readString(m['id']),
        storeId: readString(m['storeId'], 'store_primary'),
        saleId: readString(m['saleId']),
        invoiceNumber: readString(m['invoiceNumber']),
        customerName: readString(m['customerName']),
        lines: ((m['lines'] as List?) ?? const [])
            .map((e) => ReturnLine.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        refundMode: RefundMode.fromString(m['refundMode'] as String?),
        reason: readString(m['reason']),
        createdAt: readDate(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
        createdBy: readString(m['createdBy']),
        createdByName: readString(m['createdByName']),
      );
}

/// The result of checking a return against the bill as it is now.
class ReturnPlan {
  final List<ReturnLine> lines;
  final List<int> newReturnedUnits; // for the sale, same order as its lines
  final int refundPaise;

  const ReturnPlan({required this.lines, required this.newReturnedUnits, required this.refundPaise});
}

class SaleReturnPlanner {
  /// [units] maps a line index of [sale] to the base units coming back.
  /// The refund is what the customer paid for those units, worked out so
  /// that returning a line bit by bit refunds exactly what returning it at
  /// once would: never a paisa more than the line cost them.
  static ReturnPlan plan({
    required SaleInvoice sale,
    required Map<int, int> units,
    required RefundMode mode,
  }) {
    final problems = <String>[];
    if (sale.isCancelled) problems.add('This bill is cancelled.');
    if (mode == RefundMode.udhaar && sale.customerId == null) {
      problems.add('This was not an udhaar bill; refund in cash or UPI.');
    }
    final returned = [for (var i = 0; i < sale.lines.length; i++) sale.returnedOf(i)];
    final lines = <ReturnLine>[];
    final indexes = units.keys.toList()..sort();
    for (final i in indexes) {
      final qty = units[i]!;
      if (qty == 0) continue;
      if (i < 0 || i >= sale.lines.length) {
        problems.add('That line is not on this bill.');
        continue;
      }
      final line = sale.lines[i];
      if (qty < 0) {
        problems.add('${line.name}: quantity cannot be negative.');
        continue;
      }
      final before = returned[i];
      if (before + qty > line.quantity) {
        problems.add('${line.name}: only ${line.quantity - before} can still be returned.');
        continue;
      }
      int share(int total, int u) => line.quantity == 0 ? 0 : (total * u * 2 + line.quantity) ~/ (line.quantity * 2);
      final refund = share(line.lineTotalPaise, before + qty) - share(line.lineTotalPaise, before);
      final cost = share(line.costPaise, before + qty) - share(line.costPaise, before);
      returned[i] = before + qty;
      lines.add(ReturnLine(
        lineIndex: i,
        medicineId: line.medicineId,
        batchId: line.batchId,
        name: line.name,
        batchNumber: line.batchNumber,
        unitsPerPack: line.unitsPerPack,
        quantity: qty,
        refundPaise: refund,
        costPaise: cost,
        gstRate: line.gstRate,
      ));
    }
    if (lines.isEmpty && problems.isEmpty) problems.add('Choose what the customer is returning.');
    if (problems.isNotEmpty) throw ReturnException(problems.toSet().toList());
    return ReturnPlan(
      lines: lines,
      newReturnedUnits: returned,
      refundPaise: lines.fold(0, (s, l) => s + l.refundPaise),
    );
  }
}

class ReturnException implements Exception {
  final List<String> problems;
  const ReturnException(this.problems);

  @override
  String toString() => problems.join('\n');
}
