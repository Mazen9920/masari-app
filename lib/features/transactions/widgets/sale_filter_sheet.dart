import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/models/sale_model.dart';

// ═════════════════════════════════════════════════════════
//  Sale Filter Model
// ═════════════════════════════════════════════════════════

class SaleFilter {
  final PaymentStatus? paymentStatus;
  final FulfillmentStatus? fulfillmentStatus;
  final RangeValues amountRange; // 0..infinity = no cap

  const SaleFilter({
    this.paymentStatus,
    this.fulfillmentStatus,
    this.amountRange = const RangeValues(0, double.infinity),
  });

  SaleFilter copyWith({
    PaymentStatus? Function()? paymentStatus,
    FulfillmentStatus? Function()? fulfillmentStatus,
    RangeValues? amountRange,
  }) {
    return SaleFilter(
      paymentStatus: paymentStatus != null ? paymentStatus() : this.paymentStatus,
      fulfillmentStatus: fulfillmentStatus != null ? fulfillmentStatus() : this.fulfillmentStatus,
      amountRange: amountRange ?? this.amountRange,
    );
  }

  int get activeCount {
    int count = 0;
    if (paymentStatus != null) count++;
    if (fulfillmentStatus != null) count++;
    if (amountRange != const RangeValues(0, double.infinity)) count++;
    return count;
  }

  bool get isDefault =>
      paymentStatus == null &&
      fulfillmentStatus == null &&
      amountRange == const RangeValues(0, double.infinity);

  static const SaleFilter empty = SaleFilter();
}

// ═════════════════════════════════════════════════════════
//  Sale Filter Bottom Sheet
// ═════════════════════════════════════════════════════════

class SaleFilterSheet extends StatefulWidget {
  final SaleFilter initialFilter;

  const SaleFilterSheet({super.key, required this.initialFilter});

  @override
  State<SaleFilterSheet> createState() => _SaleFilterSheetState();
}

class _SaleFilterSheetState extends State<SaleFilterSheet> {
  PaymentStatus? _paymentStatus;
  FulfillmentStatus? _fulfillmentStatus;
  late RangeValues _amountRange;

  @override
  void initState() {
    super.initState();
    _paymentStatus = widget.initialFilter.paymentStatus;
    _fulfillmentStatus = widget.initialFilter.fulfillmentStatus;
    final end = widget.initialFilter.amountRange.end;
    _amountRange = RangeValues(
      widget.initialFilter.amountRange.start,
      end.isInfinite || end > 10000 ? 10000 : end,
    );
  }

  void _reset() {
    HapticFeedback.lightImpact();
    setState(() {
      _paymentStatus = null;
      _fulfillmentStatus = null;
      _amountRange = const RangeValues(0, 10000);
    });
  }

  void _apply() {
    HapticFeedback.mediumImpact();
    final effectiveEnd =
        _amountRange.end >= 10000 ? double.infinity : _amountRange.end;
    Navigator.of(context).pop(
      SaleFilter(
        paymentStatus: _paymentStatus,
        fulfillmentStatus: _fulfillmentStatus,
        amountRange: RangeValues(_amountRange.start, effectiveEnd),
      ),
    );
  }

  int get _activeFilterCount {
    int count = 0;
    if (_paymentStatus != null) count++;
    if (_fulfillmentStatus != null) count++;
    if (_amountRange.start > 0 || _amountRange.end < 10000) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filter Sales',
                  style: AppTypography.h2.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                GestureDetector(
                  onTap: _reset,
                  child: Text(
                    'Reset',
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.accentOrange,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Container(height: 1, color: AppColors.borderLight.withOpacity(0.5)),

          // Scrollable content
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 20, 20, 100 + bottomPadding),
              children: [
                _buildPaymentStatusSelector(),
                const SizedBox(height: 28),
                _buildOrderStatusSelector(),
                const SizedBox(height: 28),
                _buildAmountRange(),
              ],
            ),
          ),

          // Sticky apply button
          Container(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomPadding),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: AppColors.borderLight.withOpacity(0.5)),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _apply,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Apply Filters',
                      style: AppTypography.labelLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    if (_activeFilterCount > 0) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '$_activeFilterCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  PAYMENT STATUS
  // ═══════════════════════════════════════════════════
  Widget _buildPaymentStatusSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Payment Status'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [null, ...PaymentStatus.values].map((status) {
            final isSelected = _paymentStatus == status;
            final label = switch (status) {
              null => 'All',
              PaymentStatus.unpaid => 'Unpaid',
              PaymentStatus.partial => 'Partial',
              PaymentStatus.paid => 'Paid',
              PaymentStatus.refunded => 'Refunded',
            };
            final color = switch (status) {
              null => AppColors.textPrimary,
              PaymentStatus.unpaid => const Color(0xFFEF4444),
              PaymentStatus.partial => const Color(0xFFF59E0B),
              PaymentStatus.paid => const Color(0xFF22C55E),
              PaymentStatus.refunded => const Color(0xFF8B5CF6),
            };
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _paymentStatus = status);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? color : AppColors.borderLight,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? color : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  FULFILLMENT STATUS
  // ═══════════════════════════════════════════════════
  Widget _buildOrderStatusSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Fulfillment Status'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [null, ...FulfillmentStatus.values].map((status) {
            final isSelected = _fulfillmentStatus == status;
            final label = switch (status) {
              null => 'All',
              FulfillmentStatus.unfulfilled => 'Unfulfilled',
              FulfillmentStatus.partial => 'Partial',
              FulfillmentStatus.fulfilled => 'Fulfilled',
            };
            return GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _fulfillmentStatus = status);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryNavy.withOpacity(0.08)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected ? AppColors.primaryNavy : AppColors.borderLight,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? AppColors.primaryNavy
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════
  //  AMOUNT RANGE SLIDER
  // ═══════════════════════════════════════════════════
  Widget _buildAmountRange() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel('Amount Range'),
            Text(
              '\$${_amountRange.start.toInt()} - \$${_amountRange.end.toInt() >= 10000 ? '10k+' : _amountRange.end.toInt().toString()}',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.accentOrange,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.accentOrange,
            inactiveTrackColor: AppColors.borderLight,
            thumbColor: Colors.white,
            overlayColor: AppColors.accentOrange.withOpacity(0.1),
            trackHeight: 4,
            rangeThumbShape: _CustomRangeThumbShape(),
          ),
          child: RangeSlider(
            values: _amountRange,
            min: 0,
            max: 10000,
            divisions: 100,
            onChanged: (values) {
              setState(() => _amountRange = values);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('\$0',
                  style: AppTypography.captionSmall
                      .copyWith(color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
              Text('\$10k+',
                  style: AppTypography.captionSmall
                      .copyWith(color: AppColors.textTertiary, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: AppTypography.captionSmall.copyWith(
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.0,
        fontSize: 11,
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
//  Custom range slider thumb
// ═══════════════════════════════════════════════════
class _CustomRangeThumbShape extends RangeSliderThumbShape {
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(24, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool? isDiscrete,
    bool? isEnabled,
    bool? isOnTop,
    bool? isPressed,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(
      center + const Offset(0, 1),
      12,
      Paint()
        ..color = Colors.black.withOpacity(0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(center, 12, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      12,
      Paint()
        ..color = AppColors.accentOrange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }
}
