import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models/sale_invoice.dart';
import '../domain/models/store_profile.dart';
import '../domain/services/billing_calculator.dart';
import '../domain/services/pack_units.dart';

/// Formats a sale as a WhatsApp e-bill and opens a wa.me chat with it.
class WhatsAppBill {
  static String message(SaleInvoice invoice, StoreProfile store) {
    final date = DateFormat('dd MMM yyyy, hh:mm a').format(invoice.createdAt);
    final b = StringBuffer()
      ..writeln('*${store.name}*')
      ..writeln('Tax Invoice *${invoice.invoiceNumber}*')
      ..writeln(date)
      ..writeln('Customer: ${invoice.customerName}')
      ..writeln('------------------------------');
    for (final l in invoice.lines) {
      final qty = l.unitsPerPack > 1 ? PackUnits.describe(l.quantity, l.unitsPerPack) : '${l.quantity}';
      b.writeln('${l.name} ($qty) — ${formatRupees(l.lineTotalPaise)}');
    }
    b
      ..writeln('------------------------------')
      ..writeln('GST included: ${formatRupees(invoice.gstPaise)}')
      ..writeln('*Total: ${formatRupees(invoice.payablePaise)}* (${invoice.paymentMode.label})');
    if (invoice.isCancelled) b.writeln('_This invoice has been cancelled._');
    b.write('Thank you for choosing ${store.name}!');
    return b.toString();
  }

  /// Digits only; a 10-digit Indian mobile gets the 91 country code.
  /// Returns null if what's left can't be a phone number.
  static String? normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length == 10) return '91$digits';
    if (digits.length == 12 && digits.startsWith('91')) return digits;
    return null;
  }

  static Uri uri(SaleInvoice invoice, StoreProfile store) {
    final phone = normalizePhone(invoice.customerPhone);
    final text = Uri.encodeComponent(message(invoice, store));
    // Without a valid number, wa.me opens WhatsApp's contact picker instead.
    return Uri.parse(phone == null ? 'https://wa.me/?text=$text' : 'https://wa.me/$phone?text=$text');
  }

  static Future<bool> send(SaleInvoice invoice, StoreProfile store) =>
      launchUrl(uri(invoice, store), mode: LaunchMode.externalApplication);
}
