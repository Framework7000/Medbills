import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/models/sale_invoice.dart';
import '../domain/models/store_profile.dart';
import '../domain/services/billing_calculator.dart';
import '../domain/services/pack_units.dart';
import 'pdf_downloader.dart';

enum InvoicePaper {
  a4('A4'),
  thermal80('80 mm receipt');

  const InvoicePaper(this.label);
  final String label;
}

/// GST tax invoice rendering. Embeds Work Sans (Latin + ₹) with Noto Sans
/// Devanagari as fallback, so customer names typed in Hindi render instead
/// of crashing the generator (the PDF standard fonts are ASCII-only).
class InvoicePdf {
  static pw.ThemeData? _theme;

  static Future<pw.ThemeData> _loadTheme() async {
    if (_theme != null) return _theme!;
    Future<pw.Font> font(String path) async => pw.Font.ttf(await rootBundle.load(path));
    final regular = await font('assets/fonts/WorkSans-Regular.ttf');
    final bold = await font('assets/fonts/WorkSans-Bold.ttf');
    final devanagari = await font('assets/fonts/NotoSansDevanagari-Regular.ttf');
    final devanagariBold = await font('assets/fonts/NotoSansDevanagari-Bold.ttf');
    _theme = pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      fontFallback: [devanagari, devanagariBold],
    );
    return _theme!;
  }

  static final _date = DateFormat('dd MMM yyyy, hh:mm a');
  static final _expiry = DateFormat('MM/yy');

  static String _rate(double r) => r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);

  static String _qty(SaleLine l) =>
      l.unitsPerPack > 1 ? PackUnits.describe(l.quantity, l.unitsPerPack) : '${l.quantity}';

  static Future<Uint8List> build(
    SaleInvoice invoice,
    StoreProfile store, {
    InvoicePaper paper = InvoicePaper.a4,
  }) async {
    final theme = await _loadTheme();
    final doc = pw.Document(theme: theme, title: invoice.invoiceNumber, author: store.name);
    if (paper == InvoicePaper.thermal80) {
      doc.addPage(_thermalPage(invoice, store));
    } else {
      doc.addPage(_a4Page(invoice, store));
    }
    return doc.save();
  }

  static pw.Widget _storeHeader(StoreProfile store, {required bool compact}) {
    final small = pw.TextStyle(fontSize: compact ? 7 : 8.5);
    return pw.Column(
      crossAxisAlignment: compact ? pw.CrossAxisAlignment.center : pw.CrossAxisAlignment.start,
      children: [
        pw.Text(store.name,
            style: pw.TextStyle(fontSize: compact ? 11 : 16, fontWeight: pw.FontWeight.bold)),
        if (store.fullAddress.isNotEmpty) pw.Text(store.fullAddress, style: small),
        if (store.phone.isNotEmpty) pw.Text('Phone: ${store.phone}', style: small),
        if (store.gstin.isNotEmpty) pw.Text('GSTIN: ${store.gstin}', style: small),
        if (store.drugLicenseNumbers.isNotEmpty) pw.Text('D.L. No: ${store.drugLicenseNumbers}', style: small),
      ],
    );
  }

  static pw.Page _a4Page(SaleInvoice inv, StoreProfile store) {
    const headerColor = PdfColor.fromInt(0xFF14493D);
    final cell = const pw.TextStyle(fontSize: 8);
    final head = const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);

    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      header: (context) => pw.Column(children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(child: _storeHeader(store, compact: false)),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: headerColor,
                child: pw.Text(inv.isCancelled ? 'TAX INVOICE — CANCELLED' : 'TAX INVOICE',
                    style: const pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 10)),
              ),
              pw.SizedBox(height: 4),
              pw.Text('No: ${inv.invoiceNumber}', style: const pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(_date.format(inv.createdAt), style: cell),
              pw.Text('Payment: ${inv.paymentMode.label}', style: cell),
            ]),
          ],
        ),
        pw.Divider(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Customer: ${inv.customerName}${inv.customerPhone.isEmpty ? '' : '  (${inv.customerPhone})'}',
              style: cell),
          if (context.pagesCount > 1) pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: cell),
        ]),
        if (inv.prescription != null)
          pw.Text(
            'Rx — Patient: ${inv.prescription!.patientName} (${inv.prescription!.patientPhone}); '
            'Dr. ${inv.prescription!.doctorName}, Reg. ${inv.prescription!.doctorRegistrationNumber}',
            style: cell,
          ),
        pw.SizedBox(height: 6),
      ]),
      footer: (context) => pw.Column(children: [
        pw.Divider(),
        pw.Text('Prices are MRP, inclusive of GST. Goods once sold will be taken back only as per store policy.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
      ]),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headerStyle: head,
          headerDecoration: const pw.BoxDecoration(color: headerColor),
          cellStyle: cell,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          columnWidths: {
            0: const pw.FixedColumnWidth(18),
            1: const pw.FlexColumnWidth(4),
            2: const pw.FixedColumnWidth(42),
            3: const pw.FixedColumnWidth(54),
            4: const pw.FixedColumnWidth(34),
            5: const pw.FixedColumnWidth(48),
            6: const pw.FixedColumnWidth(48),
            7: const pw.FixedColumnWidth(28),
            8: const pw.FixedColumnWidth(56),
          },
          cellAlignments: {
            0: pw.Alignment.centerRight,
            4: pw.Alignment.center,
            6: pw.Alignment.centerRight,
            7: pw.Alignment.centerRight,
            8: pw.Alignment.centerRight,
          },
          headers: ['#', 'Item', 'HSN', 'Batch', 'Exp', 'Qty', 'MRP/pack', 'GST', 'Amount'],
          data: [
            for (var i = 0; i < inv.lines.length; i++)
              [
                '${i + 1}',
                inv.lines[i].name,
                inv.lines[i].hsnCode,
                inv.lines[i].batchNumber,
                _expiry.format(inv.lines[i].expiryDate),
                _qty(inv.lines[i]),
                formatRupees(inv.lines[i].mrpPaise, symbol: false),
                '${_rate(inv.lines[i].gstRate)}%',
                formatRupees(inv.lines[i].lineTotalPaise, symbol: false),
              ],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.TableHelper.fromTextArray(
              headerStyle: const pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellAlignment: pw.Alignment.centerRight,
              headers: ['GST %', 'Taxable', 'CGST', 'SGST', 'Total GST'],
              data: [
                for (final s in inv.slabs)
                  [
                    '${_rate(s.rate)}%',
                    formatRupees(s.taxablePaise, symbol: false),
                    formatRupees(s.cgstPaise, symbol: false),
                    formatRupees(s.sgstPaise, symbol: false),
                    formatRupees(s.gstPaise, symbol: false),
                  ],
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.SizedBox(
            width: 170,
            child: pw.Column(children: [
              _totalRow('Taxable value', inv.taxablePaise),
              _totalRow('GST', inv.gstPaise),
              _totalRow('Total (MRP)', inv.grossPaise),
              _totalRow('Round off', inv.roundOffPaise),
              pw.Divider(height: 6),
              _totalRow('Amount payable', inv.payablePaise, bold: true),
            ]),
          ),
        ]),
        if (inv.isCancelled) ...[
          pw.SizedBox(height: 10),
          pw.Text('Cancelled by ${inv.cancelledByName ?? '-'}: ${inv.cancellationReason ?? ''}',
              style: const pw.TextStyle(color: PdfColors.red800, fontWeight: pw.FontWeight.bold)),
        ],
        pw.SizedBox(height: 18),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Billed by: ${inv.createdByName}', style: cell),
          pw.Text('for ${store.name}\n\n\nPharmacist signature',
              textAlign: pw.TextAlign.right, style: cell),
        ]),
      ],
    );
  }

  static pw.Widget _totalRow(String label, int paise, {bool bold = false, double size = 9}) {
    final style = pw.TextStyle(fontSize: size, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(label, style: style),
        pw.Text(formatRupees(paise), style: style),
      ]),
    );
  }

  static pw.Page _thermalPage(SaleInvoice inv, StoreProfile store) {
    final small = const pw.TextStyle(fontSize: 7);
    return pw.MultiPage(
      pageFormat: PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      build: (context) => [
        _storeHeader(store, compact: true),
        pw.SizedBox(height: 4),
        pw.Center(
          child: pw.Text(inv.isCancelled ? 'TAX INVOICE (CANCELLED)' : 'TAX INVOICE',
              style: const pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Text('${inv.invoiceNumber}   ${_date.format(inv.createdAt)}', style: small),
        pw.Text('Customer: ${inv.customerName}', style: small),
        pw.Divider(height: 6),
        for (final l in inv.lines)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(l.name, style: const pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold)),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('B:${l.batchNumber} E:${_expiry.format(l.expiryDate)} ${_qty(l)} '
                    '@${formatRupees(l.mrpPaise, symbol: false)} ${_rate(l.gstRate)}%', style: small),
                pw.Text(formatRupees(l.lineTotalPaise, symbol: false), style: small),
              ]),
            ]),
          ),
        pw.Divider(height: 6),
        for (final s in inv.slabs)
          pw.Text('GST ${_rate(s.rate)}%: taxable ${formatRupees(s.taxablePaise, symbol: false)}, '
              'CGST ${formatRupees(s.cgstPaise, symbol: false)}, SGST ${formatRupees(s.sgstPaise, symbol: false)}',
              style: small),
        _totalRow('Total (MRP)', inv.grossPaise, size: 8),
        _totalRow('Round off', inv.roundOffPaise, size: 8),
        _totalRow('PAYABLE', inv.payablePaise, bold: true, size: 10),
        pw.Text('Paid by ${inv.paymentMode.label}', style: small),
        if (inv.prescription != null)
          pw.Text('Rx: ${inv.prescription!.patientName} / Dr. ${inv.prescription!.doctorName} '
              '(${inv.prescription!.doctorRegistrationNumber})', style: small),
        pw.SizedBox(height: 6),
        pw.Center(child: pw.Text('Thank you! Get well soon.', style: small)),
      ],
    );
  }

  static String fileName(SaleInvoice invoice) =>
      '${invoice.invoiceNumber.replaceAll('/', '-')}.pdf';

  static Future<bool> save(SaleInvoice invoice, StoreProfile store, {InvoicePaper paper = InvoicePaper.a4}) async {
    final bytes = await build(invoice, store, paper: paper);
    return savePdf(bytes, fileName(invoice));
  }

  static Future<bool> printInvoice(SaleInvoice invoice, StoreProfile store,
      {InvoicePaper paper = InvoicePaper.a4}) async {
    final bytes = await build(invoice, store, paper: paper);
    return Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileName(invoice),
      format: paper == InvoicePaper.thermal80 ? PdfPageFormat.roll80 : PdfPageFormat.a4,
    );
  }
}
