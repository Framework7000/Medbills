import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/models/sale_invoice.dart';
import '../../domain/models/store_profile.dart';
import '../../domain/services/billing_calculator.dart';
import '../../domain/services/pack_units.dart';
import '../../platform/bill_share.dart';
import '../../platform/invoice_pdf.dart';
import '../../platform/whatsapp_bill.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'return_dialog.dart';

Future<void> showInvoice(BuildContext context, SaleInvoice sale, {bool justCompleted = false}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => InvoiceScreen(saleId: sale.id, initial: sale, justCompleted: justCompleted),
  ));
}

class InvoiceScreen extends ConsumerWidget {
  const InvoiceScreen({super.key, required this.saleId, required this.initial, this.justCompleted = false});

  final String saleId;
  final SaleInvoice initial;
  final bool justCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.watch(recentSalesProvider).valueOrNull ?? const [];
    final sale = sales.where((s) => s.id == saleId).firstOrNull ?? initial;
    final store = ref.watch(storeProvider).valueOrNull ??
        StoreProfile(storeId: sale.storeId, name: 'MedBills Pharmacy');
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(justCompleted ? 'Sale complete' : sale.invoiceNumber),
        actions: [
          if (user != null && user.role.canCancelSales && !sale.isCancelled && !sale.fullyReturned)
            TextButton.icon(
              key: const ValueKey('return-items'),
              onPressed: () => showReturnDialog(context, ref, sale),
              icon: const Icon(PhosphorIconsRegular.arrowUUpLeft),
              label: const Text('Return'),
            ),
          if (user != null && user.role.canCancelSales && !sale.isCancelled && !sale.hasReturns)
            IconButton(
              tooltip: 'Cancel this sale',
              icon: const Icon(PhosphorIconsRegular.prohibit),
              onPressed: () => _cancel(context, ref, sale),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(Space.l),
              children: [
                if (justCompleted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.l),
                    child: Card(
                      color: AppColors.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(Space.l),
                        child: Row(children: [
                          const Icon(PhosphorIconsRegular.checkCircle, color: AppColors.primary),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Text('${sale.invoiceNumber} saved · collect ${formatRupees(sale.payablePaise)}'
                                ' (${sale.paymentMode.label})',
                                style: Theme.of(context).textTheme.titleMedium),
                          ),
                        ]),
                      ),
                    ),
                  ),
                _InvoiceActions(sale: sale, store: store),
                const SizedBox(height: Space.l),
                InvoicePaperView(sale: sale, store: store),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref, SaleInvoice sale) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel ${sale.invoiceNumber}?'),
        content: DialogBody(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('The invoice stays on record marked CANCELLED, its stock goes back to the batches, '
                'and any udhaar is reversed. This cannot be undone.'),
            const SizedBox(height: Space.m),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
              textCapitalization: TextCapitalization.sentences,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              if (controller.text.trim().isEmpty) return;
              Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Cancel sale'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(repositoryProvider)!.cancelSale(sale.id, reason);
      if (context.mounted) showMessage(context, '${sale.invoiceNumber} cancelled; stock returned.');
    } catch (e) {
      if (context.mounted) showMessage(context, friendlyError(e), error: true);
    }
  }
}

class _InvoiceActions extends StatefulWidget {
  const _InvoiceActions({required this.sale, required this.store});
  final SaleInvoice sale;
  final StoreProfile store;

  @override
  State<_InvoiceActions> createState() => _InvoiceActionsState();
}

class _InvoiceActionsState extends State<_InvoiceActions> {
  bool _busy = false;

  Future<void> _run(Future<bool> Function() action, String failure) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await action();
      if (!ok && mounted) showMessage(context, failure, error: true);
    } catch (e) {
      if (mounted) showMessage(context, '$failure (${friendlyError(e)})', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(BillFormat format) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await shareBill(widget.sale, widget.store, format);
      if (!mounted) return;
      if (saved == null) {
        showMessage(context, 'Could not make the bill ${format == BillFormat.pdf ? 'PDF' : 'photo'}.', error: true);
      } else if (saved.isNotEmpty) {
        showMessage(context, 'Bill saved: $saved\nWhatsApp is opening — drag the file into the chat.');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    final store = widget.store;
    return Wrap(
      spacing: Space.s,
      runSpacing: Space.s,
      children: [
        PopupMenuButton<InvoicePaper>(
          enabled: !_busy,
          tooltip: 'Print',
          onSelected: (paper) =>
              _run(() => InvoicePdf.printInvoice(sale, store, paper: paper), 'Printing was cancelled or failed.'),
          itemBuilder: (_) => [
            for (final p in InvoicePaper.values) PopupMenuItem(value: p, child: Text('Print — ${p.label}')),
          ],
          child: IgnorePointer(
            child: FilledButton.icon(onPressed: _busy ? null : () {}, icon: const Icon(PhosphorIconsRegular.printer), label: const Text('Print')),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : () => _run(() => InvoicePdf.save(sale, store), 'Could not save the PDF.'),
          icon: const Icon(PhosphorIconsRegular.filePdf),
          label: const Text('PDF'),
        ),
        PopupMenuButton<String>(
          key: const ValueKey('whatsapp-menu'),
          enabled: !_busy,
          tooltip: 'Send on WhatsApp',
          onSelected: (v) => v == 'text'
              ? _run(() => WhatsAppBill.send(sale, store), 'Could not open WhatsApp.')
              : _share(v == 'pdf' ? BillFormat.pdf : BillFormat.photo),
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'pdf', child: ListTile(leading: Icon(PhosphorIconsRegular.filePdf), title: Text('Send bill as PDF'))),
            PopupMenuItem(
                value: 'photo', child: ListTile(leading: Icon(PhosphorIconsRegular.image), title: Text('Send bill as photo'))),
            PopupMenuItem(
                value: 'text', child: ListTile(leading: Icon(PhosphorIconsRegular.chatText), title: Text('Send as text message'))),
          ],
          child: IgnorePointer(
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () {},
              icon: const Icon(PhosphorIconsRegular.chatCircle),
              label: const Text('WhatsApp'),
            ),
          ),
        ),
        if (_busy) const Padding(padding: EdgeInsets.all(Space.s), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      ],
    );
  }
}

/// The invoice laid out like the printed copy, built from Flutter widgets.
class InvoicePaperView extends StatelessWidget {
  const InvoicePaperView({super.key, required this.sale, required this.store});
  final SaleInvoice sale;
  final StoreProfile store;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);
    final date = DateFormat('dd MMM yyyy, hh:mm a').format(sale.createdAt);
    String rate(double r) => r == r.roundToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Space.l),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(store.name, style: text.titleLarge),
                if (store.fullAddress.isNotEmpty) Text(store.fullAddress, style: muted),
                if (store.gstin.isNotEmpty) Text('GSTIN ${store.gstin}', style: muted),
                if (store.drugLicenseNumbers.isNotEmpty) Text('D.L. ${store.drugLicenseNumbers}', style: muted),
              ]),
            ),
            const SizedBox(width: Space.m),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (sale.isCancelled)
                const Pill('CANCELLED', foreground: AppColors.danger, background: AppColors.dangerContainer)
              else
                const Pill('TAX INVOICE', foreground: AppColors.primary, background: AppColors.primaryContainer),
              const SizedBox(height: Space.xs),
              Text(sale.invoiceNumber, style: text.titleSmall),
              Text(date, style: muted),
            ]),
          ]),
          const Divider(height: Space.xl),
          Text('${sale.customerName}${sale.customerPhone.isEmpty ? '' : ' · ${sale.customerPhone}'}',
              style: text.bodyMedium),
          Text('Paid by ${sale.paymentMode.label} · billed by ${sale.createdByName}', style: muted),
          if (sale.prescription != null)
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                'Rx: ${sale.prescription!.patientName} (${sale.prescription!.patientPhone}) · '
                'Dr. ${sale.prescription!.doctorName}, Reg. ${sale.prescription!.doctorRegistrationNumber}',
                style: muted,
              ),
            ),
          const SizedBox(height: Space.m),
          for (final line in sale.lines) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(line.name, style: text.bodyLarge),
                    Text(
                      'Batch ${line.batchNumber} · Exp ${DateFormat('MM/yy').format(line.expiryDate)} · '
                      'HSN ${line.hsnCode} · GST ${rate(line.gstRate)}%',
                      style: muted,
                    ),
                    Text(
                      '${line.unitsPerPack > 1 ? PackUnits.describe(line.quantity, line.unitsPerPack) : line.quantity} '
                      '@ ${formatRupees(line.ratePaise)}${line.unitsPerPack > 1 ? '/pack' : ''}'
                      '${line.ratePaise < line.mrpPaise ? ' (MRP ${formatRupees(line.mrpPaise)})' : ''}',
                      style: muted,
                    ),
                    if (sale.returnedOf(sale.lines.indexOf(line)) > 0)
                      Text(
                        'Returned ${PackUnits.describe(sale.returnedOf(sale.lines.indexOf(line)), line.unitsPerPack)}',
                        style: text.bodySmall?.copyWith(color: AppColors.warning),
                      ),
                  ]),
                ),
                const SizedBox(width: Space.m),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (line.discountPaise > 0)
                    Text(formatRupees(line.mrpLinePaise),
                        style: muted?.copyWith(decoration: TextDecoration.lineThrough)),
                  Text(formatRupees(line.lineTotalPaise), style: text.bodyLarge),
                ]),
              ]),
            ),
            const Divider(),
          ],
          const SizedBox(height: Space.s),
          for (final slab in sale.slabs)
            AmountRow('GST ${rate(slab.rate)}% on ${formatRupees(slab.taxablePaise)} '
                '(CGST ${formatRupees(slab.cgstPaise)} + SGST ${formatRupees(slab.sgstPaise)})',
                formatRupees(slab.gstPaise)),
          AmountRow('Taxable value', formatRupees(sale.taxablePaise)),
          if (sale.discountPaise > 0) ...[
            AmountRow('MRP total', formatRupees(sale.mrpTotalPaise)),
            AmountRow('Discount', '−${formatRupees(sale.discountPaise)}'),
          ],
          AmountRow('Total (incl. GST)', formatRupees(sale.grossPaise)),
          AmountRow('Round off', formatRupees(sale.roundOffPaise)),
          const Divider(height: Space.l),
          AmountRow('Amount payable', formatRupees(sale.payablePaise), emphasis: true),
          if (sale.refundedPaise > 0) ...[
            AmountRow('Returned (refunded)', '−${formatRupees(sale.refundedPaise)}'),
            AmountRow('Net after returns', formatRupees(sale.payablePaise - sale.refundedPaise), emphasis: true),
          ],
          if (sale.isCancelled) ...[
            const SizedBox(height: Space.m),
            Text(
              'Cancelled by ${sale.cancelledByName ?? '-'}'
              '${sale.cancelledAt == null ? '' : ' on ${DateFormat('dd MMM yyyy, hh:mm a').format(sale.cancelledAt!)}'}: '
              '${sale.cancellationReason ?? ''}',
              style: text.bodyMedium?.copyWith(color: AppColors.danger),
            ),
          ],
        ]),
      ),
    );
  }
}
