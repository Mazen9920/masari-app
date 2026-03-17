import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../core/theme/app_colors.dart';

/// A shared toggle widget for switching between chart and table views.
class ChartToggle extends StatelessWidget {
  final bool showChart;
  final VoidCallback onToggle;
  final IconData firstIcon;
  final IconData secondIcon;

  const ChartToggle({
    super.key,
    required this.showChart,
    required this.onToggle,
    this.firstIcon = Icons.table_chart_rounded,
    this.secondIcon = Icons.show_chart_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildOption(firstIcon, !showChart),
          _buildOption(secondIcon, showChart),
        ],
      ),
    );
  }

  Widget _buildOption(IconData icon, bool isSelected) {
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          HapticFeedback.lightImpact();
          onToggle();
        }
      },
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                  ),
                ]
              : [],
        ),
        child: Icon(
          icon,
          size: 18,
          color: isSelected ? AppColors.textPrimary : AppColors.textTertiary,
        ),
      ),
    );
  }
}
