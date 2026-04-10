import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/category_data.dart';
import '../../l10n/app_localizations.dart';
import 'add_category_sheet.dart';
import 'category_detail_screen.dart';

/// Manage Categories — reorder, swipe to archive/delete, AI suggestions.
class ManageCategoriesScreen extends ConsumerStatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  ConsumerState<ManageCategoriesScreen> createState() =>
      _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState
    extends ConsumerState<ManageCategoriesScreen> {
  bool _showAiSuggestion = true;
  final _expandedSections = <CategoryGroup>{
    CategoryGroup.operatingExpense,
    CategoryGroup.income,
  };

  static const _sectionOrder = [
    CategoryGroup.operatingExpense,
    CategoryGroup.income,
    CategoryGroup.autoSystem,
    CategoryGroup.financing,
  ];

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final categories = categoriesAsync.value ?? [];
    final transactions = ref.watch(transactionsProvider).value ?? [];

    // Count transactions per category
    final txCountMap = <String, int>{};
    for (final tx in transactions) {
      final cat = CategoryData.findById(tx.categoryId);
      txCountMap[cat.name] = (txCountMap[cat.name] ?? 0) + 1;
    }

    // Group categories by logical group
    final grouped = <CategoryGroup, List<CategoryData>>{};
    for (final cat in categories) {
      (grouped[cat.categoryGroup] ??= []).add(cat);
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Stack(
                children: [
                  _buildGroupedList(grouped, txCountMap),
                  // AI suggestion banner
                  if (_showAiSuggestion && categories.length >= 2)
                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: _AiSuggestionBanner(
                        categoryA: categories.isNotEmpty ? categories[0].localizedName(AppLocalizations.of(context)!) : '',
                        categoryB: categories.length > 3 ? categories[3].localizedName(AppLocalizations.of(context)!) : (categories.length > 1 ? categories[1].localizedName(AppLocalizations.of(context)!) : ''),
                        onDismiss: () =>
                            setState(() => _showAiSuggestion = false),
                      )
                          .animate()
                          .fadeIn(duration: 350.ms, delay: 400.ms)
                          .slideY(begin: 0.15),
                    ),
                ],
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
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderLight.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Expanded(
            child: Center(
              child: Text(
                AppLocalizations.of(context)!.budgetAndCategories,
                style: AppTypography.h2.copyWith(
                  color: AppColors.primaryNavy,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              showAddCategorySheet(context);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Text(
                AppLocalizations.of(context)!.addLabel,
                style: TextStyle(
                  color: const Color(0xFFE67E22),
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  GROUPED LIST
  // ═══════════════════════════════════════════════════════
  Widget _buildGroupedList(
      Map<CategoryGroup, List<CategoryData>> grouped,
      Map<String, int> txCountMap) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, _showAiSuggestion ? 140 : 40),
      children: [
        for (final group in _sectionOrder)
          if ((grouped[group] ?? []).isNotEmpty)
            _buildSection(group, grouped[group]!, txCountMap),
      ],
    );
  }

  Widget _buildSection(
      CategoryGroup group, List<CategoryData> cats, Map<String, int> txCountMap) {
    final l10n = AppLocalizations.of(context)!;
    final isExpanded = _expandedSections.contains(group);
    final isLocked =
        group == CategoryGroup.autoSystem || group == CategoryGroup.financing;

    final (title, icon, color) = switch (group) {
      CategoryGroup.operatingExpense => (
        l10n.operatingExpenses,
        Icons.receipt_long_rounded,
        const Color(0xFFE67E22),
      ),
      CategoryGroup.income => (
        l10n.incomeSources,
        Icons.trending_up_rounded,
        const Color(0xFF27AE60),
      ),
      CategoryGroup.autoSystem => (
        l10n.systemCategories,
        Icons.sync_rounded,
        const Color(0xFF6366F1),
      ),
      CategoryGroup.financing => (
        l10n.financingEquity,
        Icons.account_balance_rounded,
        const Color(0xFF3B82F6),
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              if (isExpanded) {
                _expandedSections.remove(group);
              } else {
                _expandedSections.add(group);
              }
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        l10n.nCategoriesCount(cats.length),
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLocked) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.borderLight.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_rounded,
                            size: 11, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Text(
                          l10n.autoManaged,
                          style: AppTypography.captionSmall.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.expand_more_rounded,
                    size: 22,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Section content
        AnimatedCrossFade(
          firstChild: isLocked
              ? _buildLockedSection(cats, txCountMap)
              : _buildReorderableSection(group, cats, txCountMap),
          secondChild: const SizedBox.shrink(),
          crossFadeState:
              isExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          duration: const Duration(milliseconds: 250),
          sizeCurve: Curves.easeInOut,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildLockedSection(
      List<CategoryData> cats, Map<String, int> txCountMap) {
    final currency = ref.watch(currencyProvider);
    return Column(
      children: [
        for (int i = 0; i < cats.length; i++)
          _CategoryTile(
            key: ValueKey(cats[i].name),
            category: cats[i],
            itemCount: txCountMap[cats[i].name] ?? 0,
            index: i,
            isLocked: true,
            currency: currency,
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CategoryDetailScreen(category: cats[i]),
                ),
              );
            },
            onArchive: () {},
            onDelete: () {},
          ),
      ],
    );
  }

  Widget _buildReorderableSection(CategoryGroup group,
      List<CategoryData> cats, Map<String, int> txCountMap) {
    final currency = ref.watch(currencyProvider);
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      proxyDecorator: _proxyDecorator,
      itemCount: cats.length,
      onReorder: (oldIndex, newIndex) =>
          _reorderInGroup(group, oldIndex, newIndex),
      itemBuilder: (context, index) {
        final cat = cats[index];
        final count = txCountMap[cat.name] ?? 0;

        return _CategoryTile(
          key: ValueKey(cat.name),
          category: cat,
          itemCount: count,
          index: index,
          isLocked: false,
          currency: currency,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CategoryDetailScreen(category: cat),
              ),
            );
          },
          onArchive: () {
            HapticFeedback.mediumImpact();
            ref.read(categoriesProvider.notifier).removeCategory(cat.id);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.categoryArchived(
                    cat.localizedName(AppLocalizations.of(context)!))),
                backgroundColor: AppColors.primaryNavy,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                action: SnackBarAction(
                  label: AppLocalizations.of(context)!.undoLabel,
                  textColor: const Color(0xFFE67E22),
                  onPressed: () {
                    ref.read(categoriesProvider.notifier).addCategory(cat);
                  },
                ),
              ),
            );
          },
          onDelete: () {
            HapticFeedback.heavyImpact();
            _showDeleteDialog(cat);
          },
        );
      },
    );
  }

  void _reorderInGroup(CategoryGroup group, int oldIdx, int newIdx) {
    HapticFeedback.lightImpact();
    if (newIdx > oldIdx) newIdx--;
    if (oldIdx == newIdx) return;

    final allCats =
        List<CategoryData>.from(ref.read(categoriesProvider).value ?? []);

    // Extract positions and items belonging to this group
    final indices = <int>[];
    final items = <CategoryData>[];
    for (int i = 0; i < allCats.length; i++) {
      if (allCats[i].categoryGroup == group) {
        indices.add(i);
        items.add(allCats[i]);
      }
    }

    if (oldIdx >= items.length || newIdx >= items.length) return;

    // Reorder within the group
    final item = items.removeAt(oldIdx);
    items.insert(newIdx, item);

    // Place reordered items back at the same global positions
    for (int i = 0; i < indices.length; i++) {
      allCats[indices[i]] = items[i];
    }

    // ignore: invalid_use_of_visible_for_testing_member, invalid_use_of_protected_member
    ref.read(categoriesProvider.notifier).state = AsyncValue.data(allCats);
  }

  void _showDeleteDialog(CategoryData cat) {
    final transactions = ref.read(transactionsProvider).value ?? [];
    final txCount = transactions.where((tx) => tx.categoryId == cat.id).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          AppLocalizations.of(context)!.deleteCategoryTitle(cat.localizedName(AppLocalizations.of(context)!)),
          style: AppTypography.h2.copyWith(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          txCount > 0
              ? AppLocalizations.of(context)!.deleteCategoryHasTx(txCount)
              : AppLocalizations.of(context)!.deleteCategoryEmpty,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              AppLocalizations.of(context)!.cancelLabel,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(categoriesProvider.notifier).removeCategory(cat.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(AppLocalizations.of(context)!.categoryDeleted(cat.localizedName(AppLocalizations.of(context)!))),
                  backgroundColor: const Color(0xFFDC2626),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Text(
              AppLocalizations.of(context)!.deleteAction,
              style: TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final val = Curves.easeInOut.transform(animation.value);
        return Transform.scale(
          scale: 1.0 + 0.02 * val,
          child: Material(
            elevation: 4.0 + 8.0 * val,
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
//  CATEGORY TILE (with swipe-to-reveal)
// ═══════════════════════════════════════════════════════
class _CategoryTile extends StatefulWidget {
  final CategoryData category;
  final int itemCount;
  final int index;
  final bool isLocked;
  final String currency;
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _CategoryTile({
    super.key,
    required this.category,
    required this.itemCount,
    required this.index,
    required this.isLocked,
    required this.currency,
    required this.onTap,
    required this.onArchive,
    required this.onDelete,
  });

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  // ignore: unused_field
  late Animation<Offset> _slideAnimation;
  double _dragExtent = 0;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation =
        Tween<Offset>(begin: Offset.zero, end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragExtent += details.delta.dx;
      _dragExtent = _dragExtent.clamp(-140.0, 0.0);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_dragExtent < -60) {
      // Snap open
      setState(() => _dragExtent = -140.0);
    } else {
      // Snap closed
      setState(() => _dragExtent = 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final budget = widget.category.budgetLimit;
    final hasBudget = budget != null && budget > 0;

    // Format budget pill text
    String? budgetText;
    if (hasBudget) {
      final fmt = NumberFormat('#,##0', 'en');
      budgetText = l10n.budgetPerMonth(
          '${widget.currency} ${fmt.format(budget)}');
    }

    // Locked tiles: simple card, no swipe
    if (widget.isLocked) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 68,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.borderLight.withValues(alpha: 0.5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // Lock icon instead of drag handle
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: AppColors.borderLight,
                  ),
                ),
                // Category icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.category.displayBgColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    widget.category.iconData,
                    size: 20,
                    color: widget.category.displayColor,
                  ),
                ),
                const SizedBox(width: 12),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        widget.category
                            .localizedName(l10n),
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.primaryNavy,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.nItems(widget.itemCount),
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.borderLight,
                ),
              ],
            ),
          ),
        ),
      )
          .animate()
          .fadeIn(duration: 200.ms, delay: (50 + widget.index * 30).ms);
    }

    // Normal (unlocked) tiles: swipe-to-reveal actions
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 68,
          child: Stack(
            children: [
              // ── Action buttons behind ──
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Archive
                      GestureDetector(
                        onTap: () {
                          setState(() => _dragExtent = 0);
                          widget.onArchive();
                        },
                        child: Container(
                          width: 70,
                          height: double.infinity,
                          color: const Color(0xFF94A3B8),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.archive_rounded,
                                  color: Colors.white, size: 20),
                              const SizedBox(height: 2),
                              Text(
                                l10n.archiveAction,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Delete
                      GestureDetector(
                        onTap: () {
                          setState(() => _dragExtent = 0);
                          widget.onDelete();
                        },
                        child: Container(
                          width: 70,
                          height: double.infinity,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            borderRadius: BorderRadius.only(
                              topRight: Radius.circular(14),
                              bottomRight: Radius.circular(14),
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.delete_rounded,
                                  color: Colors.white, size: 20),
                              const SizedBox(height: 2),
                              Text(
                                l10n.deleteAction,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Foreground card ──
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(_dragExtent, 0, 0),
                child: GestureDetector(
                  onHorizontalDragUpdate: _onHorizontalDragUpdate,
                  onHorizontalDragEnd: _onHorizontalDragEnd,
                  onTap: () {
                    if (_dragExtent < 0) {
                      setState(() => _dragExtent = 0);
                    } else {
                      widget.onTap();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.borderLight.withValues(alpha: 0.5),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Drag handle
                        ReorderableDragStartListener(
                          index: widget.index,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              size: 20,
                              color: AppColors.borderLight,
                            ),
                          ),
                        ),
                        // Icon
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: widget.category.displayBgColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            widget.category.iconData,
                            size: 20,
                            color: widget.category.displayColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Text
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                widget.category
                                    .localizedName(l10n),
                                style: AppTypography.labelMedium.copyWith(
                                  color: AppColors.primaryNavy,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    l10n.nItems(widget.itemCount),
                                    style:
                                        AppTypography.captionSmall.copyWith(
                                      color: AppColors.textTertiary,
                                      fontSize: 11,
                                    ),
                                  ),
                                  if (budgetText != null) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: widget.category.isExpense
                                            ? const Color(0xFFFFF3E0)
                                            : const Color(0xFFE8F5E9),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        budgetText,
                                        style: TextStyle(
                                          color: widget.category.isExpense
                                              ? const Color(0xFFE65100)
                                              : const Color(0xFF2E7D32),
                                          fontSize: 9,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Chevron
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: AppColors.borderLight,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 200.ms, delay: (50 + widget.index * 30).ms);
  }
}

// ═══════════════════════════════════════════════════════
//  AI SUGGESTION BANNER
// ═══════════════════════════════════════════════════════
class _AiSuggestionBanner extends StatelessWidget {
  final String categoryA;
  final String categoryB;
  final VoidCallback onDismiss;

  const _AiSuggestionBanner({
    required this.categoryA,
    required this.categoryB,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryNavy,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryNavy.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Decorative glows
          Positioned(
            top: -30,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFE67E22).withValues(alpha: 0.2),
              ),
            ),
          ),
          Positioned(
            bottom: -25,
            left: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blue.withValues(alpha: 0.12),
              ),
            ),
          ),
          // Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_rounded,
                      color: Color(0xFFE67E22), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w300,
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(text: AppLocalizations.of(context)!.aiSuggestsMerging),
                          TextSpan(
                            text: '"$categoryA"',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          TextSpan(text: AppLocalizations.of(context)!.andWord),
                          TextSpan(
                            text: '"$categoryB"',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          TextSpan(
                              text:
                                  AppLocalizations.of(context)!.toSimplifyTracking),
                        ],
                      ),
                    ),
                  ),
                  // Dismiss
                  GestureDetector(
                    onTap: onDismiss,
                    child: Icon(Icons.close_rounded,
                        size: 16,
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onDismiss();
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppLocalizations.of(context)!.reviewSuggestion,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
