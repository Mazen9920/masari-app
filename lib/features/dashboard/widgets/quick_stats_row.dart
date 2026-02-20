import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';

/// Horizontal scrolling row of stat cards: Revenue, Expenses, Net Profit.
class QuickStatsRow extends StatelessWidget {
  const QuickStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: const [
          _StatCard(
            label: 'Revenue',
            amount: 'EGP 124,500',
            change: '+8.2% vs last mo',
            changePositive: true,
            icon: Icons.trending_up_rounded,
            accentColor: AppColors.success,
          ),
          SizedBox(width: 12),
          _StatCard(
            label: 'Expenses',
            amount: 'EGP 42,200',
            change: '+12% vs last mo',
            changePositive: false,
            icon: Icons.trending_down_rounded,
            accentColor: AppColors.danger,
          ),
          SizedBox(width: 12),
          _StatCard(
            label: 'Net Profit',
            amount: 'EGP 82,300',
            change: 'Healthy margin',
            changePositive: true,
            icon: Icons.monetization_on_rounded,
            accentColor: AppColors.accentOrange,
          ),
          SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String amount;
  final String change;
  final bool changePositive;
  final IconData icon;
  final Color accentColor;

  const _StatCard({
    required this.label,
    required this.amount,
    required this.change,
    required this.changePositive,
    required this.icon,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top colored bar
          Container(
            width: double.infinity,
            height: 3,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Icon + label row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 16, color: accentColor),
              ),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Amount
          Text(
            amount,
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 2),
          // Change
          Text(
            change,
            style: AppTypography.captionSmall.copyWith(
              color: changePositive ? AppColors.success : AppColors.danger,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
