import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_service.dart';
import '../../data/pharmacy_repository.dart';
import '../../domain/models/schedule_type.dart';
import '../../domain/services/checkout_engine.dart';
import '../../domain/services/fefo_selector.dart';
import '../../domain/services/stock_summary.dart';
import '../theme.dart';

/// Turns any failure into a sentence a store employee can act on.
String friendlyError(Object error) {
  if (error is CheckoutException) return error.problems.join('\n');
  if (error is OperationException) return error.problems.join('\n');
  if (error is NotPermittedException) return error.message;
  if (error is AuthFailure) return error.message;
  if (error is InsufficientStockException) {
    return error.available == 0 ? 'Out of stock.' : 'Only ${error.available} in stock.';
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Your account isn\'t allowed to do that.';
      case 'unavailable':
        return 'Can\'t reach the server. Check the internet connection and try again.';
      case 'aborted':
      case 'failed-precondition':
        return 'Someone else changed this at the same moment. Please try again.';
      default:
        return error.message ?? 'Server error (${error.code}).';
    }
  }
  return error.toString().replaceFirst('Exception: ', '');
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : null,
      duration: Duration(seconds: error ? 6 : 3),
    ));
}

/// Standard loading / error handling around an [AsyncValue].
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorPanel(message: friendlyError(e)),
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
          const SizedBox(height: Space.m),
          Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: AppColors.muted),
          const SizedBox(height: Space.m),
          Text(title, textAlign: TextAlign.center, style: text.titleMedium),
          if (message != null) ...[
            const SizedBox(height: Space.xs),
            Text(message!, textAlign: TextAlign.center, style: text.bodyMedium?.copyWith(color: AppColors.muted)),
          ],
          if (action != null) ...[const SizedBox(height: Space.l), action!],
        ]),
      ),
    );
  }
}

/// Small rounded label, e.g. "Rx", "Low", "Expired".
class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.foreground, required this.background, this.tooltip});

  final String label;
  final Color foreground;
  final Color background;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600)),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

class ScheduleBadge extends StatelessWidget {
  const ScheduleBadge(this.schedule, {super.key});
  final ScheduleType schedule;

  @override
  Widget build(BuildContext context) {
    switch (schedule) {
      case ScheduleType.otc:
        return const SizedBox.shrink();
      case ScheduleType.scheduleH:
        return const Pill('Rx', foreground: AppColors.warning, background: AppColors.warningContainer,
            tooltip: 'Schedule H — sell only against a prescription');
      case ScheduleType.scheduleH1:
        return const Pill('H1', foreground: AppColors.danger, background: AppColors.dangerContainer,
            tooltip: 'Schedule H1 — prescription + register entry required');
      case ScheduleType.scheduleX:
        return const Pill('X', foreground: AppColors.danger, background: AppColors.dangerContainer,
            tooltip: 'Schedule X — prescription + register entry required');
      case ScheduleType.unknown:
        return const Pill('Unclassified', foreground: AppColors.muted, background: AppColors.infoContainer,
            tooltip: 'Set the drug schedule before selling');
    }
  }
}

class StockFlags extends StatelessWidget {
  const StockFlags(this.stock, {super.key});
  final StockSummary stock;

  @override
  Widget build(BuildContext context) {
    final flags = <Widget>[
      if (stock.isOutOfStock)
        const Pill('Out of stock', foreground: AppColors.danger, background: AppColors.dangerContainer)
      else if (stock.isLowStock)
        const Pill('Low', foreground: AppColors.warning, background: AppColors.warningContainer),
      if (stock.hasExpiringSoon)
        const Pill('Expiring', foreground: AppColors.warning, background: AppColors.warningContainer,
            tooltip: 'A batch expires within 90 days'),
      if (stock.hasExpiredStock)
        const Pill('Expired stock', foreground: AppColors.danger, background: AppColors.dangerContainer,
            tooltip: 'Remove expired strips from the shelf'),
    ];
    if (flags.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: Space.xs, runSpacing: Space.xs, children: flags);
  }
}

/// Labelled amount row used in bill summaries.
class AmountRow extends StatelessWidget {
  const AmountRow(this.label, this.value, {super.key, this.emphasis = false});
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = emphasis ? text.titleMedium : text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: style?.copyWith(color: emphasis ? null : AppColors.muted))),
        const SizedBox(width: Space.s),
        Text(value, style: style, textAlign: TextAlign.right),
      ]),
    );
  }
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String confirmLabel = 'Confirm', bool danger = false}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Constrains dialog content so it never exceeds the screen on a phone and
/// never stretches absurdly wide on a desktop.
class DialogBody extends StatelessWidget {
  const DialogBody({super.key, required this.child, this.maxWidth = 460});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 280),
      child: SingleChildScrollView(child: child),
    );
  }
}
