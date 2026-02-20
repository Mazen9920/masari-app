import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/product_model.dart';
import 'edit_product_screen.dart';

class ProductDetailScreen extends ConsumerStatefulWidget {
  final String productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  int _adjustQuantity = 0;
  String _adjustReason = 'Correction';
  bool _showAdjustment = false;

  static const _reasons = [
    'Correction',
    'Damage',
    'Loss',
    'Return',
    'Restock',
  ];

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(inventoryProvider);
    final product = products.firstWhere(
      (p) => p.id == widget.productId,
      orElse: () => products.first,
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ProductHeader(product: product),
                    const SizedBox(height: 16),
                    _StockOverviewCard(product: product),
                    const SizedBox(height: 14),
                    _buildActionButtons(),
                    const SizedBox(height: 14),
                    if (_showAdjustment)
                      _buildAdjustmentSection(product),
                    if (_showAdjustment) const SizedBox(height: 14),
                    _PricingCard(product: product),
                    const SizedBox(height: 14),
                    _MovementHistory(movements: product.movements),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: AppColors.primaryNavy,
          ),
          const Spacer(),
          Text(
            'Product Details',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EditProductScreen(productId: widget.productId),
                ),
              );
            },
            child: Text(
              'Edit',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              _showAddStockDialog();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accentOrange, width: 2),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_rounded,
                      size: 20, color: AppColors.accentOrange),
                  const SizedBox(width: 6),
                  Text(
                    'Add Stock',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.accentOrange,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              setState(() => _showAdjustment = !_showAdjustment);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.accentOrange,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accentOrange.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.tune_rounded,
                      size: 20, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    'Adjust Stock',
                    style: AppTypography.labelMedium.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(duration: 300.ms, delay: 150.ms);
  }

  // ═══════════════════════════════════════════════════
  //  QUICK ADJUSTMENT SECTION
  // ═══════════════════════════════════════════════════
  Widget _buildAdjustmentSection(Product product) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppColors.accentOrange.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accentOrange,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Quick Adjustment',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                'Manual Correction',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Stepper
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    children: [
                      _stepperButton(Icons.remove_rounded, () {
                        HapticFeedback.lightImpact();
                        setState(() => _adjustQuantity--);
                      }),
                      Expanded(
                        child: Center(
                          child: Text(
                            '$_adjustQuantity',
                            style: AppTypography.h3.copyWith(
                              color: _adjustQuantity < 0
                                  ? AppColors.danger
                                  : _adjustQuantity > 0
                                      ? AppColors.success
                                      : AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      _stepperButton(Icons.add_rounded, () {
                        HapticFeedback.lightImpact();
                        setState(() => _adjustQuantity++);
                      }),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Reason dropdown
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundLight,
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: AppColors.borderLight),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _adjustReason,
                      icon: const Icon(Icons.expand_more_rounded,
                          color: AppColors.textTertiary, size: 20),
                      isExpanded: true,
                      items: _reasons
                          .map((r) => DropdownMenuItem(
                                value: r,
                                child: Text(
                                  r,
                                  style: AppTypography.labelMedium
                                      .copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _adjustReason = v ?? 'Correction'),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _adjustQuantity != 0
                  ? () {
                      ref.read(inventoryProvider.notifier).adjustStock(
                            widget.productId,
                            _adjustQuantity,
                            _adjustReason,
                          );
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _adjustQuantity = 0;
                        _showAdjustment = false;
                      });
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.textTertiary.withValues(alpha: 0.3),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Save Adjustment',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: -0.05, end: 0, duration: 300.ms);
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: AppColors.textSecondary),
      ),
    );
  }

  void _showAddStockDialog() {
    int quantity = 0;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.success.withValues(alpha: 0.1),
                ),
                child: const Icon(Icons.add_rounded,
                    size: 20, color: AppColors.success),
              ),
              const SizedBox(width: 10),
              Text(
                'Add Stock',
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'How many units to restock?',
                style: AppTypography.bodySmall
                    .copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderLight),
                  color: AppColors.backgroundLight,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (quantity > 0) {
                          setDialogState(() => quantity--);
                          HapticFeedback.lightImpact();
                        }
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.remove_rounded,
                            size: 22, color: AppColors.textSecondary),
                      ),
                    ),
                    Text(
                      '$quantity',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: quantity > 0
                            ? AppColors.success
                            : AppColors.textPrimary,
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        setDialogState(() => quantity++);
                        HapticFeedback.lightImpact();
                      },
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.add_rounded,
                            size: 22, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.textTertiary),
              ),
            ),
            ElevatedButton(
              onPressed: quantity > 0
                  ? () {
                      ref.read(inventoryProvider.notifier).adjustStock(
                            widget.productId,
                            quantity,
                            'Restock',
                          );
                      HapticFeedback.mediumImpact();
                      Navigator.pop(ctx);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.textTertiary.withValues(alpha: 0.2),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
              ),
              child: Text(
                'Restock +$quantity',
                style: AppTypography.labelMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PRODUCT HEADER
// ═══════════════════════════════════════════════════════════
class _ProductHeader extends StatelessWidget {
  final Product product;

  const _ProductHeader({required this.product});

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (product.status) {
      StockStatus.inStock => 'In Stock',
      StockStatus.lowStock => 'Low Stock',
      StockStatus.outOfStock => 'Out of Stock',
    };
    final statusColor = switch (product.status) {
      StockStatus.inStock => AppColors.success,
      StockStatus.lowStock => AppColors.warning,
      StockStatus.outOfStock => AppColors.danger,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: product.color.withValues(alpha: 0.1),
            border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.5)),
          ),
          child: Icon(product.icon, size: 36, color: product.color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                product.name,
                style: AppTypography.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                'SKU: ${product.sku}',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(duration: 400.ms);
  }
}

// ═══════════════════════════════════════════════════════════
//  STOCK OVERVIEW CARD
// ═══════════════════════════════════════════════════════════
class _StockOverviewCard extends StatelessWidget {
  final Product product;

  const _StockOverviewCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative
          Positioned(
            top: -16,
            right: -16,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryNavy.withValues(alpha: 0.03),
              ),
            ),
          ),
          Column(
            children: [
              Text(
                'CURRENT INVENTORY',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  TweenAnimationBuilder<int>(
                    tween:
                        IntTween(begin: 0, end: product.currentStock),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, value, __) => Text(
                      '$value',
                      style: TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryNavy,
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Units',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.only(top: 14),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: AppColors.borderLight.withValues(alpha: 0.5)),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Total Value',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'EGP ${product.totalValue.toStringAsFixed(0)}',
                            style: AppTypography.labelMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 36,
                      color:
                          AppColors.borderLight.withValues(alpha: 0.5),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            'Reorder Point',
                            style: AppTypography.captionSmall.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${product.reorderPoint}',
                            style: AppTypography.labelMedium.copyWith(
                              color: product.currentStock <=
                                      product.reorderPoint
                                  ? AppColors.accentOrange
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 50.ms);
  }
}

// ═══════════════════════════════════════════════════════════
//  PRICING CARD (additional enhancement)
// ═══════════════════════════════════════════════════════════
class _PricingCard extends StatelessWidget {
  final Product product;

  const _PricingCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PRICING',
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _priceItem('Cost', 'EGP ${product.costPrice.toStringAsFixed(0)}'),
              _priceItem(
                  'Selling', 'EGP ${product.sellingPrice.toStringAsFixed(0)}'),
              _priceItem(
                'Margin',
                '${product.profitMargin.toStringAsFixed(1)}%',
                color: AppColors.success,
              ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms, delay: 200.ms);
  }

  Widget _priceItem(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: AppTypography.captionSmall.copyWith(
              color: AppColors.textTertiary,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTypography.labelMedium.copyWith(
              color: color ?? AppColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  MOVEMENT HISTORY
// ═══════════════════════════════════════════════════════════
class _MovementHistory extends StatelessWidget {
  final List<StockMovement> movements;

  const _MovementHistory({required this.movements});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'RECENT MOVEMENTS',
          style: AppTypography.captionSmall.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 12),
        if (movements.isEmpty)
          _buildEmpty()
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.borderLight.withValues(alpha: 0.5)),
            ),
            child: Column(
              children: [
                for (int i = 0; i < movements.length; i++) ...[
                  _MovementTile(movement: movements[i], index: i),
                  if (i < movements.length - 1)
                    Divider(
                      height: 1,
                      color: AppColors.borderLight.withValues(alpha: 0.5),
                      indent: 16,
                      endIndent: 16,
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(32),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.history_rounded,
              size: 32,
              color: AppColors.textTertiary.withValues(alpha: 0.4)),
          const SizedBox(height: 10),
          Text(
            'No movements yet',
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _MovementTile extends StatelessWidget {
  final StockMovement movement;
  final int index;

  const _MovementTile({required this.movement, required this.index});

  String get _formattedDate {
    final d = movement.dateTime;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hour = d.hour > 12 ? d.hour - 12 : d.hour;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year} • ${hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final isPositive = movement.quantity > 0;

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: movement.iconColor.withValues(alpha: 0.1),
            ),
            child: Icon(
              movement.icon,
              size: 20,
              color: movement.iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.note ?? movement.type,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formattedDate,
                  style: AppTypography.captionSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isPositive ? '+' : ''}${movement.quantity}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: isPositive ? AppColors.success : AppColors.textPrimary,
                ),
              ),
              Text(
                'Units',
                style: AppTypography.captionSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(
            duration: 250.ms,
            delay: Duration(milliseconds: 40 * index))
        .slideX(begin: 0.02, end: 0);
  }
}
