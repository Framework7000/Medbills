import 'dart:io';

import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/models/sale_invoice.dart';
import '../domain/models/store_profile.dart';
import 'bill_share.dart';
import 'invoice_pdf.dart';
import 'whatsapp_bill.dart';

Future<String?> shareBill(SaleInvoice sale, StoreProfile store, BillFormat format) async {
  final bytes = format == BillFormat.pdf ? await InvoicePdf.build(sale, store) : await InvoicePdf.png(sale, store);
  if (bytes == null) return null;
  final base = InvoicePdf.fileName(sale).replaceAll('.pdf', '');
  final name = format == BillFormat.pdf ? '$base.pdf' : '$base.png';

  if (Platform.isAndroid || Platform.isIOS) {
    final ok = await Printing.sharePdf(
      bytes: bytes,
      filename: name,
      subject: '${store.name} · ${sale.invoiceNumber}',
      body: WhatsAppBill.message(sale, store),
    );
    return ok ? '' : null;
  }

  // A computer: keep the file where it is easy to find, show it, and open
  // the customer's chat so it can be dropped in.
  final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? Directory.systemTemp.path;
  final dir = Directory('$home${Platform.pathSeparator}Downloads${Platform.pathSeparator}MedBills bills');
  await dir.create(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsBytes(bytes, flush: true);
  try {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', file.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', ['-R', file.path]);
    }
  } catch (_) {}
  try {
    await launchUrl(WhatsAppBill.uri(sale, store), mode: LaunchMode.externalApplication);
  } catch (_) {}
  return file.path;
}
