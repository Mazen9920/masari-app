import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../l10n/app_localizations.dart';

/// Color used for a given margin percentage (shared across manufacturing UI).
Color marginColorFor(double marginPct, {bool belowCost = false}) {
  if (belowCost) return AppColors.danger;
  if (marginPct >= 40) return AppColors.success;
  if (marginPct >= 20) return AppColors.warning;
  return AppColors.accentOrange;
}

/// Horizontal stacked bar showing the materials vs finishing split of unit cost.
class CostCompositionBar extends StatelessWidget {
  final double materials;
  final double labor;
  final double height;
  final bool showLegend;
  const CostCompositionBar({
    super.key,
    required this.materials,
    required this.labor,
    this.height = 8,
    this.showLegend = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final total = materials + labor;
    final matFlex = total <= 0 ? 1 : (materials / total * 1000).round();
    final labFlex = total <= 0 ? 0 : (labor / total * 1000).round();

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: total <= 0
            ? Container(color: AppColors.borderLight.withValues(alpha: 0.4))
            : Row(
                children: [
                  Expanded(
                    flex: matFlex,
                    child: Container(color: AppColors.primaryNavy),
                  ),
                  if (labFlex > 0)
                    Expanded(
                      flex: labFlex,
                      child: Container(color: AppColors.accentOrange),
                    ),
                ],
              ),
      ),
    );

    if (!showLegend) return bar;

    final matPct = total <= 0 ? 0 : (materials / total * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar,
        const SizedBox(height: 8),
        Row(
          children: [
            _legendDot(AppColors.primaryNavy),
            const SizedBox(width: 4),
            Text('${l10n.mfgMaterialsLabel} $matPct%',
                style: AppTypography.captionSmall
                    .copyWith(color: AppColors.textSecondary)),
            const SizedBox(width: 14),
            _legendDot(AppColors.accentOrange),
            const SizedBox(width: 4),
            Text('${l10n.mfgFinishingWord} ${100 - matPct}%',
                style: AppTypography.captionSmall
                    .copyWith(color: AppColors.textSecondary)),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color c) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

/// Horizontal margin meter: a 0–100% track with a filled portion colored by
/// margin health, plus an inline label.
class MarginMeter extends StatelessWidget {
  final double marginPct;
  final bool belowCost;
  final bool hasSellingPrice;
  const MarginMeter({
    super.key,
    required this.marginPct,
    required this.belowCost,
    required this.hasSellingPrice,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!hasSellingPrice) {
      return Text(l10n.mfgNoMargin,
          style: AppTypography.captionSmall
              .copyWith(color: AppColors.textTertiary));
    }
    final color = marginColorFor(marginPct, belowCost: belowCost);
    final fill = (marginPct.clamp(0, 100)) / 100.0;
    final tag = belowCost
        ? l10n.mfgBelowCost
        : marginPct >= 40
            ? l10n.mfgHealthyMargin
            : l10n.mfgThinMargin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('${marginPct.toStringAsFixed(0)}%',
                style: AppTypography.labelMedium
                    .copyWith(color: color, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(tag,
                  style: AppTypography.captionSmall.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(
                height: 6,
                color: AppColors.borderLight.withValues(alpha: 0.5),
              ),
              FractionallySizedBox(
                widthFactor: belowCost ? 0.06 : fill.clamp(0.0, 1.0),
                child: Container(height: 6, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A rounded box with a dashed border — used for "add" affordances.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const DottedBorderBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
          color: color ?? AppColors.primaryNavy.withValues(alpha: 0.4),
          radius: 12),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  static const double _dash = 5;
  static const double _gap = 4;
  _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final next = dist + _dash;
        canvas.drawPath(
          metric.extractPath(dist, next.clamp(0, metric.length)),
          paint,
        );
        dist = next + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Selectable pill used for sort/filter rows.
class MfgChip extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const MfgChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryNavy : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected
                  ? AppColors.primaryNavy
                  : AppColors.borderLight.withValues(alpha: 0.7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 13,
                  color: selected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: AppTypography.captionSmall.copyWith(
                color: selected ? Colors.white : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
