import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/services/shopify_sync_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/models/product_model.dart';
import '../../../shared/models/shopify_product_mapping_model.dart';
import '../providers/shopify_product_mappings_provider.dart';
import '../providers/shopify_sync_provider.dart';
import '../../../shared/utils/safe_pop.dart';
import '../../../l10n/app_localizations.dart';

/// Inventory sync screen — Pull from Shopify or Push to Shopify.
///
/// Flow: Select direction → Fetch Preview → Review delta table → Confirm
class ShopifyInventorySyncScreen extends ConsumerStatefulWidget {
  const ShopifyInventorySyncScreen({super.key});

  @override
  ConsumerState<ShopifyInventorySyncScreen> createState() =>
      _ShopifyInventorySyncScreenState();
}

class _ShopifyInventorySyncScreenState
    extends ConsumerState<ShopifyInventorySyncScreen>
    with SingleTickerProviderStateMixin {
  AppLocalizations get l10n => AppLocalizations.of(context)!;
  late TabController _tabController;
  final _selectedProductIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
      final l10n = AppLocalizations.of(context)!;
    final syncStatus = ref.watch(shopifySyncProvider);
    final asyncMappings = ref.watch(shopifyMappingsProvider);
    final products = ref.watch(inventoryProvider).value ?? [];

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            // Tab bar
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primaryNavy,
                labelColor: AppColors.primaryNavy,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: AppTypography.labelMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: AppTypography.labelMedium,
                tabs: [
                  Tab(text: l10n.pullFromShopify),
                  Tab(text: l10n.pushToShopify),
                ],
              ),
            ),
            // Sync status banner
            if (syncStatus.isSyncing ||
                syncStatus.phase == SyncPhase.error)
              _SyncBanner(status: syncStatus),

            Expanded(
              child: asyncMappings.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primaryNavy),
                ),
                error: (e, _) => Center(
                  child: Text(
                     'Failed to load mappings:\n$e',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ),
                data: (mappings) {
                  final mappedProductIds = <String>{
                    for (final m in mappings) m.masariProductId,
                  };
                  final mappedProducts = products
                      .where((p) => mappedProductIds.contains(p.id))
                      .toList();

                  if (mappedProducts.isEmpty) {
                    return _buildNoMappings();
                  }

                  return TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPullTab(
                          mappedProducts, mappings, syncStatus),
                      _buildPushTab(
                          mappedProducts, mappings, syncStatus),
                    ],
                  );
                },
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
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: AppColors.primaryNavy,
          ),
          const Spacer(),
          Text(
             'Inventory Sync',
            style: AppTypography.labelMedium.copyWith(
              color: AppColors.primaryNavy,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildNoMappings() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off_rounded,
                size: 48, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text(
               'No Product Mappings',
              style: AppTypography.h3.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
               'Link your Masari products to Shopify products first\n'
              'using the Product Mappings screen.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════
  //  PULL TAB
  // ══════════════════════════════════════════════════════════

  Widget _buildPullTab(
    List<Product> mappedProducts,
    List<ShopifyProductMapping> mappings,
    SyncStatus syncStatus,
  ) {
    final notifier = ref.read(shopifySyncProvider.notifier);
    final preview = notifier.pullPreview;
    final hasPreview = preview != null && preview.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoBanner(
                  color: AppColors.primaryNavy,
                  icon: Icons.info_outline_rounded,
                  text:  'Pull will update stock levels in Masari to '
                      'match Shopify for all mapped products.  Review the preview before confirming.',
                ).animate().fadeIn(duration: 200.ms),
                const SizedBox(height: 16),

                if (!hasPreview) ...[
                  // Show mapped products list
                  Text(
                    '${mappedProducts.length} MAPPED PRODUCT(S)',
                    style: AppTypography.captionSmall.copyWith(
                      color: AppColors.textTertiary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < mappedProducts.length; i++)
                    _ProductSyncTile(
                      product: mappedProducts[i],
                      direction: 'pull',
                    )
                        .animate()
                        .fadeIn(
                            duration: 200.ms, delay: (i * 30).ms),
                ] else ...[
                  // Show preview table
                  _PreviewTable(
                    items: preview,
                    direction: 'pull',
                  ).animate().fadeIn(duration: 250.ms),
                ],
              ],
            ),
          ),
        ),
        if (!hasPreview)
          _buildBottomAction(
            label: l10n.fetchPreview,
            icon: Icons.preview_rounded,
            isSyncing: syncStatus.isSyncing,
            onTap: () {
              HapticFeedback.mediumImpact();
              notifier.previewPull();
            },
          )
        else
          _buildDualActions(
            cancelLabel: l10n.cancel,
            confirmLabel:
                 'Confirm Pull (${preview.where((i) => i.hasChange).length} changes)',
            isSyncing: syncStatus.isSyncing,
            hasChanges: preview.any((i) => i.hasChange),
            onCancel: () {
              setState(() => notifier.clearPreviews());
            },
            onConfirm: () {
              HapticFeedback.heavyImpact();
              notifier.confirmPull();
            },
          ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  //  PUSH TAB
  // ══════════════════════════════════════════════════════════

  Widget _buildPushTab(
    List<Product> mappedProducts,
    List<ShopifyProductMapping> mappings,
    SyncStatus syncStatus,
  ) {
    final notifier = ref.read(shopifySyncProvider.notifier);
    final preview = notifier.pushPreview;
    final hasPreview = preview != null && preview.isNotEmpty;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoBanner(
                  color: AppColors.warning,
                  icon: Icons.warning_amber_rounded,
                  text:  'Push will overwrite Shopify stock levels with '
                      'your Masari inventory values. Select products, '
                      'then review the preview.',
                ).animate().fadeIn(duration: 200.ms),
                const SizedBox(height: 16),

                if (!hasPreview) ...[
                  // Select all row
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            if (_selectedProductIds.length ==
                                mappedProducts.length) {
                              _selectedProductIds.clear();
                            } else {
                              _selectedProductIds.addAll(
                                  mappedProducts.map((p) => p.id));
                            }
                          });
                        },
                        child: Row(
                          children: [
                            Icon(
                              _selectedProductIds.length ==
                                      mappedProducts.length
                                  ? Icons.check_box_rounded
                                  : Icons
                                      .check_box_outline_blank_rounded,
                              size: 22,
                              color: AppColors.primaryNavy,
                            ),
                            const SizedBox(width: 8),
                            Text(
                               'Select All (${mappedProducts.length})',
                              style:
                                  AppTypography.labelMedium.copyWith(
                                color: AppColors.primaryNavy,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (var i = 0; i < mappedProducts.length; i++)
                    _SelectableProductTile(
                      product: mappedProducts[i],
                      isSelected: _selectedProductIds
                          .contains(mappedProducts[i].id),
                      onToggle: () {
                        setState(() {
                          final id = mappedProducts[i].id;
                          if (_selectedProductIds.contains(id)) {
                            _selectedProductIds.remove(id);
                          } else {
                            _selectedProductIds.add(id);
                          }
                        });
                      },
                      mappings: mappings
                          .where((m) =>
                              m.masariProductId ==
                              mappedProducts[i].id)
                          .toList(),
                    )
                        .animate()
                        .fadeIn(
                            duration: 200.ms, delay: (i * 30).ms),
                ] else ...[
                  _PreviewTable(
                    items: preview,
                    direction: 'push',
                  ).animate().fadeIn(duration: 250.ms),
                ],
              ],
            ),
          ),
        ),
        if (!hasPreview)
          _buildBottomAction(
            label: _selectedProductIds.isEmpty
                ? l10n.selectProductsToPreview
                :  'Fetch Preview (${_selectedProductIds.length})',
            icon: Icons.preview_rounded,
            isSyncing: syncStatus.isSyncing,
            enabled: _selectedProductIds.isNotEmpty,
            onTap: () {
              HapticFeedback.mediumImpact();
              notifier.previewPush(
                productIds: _selectedProductIds,
              );
            },
          )
        else
          _buildDualActions(
            cancelLabel: l10n.cancel,
            confirmLabel:
                 'Confirm Push (${preview.where((i) => i.hasChange).length} changes)',
            isSyncing: syncStatus.isSyncing,
            hasChanges: preview.any((i) => i.hasChange),
            onCancel: () {
              setState(() => notifier.clearPreviews());
            },
            onConfirm: () {
              HapticFeedback.heavyImpact();
              notifier.confirmPush();
            },
          ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════
  //  BOTTOM ACTIONS
  // ══════════════════════════════════════════════════════════

  Widget _buildBottomAction({
    required String label,
    required IconData icon,
    required bool isSyncing,
    bool enabled = true,
    required VoidCallback onTap,
  }) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: GestureDetector(
        onTap: isSyncing || !enabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSyncing || !enabled
                ? AppColors.textTertiary
                : AppColors.primaryNavy,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Center(
            child: isSyncing
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Loading…',
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildDualActions({
    required String cancelLabel,
    required String confirmLabel,
    required bool isSyncing,
    required bool hasChanges,
    required VoidCallback onCancel,
    required VoidCallback onConfirm,
  }) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad + 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.5)),
        ),
      ),
      child: isSyncing
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primaryNavy,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Syncing…',
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onCancel,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.borderLight),
                      ),
                      child: Text(
                        cancelLabel,
                        textAlign: TextAlign.center,
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: hasChanges ? onConfirm : null,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: hasChanges
                            ? AppColors.primaryNavy
                            : AppColors.textTertiary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        hasChanges
                            ? confirmLabel
                            :  'No Changes',
                        textAlign: TextAlign.center,
                        style: AppTypography.labelMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  PRIVATE WIDGETS
// ═══════════════════════════════════════════════════════════

class _InfoBanner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;

  const _InfoBanner({
    required this.color,
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: color,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  final SyncStatus status;

  const _SyncBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    Color bg;
    Color fg;
    IconData icon;

    if (status.isSyncing) {
      bg = AppColors.secondaryBlue.withValues(alpha: 0.08);
      fg = AppColors.secondaryBlue;
      icon = Icons.sync_rounded;
    } else {
      bg = AppColors.danger.withValues(alpha: 0.08);
      fg = AppColors.danger;
      icon = Icons.error_outline_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 10),
      color: bg,
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status.message ?? '',
              style: AppTypography.bodySmall.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
          if (status.isSyncing)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: fg,
              ),
            ),
        ],
      ),
    );
  }
}

// ── Preview Table ─────────────────────────────────────────

class _PreviewTable extends StatelessWidget {
  final List<InventoryPreviewItem> items;
  final String direction;

  const _PreviewTable({required this.items, required this.direction});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final changedItems = items.where((i) => i.hasChange).toList();
    final unchangedItems =
        items.where((i) => !i.hasChange && !i.isUnmapped).toList();
    final unmappedItems = items.where((i) => i.isUnmapped).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: changedItems.isNotEmpty
                ? AppColors.success.withValues(alpha: 0.06)
                : AppColors.textTertiary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                changedItems.isNotEmpty
                    ? Icons.compare_arrows_rounded
                    : Icons.check_circle_outline_rounded,
                size: 20,
                color: changedItems.isNotEmpty
                    ? AppColors.success
                    : AppColors.textTertiary,
              ),
              const SizedBox(width: 10),
              Text(
                changedItems.isNotEmpty
                    ? '${changedItems.length} variant(s) will change, '
                        '${unchangedItems.length} unchanged'
                    :  'All variants are already in sync!',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Table header
        _tableHeader(direction),
        const Divider(height: 1),

        // Changed items first
        for (final item in changedItems) _PreviewRow(item: item),

        if (unchangedItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
               'UNCHANGED (${unchangedItems.length})',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                fontSize: 10,
              ),
            ),
          ),
          for (final item in unchangedItems)
            _PreviewRow(item: item, dimmed: true),
        ],

        // Unmapped warnings
        if (unmappedItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Text(
                      '${unmappedItems.length} variant(s) skipped',
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final item in unmappedItems)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${item.displayName}'
                      '${item.warning != null ? ' — ${item.warning}' : ' — no Shopify level found'}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _tableHeader(String direction) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
               'PRODUCT',
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                fontSize: 10,
              ),
            ),
          ),
          SizedBox(
            width: 55,
            child: Text(
               'MASARI',
              textAlign: TextAlign.center,
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                fontSize: 10,
              ),
            ),
          ),
          SizedBox(
            width: 55,
            child: Text(
               'SHOPIFY',
              textAlign: TextAlign.center,
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                fontSize: 10,
              ),
            ),
          ),
          SizedBox(
            width: 50,
            child: Text(
               'DELTA',
              textAlign: TextAlign.center,
              style: AppTypography.captionSmall.copyWith(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final InventoryPreviewItem item;
  final bool dimmed;

  const _PreviewRow({required this.item, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final deltaColor = item.delta > 0
        ? AppColors.success
        : item.delta < 0
            ? AppColors.danger
            : AppColors.textTertiary;
    final deltaPrefix = item.delta > 0 ? '+' : '';
    final alpha = dimmed ? 0.5 : 1.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color:
                  AppColors.borderLight.withValues(alpha: 0.2)),
        ),
      ),
      child: Opacity(
        opacity: alpha,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.variantName != null)
                    Text(
                      item.variantName!,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            SizedBox(
              width: 55,
              child: Text(
                '${item.masariStock}',
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 55,
              child: Text(
                '${item.shopifyStock}',
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 50,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: item.delta != 0
                      ? deltaColor.withValues(alpha: 0.1)
                      : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.delta == 0
                      ? '—'
                      : '$deltaPrefix${item.delta}',
                  textAlign: TextAlign.center,
                  style: AppTypography.labelSmall.copyWith(
                    color: deltaColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Product Tiles ─────────────────────────────────────────

class _ProductSyncTile extends StatelessWidget {
  final Product product;
  final String direction;

  const _ProductSyncTile({
    required this.product,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalStock = product.variants.fold<int>(
        0, (sum, v) => sum + v.currentStock);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryNavy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.inventory_2_rounded,
                size: 18, color: AppColors.primaryNavy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${product.variants.length} variant(s) · $totalStock in stock',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            direction == 'pull'
                ? Icons.arrow_back_rounded
                : Icons.arrow_forward_rounded,
            size: 18,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

class _SelectableProductTile extends StatelessWidget {
  final Product product;
  final bool isSelected;
  final VoidCallback onToggle;
  final List<ShopifyProductMapping> mappings;

  const _SelectableProductTile({
    required this.product,
    required this.isSelected,
    required this.onToggle,
    required this.mappings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final totalStock = product.variants.fold<int>(
        0, (sum, v) => sum + v.currentStock);

    return GestureDetector(
      onTap: onToggle,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryNavy.withValues(alpha: 0.04)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryNavy.withValues(alpha: 0.3)
                : AppColors.borderLight.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              size: 22,
              color: isSelected
                  ? AppColors.primaryNavy
                  : AppColors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${mappings.length} mapping(s) · $totalStock in stock',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_rounded,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
