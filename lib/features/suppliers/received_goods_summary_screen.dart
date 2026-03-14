import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_styles.dart';
import '../../core/providers/app_providers.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../shared/models/goods_receipt_model.dart';
import '../../shared/models/purchase_model.dart';
import '../../shared/utils/safe_pop.dart';
import '../../l10n/app_localizations.dart';

/// Received Goods Summary — overview of goods receipts grouped by purchase.
class ReceivedGoodsSummaryScreen extends ConsumerWidget {
  const ReceivedGoodsSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = NumberFormat('#,##0');
    final dateFmt = DateFormat('dd MMM');
    final currency = ref.watch(currencyProvider);
    final receipts = ref.watch(goodsReceiptsProvider);
    final purchases = ref.watch(purchasesProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: receipts.isEmpty && purchases.isEmpty
                  ? _buildEmpty(context)
                  : _buildBody(
                      context,
                      ref,
                      receipts: receipts,
                      purchases: purchases,
                      currency: currency,
                      fmt: fmt,
                      dateFmt: dateFmt,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref, {
    required List<GoodsReceipt> receipts,
    required List<Purchase> purchases,
    required String currency,
    required NumberFormat fmt,
    required DateFormat dateFmt,
  }) {
    final l10n = AppLocalizations.of(context)!;
    // Metrics
    final totalCost =
        receipts.fold<double>(0, (sum, r) => sum + r.totalCost);
    final confirmedCount =
        receipts.where((r) => r.status == ReceiptStatus.confirmed).length;
    final pendingCount =
        receipts.where((r) => r.status == ReceiptStatus.pending).length;

    // Group receipts by purchaseId
    final grouped = <String, List<GoodsReceipt>>{};
    for (final r in receipts) {
      final key = r.purchaseId ?? 'unlinked';
      (grouped[key] ??= []).add(r);
    }

    // Sort purchases by date descending
    final sortedPurchases = [...purchases]
      ..sort((a, b) => b.date.compareTo(a.date));

    // Purchases that have receipts + those that don't
    final linkedPurchaseIds = grouped.keys.toSet();
    final purchasesWithReceipts = sortedPurchases
        .where((p) => linkedPurchaseIds.contains(p.id))
        .toList();
    final purchasesWithoutReceipts = sortedPurchases
        .where((p) => !linkedPurchaseIds.contains(p.id))
        .toList();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroCard(
            currency: currency,
            fmt: fmt,
            totalCost: totalCost,
            receiptCount: receipts.length,
            confirmedCount: confirmedCount,
            pendingCount: pendingCount,
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04),
          const SizedBox(height: 16),
          _StatsRow(
            confirmedCount: confirmedCount,
            pendingCount: pendingCount,
            purchaseCount: purchases.length,
          ).animate().fadeIn(duration: 250.ms, delay: 60.ms),
          const SizedBox(height: 20),
          // Purchases with receipts
          if (purchasesWithReceipts.isNotEmpty) ...[
            _sectionTitle(l10n.purchasesWithReceipts),
            const SizedBox(height: 10),
            ...purchasesWithReceipts.asMap().entries.map((e) {
              final p = e.value;
              final pReceipts = grouped[p.id] ?? [];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PurchaseReceiptCard(
                  purchase: p,
                  receipts: pReceipts,
                  currency: currency,
                  fmt: fmt,
                  dateFmt: dateFmt,
                ),
              );
            }).toList().animate(interval: 40.ms).fadeIn(duration: 200.ms),
          ],
          // Unlinked receipts
          if (grouped.containsKey('unlinked')) ...[
            SizedBox(height: 16),
            _sectionTitle(l10n.unlinkedReceipts),
            const SizedBox(height: 10),
            ...grouped['unlinked']!.map((r) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReceiptRow(
                  receipt: r,
                  currency: currency,
                  fmt: fmt,
                  dateFmt: dateFmt,
                ),
              );
            }),
          ],
          // Purchases without receipts (awaiting)
          if (purchasesWithoutReceipts.isNotEmpty) ...[
            SizedBox(height: 16),
            _sectionTitle(l10n.awaitingReceipt),
            const SizedBox(height: 10),
            ...purchasesWithoutReceipts.asMap().entries.map((e) {
              final p = e.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PurchaseReceiptCard(
                  purchase: p,
                  receipts: const [],
                  currency: currency,
                  fmt: fmt,
                  dateFmt: dateFmt,
                ),
              );
            }).toList().animate(interval: 40.ms).fadeIn(duration: 200.ms),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 56,
              color: AppColors.textTertiary.withValues(alpha: 0.4)),
          SizedBox(height: 16),
          Text(l10n.noReceivedGoodsYet,
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.textTertiary)),
          SizedBox(height: 6),
          Text(l10n.recordGoodsReceiptHelp,
              style: AppTypography.captionSmall
                  .copyWith(color: AppColors.textTertiary)),
          SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => context.pushNamed('ReceiveGoodsScreen'),
            icon: Icon(Icons.add_rounded),
            label: Text(l10n.receiveGoods),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
      final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
            bottom: BorderSide(
                color: AppColors.borderLight.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Expanded(
            child: Center(
              child: Text(
                l10n.receivedGoods,
                style: AppTypography.h2.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  HERO CARD
// ═══════════════════════════════════════════════════════
class _HeroCard extends StatelessWidget {
  final String currency;
  final NumberFormat fmt;
  final double totalCost;
  final int receiptCount;
  final int confirmedCount;
  final int pendingCount;

  const _HeroCard({
    required this.currency,
    required this.fmt,
    required this.totalCost,
    required this.receiptCount,
    required this.confirmedCount,
    required this.pendingCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    const accentColor = Color(0xFF8B5CF6);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: accentColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: accentColor.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Stack(
        children: [
          Positioned(
              top: -20,
              right: -20,
              child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle))),
          Positioned(
              bottom: -16,
              left: -16,
              child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      shape: BoxShape.circle))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.inventory_2_rounded,
                    color: Colors.white.withValues(alpha: 0.7), size: 16),
                SizedBox(width: 6),
                Text(l10n.totalReceivedValue,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                        fontSize: 14)),
              ]),
              const SizedBox(height: 12),
              Text(
                '$currency ${fmt.format(totalCost)}',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 36,
                    letterSpacing: -1),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  _chip(Icons.receipt_long_rounded,
                      '$receiptCount Receipt${receiptCount == 1 ? '' : 's'}'),
                  if (pendingCount > 0)
                    _chip(Icons.pending_rounded, '$pendingCount Pending'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              color: Colors.white.withValues(alpha: 0.9), size: 13),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w500,
                  fontSize: 12)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SECONDARY STATS
// ═══════════════════════════════════════════════════════
class _StatsRow extends StatelessWidget {
  final int confirmedCount;
  final int pendingCount;
  final int purchaseCount;
  const _StatsRow({
    required this.confirmedCount,
    required this.pendingCount,
    required this.purchaseCount,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
            child: _statCard(
           'Confirmed',
          '$confirmedCount',
           'Receipts verified',
          const Color(0xFF27AE60),
          Icons.check_circle_rounded,
        )),
        const SizedBox(width: 12),
        Expanded(
            child: _statCard(
           'Pending',
          '$pendingCount',
          pendingCount == 0 ? 'All confirmed ✓' :  'Awaiting review',
          pendingCount > 0
              ? const Color(0xFFE67E22)
              : const Color(0xFF27AE60),
          pendingCount > 0
              ? Icons.pending_rounded
              : Icons.check_circle_rounded,
        )),
      ],
    );
  }

  Widget _statCard(
      String label, String value, String sub, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.borderLight.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13)),
              Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 16)),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 24)),
          const SizedBox(height: 4),
          Text(sub,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w500, fontSize: 12)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  PURCHASE + RECEIPT CARD  — grouped view
// ═══════════════════════════════════════════════════════
class _PurchaseReceiptCard extends StatelessWidget {
  final Purchase purchase;
  final List<GoodsReceipt> receipts;
  final String currency;
  final NumberFormat fmt;
  final DateFormat dateFmt;

  const _PurchaseReceiptCard({
    required this.purchase,
    required this.receipts,
    required this.currency,
    required this.fmt,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Total ordered (from purchase), total received (across all receipts)
    final totalOrdered =
        purchase.items.fold<int>(0, (s, i) => s + i.qty);
    final totalReceived = purchase.items
        .fold<int>(0, (s, i) => s + i.receivedQty);
    final fulfilmentPct =
        totalOrdered > 0 ? (totalReceived / totalOrdered * 100) : 0.0;
    final isComplete = fulfilmentPct >= 100;
    final barColor =
        isComplete ? const Color(0xFF27AE60) : const Color(0xFF8B5CF6);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: AppColors.borderLight.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Purchase header — tappable to view received items details
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              _showReceivedItemsSheet(
                context,
                purchase: purchase,
                receipts: receipts,
                currency: currency,
                fmt: fmt,
                dateFmt: dateFmt,
                totalReceived: totalReceived,
                totalOrdered: totalOrdered,
                fulfilmentPct: fulfilmentPct,
                isComplete: isComplete,
                barColor: barColor,
              );
            },
            child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                      child: Icon(Icons.shopping_cart_rounded,
                          color: Color(0xFF8B5CF6), size: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        purchase.referenceNo.isNotEmpty
                            ? 'PO #${purchase.referenceNo} – ${purchase.supplierName}'
                            : '${purchase.items.map((i) => i.name).take(2).join(', ')}${purchase.items.length > 2 ? ' +${purchase.items.length - 2}' : ''}',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.store_rounded,
                              size: 11, color: AppColors.textTertiary),
                          const SizedBox(width: 4),
                          Flexible(
                              child: Text(purchase.supplierName,
                                  style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 12),
                                  overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          Text('· ${dateFmt.format(purchase.date)}',
                              style: TextStyle(
                                  color: AppColors.textTertiary,
                                  fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                Text('$currency ${fmt.format(purchase.total)}',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right_rounded,
                    color: AppColors.textTertiary, size: 18),
              ],
            ),
          ),
          ),

          // Fulfilment progress
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$totalReceived / $totalOrdered items received',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                    Text(
                      '${fulfilmentPct.toStringAsFixed(0)}%',
                      style: TextStyle(
                          color: barColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (fulfilmentPct / 100).clamp(0.0, 1.0),
                    backgroundColor:
                        AppColors.borderLight.withValues(alpha: 0.3),
                    color: barColor,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),

          // Receipt rows
          if (receipts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(
                height: 1,
                color: AppColors.borderLight.withValues(alpha: 0.3)),
            ...receipts.map((r) {
              final statusColor = _receiptStatusColor(r.status);
              final itemNames = r.items.map((i) => i.productName).take(2).join(', ');
              final overflow = r.items.length > 2 ? ' +${r.items.length - 2}' : '';
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  context.pushNamed('ReceiptDetailScreen', extra: {'receipt': r});
                },
                child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.local_shipping_rounded,
                        size: 16, color: statusColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$itemNames$overflow · ${dateFmt.format(r.date)}',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        r.statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 16,
                      icon: Icon(Icons.more_vert_rounded,
                          color: AppColors.textTertiary, size: 16),
                      onSelected: (v) {
                        if (v == 'view') {
                          context.pushNamed('ReceiptDetailScreen',
                              extra: {'receipt': r});
                        } else if (v == 'edit') {
                          context.pushNamed('EditReceiptScreen',
                              extra: {'receipt': r});
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'view',
                          child: Row(children: [
                            Icon(Icons.visibility_rounded, size: 18),
                            SizedBox(width: 8),
                            Text(l10n.viewDetails),
                          ]),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(children: [
                            Icon(Icons.edit_rounded, size: 18),
                            SizedBox(width: 8),
                            Text(l10n.editReceipt),
                          ]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              );
            }),
          ],

          // Receive items button
          if (!isComplete) ...[
            Divider(
                height: 1,
                color: AppColors.borderLight.withValues(alpha: 0.3)),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                context.pushNamed('ReceiveGoodsScreen', extra: {
                  'preselectedSupplierId': purchase.supplierId,
                  'preselectedPurchaseId': purchase.id,
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_rounded,
                        size: 16, color: const Color(0xFF8B5CF6)),
                    const SizedBox(width: 6),
                    Text(
                       'Receive Items',
                      style: TextStyle(
                          color: const Color(0xFF8B5CF6),
                          fontWeight: FontWeight.w600,
                          fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (isComplete)
            const SizedBox(height: 6),
        ],
      ),
    );
  }

  Color _receiptStatusColor(ReceiptStatus status) {
    switch (status) {
      case ReceiptStatus.confirmed:
        return const Color(0xFF27AE60);
      case ReceiptStatus.pending:
        return const Color(0xFFE67E22);
      case ReceiptStatus.rejected:
        return const Color(0xFFE74C3C);
    }
  }
}

// ═══════════════════════════════════════════════════════
//  RECEIVED ITEMS BOTTOM SHEET
// ═══════════════════════════════════════════════════════
void _showReceivedItemsSheet(
  BuildContext context, {
  required Purchase purchase,
  required List<GoodsReceipt> receipts,
  required String currency,
  required NumberFormat fmt,
  required DateFormat dateFmt,
  required int totalReceived,
  required int totalOrdered,
  required double fulfilmentPct,
  required bool isComplete,
  required Color barColor,
}) {
  final l10n = AppLocalizations.of(context)!;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_rounded,
                      color: Color(0xFF7C3AED), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                       'Received Items',
                      style: TextStyle(
                        color: AppColors.primaryNavy,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  Text(
                    '$totalReceived / $totalOrdered',
                    style: TextStyle(
                      color: barColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Progress bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (fulfilmentPct / 100).clamp(0.0, 1.0),
                      backgroundColor:
                          AppColors.borderLight.withValues(alpha: 0.3),
                      color: barColor,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isComplete ? 'Fully received' :  'Awaiting receipt',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12),
                      ),
                      Text(
                        '${fulfilmentPct.toStringAsFixed(0)}%',
                        style: TextStyle(
                            color: barColor,
                            fontWeight: FontWeight.w700,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Divider(
                height: 1,
                color: AppColors.borderLight.withValues(alpha: 0.3)),
            // Scrollable content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // Ordered items with received status
                  Text(
                     'Ordered Items',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...purchase.items.map((item) {
                    final pct = item.qty > 0
                        ? (item.receivedQty / item.qty * 100)
                        : 0.0;
                    final c = pct >= 100
                        ? const Color(0xFF27AE60)
                        : const Color(0xFF8B5CF6);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: TextStyle(
                                    color: AppColors.primaryNavy,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Text(
                                '$currency ${fmt.format(item.unitPrice * item.receivedQty)}',
                                style: TextStyle(
                                  color: c,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                             'Received ${item.receivedQty} of ${item.qty} · $currency ${fmt.format(item.unitPrice)} ea',
                            style: TextStyle(
                                color: AppColors.textTertiary, fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: (pct / 100).clamp(0.0, 1.0),
                              backgroundColor:
                                  AppColors.borderLight.withValues(alpha: 0.3),
                              color: c,
                              minHeight: 4,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // Receipts section
                  if (receipts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                       'Receipts',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...receipts.map((r) {
                      final color = _sheetReceiptColor(r.status);
                      final totalItems = r.items
                          .fold<double>(0, (s, i) => s + i.receivedQty);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.borderLight
                                  .withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                              child: Row(
                                children: [
                                  Icon(Icons.local_shipping_rounded,
                                      size: 18, color: color),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${totalItems.toInt()} item${totalItems.toInt() == 1 ? '' : 's'} received',
                                          style: TextStyle(
                                            color: AppColors.primaryNavy,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          dateFmt.format(r.date),
                                          style: TextStyle(
                                              color: AppColors.textTertiary,
                                              fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      r.statusLabel,
                                      style: TextStyle(
                                          color: color,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                                height: 1,
                                color: AppColors.borderLight
                                    .withValues(alpha: 0.3)),
                            Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      context.pushNamed('ReceiptDetailScreen',
                                          extra: {'receipt': r});
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 11),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.visibility_rounded,
                                              size: 14,
                                              color: Color(0xFF7C3AED)),
                                          SizedBox(width: 5),
                                          Text(
                                            l10n.viewDetails,
                                            style: TextStyle(
                                              color: Color(0xFF7C3AED),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 28,
                                  color: AppColors.borderLight
                                      .withValues(alpha: 0.3),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.pop(ctx);
                                      context.pushNamed('EditReceiptScreen',
                                          extra: {'receipt': r});
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 11),
                                      child: const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.edit_rounded,
                                              size: 14,
                                              color: Color(0xFFEA580C)),
                                          SizedBox(width: 5),
                                          Text(
                                             'Edit',
                                            style: TextStyle(
                                              color: Color(0xFFEA580C),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  // Receive Items button
                  if (!isComplete) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        context.pushNamed('ReceiveGoodsScreen', extra: {
                          'preselectedSupplierId': purchase.supplierId,
                          'preselectedPurchaseId': purchase.id,
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_rounded,
                                color: Colors.white, size: 18),
                            SizedBox(width: 6),
                            Text(
                               'Receive Items',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Color _sheetReceiptColor(ReceiptStatus status) {
  switch (status) {
    case ReceiptStatus.confirmed:
      return const Color(0xFF27AE60);
    case ReceiptStatus.pending:
      return const Color(0xFFE67E22);
    case ReceiptStatus.rejected:
      return const Color(0xFFE74C3C);
  }
}

// ═══════════════════════════════════════════════════════
//  UNLINKED RECEIPT ROW
// ═══════════════════════════════════════════════════════
class _ReceiptRow extends StatelessWidget {
  final GoodsReceipt receipt;
  final String currency;
  final NumberFormat fmt;
  final DateFormat dateFmt;

  const _ReceiptRow({
    required this.receipt,
    required this.currency,
    required this.fmt,
    required this.dateFmt,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final statusColor = _receiptStatusColor(receipt.status);
    final itemNames = receipt.items.map((i) => i.productName).take(2).join(', ');
    final overflow = receipt.items.length > 2 ? ' +${receipt.items.length - 2}' : '';
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.pushNamed('ReceiptDetailScreen', extra: {'receipt': receipt});
      },
      child: Container(
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
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
                child: Icon(Icons.local_shipping_rounded,
                    color: statusColor, size: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$itemNames$overflow',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${receipt.supplierName} · ${dateFmt.format(receipt.date)}',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$currency ${fmt.format(receipt.totalCost)}',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              const SizedBox(height: 3),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(receipt.statusLabel,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            iconSize: 18,
            icon: Icon(Icons.more_vert_rounded,
                color: AppColors.textTertiary, size: 18),
            onSelected: (v) {
              if (v == 'view') {
                context.pushNamed('ReceiptDetailScreen',
                    extra: {'receipt': receipt});
              } else if (v == 'edit') {
                context.pushNamed('EditReceiptScreen',
                    extra: {'receipt': receipt});
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'view',
                child: Row(children: [
                  Icon(Icons.visibility_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(l10n.viewDetails),
                ]),
              ),
              PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(l10n.editReceipt),
                ]),
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Color _receiptStatusColor(ReceiptStatus status) {
    switch (status) {
      case ReceiptStatus.confirmed:
        return const Color(0xFF27AE60);
      case ReceiptStatus.pending:
        return const Color(0xFFE67E22);
      case ReceiptStatus.rejected:
        return const Color(0xFFE74C3C);
    }
  }
}
