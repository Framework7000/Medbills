import '../domain/models/sale_invoice.dart';
import '../domain/models/store_profile.dart';
import 'bill_share_web.dart' if (dart.library.io) 'bill_share_io.dart' as impl;

/// How the bill goes out.
enum BillFormat { pdf, photo }

/// Sends the bill on WhatsApp as a PDF or a photo (PNG).
///
/// Phone: opens the share sheet with the file — pick WhatsApp and the chat.
/// Computer: saves the file in Downloads\MedBills bills, shows it in the
/// folder and opens the customer's WhatsApp chat; drag the file into it.
/// Returns where the file was saved on a computer, '' on a phone, or null
/// if it could not be made.
Future<String?> shareBill(SaleInvoice sale, StoreProfile store, BillFormat format) =>
    impl.shareBill(sale, store, format);
