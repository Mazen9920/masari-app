import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../l10n/app_localizations.dart';

/// Shopify branded color constants.
class ShopifyColors {
  ShopifyColors._();
  static const green = Color(0xFF96BF48);
  static const greenDark = Color(0xFF5E8E3E);
}

/// Shows a "Shopify" source badge on a Sale Detail screen.
///
/// Displays the Shopify order number and a "View on Shopify" link.
class ShopifySaleBadge extends StatelessWidget {
  final String? externalOrderId;
  final String? shopDomain;

  const ShopifySaleBadge({
    super.key,
    this.externalOrderId,
    this.shopDomain,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShopifyColors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ShopifyColors.green.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Shopify icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [ShopifyColors.green, ShopifyColors.greenDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.shopping_bag_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.shopifyOrder,
                      style: AppTypography.labelMedium.copyWith(
                        color: ShopifyColors.greenDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ShopifyColors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                         l10n.shopifyBadge,
                        style: AppTypography.captionSmall.copyWith(
                          color: ShopifyColors.greenDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                if (externalOrderId != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '#$externalOrderId',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (shopDomain != null &&
              shopDomain!.isNotEmpty &&
              externalOrderId != null)
            GestureDetector(
              onTap: () => _openInShopify(context),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: ShopifyColors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.open_in_new_rounded,
                        size: 14, color: ShopifyColors.greenDark),
                    const SizedBox(width: 4),
                    Text(
                       l10n.shopifyViewButton,
                      style: AppTypography.labelSmall.copyWith(
                        color: ShopifyColors.greenDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openInShopify(BuildContext context) async {
    HapticFeedback.lightImpact();
    final domain =
        shopDomain!.replaceAll('.myshopify.com', '');
    final url = Uri.parse(
        'https://$domain.myshopify.com/admin/orders/$externalOrderId');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}

/// Shows a "Linked to Shopify" badge on a Product Detail screen.
///
/// Displays the Shopify product link status and last inventory sync time.
class ShopifyProductBadge extends StatelessWidget {
  final String? shopifyProductId;
  final DateTime? lastInventorySyncAt;
  final String? shopDomain;

  const ShopifyProductBadge({
    super.key,
    this.shopifyProductId,
    this.lastInventorySyncAt,
    this.shopDomain,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ShopifyColors.green.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ShopifyColors.green.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Shopify icon
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [ShopifyColors.green, ShopifyColors.greenDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.link_rounded,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                       l10n.shopifyLinkedToShopify,
                      style: AppTypography.labelMedium.copyWith(
                        color: ShopifyColors.greenDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: ShopifyColors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 12,
                        color: ShopifyColors.greenDark,
                      ),
                    ),
                  ],
                ),
                if (lastInventorySyncAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                     l10n.shopifyLastSyncTime(_timeAgo(l10n, lastInventorySyncAt!)),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(AppLocalizations l10n, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inMinutes < 60) return l10n.shopifyTimeMinAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.shopifyTimeHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.shopifyTimeDaysAgo(diff.inDays);
    return DateFormat( 'MMM dd').format(dt);
  }
}
