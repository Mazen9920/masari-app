import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';

/// Cash flow bar chart showing last 6 months.
/// Current month gets orange highlight + glow effect.
class CashFlowChart extends StatefulWidget {
  const CashFlowChart({super.key});

  @override
  State<CashFlowChart> createState() => _CashFlowChartState();
}

class _CashFlowChartState extends State<CashFlowChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _barAnimation;
  String _selectedPeriod = 'Last 6 Months';

  // Sample data — replace with real data from backend
  final List<_BarData> _data = [
    _BarData('May', 0.40),
    _BarData('Jun', 0.55),
    _BarData('Jul', 0.45),
    _BarData('Aug', 0.70),
    _BarData('Sep', 0.60),
    _BarData('Oct', 0.85, isCurrent: true),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _barAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Cash Flow',
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedPeriod,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Bar chart
          AnimatedBuilder(
            animation: _barAnimation,
            builder: (context, _) {
              return SizedBox(
                height: 140,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _data.map((bar) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _buildBar(bar),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBar(_BarData bar) {
    final animatedFill = bar.fillPercent * _barAnimation.value;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // The bar container
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: bar.isCurrent
                  ? AppColors.accentOrange.withOpacity(0.1)
                  : AppColors.backgroundLight,
              borderRadius: BorderRadius.circular(20),
              border: bar.isCurrent
                  ? Border.all(
                      color: AppColors.accentOrange.withOpacity(0.2),
                    )
                  : null,
            ),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: animatedFill,
                child: Container(
                  decoration: BoxDecoration(
                    color: bar.isCurrent
                        ? AppColors.accentOrange
                        : AppColors.accentOrange.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: bar.isCurrent
                        ? [
                            BoxShadow(
                              color: AppColors.accentOrange.withOpacity(0.35),
                              blurRadius: 12,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Month label
        Text(
          bar.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: bar.isCurrent ? FontWeight.w800 : FontWeight.w500,
            color: bar.isCurrent
                ? AppColors.textPrimary
                : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _BarData {
  final String label;
  final double fillPercent; // 0.0 to 1.0
  final bool isCurrent;

  const _BarData(this.label, this.fillPercent, {this.isCurrent = false});
}
