import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../shared/models/category_data.dart';
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

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final transactions = ref.watch(transactionsProvider);

    // Count transactions per category
    final txCountMap = <String, int>{};
    for (final tx in transactions) {
      txCountMap[tx.category.name] = (txCountMap[tx.category.name] ?? 0) + 1;
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
                  // Category list
                  _buildCategoryList(categories, txCountMap),
                  // AI suggestion banner
                  if (_showAiSuggestion && categories.length >= 2)
                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: _AiSuggestionBanner(
                        categoryA: categories.length > 0 ? categories[0].name : '',
                        categoryB: categories.length > 3 ? categories[3].name : (categories.length > 1 ? categories[1].name : ''),
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
                'Manage Categories',
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
                '+ Add',
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
  //  CATEGORY LIST
  // ═══════════════════════════════════════════════════════
  Widget _buildCategoryList(
      List<CategoryData> categories, Map<String, int> txCountMap) {
    return ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, _showAiSuggestion ? 140 : 40),
      proxyDecorator: _proxyDecorator,
      itemCount: categories.length,
      onReorder: (oldIndex, newIndex) {
        HapticFeedback.lightImpact();
        if (newIndex > oldIndex) newIndex--;
        final cats = ref.read(categoriesProvider.notifier);
        final list = List<CategoryData>.from(ref.read(categoriesProvider));
        final item = list.removeAt(oldIndex);
        list.insert(newIndex, item);
        // Update state
        cats.state = list;
      },
      itemBuilder: (context, index) {
        final cat = categories[index];
        final count = txCountMap[cat.name] ?? 0;

        return _CategoryTile(
          key: ValueKey(cat.name),
          category: cat,
          itemCount: count,
          index: index,
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${cat.name} archived'),
                backgroundColor: AppColors.primaryNavy,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                action: SnackBarAction(
                  label: 'Undo',
                  textColor: const Color(0xFFE67E22),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category restored')));
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

  void _showDeleteDialog(CategoryData cat) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete "${cat.name}"?',
          style: AppTypography.h2.copyWith(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This will permanently remove this category. All related transactions will be marked as uncategorized.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 14),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(categoriesProvider.notifier).removeCategory(cat.name);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${cat.name} deleted'),
                  backgroundColor: const Color(0xFFDC2626),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: const Text(
              'Delete',
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
  final VoidCallback onTap;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _CategoryTile({
    super.key,
    required this.category,
    required this.itemCount,
    required this.index,
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
                                'Archive',
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
                                'Delete',
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
                            color: widget.category.bgColor,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            widget.category.icon,
                            size: 20,
                            color: widget.category.color,
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
                                widget.category.name,
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
                                '${widget.itemCount} items',
                                style: AppTypography.captionSmall.copyWith(
                                  color: AppColors.textTertiary,
                                  fontSize: 11,
                                ),
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
                          const TextSpan(text: 'AI suggests merging '),
                          TextSpan(
                            text: '"$categoryA"',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const TextSpan(text: ' and '),
                          TextSpan(
                            text: '"$categoryB"',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const TextSpan(
                              text:
                                  ' to simplify your tracking.'),
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
                      'Review Suggestion',
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
