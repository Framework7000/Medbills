/// All bill arithmetic, in integer paise (Rule 12).
///
/// MRP in India is GST-inclusive (Rule 4), so tax is *extracted* from the
/// amount charged, never added on top. Extraction is rounded once per GST
/// slab, never per line (Rule 5), so the invoice reconciles with GSTR-1.
class BillingCalculator {
  /// Price of [quantityUnits] base units when [mrpPaisePerPack] buys
  /// [unitsPerPack] of them, rounded half-up to the paisa.
  static int linePaise({
    required int mrpPaisePerPack,
    required int unitsPerPack,
    required int quantityUnits,
  }) {
    final perPack = unitsPerPack < 1 ? 1 : unitsPerPack;
    return (mrpPaisePerPack * quantityUnits * 2 + perPack) ~/ (perPack * 2);
  }

  /// Taxable value inside a GST-inclusive [grossPaise] at [gstRate] percent.
  static int taxableFromGross(int grossPaise, double gstRate) {
    final rateBp = (gstRate * 100).round(); // 12% → 1200 basis points
    final divisor = 10000 + rateBp;
    return (grossPaise * 10000 * 2 + divisor) ~/ (divisor * 2);
  }

  static BillSummary summarise(Iterable<BillLine> lines) {
    final grossBySlab = <double, int>{};
    for (final line in lines) {
      grossBySlab.update(line.gstRate, (v) => v + line.lineTotalPaise,
          ifAbsent: () => line.lineTotalPaise);
    }

    final slabs = <GstSlab>[];
    final rates = grossBySlab.keys.toList()..sort();
    for (final rate in rates) {
      final gross = grossBySlab[rate]!;
      final taxable = taxableFromGross(gross, rate);
      slabs.add(GstSlab(rate: rate, grossPaise: gross, taxablePaise: taxable));
    }

    final gross = slabs.fold<int>(0, (sum, s) => sum + s.grossPaise);
    // Retail bills are settled to the nearest rupee; the difference is shown
    // as a separate "round off" line rather than hidden in the totals.
    final payable = ((gross + 50) ~/ 100) * 100;
    return BillSummary(slabs: slabs, grossPaise: gross, payablePaise: payable);
  }
}

class BillLine {
  final int lineTotalPaise;
  final double gstRate;

  const BillLine({required this.lineTotalPaise, required this.gstRate});
}

class GstSlab {
  final double rate;
  final int grossPaise; // MRP value of all lines in this slab (GST-inclusive)
  final int taxablePaise;

  const GstSlab({required this.rate, required this.grossPaise, required this.taxablePaise});

  int get gstPaise => grossPaise - taxablePaise;

  /// Intra-state supply splits GST equally into CGST and SGST; the odd
  /// paisa, if any, goes to CGST so the halves always sum to [gstPaise].
  int get cgstPaise => gstPaise - sgstPaise;
  int get sgstPaise => gstPaise ~/ 2;

  Map<String, dynamic> toMap() => {
        'rate': rate,
        'grossPaise': grossPaise,
        'taxablePaise': taxablePaise,
        'gstPaise': gstPaise,
      };

  factory GstSlab.fromMap(Map<String, dynamic> map) => GstSlab(
        rate: (map['rate'] as num).toDouble(),
        grossPaise: (map['grossPaise'] as num).toInt(),
        taxablePaise: (map['taxablePaise'] as num).toInt(),
      );
}

class BillSummary {
  final List<GstSlab> slabs;
  final int grossPaise;
  final int payablePaise;

  const BillSummary({required this.slabs, required this.grossPaise, required this.payablePaise});

  int get taxablePaise => slabs.fold(0, (sum, s) => sum + s.taxablePaise);
  int get gstPaise => slabs.fold(0, (sum, s) => sum + s.gstPaise);
  int get roundOffPaise => payablePaise - grossPaise;

  static const empty = BillSummary(slabs: [], grossPaise: 0, payablePaise: 0);
}

/// Formats paise as "₹1,234.50" (Indian digit grouping).
String formatRupees(int paise, {bool symbol = true}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final fraction = (abs % 100).toString().padLeft(2, '0');
  final digits = rupees.toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${negative ? '-' : ''}${symbol ? '₹' : ''}$grouped.$fraction';
}

/// Parses a user-typed rupee amount ("12", "12.5", "1,234.50") into paise.
/// Returns null for anything that isn't a non-negative amount with at most
/// two decimals.
int? parseRupeesToPaise(String input) {
  final cleaned = input.replaceAll(',', '').replaceAll('₹', '').trim();
  final match = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$').firstMatch(cleaned);
  if (match == null) return null;
  final rupees = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return rupees * 100 + int.parse(fraction);
}
