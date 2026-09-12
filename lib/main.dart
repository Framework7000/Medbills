import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'domain/models/batch.dart';
import 'domain/models/medicine.dart';
import 'domain/models/sale_invoice.dart';
import 'domain/models/schedule_type.dart';
import 'domain/services/pdf_invoice_service.dart';
import 'domain/services/profit_loss_service.dart';
import 'domain/services/schedule_h1_compliance.dart';
import 'domain/services/whatsapp_bill_service.dart';
import 'firebase_options.dart';
import 'state/bill_history_provider.dart';
import 'state/cart_provider.dart';
import 'state/database_provider.dart';
import 'state/inventory_batches_provider.dart';
import 'state/medicine_providers.dart';
import 'state/purchase_history_provider.dart';
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // lib/firebase_options.dart carries real credentials for the
  // medbills-176df project — Firestore there is genuinely seeded (see
  // scripts/seed_mp_medicines.dart). Every screen in this app still reads
  // from local, in-memory providers (cart, inventory batches, bill
  // history) rather than Firestore directly, so running without a live
  // connection never blocks the UI.
  //
  // On web specifically, firebase_core lazily `import()`s the Firebase JS
  // SDK from https://www.gstatic.com the first time initializeApp() is
  // called. When that host is unreachable — a restrictive network, a
  // sandboxed preview, or (as verified against this exact deployment) a
  // CSP that only allow-lists a handful of CDNs for scripts — the
  // rejection surfaces as an uncaught top-level JS error that Dart's
  // try/catch here cannot see: it blanks the entire page instead of just
  // failing to connect. That's a property of the hosting network, not of
  // whether credentials are configured, so it can't be detected at
  // runtime before it's too late. Web init is therefore opt-in via
  // --dart-define=ENABLE_FIREBASE_WEB=true at build time, for deployments
  // (e.g. Firebase Hosting itself, or an unrestricted server) known to
  // reach gstatic.com. Desktop/mobile builds don't have this failure mode
  // and always attempt it.
  const enableFirebaseWeb = bool.fromEnvironment('ENABLE_FIREBASE_WEB');
  final options = DefaultFirebaseOptions.currentPlatform;

  var firebaseConnected = false;
  if (!kIsWeb || enableFirebaseWeb) {
    try {
      await Firebase.initializeApp(options: options);
      firebaseConnected = true;
    } catch (error) {
      debugPrint('Firebase unreachable — running on local data only. ($error)');
    }
  } else {
    debugPrint(
        'Firebase web init skipped by default (gstatic.com may be blocked by this host\'s '
        'network/CSP). Rebuild with --dart-define=ENABLE_FIREBASE_WEB=true once deployed '
        'somewhere that can reach it.');
  }

  runApp(ProviderScope(
    overrides: [
      databaseStatusProvider.overrideWith(
        (ref) => DatabaseStatusNotifier(initiallyConnected: firebaseConnected),
      ),
    ],
    child: const MedBillsApp(),
  ));
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
        fontFamily: 'WorkSans',
        textTheme: const TextTheme(
          headlineLarge: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
          headlineSmall: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600),
          titleLarge: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600),
        ),
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
    final dbStatus = ref.watch(databaseStatusProvider);

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
                    const SizedBox(height: 8),
                    Tooltip(
                      message: dbStatus.isConnected
                          ? 'Connected to Firebase'
                          : 'Running on local data only — Firebase not configured',
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: dbStatus.isConnected
                              ? Colors.green.shade50
                              : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              dbStatus.isConnected ? Icons.cloud_done : Icons.cloud_off,
                              size: 12,
                              color: dbStatus.isConnected ? Colors.green.shade800 : AppColors.muted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              dbStatus.isConnected ? 'Cloud' : 'Local',
                              style: TextStyle(
                                fontSize: 10,
                                color: dbStatus.isConnected ? Colors.green.shade800 : AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

    final inventory = ref.read(inventoryBatchesProvider.notifier);
    final shortfalls = <String>[];
    for (final item in cart) {
      if (!inventory.hasStock(item.medicineId, item.quantity)) {
        final available = inventory.totalStockFor(item.medicineId);
        shortfalls.add('${item.name}: need ${item.quantity}, only $available in stock');
      }
    }
    if (shortfalls.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Insufficient stock — ${shortfalls.join('; ')}')),
      );
      return;
    }

    // Rule 9: Schedule H1 sales are hard-blocked, not a dismissible
    // warning — capture patient + prescriber identity before the sale
    // can proceed, or abort entirely if the pharmacist cancels.
    final catalogue = ref.read(globalCatalogueRepositoryProvider);
    final scheduleTypes = cart.map((item) {
      final matches = catalogue.searchCatalogue('').where((m) => m.id == item.medicineId);
      return matches.isEmpty ? ScheduleType.unknown : matches.first.scheduleType;
    });

    PrescriberDetails? prescriberDetails;
    if (ScheduleH1Compliance.requiresPrescriberCapture(scheduleTypes)) {
      if (!mounted) return;
      prescriberDetails = await _capturePrescriberDetails();
      if (prescriberDetails == null) return; // pharmacist cancelled — sale not completed
    }

    for (final item in cart) {
      inventory.dispense(item.medicineId, item.quantity);
    }

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
      patientName: prescriberDetails?.patientName,
      patientPhone: prescriberDetails?.patientPhone,
      doctorName: prescriberDetails?.doctorName,
      doctorRegistrationNumber: prescriberDetails?.doctorRegistrationNumber,
    );

    ref.read(billHistoryProvider.notifier).addInvoice(invoice);
    ref.read(cartProvider.notifier).clearCart();

    if (!mounted) return;
    await PdfInvoiceService.showPdfPreviewModal(context, invoice);
  }

  /// Blocks (via a non-dismissible-until-valid form) until complete patient
  /// + prescriber details are entered, or returns null if cancelled.
  Future<PrescriberDetails?> _capturePrescriberDetails() {
    final formKey = GlobalKey<FormState>();
    final patientNameController = TextEditingController();
    final patientPhoneController = TextEditingController();
    final doctorNameController = TextEditingController();
    final doctorRegController = TextEditingController();

    return showDialog<PrescriberDetails>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Schedule H1 — Patient & Prescriber Details Required'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'This sale contains a Schedule H1 medicine. Indian law requires '
                    'recording the patient and prescribing doctor before dispensing.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: patientNameController,
                    decoration: const InputDecoration(labelText: 'Patient Name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: patientPhoneController,
                    decoration: const InputDecoration(labelText: 'Patient Mobile'),
                    keyboardType: TextInputType.phone,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: doctorNameController,
                    decoration: const InputDecoration(labelText: 'Doctor Name'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: doctorRegController,
                    decoration: const InputDecoration(labelText: 'Doctor Registration No.'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel Sale'),
            ),
            ElevatedButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.of(context).pop(PrescriberDetails(
                  patientName: patientNameController.text.trim(),
                  patientPhone: patientPhoneController.text.trim(),
                  doctorName: doctorNameController.text.trim(),
                  doctorRegistrationNumber: doctorRegController.text.trim(),
                ));
              },
              child: const Text('Confirm & Continue'),
            ),
          ],
        );
      },
    );
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

    return SingleChildScrollView(
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
          const SizedBox(height: 16),
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
          Flexible(child: Text(label, style: style, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Rs. ${value.toStringAsFixed(2)}',
              style: style,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
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
    final dbStatus = ref.watch(databaseStatusProvider);

    // Cloud mode: read the live Firestore-backed medicine + batch streams
    // (medicinesStreamProvider / firestoreStockForMedicineProvider) once a
    // real project is connected. Local mode: the in-memory seed catalogue
    // and inventoryBatchesProvider ledger, which Purchases writes to and
    // Billing Counter checkouts deplete — so the app works fully offline
    // even when Firebase isn't reachable (see main()'s ENABLE_FIREBASE_WEB
    // gate for why that's the default on web).
    if (dbStatus.isConnected) {
      final medicinesAsync = ref.watch(medicinesStreamProvider);
      return Scaffold(
        appBar: AppBar(title: const Text('Inventory Master (Cloud)')),
        body: medicinesAsync.when(
          data: (medicines) {
            if (medicines.isEmpty) {
              return const Center(child: Text('No medicines in Firestore yet for this store.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: medicines.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (context, index) {
                final m = medicines[index];
                final stockAsync = ref.watch(firestoreStockForMedicineProvider(m.id));
                return _InventoryTile(
                  medicine: m,
                  stock: stockAsync.asData?.value,
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(child: Text('Failed to load from Firestore: $err')),
        ),
      );
    }

    final repo = ref.watch(globalCatalogueRepositoryProvider);
    final medicines = repo.searchCatalogue('');
    ref.watch(inventoryBatchesProvider);
    final inventory = ref.read(inventoryBatchesProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Master')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: medicines.length,
        separatorBuilder: (_, _) => const Divider(),
        itemBuilder: (context, index) {
          final m = medicines[index];
          return _InventoryTile(medicine: m, stock: inventory.totalStockFor(m.id));
        },
      ),
    );
  }
}

class _InventoryTile extends StatelessWidget {
  const _InventoryTile({required this.medicine, required this.stock});

  final Medicine medicine;
  final int? stock;

  @override
  Widget build(BuildContext context) {
    final lowStock = stock != null && stock! <= medicine.minStock;
    return ListTile(
      title: Row(
        children: [
          Expanded(child: Text(medicine.name)),
          if (medicine.scheduleType.requiresPrescription)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Rx', style: TextStyle(fontSize: 11, color: Colors.deepOrange)),
            ),
        ],
      ),
      subtitle: Text('${medicine.manufacturer} · ${medicine.type} · HSN ${medicine.hsnCode}'),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('GST ${medicine.gstRate.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          Text(
            stock == null ? '…' : '$stock in stock',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: stock == null
                  ? AppColors.muted
                  : stock == 0
                      ? Colors.red
                      : lowStock
                          ? Colors.orange.shade800
                          : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Purchases
// ---------------------------------------------------------------------------

class PurchasesView extends ConsumerStatefulWidget {
  const PurchasesView({super.key});

  @override
  ConsumerState<PurchasesView> createState() => _PurchasesViewState();
}

class _PurchasesViewState extends ConsumerState<PurchasesView> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedMedicineId;
  final _batchNumberController = TextEditingController();
  final _purchasePriceController = TextEditingController();
  final _mrpController = TextEditingController();
  final _quantityController = TextEditingController();
  DateTime? _expiryDate;

  @override
  void dispose() {
    _batchNumberController.dispose();
    _purchasePriceController.dispose();
    _mrpController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year + 1, now.month),
      firstDate: now,
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedMedicineId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select a medicine')));
      return;
    }
    if (_expiryDate == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick an expiry date')));
      return;
    }

    final repo = ref.read(globalCatalogueRepositoryProvider);
    final medicine = repo.searchCatalogue('').firstWhere((m) => m.id == _selectedMedicineId);
    final purchasePricePaise = (double.parse(_purchasePriceController.text) * 100).round();
    final mrpPaise = (double.parse(_mrpController.text) * 100).round();
    final quantity = int.parse(_quantityController.text);

    final batch = Batch(
      id: '${medicine.id}_${_batchNumberController.text}',
      medicineId: medicine.id,
      batchNumber: _batchNumberController.text,
      expiryDate: _expiryDate!,
      purchasePricePaise: purchasePricePaise,
      mrpPaise: mrpPaise,
      quantity: quantity,
      createdAt: DateTime.now(),
    );

    ref.read(inventoryBatchesProvider.notifier).receiveBatch(batch);
    ref.read(purchaseHistoryProvider.notifier).addPurchase(PurchaseRecord(
          medicineId: medicine.id,
          medicineName: medicine.name,
          batchNumber: batch.batchNumber,
          expiryDate: batch.expiryDate,
          purchasePricePaise: purchasePricePaise,
          mrpPaise: mrpPaise,
          quantity: quantity,
          receivedAt: DateTime.now(),
        ));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Received $quantity units of ${medicine.name} (Batch ${batch.batchNumber})')),
    );

    _formKey.currentState!.reset();
    _batchNumberController.clear();
    _purchasePriceController.clear();
    _mrpController.clear();
    _quantityController.clear();
    setState(() {
      _selectedMedicineId = null;
      _expiryDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(globalCatalogueRepositoryProvider);
    final medicines = repo.searchCatalogue('');
    final purchases = ref.watch(purchaseHistoryProvider);
    final desktop = isDesktopWidth(context);
    final dateFmt = DateFormat('MMM yyyy');

    final form = Form(
      key: _formKey,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Receive Stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _selectedMedicineId,
              decoration: const InputDecoration(labelText: 'Medicine'),
              isExpanded: true,
              items: [
                for (final m in medicines)
                  DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (value) => setState(() => _selectedMedicineId = value),
              validator: (value) => value == null ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _batchNumberController,
              decoration: const InputDecoration(labelText: 'Batch Number'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _pickExpiryDate,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Expiry Date'),
                child: Text(_expiryDate == null ? 'Select date' : dateFmt.format(_expiryDate!)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _purchasePriceController,
              decoration: const InputDecoration(labelText: 'Purchase Price (₹ per unit)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a valid amount' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _mrpController,
              decoration: const InputDecoration(labelText: 'MRP (₹ per unit, GST-inclusive)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => double.tryParse(v ?? '') == null ? 'Enter a valid amount' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _quantityController,
              decoration: const InputDecoration(labelText: 'Quantity (base units)'),
              keyboardType: TextInputType.number,
              validator: (v) => int.tryParse(v ?? '') == null ? 'Enter a valid quantity' : null,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Receive Stock'),
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );

    final history = ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: purchases.length + 1,
      separatorBuilder: (_, _) => const Divider(),
      itemBuilder: (context, index) {
        if (index == 0) {
          return const Text('Purchase History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16));
        }
        final p = purchases[index - 1];
        return ListTile(
          title: Text('${p.medicineName} · Batch ${p.batchNumber}'),
          subtitle: Text('Qty ${p.quantity} · Exp ${dateFmt.format(p.expiryDate)}'),
          trailing: Text('Rs. ${(p.totalCostPaise / 100).toStringAsFixed(2)}'),
        );
      },
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Purchases')),
      body: desktop
          ? Row(
              children: [
                Expanded(child: SingleChildScrollView(child: form)),
                const VerticalDivider(width: 1, color: AppColors.border),
                Expanded(child: history),
              ],
            )
          : ListView(
              children: [
                form,
                const Divider(),
                SizedBox(height: 400, child: history),
              ],
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
              separatorBuilder: (_, _) => const Divider(),
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
