import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'domain/models/sale_invoice.dart';
import 'domain/services/pdf_invoice_service.dart';
import 'domain/services/profit_loss_service.dart';
import 'domain/services/whatsapp_bill_service.dart';
import 'state/bill_history_provider.dart';
import 'state/cart_provider.dart';
import 'state/database_provider.dart';
import 'state/search_preferences_provider.dart';
import 'state/user_role_provider.dart';

// ---------------------------------------------------------------------------
// Design tokens (blueprint section 13)
// ---------------------------------------------------------------------------

class AppColors {
  static const primary = Color(0xFF14493D);
  static const accent = Color(0xFF22C55E);
  static const surface = Color(0xFFFFFFFF);
  static const scaffold = Color(0xFFF8FAFC);
  static const border = Color(0xFFE2E8F0);
  static const muted = Color(0xFF64748B);
}

bool isDesktopWidth(BuildContext context) => MediaQuery.of(context).size.width >= 800;

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

void main() {
  runApp(const ProviderScope(child: MedBillsApp()));
}

class MedBillsApp extends ConsumerWidget {
  const MedBillsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'MedBills — Nuskha PMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.scaffold,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
        ),
        textTheme: GoogleFonts.workSansTextTheme(),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.surface,
          foregroundColor: Colors.black87,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      home: const MainShellView(),
    );
  }
}

// ---------------------------------------------------------------------------
// Main shell navigation
// ---------------------------------------------------------------------------

enum AppPage { billing, inventory, purchases, reports, billHistory }

class MainShellView extends ConsumerStatefulWidget {
  const MainShellView({super.key});

  @override
  ConsumerState<MainShellView> createState() => _MainShellViewState();
}

class _MainShellViewState extends ConsumerState<MainShellView> {
  AppPage _current = AppPage.billing;

  static const _destinations = [
    (icon: Icons.point_of_sale, label: 'Billing', page: AppPage.billing),
    (icon: Icons.inventory_2_outlined, label: 'Inventory', page: AppPage.inventory),
    (icon: Icons.shopping_cart_outlined, label: 'Purchases', page: AppPage.purchases),
    (icon: Icons.bar_chart, label: 'Reports', page: AppPage.reports),
    (icon: Icons.receipt_long_outlined, label: 'Bill History', page: AppPage.billHistory),
  ];

  Widget _buildPage(AppPage page) {
    switch (page) {
      case AppPage.billing:
        return const BillingCounterView();
      case AppPage.inventory:
        return const InventoryMasterView();
      case AppPage.purchases:
        return const PurchasesView();
      case AppPage.reports:
        return const ReportsView();
      case AppPage.billHistory:
        return const BillHistoryView();
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = isDesktopWidth(context);
    final user = ref.watch(userAuthProvider);

    final body = _buildPage(_current);

    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              backgroundColor: AppColors.surface,
              selectedIndex: AppPage.values.indexOf(_current),
              labelType: NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    const Icon(Icons.local_pharmacy, color: AppColors.primary, size: 32),
                    const SizedBox(height: 4),
                    Text(user.name, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
                  ],
                ),
              ),
              onDestinationSelected: (i) => setState(() => _current = AppPage.values[i]),
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, color: AppColors.border),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: AppPage.values.indexOf(_current),
        onDestinationSelected: (i) => setState(() => _current = AppPage.values[i]),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.icon), label: d.label),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Billing Counter — the core POS screen
// ---------------------------------------------------------------------------

class BillingCounterView extends ConsumerStatefulWidget {
  const BillingCounterView({super.key});

  @override
  ConsumerState<BillingCounterView> createState() => _BillingCounterViewState();
}

class _BillingCounterViewState extends ConsumerState<BillingCounterView> {
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.f1:
        _showGuide();
        break;
      case LogicalKeyboardKey.f2:
        _openMedicineSearchDialog();
        break;
      case LogicalKeyboardKey.f3:
        _openBarcodeScanDialog();
        break;
      case LogicalKeyboardKey.f9:
        _completeAndPrint();
        break;
      default:
        break;
    }
  }

  void _showGuide() {
    showDialog(
      context: context,
      builder: (context) => const AlertDialog(
        title: Text('Keyboard Shortcuts'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('F1 — This guide'),
            Text('F2 — Search medicine'),
            Text('F3 — Scan barcode'),
            Text('F9 — Complete and print'),
          ],
        ),
      ),
    );
  }

  void _openMedicineSearchDialog() {
    final repo = ref.read(globalCatalogueRepositoryProvider);
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final results = repo.searchCartItems(controller.text);
            return AlertDialog(
              title: const Text('Search Medicine (F2)'),
              content: SizedBox(
                width: 420,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Type medicine name...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final r = results[index];
                          return ListTile(
                            title: Text(r.name),
                            subtitle: Text('Batch ${r.batchNumber} · MRP Rs. ${(r.mrpPaise / 100).toStringAsFixed(2)}'),
                            onTap: () {
                              ref.read(cartProvider.notifier).addItem(CartItem(
                                    medicineId: r.medicineId,
                                    name: r.name,
                                    batchNumber: r.batchNumber,
                                    expiry: r.expiry,
                                    quantity: 1,
                                    mrpPaise: r.mrpPaise,
                                    gstRate: r.gstRate,
                                  ));
                              ref.read(searchPreferencesProvider.notifier).addRecentSearch(controller.text);
                              Navigator.of(context).pop();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
              ],
            );
          },
        );
      },
    );
  }

  void _openBarcodeScanDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Scan Barcode (F3)'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Scan or type barcode...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Lookup'),
          ),
        ],
      ),
    );
  }

  Future<void> _completeAndPrint() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    final grand = ref.read(cartGrandTotalProvider);
    final gst = ref.read(cartGstTotalProvider);
    final customerName = ref.read(customerNameProvider);
    final customerPhone = ref.read(customerPhoneProvider);
    final paymentMode = ref.read(selectedPaymentModeProvider);

    final invoice = SaleInvoice(
      invoiceNumber: 'INV-2026-${1000 + ref.read(billHistoryProvider).length + 51}',
      storeId: 'store_primary',
      timestamp: DateTime.now(),
      customerName: customerName,
      customerPhone: customerPhone,
      paymentMode: paymentMode,
      grandTotalPaise: (grand * 100).round(),
      gstTotalPaise: (gst * 100).round(),
      items: [
        for (final item in cart)
          InvoiceItemRecord(
            medicineId: item.medicineId,
            name: item.name,
            batchNumber: item.batchNumber,
            expiry: item.expiry,
            quantity: item.quantity,
            mrpPaise: item.mrpPaise,
            gstRate: item.gstRate,
          ),
      ],
    );

    ref.read(billHistoryProvider.notifier).addInvoice(invoice);
    ref.read(cartProvider.notifier).clearCart();

    if (!mounted) return;
    await PdfInvoiceService.showPdfPreviewModal(context, invoice);
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final desktop = isDesktopWidth(context);

    final cartPanel = _CartPanel(
      onSearch: _openMedicineSearchDialog,
      onScan: _openBarcodeScanDialog,
    );
    final summaryPanel = _CheckoutSummaryPanel(onCompleteAndPrint: _completeAndPrint);

    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Billing Counter'),
          actions: [
            IconButton(icon: const Icon(Icons.help_outline), tooltip: 'F1', onPressed: _showGuide),
            IconButton(icon: const Icon(Icons.search), tooltip: 'F2', onPressed: _openMedicineSearchDialog),
            IconButton(icon: const Icon(Icons.qr_code_scanner), tooltip: 'F3', onPressed: _openBarcodeScanDialog),
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'F9',
              onPressed: cart.isEmpty ? null : _completeAndPrint,
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: desktop
            ? Row(
                children: [
                  Expanded(flex: 2, child: cartPanel),
                  const VerticalDivider(width: 1, color: AppColors.border),
                  Expanded(child: summaryPanel),
                ],
              )
            : ListView(
                children: [
                  SizedBox(height: 400, child: cartPanel),
                  summaryPanel,
                ],
              ),
      ),
    );
  }
}

class _CartPanel extends ConsumerWidget {
  const _CartPanel({required this.onSearch, required this.onScan});

  final VoidCallback onSearch;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    if (cart.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_cart_outlined, size: 48, color: AppColors.muted),
            const SizedBox(height: 12),
            const Text('Cart is empty — press F2 to search a medicine'),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: onSearch, child: const Text('+ Add Medicine')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Medicine')),
          DataColumn(label: Text('Batch')),
          DataColumn(label: Text('MRP')),
          DataColumn(label: Text('Qty')),
          DataColumn(label: Text('GST')),
          DataColumn(label: Text('Total')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (var i = 0; i < cart.length; i++)
            DataRow(cells: [
              DataCell(Text(cart[i].name)),
              DataCell(Text(cart[i].batchNumber)),
              DataCell(Text('Rs. ${(cart[i].mrpPaise / 100).toStringAsFixed(2)}')),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(i, cart[i].quantity - 1),
                  ),
                  Text('${cart[i].quantity}'),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    onPressed: () => ref
                        .read(cartProvider.notifier)
                        .updateQuantity(i, cart[i].quantity + 1),
                  ),
                ],
              )),
              DataCell(Text('${cart[i].gstRate.toStringAsFixed(0)}%')),
              DataCell(Text('Rs. ${cart[i].lineTotalRupees.toStringAsFixed(2)}')),
              DataCell(IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => ref.read(cartProvider.notifier).removeItem(i),
              )),
            ]),
        ],
      ),
    );
  }
}

class _CheckoutSummaryPanel extends ConsumerWidget {
  const _CheckoutSummaryPanel({required this.onCompleteAndPrint});

  final VoidCallback onCompleteAndPrint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subtotal = ref.watch(cartSubtotalProvider);
    final gst = ref.watch(cartGstTotalProvider);
    final grand = ref.watch(cartGrandTotalProvider);
    final cart = ref.watch(cartProvider);
    final paymentMode = ref.watch(selectedPaymentModeProvider);
    final customerName = ref.watch(customerNameProvider);
    final customerPhone = ref.watch(customerPhoneProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Customer', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: customerName,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (v) => ref.read(customerNameProvider.notifier).state = v,
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: customerPhone,
            decoration: const InputDecoration(labelText: 'Phone'),
            onChanged: (v) => ref.read(customerPhoneProvider.notifier).state = v,
          ),
          const SizedBox(height: 16),
          const Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.bold)),
          Wrap(
            spacing: 8,
            children: [
              for (final mode in ['Cash', 'UPI', 'Card', 'Credit'])
                ChoiceChip(
                  label: Text(mode),
                  selected: paymentMode == mode,
                  onSelected: (_) => ref.read(selectedPaymentModeProvider.notifier).state = mode,
                ),
            ],
          ),
          const Spacer(),
          const Divider(),
          _summaryRow('Subtotal', subtotal),
          _summaryRow('GST', gst),
          const Divider(),
          _summaryRow('Grand Total', grand, bold: true),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Complete and Print (F9)'),
            onPressed: cart.isEmpty ? null : onCompleteAndPrint,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Send WhatsApp E-Bill'),
            onPressed: cart.isEmpty
                ? null
                : () {
                    final invoice = SaleInvoice(
                      invoiceNumber: 'PREVIEW',
                      storeId: 'store_primary',
                      timestamp: DateTime.now(),
                      customerName: customerName,
                      customerPhone: customerPhone,
                      paymentMode: paymentMode,
                      grandTotalPaise: (grand * 100).round(),
                      gstTotalPaise: (gst * 100).round(),
                      items: [
                        for (final item in cart)
                          InvoiceItemRecord(
                            medicineId: item.medicineId,
                            name: item.name,
                            batchNumber: item.batchNumber,
                            expiry: item.expiry,
                            quantity: item.quantity,
                            mrpPaise: item.mrpPaise,
                            gstRate: item.gstRate,
                          ),
                      ],
                    );
                    WhatsAppBillService.sendEBillViaWhatsApp(invoice);
                  },
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, double value, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('Rs. ${value.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Inventory Master
// ---------------------------------------------------------------------------

class InventoryMasterView extends ConsumerWidget {
  const InventoryMasterView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Renders from the in-memory seed catalogue so Inventory works without a
    // live Firestore connection (e.g. in dev/demo builds); production reads
    // from medicinesStreamProvider once Firestore is seeded.
    final repo = ref.watch(globalCatalogueRepositoryProvider);
    final medicines = repo.searchCatalogue('');

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Master')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: medicines.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final m = medicines[index];
          return ListTile(
            title: Text(m.name),
            subtitle: Text('${m.manufacturer} · ${m.type} · HSN ${m.hsnCode}'),
            trailing: Text('GST ${m.gstRate.toStringAsFixed(0)}%'),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Purchases
// ---------------------------------------------------------------------------

class PurchasesView extends StatelessWidget {
  const PurchasesView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Purchases')),
      body: const Center(
        child: Text('Purchase order intake — coming soon'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reports
// ---------------------------------------------------------------------------

class ReportsView extends ConsumerWidget {
  const ReportsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(billHistoryProvider);
    final report = ProfitLossService.calculate(invoices: invoices, costLookup: const {});

    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _reportCard('Total Sales', 'Rs. ${(report.totalSalesPaise / 100).toStringAsFixed(2)}'),
            _reportCard('Gross Profit', 'Rs. ${(report.grossProfitPaise / 100).toStringAsFixed(2)}'),
            _reportCard('Margin', '${report.profitMarginPercentage.toStringAsFixed(1)}%'),
            _reportCard('Invoices', '${invoices.length}'),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bill History
// ---------------------------------------------------------------------------

class BillHistoryView extends ConsumerWidget {
  const BillHistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(billHistoryProvider);
    final dateFmt = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Bill History')),
      body: invoices.isEmpty
          ? const Center(child: Text('No invoices yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: invoices.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final invoice = invoices[index];
                return ListTile(
                  title: Text(invoice.invoiceNumber),
                  subtitle: Text('${invoice.customerName} · ${dateFmt.format(invoice.timestamp)}'),
                  trailing: Text('Rs. ${(invoice.grandTotalPaise / 100).toStringAsFixed(2)}'),
                  onTap: () => PdfInvoiceService.showPdfPreviewModal(context, invoice),
                );
              },
            ),
    );
  }
}
