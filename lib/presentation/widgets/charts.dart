import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/services/billing_calculator.dart';
import '../theme.dart';

/// Colours for chart slices and bars, distinct on white and for most
/// colour-blind eyes (with the legend always showing the amounts).
class ChartColors {
  static const cash = Color(0xFF1E8E5A);
  static const upi = Color(0xFF2F6FB3);
  static const card = Color(0xFF7B5CC4);
  static const udhaar = Color(0xFFD08A00);
  static const out = Color(0xFFC2453D);
  static const muted = Color(0xFFB8C2CB);
}

class ChartSlice {
  final String label;
  final int paise;
  final Color color;
  const ChartSlice(this.label, this.paise, this.color);
}

/// A ring chart with the total in the middle and a legend with amounts and
/// shares, so nothing has to be read off the picture.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.slices, required this.centerLabel, this.centerValue, this.centerColor, this.size = 150});
  final List<ChartSlice> slices;
  final String centerLabel;
  /// Shown in the middle instead of the total (e.g. "+₹1,200").
  final String? centerValue;
  final Color? centerColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final shown = slices.where((s) => s.paise > 0).toList();
    final total = shown.fold<int>(0, (s, x) => s + x.paise);
    final ring = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(shown, total),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(size * 0.2),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FittedBox(
                child: Text(centerValue ?? formatRupees(total),
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: centerColor)),
              ),
              Text(centerLabel, style: text.labelSmall?.copyWith(color: AppColors.muted), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
    final legend = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      for (final s in slices)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: Space.s),
            Text('${s.label}  ', style: text.bodyMedium),
            Text(formatRupees(s.paise), style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (total > 0 && s.paise > 0)
              Text('  ${(s.paise * 100 / total).toStringAsFixed(0)}%', style: text.bodySmall?.copyWith(color: AppColors.muted)),
          ]),
        ),
    ]);
    return Wrap(
      spacing: Space.l,
      runSpacing: Space.m,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.center,
      children: [ring, legend],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.total);
  final List<ChartSlice> slices;
  final int total;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.16;
    final rect = Offset.zero & size;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final arc = rect.deflate(stroke / 2);
    if (total <= 0) {
      canvas.drawArc(arc, 0, math.pi * 2, false, paint..color = ChartColors.muted.withValues(alpha: 0.4));
      return;
    }
    var start = -math.pi / 2;
    const gap = 0.025;
    for (final s in slices) {
      final sweep = math.pi * 2 * s.paise / total;
      final drawn = slices.length > 1 ? math.max(0.0, sweep - gap) : sweep;
      canvas.drawArc(arc, start + (sweep - drawn) / 2, drawn, false, paint..color = s.color);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.total != total || old.slices.length != slices.length;
}

class BarSeries {
  final String label;
  final Color color;
  final List<int> values; // paise, one per bar group
  const BarSeries(this.label, this.color, this.values);
}

/// Side-by-side bars per day (or month), e.g. sales against money paid out.
/// Tap a group to see its exact amounts.
class GroupedBarChart extends StatefulWidget {
  const GroupedBarChart({super.key, required this.labels, required this.series, this.height = 180});
  final List<String> labels;
  final List<BarSeries> series;
  final double height;

  @override
  State<GroupedBarChart> createState() => _GroupedBarChartState();
}

class _GroupedBarChartState extends State<GroupedBarChart> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final n = widget.labels.length;
    final maxV = [for (final s in widget.series) ...s.values].fold<int>(0, math.max);
    final sel = _selected;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: Space.l, children: [
        for (final s in widget.series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: Space.xs),
            Text(s.label, style: text.bodySmall),
          ]),
      ]),
      const SizedBox(height: Space.s),
      SizedBox(
        height: widget.height,
        child: LayoutBuilder(builder: (context, c) {
          final groupW = n == 0 ? 0.0 : c.maxWidth / n;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) {
              if (groupW <= 0) return;
              final i = (d.localPosition.dx / groupW).floor().clamp(0, n - 1);
              setState(() => _selected = _selected == i ? null : i);
            },
            child: CustomPaint(
              size: Size(c.maxWidth, widget.height),
              painter: _BarsPainter(widget.series, n, maxV, sel),
            ),
          );
        }),
      ),
      const SizedBox(height: Space.xs),
      Row(children: [
        for (var i = 0; i < n; i++)
          Expanded(
            child: Text(
              n <= 16 || i % ((n / 10).ceil()) == 0 ? widget.labels[i] : '',
              textAlign: TextAlign.center,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: text.labelSmall?.copyWith(color: i == sel ? AppColors.primary : AppColors.muted),
            ),
          ),
      ]),
      if (sel != null && sel < n) ...[
        const SizedBox(height: Space.s),
        Text(
          '${widget.labels[sel]}: ${[for (final s in widget.series) '${s.label} ${formatRupees(s.values[sel])}'].join(' · ')}',
          style: text.bodyMedium,
        ),
      ],
    ]);
  }
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.series, this.n, this.maxV, this.selected);
  final List<BarSeries> series;
  final int n;
  final int maxV;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;
    for (var k = 0; k <= 4; k++) {
      final y = size.height * k / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (n == 0 || maxV <= 0) return;
    final groupW = size.width / n;
    final inner = groupW * 0.78;
    final barW = inner / series.length;
    for (var i = 0; i < n; i++) {
      if (selected == i) {
        canvas.drawRect(Rect.fromLTWH(i * groupW, 0, groupW, size.height),
            Paint()..color = AppColors.primaryContainer.withValues(alpha: 0.6));
      }
      for (var j = 0; j < series.length; j++) {
        final v = series[j].values[i];
        if (v <= 0) continue;
        final h = size.height * v / maxV;
        final x = i * groupW + (groupW - inner) / 2 + j * barW;
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x + 0.5, size.height - h, math.max(1, barW - 1), h),
              topLeft: const Radius.circular(3), topRight: const Radius.circular(3)),
          Paint()..color = series[j].color,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => true;
}

/// One big figure with a label, for the top of a statement.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.paise, this.color, this.caption, this.signed = false, this.onTap});
  final String label;
  final int paise;
  final Color? color;
  final String? caption;
  final bool signed; // show + / − in green / red
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = signed ? (paise >= 0 ? AppColors.accent : AppColors.danger) : color ?? AppColors.primary;
    final value = signed ? '${paise >= 0 ? '+' : '−'}${formatRupees(paise.abs())}' : formatRupees(paise);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.m),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(label, style: text.labelMedium?.copyWith(color: AppColors.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: text.titleLarge?.copyWith(color: c, fontWeight: FontWeight.w700)),
            ),
            if (caption != null)
              Text(caption!, style: text.bodySmall?.copyWith(color: AppColors.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }
}

/// Lays tiles out 2 per row on a phone, 4 on a wide screen.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 3 : 2);
      final w = (c.maxWidth - Space.m * (cols - 1)) / cols;
      return Wrap(spacing: Space.m, runSpacing: Space.m, children: [
        for (final child in children) SizedBox(width: w, child: child),
      ]);
    });
  }
}
