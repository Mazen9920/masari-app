import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/pinned_actions_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../l10n/app_localizations.dart';

/// Pinned Actions screen — reorder and toggle visibility of hub quick actions.
class PinnedActionsScreen extends ConsumerStatefulWidget {
  const PinnedActionsScreen({super.key});

  @override
  ConsumerState<PinnedActionsScreen> createState() => _PinnedActionsScreenState();
}

class _PinnedActionsScreenState extends ConsumerState<PinnedActionsScreen> {
  static const _visibleCount = 4;

  PinnedActionsNotifier get _notifier => ref.read(pinnedActionsProvider.notifier);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(pinnedActionsProvider);
    final actions = s.actions;

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
                AppLocalizations.of(context)!.pinnedActionsInstructions(_visibleCount),
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
                itemCount: actions.length + 1, // +1 for divider
                onReorder: _onReorder,
                itemBuilder: (context, index) {
                  // Divider between visible and hidden
                  if (index == _visibleCount) {
                    return _buildDivider(key: const ValueKey('__divider__'));
                  }

                  final actualIndex =
                      index < _visibleCount ? index : index - 1;
                  if (actualIndex >= actions.length) {
                    return const SizedBox.shrink(key: ValueKey('__empty__'));
                  }
                  final action = actions[actualIndex];
                  final isHidden = actualIndex >= _visibleCount;

                  return _ActionTile(
                    key: ValueKey(action.id),
                    action: action,
                    isHidden: isHidden,
                    index: actualIndex,
                    visibleCount: _visibleCount,
                    onVisibilityTap: () {
                      HapticFeedback.lightImpact();
                      _notifier.toggleVisibility(actualIndex);
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
              AppLocalizations.of(context)!.cancelButton,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.primaryNavy,
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            AppLocalizations.of(context)!.pinnedActionsTitle,
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context)!.pinnedActionsSaved),
                  backgroundColor: AppColors.primaryNavy,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Text(
              AppLocalizations.of(context)!.saveButton,
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
              AppLocalizations.of(context)!.hiddenFromDashboard,
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
    // Account for divider
    final oldActual =
        oldIndex < _visibleCount ? oldIndex : oldIndex - 1;

    // Skip if trying to drag the divider
    if (oldIndex == _visibleCount) return;

    var newActual =
        newIndex < _visibleCount ? newIndex : newIndex - 1;

    final actions = ref.read(pinnedActionsProvider).actions;
    // Clamp
    if (newActual > actions.length) newActual = actions.length;
    if (oldActual >= actions.length) return;

    _notifier.reorder(oldActual, newActual);
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
//  ACTION TILE
// ═══════════════════════════════════════════════════════
class _ActionTile extends StatelessWidget {
  final PinnedAction action;
  final bool isHidden;
  final int index;
  final int visibleCount;
  final VoidCallback onVisibilityTap;

  const _ActionTile({
    super.key,
    required this.action,
    required this.isHidden,
    required this.index,
    required this.visibleCount,
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
                  action.localizedLabel(AppLocalizations.of(context)!),
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
                index: index < visibleCount
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
