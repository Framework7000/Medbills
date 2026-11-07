import '../domain/models/sale_invoice.dart';
import '../domain/models/store_profile.dart';
import 'bill_share.dart';
import 'invoice_pdf.dart';

Future<String?> shareBill(SaleInvoice sale, StoreProfile store, BillFormat format) async =>
    await InvoicePdf.save(sale, store) ? '' : null;
