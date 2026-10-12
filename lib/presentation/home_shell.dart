import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/app_user.dart';
import '../state/providers.dart';
import 'billing/billing_screen.dart';
import 'inventory/inventory_screen.dart';
import 'purchases/purchases_screen.dart';
import 'reports/reports_screen.dart';
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

List<_Destination> _destinationsFor(UserRole role) => [
      _Destination('Billing', Icons.point_of_sale_outlined, Icons.point_of_sale, () => const BillingScreen()),
      _Destination('Scan', Icons.qr_code_scanner_outlined, Icons.qr_code_scanner, () => const ScanScreen()),
      _Destination('Stock', Icons.inventory_2_outlined, Icons.inventory_2, () => const InventoryScreen()),
      _Destination('Bills', Icons.receipt_long_outlined, Icons.receipt_long, () => const BillHistoryScreen()),
      if (role.canManageStock)
        _Destination('Purchases', Icons.local_shipping_outlined, Icons.local_shipping, () => const PurchasesScreen()),
      if (role.canViewReports)
        _Destination('Reports', Icons.insights_outlined, Icons.insights, () => const ReportsScreen()),
      _Destination('Settings', Icons.settings_outlined, Icons.settings, () => const SettingsScreen()),
    ];

/// Bottom-bar slots on a phone; the rest live behind "More".
const _phonePrimaryCount = 4;

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider)!;
    final destinations = _destinationsFor(user.role);
    if (_index >= destinations.length) _index = 0;

    // Low/out-of-stock count, shown as a badge on Stock so it needs no
    // separate "check your notifications" step.
    final stock = ref.watch(stockIndexProvider).valueOrNull;
    final stockAlerts = stock == null ? 0 : stock.values.where((s) => s.isLowStock || s.isOutOfStock).length;
    Widget icon(_Destination d, IconData icon) =>
        d.label == 'Stock' && stockAlerts > 0 ? Badge(label: Text('$stockAlerts'), child: Icon(icon)) : Icon(icon);

    if (context.usesRail) {
      return Scaffold(
        body: SafeArea(
          child: Row(children: [
            // A short window (resized small, or a laptop split-view) must
            // never overflow the rail — scroll it instead of clipping.
            SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height),
                child: IntrinsicHeight(
                  child: NavigationRail(
                    selectedIndex: _index,
                    labelType: NavigationRailLabelType.all,
                    leading: _RailHeader(user: user),
                    onDestinationSelected: (i) => setState(() => _index = i),
                    destinations: [
                      for (final d in destinations)
                        NavigationRailDestination(
                          icon: icon(d, d.icon),
                          selectedIcon: icon(d, d.selectedIcon),
                          label: Text(d.label),
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
          const NavigationDestination(icon: Icon(Icons.menu), selectedIcon: Icon(Icons.menu_open), label: 'More'),
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
          const Icon(Icons.local_pharmacy, color: AppColors.primary, size: 32),
          const SizedBox(height: Space.xs),
          Text(user.name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
              style: text.labelSmall),
          Text(user.role.label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: text.labelSmall?.copyWith(color: AppColors.muted)),
          const SizedBox(height: Space.xs),
          Tooltip(
            message: cloud ? 'Synced with every device of this store' : 'Demo data on this device only',
            child: Icon(cloud ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
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
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => d.builder())),
            ),
        ],
      ),
    );
  }
}
