import 'package:flutter/material.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/app_user.dart';
import '../domain/models/bill_scan.dart';
import '../platform/device_features.dart';
import '../state/providers.dart';
import 'accounts/purchase_payment_screen.dart';
import 'billing/billing_screen.dart';
import 'customers/customers_screen.dart';
import 'inventory/inventory_screen.dart';
import 'purchases/bill_scan_screen.dart' show BillReviewScreen;
import 'purchases/purchases_screen.dart';
import 'reports/reports_screen.dart';
import 'scan/scan_billing.dart' show PhoneStartup;
import 'scan/scan_screen.dart';
import 'sales/bill_history_screen.dart';
import 'settings/settings_screen.dart';
import 'theme.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.builder);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}

List<_Destination> _destinationsFor(UserRole role, {required bool udhaarEnabled}) => [
      _Destination('Billing', PhosphorIconsRegular.cashRegister, PhosphorIconsRegular.cashRegister, () => const BillingScreen()),
      _Destination('Scan', PhosphorIconsRegular.scanSmiley, PhosphorIconsRegular.scanSmiley, () => const ScanScreen()),
      _Destination('Stock', PhosphorIconsRegular.package, PhosphorIconsRegular.package, () => const InventoryScreen()),
      _Destination('Bills', PhosphorIconsRegular.receipt, PhosphorIconsRegular.receipt, () => const BillHistoryScreen()),
      // Off by default — the owner turns this on in Settings.
      if (udhaarEnabled)
        _Destination('Udhaar', PhosphorIconsRegular.wallet, PhosphorIconsRegular.wallet,
            () => const CustomersScreen()),
      if (role.canManageStock)
        _Destination('Purchases', PhosphorIconsRegular.truck, PhosphorIconsRegular.truck, () => const PurchasesScreen()),
      if (role.canManageStock)
        _Destination(paymentsLabel, PhosphorIconsRegular.handCoins, PhosphorIconsRegular.handCoins,
            () => const PurchasePaymentScreen()),
      if (role.canViewReports)
        _Destination('Reports', PhosphorIconsRegular.trendUp, PhosphorIconsRegular.trendUp, () => const ReportsScreen()),
      _Destination('Settings', PhosphorIconsRegular.gear, PhosphorIconsRegular.gear, () => const SettingsScreen()),
    ];

const paymentsLabel = 'Purchase & Payment';

/// Bottom-bar slots on a phone; the rest live behind "More".
const _phonePrimaryCount = 4;

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  // A phone is the shop's scanner: it opens on Scan. Computers open on Billing.
  int _index = DeviceFeatures.isPhone && PhoneStartup.scannerFirst ? 1 : 0;

  /// Supplier bills already known when this computer opened, plus those
  /// announced since — so each new one from a phone is announced once.
  Set<String>? _seenBillScans;

  void _announceNewBills(List<BillScan>? scans) {
    if (scans == null) return;
    final seen = _seenBillScans;
    if (seen == null) {
      _seenBillScans = {for (final s in scans) s.id};
      return;
    }
    final now = DateTime.now();
    for (final s in scans) {
      if (!seen.add(s.id) || s.status != BillScanStatus.draft || now.difference(s.createdAt).inMinutes.abs() > 10) {
        continue;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        duration: const Duration(seconds: 10),
        content: Text('New supplier bill${s.createdByName.isEmpty ? '' : ' from ${s.createdByName}'}'
            '${s.draft.invoiceNumber.isEmpty ? '' : ' · ${s.draft.invoiceNumber}'}'),
        action: SnackBarAction(
          label: 'Review',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => BillReviewScreen(scanId: s.id))),
        ),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final udhaarEnabled = ref.watch(storeProvider).valueOrNull?.udhaarEnabled ?? false;
    final destinations = _destinationsFor(user.role, udhaarEnabled: udhaarEnabled);
    // The counter computer hears about a supplier bill photographed on a
    // phone the moment it is saved, with a button to review it.
    if (!DeviceFeatures.isPhone && user.role.canManageStock) {
      ref.listen<AsyncValue<List<BillScan>>>(billScansProvider, (_, next) => _announceNewBills(next.valueOrNull));
      // Bills that were already there when this computer opened are known,
      // not new.
      if (_seenBillScans == null) _announceNewBills(ref.read(billScansProvider).valueOrNull);
    }
    if (_index >= destinations.length) _index = 0;

    // Low/out-of-stock count, shown as a badge on Stock so it needs no
    // separate "check your notifications" step.
    final stock = ref.watch(stockIndexProvider).valueOrNull;
    final stockAlerts = stock == null ? 0 : stock.values.where((s) => s.isLowStock || s.isOutOfStock).length;
    // Supplier bills due within 3 days or late, on Purchase & Payment.
    final toPay = user.role.canManageStock
        ? ref.watch(supplierLedgerProvider).valueOrNull?.remindersAt(DateTime.now()).length ?? 0
        : 0;
    Widget icon(_Destination d, IconData icon) {
      final count = d.label == 'Stock' ? stockAlerts : (d.label == paymentsLabel ? toPay : 0);
      return count > 0
          ? Badge(
              label: Text('$count'),
              backgroundColor: d.label == paymentsLabel ? AppColors.warning : null,
              child: Icon(icon),
            )
          : Icon(icon);
    }

    if (context.usesRail) {
      return Scaffold(
        body: SafeArea(
          child: Row(children: [
            // A short window (resized small, or a laptop split-view) must
            // never overflow the rail — scroll it instead of clipping.
            SingleChildScrollView(
              child: SizedBox(
                // Header plus about 80 px per destination (icon, two-line
                // label room, spacing), or the full window if taller.
                height: [MediaQuery.sizeOf(context).height, 160.0 + destinations.length * 80].reduce((a, b) => a > b ? a : b),
                child: Builder(
                  builder: (context) => NavigationRail(
                    selectedIndex: _index,
                    labelType: NavigationRailLabelType.all,
                    leading: _RailHeader(user: user),
                    onDestinationSelected: (i) => setState(() => _index = i),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: icon(d, d.icon),
                          selectedIcon: icon(d, d.selectedIcon),
                          label: Text(d.label == paymentsLabel ? 'Payments' : d.label),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [for (final d in destinations) d.builder()],
              ),
            ),
          ]),
        ),
      );
    }

    final primary = destinations.take(_phonePrimaryCount).toList();
    final more = destinations.skip(_phonePrimaryCount).toList();
    final selected = _index < primary.length ? _index : primary.length;
    return Scaffold(
      body: IndexedStack(
        index: selected,
        children: [
          for (final d in primary) d.builder(),
          _MorePage(destinations: more),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          for (final d in primary)
            NavigationDestination(icon: icon(d, d.icon), selectedIcon: icon(d, d.selectedIcon), label: d.label),
          const NavigationDestination(icon: Icon(PhosphorIconsRegular.list), selectedIcon: Icon(PhosphorIconsRegular.listDashes), label: 'More'),
        ],
      ),
    );
  }
}

class _RailHeader extends ConsumerWidget {
  const _RailHeader({required this.user});
  final AppUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cloud = ref.watch(cloudModeProvider);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.m),
      child: SizedBox(
        width: 88,
        child: Column(children: [
          const Icon(PhosphorIconsRegular.firstAidKit, color: AppColors.primary, size: 32),
          const SizedBox(height: Space.xs),
          Text(user.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: text.labelSmall),
          Text(user.role.label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: AppColors.muted)),
          const SizedBox(height: Space.xs),
          Tooltip(
            message: cloud ? 'Synced with every device of this store' : 'Demo data on this device only',
            child: Icon(cloud ? PhosphorIconsRegular.cloudCheck : PhosphorIconsRegular.cloudSlash,
                size: 16, color: cloud ? AppColors.accent : AppColors.muted),
          ),
        ]),
      ),
    );
  }
}

class _MorePage extends StatelessWidget {
  const _MorePage({required this.destinations});
  final List<_Destination> destinations;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          for (final d in destinations)
            ListTile(
              leading: Icon(d.icon),
              title: Text(d.label),
              trailing: const Icon(PhosphorIconsRegular.caretRight),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => d.builder())),
            ),
        ],
      ),
    );
  }
}
