/// GST invoice serials must be unique within a financial year (April–March)
/// and at most 16 characters. Format: INV/26-27/00001.
class InvoiceNumber {
  /// "26-27" for any date from 1 Apr 2026 to 31 Mar 2027.
  static String financialYear(DateTime date) {
    final startYear = date.month >= 4 ? date.year : date.year - 1;
    final a = (startYear % 100).toString().padLeft(2, '0');
    final b = ((startYear + 1) % 100).toString().padLeft(2, '0');
    return '$a-$b';
  }

  static String format(DateTime date, int serial) =>
      'INV/${financialYear(date)}/${serial.toString().padLeft(5, '0')}';
}
