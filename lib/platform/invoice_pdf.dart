import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../domain/models/sale_invoice.dart';
import '../domain/models/store_profile.dart';
import '../domain/services/amount_words.dart';
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

  static const _blue = PdfColor.fromInt(0xFF2D5BA8);
  static const _blueLight = PdfColor.fromInt(0xFFE8EEF8);

  static pw.ImageProvider? _image(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      return pw.MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// A4 tax invoice laid out like a classic printed estimate: shop details
  /// with the logo, a blue items table, the tax table, the amount in words,
  /// bank details, terms, and the signature with the shop's seal.
  static pw.Page _a4Page(SaleInvoice inv, StoreProfile store) {
    const cell = pw.TextStyle(fontSize: 8.5);
    const small = pw.TextStyle(fontSize: 8, color: PdfColors.grey800);
    const head = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    final logo = _image(store.logoImage);
    final signature = _image(store.signatureImage);
    final seal = _image(store.sealImage);
    final date = DateFormat('dd-MM-yyyy').format(inv.createdAt);
    final discounted = inv.lines.any((l) => l.discountPaise > 0);
    int lineGst(SaleLine l) => l.lineTotalPaise - BillingCalculator.taxableFromGross(l.lineTotalPaise, l.gstRate);
    final totalQtyUnits = inv.lines.fold<int>(0, (s, l) => s + l.quantity);

    pw.Widget sectionTitle(String t) =>
        pw.Text(t, style: const pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold));

    return pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(30, 26, 30, 26),
      header: (context) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(store.name, style: const pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              if (store.fullAddress.isNotEmpty) pw.Text(store.fullAddress, style: small),
              pw.Text(
                [
                  if (store.phone.isNotEmpty) 'Phone: ${store.phone}',
                  if (store.email.isNotEmpty) 'Email: ${store.email}',
                ].join('   '),
                style: small,
              ),
              pw.Text(
                [
                  if (store.gstin.isNotEmpty) 'GSTIN: ${store.gstin}',
                  if (store.state.isNotEmpty) 'State: ${store.state}',
                ].join('   '),
                style: small,
              ),
              if (store.drugLicenseNumbers.isNotEmpty) pw.Text('D.L. No: ${store.drugLicenseNumbers}', style: small),
            ]),
          ),
          if (logo != null) pw.SizedBox(width: 70, height: 70, child: pw.Image(logo, fit: pw.BoxFit.contain)),
        ]),
        pw.SizedBox(height: 6),
        pw.Container(height: 1.5, color: _blue),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(inv.isCancelled ? 'Tax Invoice (CANCELLED)' : 'Tax Invoice',
              style: pw.TextStyle(
                  fontSize: 15, fontWeight: pw.FontWeight.bold, color: inv.isCancelled ? PdfColors.red800 : _blue)),
        ),
        pw.SizedBox(height: 6),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              sectionTitle('Bill To:'),
              pw.Text(inv.customerName, style: const pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              if (inv.customerPhone.isNotEmpty) pw.Text('Contact No.: ${inv.customerPhone}', style: small),
              if (inv.prescription != null)
                pw.Text(
                  'Rx: ${inv.prescription!.patientName} (${inv.prescription!.patientPhone}) · '
                  'Dr. ${inv.prescription!.doctorName}, Reg. ${inv.prescription!.doctorRegistrationNumber}',
                  style: small,
                ),
            ]),
          ),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            sectionTitle('Invoice Details:'),
            pw.Text('No.: ${inv.invoiceNumber}', style: cell),
            pw.Text('Date: $date', style: cell),
            pw.Text('Payment: ${inv.paymentMode == PaymentMode.credit ? 'Udhaar (credit)' : inv.paymentMode.label}',
                style: cell),
            if (context.pagesCount > 1)
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}', style: small),
          ]),
        ]),
        pw.SizedBox(height: 8),
      ]),
      build: (context) => [
        pw.TableHelper.fromTextArray(
          headerStyle: head,
          headerDecoration: const pw.BoxDecoration(color: _blue),
          cellStyle: cell,
          oddRowDecoration: const pw.BoxDecoration(color: _blueLight),
          border: const pw.TableBorder(
            bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
            horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          ),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 4),
          columnWidths: {
            0: const pw.FixedColumnWidth(16),
            1: const pw.FlexColumnWidth(4),
            2: const pw.FixedColumnWidth(40),
            3: const pw.FixedColumnWidth(52),
            4: const pw.FixedColumnWidth(58),
            5: const pw.FixedColumnWidth(52),
            if (discounted) 6: const pw.FixedColumnWidth(44),
            (discounted ? 7 : 6): const pw.FixedColumnWidth(58),
            (discounted ? 8 : 7): const pw.FixedColumnWidth(58),
          },
          cellAlignments: {
            0: pw.Alignment.centerRight,
            3: pw.Alignment.center,
            5: pw.Alignment.centerRight,
            6: pw.Alignment.centerRight,
            7: pw.Alignment.centerRight,
            8: pw.Alignment.centerRight,
          },
          headers: [
            '#',
            'Item name',
            'HSN',
            'Quantity',
            'Unit',
            'Price/unit',
            if (discounted) 'Discount',
            'GST',
            'Amount',
          ],
          data: [
            for (var i = 0; i < inv.lines.length; i++)
              [
                '${i + 1}',
                '${inv.lines[i].name}\nBatch ${inv.lines[i].batchNumber} · Exp ${_expiry.format(inv.lines[i].expiryDate)}'
                    '${inv.returnedOf(i) > 0 ? ' · returned ${_qtyUnits(inv.returnedOf(i), inv.lines[i].unitsPerPack)}' : ''}',
                inv.lines[i].hsnCode,
                _qty(inv.lines[i]),
                inv.lines[i].unitsPerPack > 1 ? 'Pack of ${inv.lines[i].unitsPerPack}' : 'Nos',
                formatRupees(inv.lines[i].ratePaise),
                if (discounted) formatRupees(inv.lines[i].discountPaise),
                '${formatRupees(lineGst(inv.lines[i]))}\n(${_rate(inv.lines[i].gstRate)}%)',
                formatRupees(inv.lines[i].lineTotalPaise),
              ],
            [
              '',
              'Total',
              '',
              totalQtyUnits.toString(),
              'units',
              '',
              if (discounted) formatRupees(inv.lines.fold<int>(0, (s, l) => s + l.discountPaise)),
              formatRupees(inv.gstPaise),
              formatRupees(inv.grossPaise),
            ],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              pw.TableHelper.fromTextArray(
                headerStyle: head,
                headerDecoration: const pw.BoxDecoration(color: _blue),
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                cellStyle: const pw.TextStyle(fontSize: 8),
                cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight, 3: pw.Alignment.centerRight},
                headers: ['Tax type', 'Taxable amount', 'Rate', 'Tax amount'],
                data: [
                  for (final sl in inv.slabs) ...[
                    ['CGST', formatRupees(sl.taxablePaise), '${_rate(sl.rate / 2)}%', formatRupees(sl.cgstPaise)],
                    ['SGST', formatRupees(sl.taxablePaise), '${_rate(sl.rate / 2)}%', formatRupees(sl.sgstPaise)],
                  ],
                ],
              ),
              pw.SizedBox(height: 8),
              sectionTitle('Invoice Amount In Words'),
              pw.Text(rupeesInWords(inv.payablePaise), style: cell),
              pw.SizedBox(height: 8),
              sectionTitle('Terms and conditions'),
              pw.Text(store.terms.isEmpty ? StoreProfile.defaultTerms : store.terms, style: small),
              if (store.bankDetails.trim().isNotEmpty) ...[
                pw.SizedBox(height: 8),
                sectionTitle('Bank Details'),
                pw.Text(store.bankDetails.trim(), style: small),
              ],
            ]),
          ),
          pw.SizedBox(width: 16),
          pw.SizedBox(
            width: 190,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
              if (inv.discountPaise > 0) ...[
                _totalRow('MRP total', inv.mrpTotalPaise),
                _totalRow('Discount', -inv.discountPaise),
              ],
              _totalRow('Sub Total', inv.grossPaise),
              _totalRow('Round off', inv.roundOffPaise),
              pw.Container(
                color: _blue,
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('Total', style: head),
                  pw.Text(formatRupees(inv.payablePaise), style: head),
                ]),
              ),
              if (inv.refundedPaise > 0) ...[
                _totalRow('Returned', -inv.refundedPaise),
                _totalRow('Net after returns', inv.payablePaise - inv.refundedPaise, bold: true),
              ],
              pw.SizedBox(height: 14),
              pw.Text('For: ${store.name}', style: cell, textAlign: pw.TextAlign.center),
              pw.SizedBox(
                height: 72,
                child: pw.Stack(alignment: pw.Alignment.center, children: [
                  if (seal != null) pw.Opacity(opacity: 0.85, child: pw.Image(seal, height: 66, fit: pw.BoxFit.contain)),
                  if (signature != null) pw.Image(signature, height: 44, fit: pw.BoxFit.contain),
                ]),
              ),
              pw.Container(height: 0.6, color: PdfColors.grey600),
              pw.SizedBox(height: 2),
              pw.Text('Authorized Signatory', style: cell, textAlign: pw.TextAlign.center),
            ]),
          ),
        ]),
        if (inv.isCancelled) ...[
          pw.SizedBox(height: 10),
          pw.Text('Cancelled by ${inv.cancelledByName ?? '-'}: ${inv.cancellationReason ?? ''}',
              style: const pw.TextStyle(color: PdfColors.red800, fontWeight: pw.FontWeight.bold)),
        ],
        pw.SizedBox(height: 10),
        pw.Text('Billed by ${inv.createdByName} · prices include GST (MRP-inclusive)', style: small),
      ],
    );
  }

  static String _qtyUnits(int units, int perPack) => perPack > 1 ? PackUnits.describe(units, perPack) : '$units';

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
                    '@${formatRupees(l.ratePaise, symbol: false)} ${_rate(l.gstRate)}%', style: small),
                pw.Text(formatRupees(l.lineTotalPaise, symbol: false), style: small),
              ]),
            ]),
          ),
        pw.Divider(height: 6),
        for (final s in inv.slabs)
          pw.Text('GST ${_rate(s.rate)}%: taxable ${formatRupees(s.taxablePaise, symbol: false)}, '
              'CGST ${formatRupees(s.cgstPaise, symbol: false)}, SGST ${formatRupees(s.sgstPaise, symbol: false)}',
              style: small),
        if (inv.discountPaise > 0) _totalRow('MRP total', inv.mrpTotalPaise, size: 8),
        if (inv.discountPaise > 0) _totalRow('Discount', -inv.discountPaise, size: 8),
        _totalRow('Total', inv.grossPaise, size: 8),
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

  /// The first page as a PNG picture (for WhatsApp when a PDF won't do).
  static Future<Uint8List?> png(SaleInvoice invoice, StoreProfile store, {double dpi = 150}) async {
    final bytes = await build(invoice, store);
    await for (final page in Printing.raster(bytes, pages: const [0], dpi: dpi)) {
      return page.toPng();
    }
    return null;
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
