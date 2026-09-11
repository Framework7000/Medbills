import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sale_invoice.dart';

/// Formats a [SaleInvoice] into a WhatsApp e-bill message and launches the
/// wa.me deep link.
class WhatsAppBillService {
  static String formatWhatsAppMessage(SaleInvoice invoice) {
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');
    final buffer = StringBuffer();
    buffer.writeln('*MEDBILLS PHARMACY — DIGITAL INVOICE*');
    buffer.writeln('========================================');
    buffer.writeln('*Invoice No:* ${invoice.invoiceNumber}');
    buffer.writeln('*Date:* ${dateFmt.format(invoice.timestamp)}');
    buffer.writeln('*Customer:* ${invoice.customerName}');
    buffer.writeln('----------------------------------------');
    for (final item in invoice.items) {
      final total = (item.totalPaise / 100).toStringAsFixed(2);
      buffer.writeln('${item.name} x${item.quantity} — Rs. $total');
    }
    buffer.writeln('----------------------------------------');
    final gst = (invoice.gstTotalPaise / 100).toStringAsFixed(2);
    final grand = (invoice.grandTotalPaise / 100).toStringAsFixed(2);
    buffer.writeln('*GST:* Rs. $gst');
    buffer.writeln('*Grand Total:* Rs. $grand');
    buffer.writeln('*Payment Mode:* ${invoice.paymentMode}');
    buffer.writeln('========================================');
    buffer.writeln('Thank you for choosing MedBills Pharmacy!');
    return buffer.toString();
  }

  /// Strips non-digits; if the result is exactly 10 digits, prepends the
  /// India country code (91). Falls back to a placeholder store number.
  static String normalizePhone(String rawPhone) {
    final digitsOnly = rawPhone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length == 10) {
      return '91$digitsOnly';
    }
    if (digitsOnly.isEmpty) {
      return '919752408128';
    }
    return digitsOnly;
  }

  static Uri buildWhatsAppUri(SaleInvoice invoice) {
    final phone = normalizePhone(invoice.customerPhone);
    final message = formatWhatsAppMessage(invoice);
    final encoded = Uri.encodeComponent(message);
    return Uri.parse('https://wa.me/$phone?text=$encoded');
  }

  static Future<bool> sendEBillViaWhatsApp(SaleInvoice invoice) async {
    final uri = buildWhatsAppUri(invoice);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
