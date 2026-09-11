import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/sale_invoice.dart';
import 'pdf_downloader.dart';

/// Generates GST-compliant tax invoice PDFs and drives the in-app preview
/// modal. See blueprint section 11 for the full history of why this is
/// shaped the way it is.
class PdfInvoiceService {
  static final _dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

  /// Standard Helvetica (the `pdf` package's built-in font) only maps
  /// ASCII. Any Unicode glyph — rupee sign, bullets, em/en dashes — throws
  /// an unhandled "Cannot find character mapping" exception at render time
  /// (Defect 14.1). Sanitize every string before it reaches `pw.Text`.
  static String _cleanText(String text) {
    return text
        .replaceAll('•', '|')
        .replaceAll('₹', 'Rs. ')
        .replaceAll('—', '-')
        .replaceAll('–', '-');
  }

  static Future<Uint8List> generateInvoicePdf(SaleInvoice invoice) async {
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                color: const PdfColor.fromInt(0xFF14493D),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      _cleanText('MEDBILLS PHARMACY'),
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      _cleanText('TAX INVOICE'),
                      style: const pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Fixed spacing only — pw.Spacer() inside a fixed A4 page
              // throws a flex overflow once content approaches the page
              // boundary (Defect 14.2). Never use it in PDF layouts.
              pw.SizedBox(height: 20),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(_cleanText('Invoice No: ${invoice.invoiceNumber}')),
                  pw.Text(_cleanText(_dateFmt.format(invoice.timestamp))),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text(_cleanText('Customer: ${invoice.customerName}')),
              pw.Text(_cleanText('Phone: ${invoice.customerPhone}')),
              pw.SizedBox(height: 20),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(1.5),
                  2: pw.FlexColumnWidth(1),
                  3: pw.FlexColumnWidth(1.5),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _cell('Item', bold: true),
                      _cell('Batch', bold: true),
                      _cell('Qty', bold: true),
                      _cell('Amount', bold: true),
                    ],
                  ),
                  for (final item in invoice.items)
                    pw.TableRow(
                      children: [
                        _cell(item.name),
                        _cell(item.batchNumber),
                        _cell('${item.quantity}'),
                        _cell('Rs. ${(item.totalPaise / 100).toStringAsFixed(2)}'),
                      ],
                    ),
                ],
              ),
              pw.SizedBox(height: 20),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(_cleanText(
                        'GST: Rs. ${(invoice.gstTotalPaise / 100).toStringAsFixed(2)}')),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      _cleanText(
                          'Grand Total: Rs. ${(invoice.grandTotalPaise / 100).toStringAsFixed(2)}'),
                      style: const pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Text(_cleanText('Payment Mode: ${invoice.paymentMode}')),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        _cleanText(text),
        style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }

  static String generateInvoiceHtml(SaleInvoice invoice) {
    final rows = invoice.items.map((item) {
      final total = (item.totalPaise / 100).toStringAsFixed(2);
      return '<tr><td>${item.name}</td><td>${item.batchNumber}</td>'
          '<td>${item.quantity}</td><td>Rs. $total</td></tr>';
    }).join();
    final gst = (invoice.gstTotalPaise / 100).toStringAsFixed(2);
    final grand = (invoice.grandTotalPaise / 100).toStringAsFixed(2);
    return '''
<html><head><meta charset="utf-8"><title>${invoice.invoiceNumber}</title></head>
<body>
<h2>MedBills Pharmacy — Tax Invoice</h2>
<p>Invoice No: ${invoice.invoiceNumber}<br>Date: ${_dateFmt.format(invoice.timestamp)}</p>
<p>Customer: ${invoice.customerName}<br>Phone: ${invoice.customerPhone}</p>
<table border="1" cellpadding="6" cellspacing="0">
<tr><th>Item</th><th>Batch</th><th>Qty</th><th>Amount</th></tr>
$rows
</table>
<p>GST: Rs. $gst<br><b>Grand Total: Rs. $grand</b></p>
<p>Payment Mode: ${invoice.paymentMode}</p>
</body></html>
''';
  }

  static Future<bool> printOrDownloadInvoice(SaleInvoice invoice) async {
    final bytes = await generateInvoicePdf(invoice);
    return downloadPdfBytes(bytes, '${invoice.invoiceNumber}.pdf');
  }

  static Future<void> printReceipt(SaleInvoice invoice) async {
    final bytes = await generateInvoicePdf(invoice);
    await Printing.layoutPdf(onLayout: (format) async => bytes, name: invoice.invoiceNumber);
  }

  /// Flutter web's canvas-based PDF preview widgets are unreliable — they
  /// depend on PDF.js loading, browser permissions, and CORS, and users saw
  /// "Unable to display the document" (Defect 14.3). Preview the invoice as
  /// a native Flutter widget instead; only render a real PDF binary when
  /// the user actually wants to download or print.
  static Future<void> showPdfPreviewModal(BuildContext context, SaleInvoice invoice) {
    return showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Invoice ${invoice.invoiceNumber}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customer: ${invoice.customerName}'),
                        Text('Phone: ${invoice.customerPhone}'),
                        Text('Date: ${_dateFmt.format(invoice.timestamp)}'),
                        const Divider(),
                        for (final item in invoice.items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(child: Text('${item.name} x${item.quantity}')),
                                Text('Rs. ${(item.totalPaise / 100).toStringAsFixed(2)}'),
                              ],
                            ),
                          ),
                        const Divider(),
                        Text('GST: Rs. ${(invoice.gstTotalPaise / 100).toStringAsFixed(2)}'),
                        Text(
                          'Grand Total: Rs. ${(invoice.grandTotalPaise / 100).toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => printOrDownloadInvoice(invoice),
                          child: const Text('Download PDF'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => printReceipt(invoice),
                          child: const Text('Print Receipt'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
