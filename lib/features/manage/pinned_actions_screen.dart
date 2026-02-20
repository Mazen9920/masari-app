import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';

/// Pinned Actions screen — reorder and toggle visibility of hub quick actions.
class PinnedActionsScreen extends StatefulWidget {
  const PinnedActionsScreen({super.key});

  @override
  State<PinnedActionsScreen> createState() => _PinnedActionsScreenState();
}

class _PinnedActionsScreenState extends State<PinnedActionsScreen> {
  // Visible threshold — first 4 are shown on the dashboard
  static const _visibleCount = 4;

  late List<_ActionItem> _actions;

  @override
  void initState() {
    super.initState();
    _actions = [
      _ActionItem(
        icon: Icons.add_circle_rounded,
        label: 'Add Product',
        iconBg: const Color(0xFFFFF7ED),
        iconColor: const Color(0xFFE67E22),
      ),
      _ActionItem(
        icon: Icons.person_add_rounded,
        label: 'New Supplier',
        iconBg: const Color(0xFFEFF6FF),
        iconColor: AppColors.primaryNavy,
      ),
      _ActionItem(
        icon: Icons.receipt_long_rounded,
        label: 'Record Purchase',
        iconBg: const Color(0xFFEFF6FF),
        iconColor: AppColors.primaryNavy,
      ),
      _ActionItem(
        icon: Icons.category_rounded,
        label: 'Create Category',
        iconBg: const Color(0xFFFFF7ED),
        iconColor: const Color(0xFFE67E22),
      ),
      // Below threshold — hidden by default
      _ActionItem(
        icon: Icons.payments_rounded,
        label: 'Record Payment',
        iconBg: const Color(0xFFEFF6FF),
        iconColor: AppColors.primaryNavy,
      ),
      _ActionItem(
        icon: Icons.inventory_2_rounded,
        label: 'Adjust Stock',
        iconBg: const Color(0xFFEFF6FF),
        iconColor: AppColors.primaryNavy,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final visible = _actions.take(_visibleCount).toList();
    final hidden = _actions.skip(_visibleCount).toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Header ──
            _buildHeader(),

            // ── Instructions ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'Drag and drop to reorder the actions that appear on your Manage Hub. The first $_visibleCount will be visible by default.',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            ).animate().fadeIn(duration: 200.ms),

            // ── Reorderable list ──
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                proxyDecorator: _proxyDecorator,
                itemCount: _actions.length + 1, // +1 for divider
                onReorder: _onReorder,
                itemBuilder: (context, index) {
                  // Divider between visible and hidden
                  if (index == _visibleCount) {
                    return _buildDivider(key: const ValueKey('__divider__'));
                  }

                  final actualIndex =
                      index < _visibleCount ? index : index - 1;
                  final action = _actions[actualIndex];
                  final isHidden = actualIndex >= _visibleCount;

                  return _ActionTile(
                    key: ValueKey(action.label),
                    action: action,
                    isHidden: isHidden,
                    index: actualIndex,
                    onVisibilityTap: () {
                      HapticFeedback.lightImpact();
                      // Move item between visible/hidden zones
                      setState(() {
                        final item = _actions.removeAt(actualIndex);
                        if (isHidden) {
                          // Move to end of visible
                          _actions.insert(
                              _visibleCount - 1 < 0 ? 0 : _visibleCount - 1,
                              item);
                        } else {
                          // Move to start of hidden
                          _actions.insert(
                              _visibleCount < _actions.length
                                  ? _visibleCount
                                  : _actions.length,
                              item);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════════
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.backgroundLight,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            'Pinned Actions',
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop();
              // In production, persist the order
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Pinned actions saved'),
                  backgroundColor: AppColors.primaryNavy,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Text(
              'Save',
              style: TextStyle(
                color: const Color(0xFFE67E22),
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  DIVIDER
  // ═══════════════════════════════════════════════════════
  Widget _buildDivider({required Key key}) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.textTertiary.withValues(alpha: 0.3),
                    width: 1,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'HIDDEN FROM DASHBOARD',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.textTertiary.withValues(alpha: 0.3),
                    width: 1,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  REORDER LOGIC
  // ═══════════════════════════════════════════════════════
  void _onReorder(int oldIndex, int newIndex) {
    HapticFeedback.lightImpact();
    setState(() {
      // Account for divider
      final oldActual =
          oldIndex < _visibleCount ? oldIndex : oldIndex - 1;

      // Skip if trying to drag the divider
      if (oldIndex == _visibleCount) return;

      var newActual =
          newIndex < _visibleCount ? newIndex : newIndex - 1;

      // Clamp
      if (newActual > _actions.length) newActual = _actions.length;
      if (oldActual >= _actions.length) return;

      final item = _actions.removeAt(oldActual);
      if (newActual > oldActual) newActual--;
      _actions.insert(newActual.clamp(0, _actions.length), item);
    });
  }

  // ═══════════════════════════════════════════════════════
  //  DRAG PROXY
  // ═══════════════════════════════════════════════════════
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final animValue = Curves.easeInOut.transform(animation.value);
        final elevation = 4.0 + 8.0 * animValue;
        final scale = 1.0 + 0.02 * animValue;
        return Transform.scale(
          scale: scale,
          child: Material(
            elevation: elevation,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════
//  DATA CLASS
// ═══════════════════════════════════════════════════════
class _ActionItem {
  final IconData icon;
  final String label;
  final Color iconBg;
  final Color iconColor;

  const _ActionItem({
    required this.icon,
    required this.label,
    required this.iconBg,
    required this.iconColor,
  });
}

// ═══════════════════════════════════════════════════════
//  ACTION TILE
// ═══════════════════════════════════════════════════════
class _ActionTile extends StatelessWidget {
  final _ActionItem action;
  final bool isHidden;
  final int index;
  final VoidCallback onVisibilityTap;

  const _ActionTile({
    super.key,
    required this.action,
    required this.isHidden,
    required this.index,
    required this.onVisibilityTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isHidden ? 0.6 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isHidden
                ? Colors.white.withValues(alpha: 0.6)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.borderLight.withValues(alpha: 0.5),
            ),
            boxShadow: isHidden
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isHidden
                      ? action.iconBg.withValues(alpha: 0.4)
                      : action.iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  action.icon,
                  size: 22,
                  color: isHidden
                      ? action.iconColor.withValues(alpha: 0.5)
                      : action.iconColor,
                ),
              ),
              const SizedBox(width: 12),
              // Label
              Expanded(
                child: Text(
                  action.label,
                  style: AppTypography.labelLarge.copyWith(
                    color: isHidden
                        ? AppColors.textTertiary
                        : AppColors.textPrimary,
                    fontWeight: isHidden ? FontWeight.w500 : FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
              // Visibility toggle
              IconButton(
                onPressed: onVisibilityTap,
                icon: Icon(
                  isHidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 20,
                ),
                color: isHidden
                    ? AppColors.textTertiary.withValues(alpha: 0.5)
                    : AppColors.primaryNavy.withValues(alpha: 0.5),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              // Drag handle
              ReorderableDragStartListener(
                index: index < _PinnedActionsScreenState._visibleCount
                    ? index
                    : index + 1, // account for divider
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Transform.rotate(
                    angle: 1.5708, // 90° — vertical drag handle
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 22,
                      color: AppColors.borderLight,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
