import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/repository_providers.dart';
import '../../../core/services/shopify_sync_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_styles.dart';
import '../../../shared/models/sale_model.dart';
import '../../../shared/utils/safe_pop.dart';
import '../../shopify/providers/shopify_connection_provider.dart';

// ═══════════════════════════════════════════════════════════
// AUDIT MODELS
// ═══════════════════════════════════════════════════════════

enum AuditStatus { idle, checking, fixing, done, error }

enum IssueSeverity { ok, warning, critical }

/// Detail for a single affected order inside an issue.
class AuditOrderDetail {
  final String label;
  final String subtitle;
  final Sale? sale; // non-null for local orders → tap to navigate
  final String? externalId;

  const AuditOrderDetail({
    required this.label,
    required this.subtitle,
    this.sale,
    this.externalId,
  });
}

class AuditIssue {
  final String title;
  final String description;
  final IssueSeverity severity;
  final IconData icon;
  final int count;
  final List<AuditOrderDetail> orders;

  const AuditIssue({
    required this.title,
    required this.description,
    required this.severity,
    required this.icon,
    this.count = 0,
    this.orders = const [],
  });
}

class ShopifyAuditResult {
  final AuditStatus status;
  final int shopifyOrderCount;
  final int localShopifyCount;
  final int totalLocalSales;
  final List<AuditIssue> issues;
  final String? errorMessage;
  final String? fixProgress; // e.g. "Importing 3/361…"
  final DateTime? lastCheckedAt;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  const ShopifyAuditResult({
    this.status = AuditStatus.idle,
    this.shopifyOrderCount = 0,
    this.localShopifyCount = 0,
    this.totalLocalSales = 0,
    this.issues = const [],
    this.errorMessage,
    this.fixProgress,
    this.lastCheckedAt,
    this.periodStart,
    this.periodEnd,
  });

  int get criticalCount =>
      issues.where((i) => i.severity == IssueSeverity.critical).length;
  int get warningCount =>
      issues.where((i) => i.severity == IssueSeverity.warning).length;
  int get okCount =>
      issues.where((i) => i.severity == IssueSeverity.ok).length;
  int get totalIssueItems =>
      issues
          .where((i) => i.severity != IssueSeverity.ok)
          .fold(0, (s, i) => s + i.count);
  bool get allGood => criticalCount == 0 && warningCount == 0;
  bool get hasMissingOrders => issues.any(
      (i) =>
          i.title == 'Missing Orders' &&
          i.severity == IssueSeverity.critical);
}

// ═══════════════════════════════════════════════════════════
// AUDIT NOTIFIER
// ═══════════════════════════════════════════════════════════

class ShopifyAuditNotifier extends Notifier<ShopifyAuditResult> {
  Timer? _autoCheckTimer;
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  ShopifyAuditResult build() {
    ref.onDispose(() => _autoCheckTimer?.cancel());
    _scheduleAutoCheck();
    return const ShopifyAuditResult();
  }

  void _scheduleAutoCheck() {
    _autoCheckTimer?.cancel();
    final isConnected = ref.read(isShopifyConnectedProvider);
    if (!isConnected) return;

    Future.delayed(const Duration(seconds: 3), () {
      if (state.status == AuditStatus.idle) runAudit();
    });

    _autoCheckTimer = Timer.periodic(
      const Duration(seconds: 90),
      (_) => runAudit(),
    );
  }

  /// Set a custom period and re-run the audit.
  Future<void> auditPeriod(DateTime start, DateTime end) async {
    _customStart = start;
    _customEnd = end;
    await runAudit();
  }

  DateTime get _start =>
      _customStart ??
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime get _end => _customEnd ?? DateTime.now();

  Future<void> runAudit() async {
    final isConnected = ref.read(isShopifyConnectedProvider);
    if (!isConnected) {
      state = const ShopifyAuditResult(status: AuditStatus.idle);
      return;
    }

    state = ShopifyAuditResult(
      status: AuditStatus.checking,
      lastCheckedAt: state.lastCheckedAt,
      periodStart: _start,
      periodEnd: _end,
    );

    try {
      final api = ref.read(shopifyApiServiceProvider);
      final start = _start;
      final end = _end;

      // Fetch Shopify order IDs for the period
      final shopifyResult = await api.fetchOrderIds(since: start, until: end);

      if (!shopifyResult.isSuccess || shopifyResult.data == null) {
        state = ShopifyAuditResult(
          status: AuditStatus.error,
          errorMessage:
              shopifyResult.error ?? 'Failed to fetch Shopify orders',
          lastCheckedAt: DateTime.now(),
          periodStart: start,
          periodEnd: end,
        );
        return;
      }

      // Fetch local sales for the audited period (used for non-sync checks).
      final repo = ref.read(saleRepositoryProvider);
      final localResult = await repo.getSalesInRange(
        start: start,
        end: DateTime(end.year, end.month, end.day, 23, 59, 59),
      );

      // Also fetch ALL local Shopify sales to correctly match by externalOrderId.
      // Without this, orders saved under a slightly different date appear as
      // "missing" even though they are already imported.
      final allResult = await repo.getSales();
      final allLocalSales =
          allResult.isSuccess ? allResult.data! : <Sale>[];
      final allShopifySales =
          allLocalSales.where((s) => s.isShopifyOrder).toList();

      final shopifyOrders = shopifyResult.data!;
      final localSales = localResult.isSuccess ? localResult.data! : <Sale>[];

      // Build a set of all local Shopify externalOrderIds for matching.
      final allLocalExtIds = <String>{};
      for (final sale in allShopifySales) {
        if (sale.externalOrderId != null) {
          allLocalExtIds.add(sale.externalOrderId!);
        }
      }

      // Count how many Shopify orders have a local match (date-independent).
      var matchedCount = 0;
      for (final order in shopifyOrders) {
        final id = order['id']?.toString();
        if (id != null && allLocalExtIds.contains(id)) matchedCount++;
      }

      // Run all checks
      final issues = <AuditIssue>[];

      // Missing & status checks use ALL local Shopify sales (date-independent)
      _checkMissingOrders(shopifyOrders, allShopifySales, issues);
      _checkDuplicateOrders(localSales, issues);
      _checkStatusMismatches(shopifyOrders, allShopifySales, issues);
      // Other checks use period-scoped sales
      _checkZeroCostOrders(localSales, issues);
      _checkMissingCustomerInfo(localSales, issues);
      _checkUnfulfilledPaidOrders(localSales, issues);

      state = ShopifyAuditResult(
        status: AuditStatus.done,
        shopifyOrderCount: shopifyOrders.length,
        localShopifyCount: matchedCount,
        totalLocalSales: localSales.length,
        issues: issues,
        lastCheckedAt: DateTime.now(),
        periodStart: start,
        periodEnd: end,
      );
    } catch (e) {
      developer.log('Shopify audit error: $e', name: 'ShopifyAudit');
      state = ShopifyAuditResult(
        status: AuditStatus.error,
        errorMessage: e.toString(),
        lastCheckedAt: DateTime.now(),
        periodStart: _start,
        periodEnd: _end,
      );
    }
  }

  // ── Check: Missing orders (in Shopify but not local) ───

  void _checkMissingOrders(
    List<Map<String, dynamic>> shopifyOrders,
    List<Sale> localSales,
    List<AuditIssue> issues,
  ) {
    final localExternalIds = <String>{};
    for (final sale in localSales) {
      if (sale.externalOrderId != null && sale.isShopifyOrder) {
        localExternalIds.add(sale.externalOrderId!);
      }
    }

    final missingOrders = <AuditOrderDetail>[];
    for (final order in shopifyOrders) {
      final id = order['id']?.toString();
      if (id == null) continue;
      final cancelledAt = order['cancelled_at'];
      if (cancelledAt != null && cancelledAt.toString().isNotEmpty) continue;
      if (!localExternalIds.contains(id)) {
        final num = order['order_number']?.toString() ?? id;
        final status = order['financial_status']?.toString() ?? 'unknown';
        missingOrders.add(AuditOrderDetail(
          label: '#$num',
          subtitle: 'Payment: $status',
          externalId: id,
        ));
      }
    }

    if (missingOrders.isEmpty) {
      issues.add(const AuditIssue(
        title: 'Missing Orders',
        description: 'All Shopify orders are synced locally.',
        severity: IssueSeverity.ok,
        icon: Icons.cloud_download_outlined,
      ));
    } else {
      issues.add(AuditIssue(
        title: 'Missing Orders',
        description:
            '${missingOrders.length} order${missingOrders.length == 1 ? '' : 's'} '
            'in Shopify not found in app.',
        severity: IssueSeverity.critical,
        icon: Icons.cloud_off_rounded,
        count: missingOrders.length,
        orders: missingOrders,
      ));
    }
  }

  // ── Check: Duplicate orders ────────────────────────────

  void _checkDuplicateOrders(
    List<Sale> localSales,
    List<AuditIssue> issues,
  ) {
    final byExtId = <String, List<Sale>>{};
    for (final sale in localSales) {
      if (sale.externalOrderId != null && sale.isShopifyOrder) {
        byExtId.putIfAbsent(sale.externalOrderId!, () => []).add(sale);
      }
    }

    final dupOrders = <AuditOrderDetail>[];
    for (final entry in byExtId.entries) {
      if (entry.value.length > 1) {
        for (final sale in entry.value) {
          dupOrders.add(AuditOrderDetail(
            label: sale.displayOrderTitle,
            subtitle: '${entry.value.length}x duplicated · ${_moneyFmt(sale.total)}',
            sale: sale,
            externalId: entry.key,
          ));
        }
      }
    }

    if (dupOrders.isEmpty) {
      issues.add(const AuditIssue(
        title: 'Duplicate Orders',
        description: 'No duplicate Shopify orders detected.',
        severity: IssueSeverity.ok,
        icon: Icons.copy_outlined,
      ));
    } else {
      final uniqueCount =
          dupOrders.map((o) => o.externalId).toSet().length;
      issues.add(AuditIssue(
        title: 'Duplicate Orders',
        description:
            '$uniqueCount Shopify order${uniqueCount == 1 ? '' : 's'} '
            'imported more than once (${dupOrders.length} total copies). '
            'This causes double-counted revenue.',
        severity: IssueSeverity.critical,
        icon: Icons.copy_rounded,
        count: uniqueCount,
        orders: dupOrders,
      ));
    }
  }

  // ── Check: Status mismatches ───────────────────────────

  void _checkStatusMismatches(
    List<Map<String, dynamic>> shopifyOrders,
    List<Sale> localSales,
    List<AuditIssue> issues,
  ) {
    final localByExtId = <String, Sale>{};
    for (final sale in localSales) {
      if (sale.externalOrderId != null && sale.isShopifyOrder) {
        localByExtId[sale.externalOrderId!] = sale;
      }
    }

    final mismatchOrders = <AuditOrderDetail>[];
    for (final order in shopifyOrders) {
      final id = order['id']?.toString();
      if (id == null) continue;
      final local = localByExtId[id];
      if (local == null) continue;

      final shopifyCancelled = order['cancelled_at'] != null &&
          order['cancelled_at'].toString().isNotEmpty;
      final localCancelled = local.orderStatus == OrderStatus.cancelled;

      if (shopifyCancelled && !localCancelled) {
        mismatchOrders.add(AuditOrderDetail(
          label: local.displayOrderTitle,
          subtitle: 'Shopify: cancelled · App: ${local.orderStatus.name}',
          sale: local,
          externalId: id,
        ));
        continue;
      }

      final shopifyFinancial = order['financial_status']?.toString() ?? '';
      if (shopifyFinancial == 'paid' &&
          local.paymentStatus == PaymentStatus.unpaid) {
        mismatchOrders.add(AuditOrderDetail(
          label: local.displayOrderTitle,
          subtitle: 'Shopify: paid · App: unpaid',
          sale: local,
          externalId: id,
        ));
        continue;
      }
      if (shopifyFinancial == 'refunded' &&
          local.paymentStatus != PaymentStatus.refunded) {
        mismatchOrders.add(AuditOrderDetail(
          label: local.displayOrderTitle,
          subtitle: 'Shopify: refunded · App: ${local.paymentStatus.name}',
          sale: local,
          externalId: id,
        ));
      }
    }

    if (mismatchOrders.isEmpty) {
      issues.add(const AuditIssue(
        title: 'Status Mismatches',
        description: 'All order statuses match between Shopify and app.',
        severity: IssueSeverity.ok,
        icon: Icons.swap_horiz_rounded,
      ));
    } else {
      issues.add(AuditIssue(
        title: 'Status Mismatches',
        description:
            '${mismatchOrders.length} order${mismatchOrders.length == 1 ? '' : 's'} '
            'with different status in Shopify vs app.',
        severity: IssueSeverity.warning,
        icon: Icons.swap_horiz_rounded,
        count: mismatchOrders.length,
        orders: mismatchOrders,
      ));
    }
  }

  // ── Check: Zero COGS orders ────────────────────────────

  void _checkZeroCostOrders(
    List<Sale> localSales,
    List<AuditIssue> issues,
  ) {
    final zeroCostOrders = <AuditOrderDetail>[];
    for (final sale in localSales) {
      if (!sale.isShopifyOrder) continue;
      if (sale.orderStatus == OrderStatus.cancelled) continue;
      if (sale.totalCogs == 0 && sale.items.isNotEmpty) {
        zeroCostOrders.add(AuditOrderDetail(
          label: sale.displayOrderTitle,
          subtitle: 'Revenue: ${_moneyFmt(sale.total)} · COGS: 0',
          sale: sale,
        ));
      }
    }

    if (zeroCostOrders.isEmpty) {
      issues.add(const AuditIssue(
        title: 'Missing Cost Prices',
        description: 'All Shopify orders have cost data for COGS.',
        severity: IssueSeverity.ok,
        icon: Icons.attach_money_rounded,
      ));
    } else {
      issues.add(AuditIssue(
        title: 'Missing Cost Prices',
        description:
            '${zeroCostOrders.length} order${zeroCostOrders.length == 1 ? '' : 's'} '
            'with zero COGS. Gross profit may be inaccurate.',
        severity: IssueSeverity.warning,
        icon: Icons.money_off_rounded,
        count: zeroCostOrders.length,
        orders: zeroCostOrders,
      ));
    }
  }

  // ── Check: Missing customer info ───────────────────────

  void _checkMissingCustomerInfo(
    List<Sale> localSales,
    List<AuditIssue> issues,
  ) {
    final missingOrders = <AuditOrderDetail>[];
    for (final sale in localSales) {
      if (!sale.isShopifyOrder) continue;
      if (sale.orderStatus == OrderStatus.cancelled) continue;
      if ((sale.customerName == null || sale.customerName!.isEmpty) &&
          (sale.customerPhone == null || sale.customerPhone!.isEmpty)) {
        missingOrders.add(AuditOrderDetail(
          label: sale.displayOrderTitle,
          subtitle: 'No name or phone · ${_moneyFmt(sale.total)}',
          sale: sale,
        ));
      }
    }

    if (missingOrders.isEmpty) {
      issues.add(const AuditIssue(
        title: 'Customer Data',
        description: 'All Shopify orders have customer info.',
        severity: IssueSeverity.ok,
        icon: Icons.person_outlined,
      ));
    } else {
      issues.add(AuditIssue(
        title: 'Missing Customer Info',
        description:
            '${missingOrders.length} order${missingOrders.length == 1 ? '' : 's'} '
            'without customer name or phone.',
        severity: IssueSeverity.warning,
        icon: Icons.person_off_outlined,
        count: missingOrders.length,
        orders: missingOrders,
      ));
    }
  }

  // ── Check: Unfulfilled paid orders ─────────────────────

  void _checkUnfulfilledPaidOrders(
    List<Sale> localSales,
    List<AuditIssue> issues,
  ) {
    final unfulfilledOrders = <AuditOrderDetail>[];
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
    for (final sale in localSales) {
      if (!sale.isShopifyOrder) continue;
      if (sale.orderStatus == OrderStatus.cancelled) continue;
      if (sale.paymentStatus == PaymentStatus.paid &&
          sale.fulfillmentStatus == FulfillmentStatus.unfulfilled &&
          sale.date.isBefore(threeDaysAgo)) {
        final days = DateTime.now().difference(sale.date).inDays;
        unfulfilledOrders.add(AuditOrderDetail(
          label: sale.displayOrderTitle,
          subtitle: 'Paid ${days}d ago · ${_moneyFmt(sale.total)}',
          sale: sale,
        ));
      }
    }

    if (unfulfilledOrders.isEmpty) {
      issues.add(const AuditIssue(
        title: 'Fulfillment',
        description: 'No stale unfulfilled paid orders.',
        severity: IssueSeverity.ok,
        icon: Icons.local_shipping_outlined,
      ));
    } else {
      issues.add(AuditIssue(
        title: 'Stale Unfulfilled Orders',
        description:
            '${unfulfilledOrders.length} paid order${unfulfilledOrders.length == 1 ? '' : 's'} '
            'unfulfilled for 3+ days.',
        severity: IssueSeverity.warning,
        icon: Icons.local_shipping_rounded,
        count: unfulfilledOrders.length,
        orders: unfulfilledOrders,
      ));
    }
  }

  static String _moneyFmt(double v) => v.toStringAsFixed(2);

  /// Imports missing orders from Shopify.
  ///
  /// Splits the period into 3-month chunks (the CF limit) so that
  /// even year-long audits import everything.
  Future<void> fixMissingOrders() async {
    if (!state.hasMissingOrders) return;

    state = ShopifyAuditResult(
      status: AuditStatus.fixing,
      fixProgress: 'Fetching orders from Shopify…',
      lastCheckedAt: state.lastCheckedAt,
      periodStart: _start,
      periodEnd: _end,
    );

    try {
      final syncService = ref.read(shopifySyncServiceProvider);

      // Split into 3-month windows to respect the CF max window.
      var chunkStart = _start;
      var chunkIndex = 0;
      final totalMonths =
          ((_end.difference(_start).inDays) / 90).ceil().clamp(1, 100);
      while (chunkStart.isBefore(_end)) {
        chunkIndex++;
        var chunkEnd = chunkStart.add(const Duration(days: 90));
        if (chunkEnd.isAfter(_end)) chunkEnd = _end;

        state = ShopifyAuditResult(
          status: AuditStatus.fixing,
          fixProgress: totalMonths > 1
              ? 'Importing chunk $chunkIndex/$totalMonths…'
              : 'Importing missing orders…',
          lastCheckedAt: state.lastCheckedAt,
          periodStart: _start,
          periodEnd: _end,
        );

        final result =
            await syncService.importOrders(from: chunkStart, to: chunkEnd);
        if (result.isSuccess) {
          developer.log(
            'Chunk $chunkIndex: imported=${result.data!.imported}, '
            'skipped=${result.data!.skipped}, errors=${result.data!.errors}',
            name: 'ShopifyAudit',
          );
        }
        chunkStart = chunkEnd.add(const Duration(seconds: 1));
      }

      state = ShopifyAuditResult(
        status: AuditStatus.fixing,
        fixProgress: 'Verifying…',
        lastCheckedAt: state.lastCheckedAt,
        periodStart: _start,
        periodEnd: _end,
      );

      try {
        await ref.read(salesProvider.notifier).refresh();
      } catch (_) {}

      await runAudit();
    } catch (e) {
      developer.log('Shopify audit fix error: $e', name: 'ShopifyAudit');
      state = ShopifyAuditResult(
        status: AuditStatus.error,
        errorMessage: 'Fix failed: $e',
        lastCheckedAt: DateTime.now(),
        periodStart: _start,
        periodEnd: _end,
      );
    }
  }

  /// Re-fetches each status-mismatched order from Shopify and
  /// updates the local sale (statuses, financials, fulfillment).
  Future<void> fixStatusMismatches() async {
    // Collect sale IDs from the mismatch issue.
    final mismatchIssue = state.issues
        .where((i) => i.title == 'Status Mismatches')
        .firstOrNull;
    if (mismatchIssue == null || mismatchIssue.orders.isEmpty) return;

    final ordersToFix =
        mismatchIssue.orders.where((o) => o.sale != null).toList();
    if (ordersToFix.isEmpty) return;

    state = ShopifyAuditResult(
      status: AuditStatus.fixing,
      fixProgress: 'Refreshing 0/${ordersToFix.length} orders…',
      lastCheckedAt: state.lastCheckedAt,
      periodStart: _start,
      periodEnd: _end,
    );

    try {
      final api = ref.read(shopifyApiServiceProvider);
      var fixed = 0;
      var errors = 0;

      for (final order in ordersToFix) {
        state = ShopifyAuditResult(
          status: AuditStatus.fixing,
          fixProgress:
              'Refreshing ${fixed + errors + 1}/${ordersToFix.length}: '
              '${order.label}',
          lastCheckedAt: state.lastCheckedAt,
          periodStart: _start,
          periodEnd: _end,
        );

        try {
          await api.refreshShopifyOrder(saleId: order.sale!.id);
          fixed++;
        } catch (e) {
          developer.log(
            'Failed to refresh ${order.sale!.id}: $e',
            name: 'ShopifyAudit',
          );
          errors++;
        }
      }

      developer.log(
        'Status fix: $fixed fixed, $errors errors',
        name: 'ShopifyAudit',
      );

      state = ShopifyAuditResult(
        status: AuditStatus.fixing,
        fixProgress: 'Verifying…',
        lastCheckedAt: state.lastCheckedAt,
        periodStart: _start,
        periodEnd: _end,
      );

      try {
        await ref.read(salesProvider.notifier).refresh();
      } catch (_) {}

      await runAudit();
    } catch (e) {
      developer.log('Shopify status fix error: $e', name: 'ShopifyAudit');
      state = ShopifyAuditResult(
        status: AuditStatus.error,
        errorMessage: 'Fix failed: $e',
        lastCheckedAt: DateTime.now(),
        periodStart: _start,
        periodEnd: _end,
      );
    }
  }
}

final shopifyAuditProvider =
    NotifierProvider<ShopifyAuditNotifier, ShopifyAuditResult>(
        ShopifyAuditNotifier.new);

// ═══════════════════════════════════════════════════════════
// SHIELD ICON WIDGET (navigates to full-screen audit)
// ═══════════════════════════════════════════════════════════

class ShopifyAuditShield extends ConsumerWidget {
  const ShopifyAuditShield({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isConnected = ref.watch(isShopifyConnectedProvider);
    if (!isConnected) return const SizedBox.shrink();

    final audit = ref.watch(shopifyAuditProvider);

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.pushNamed('ShopifyAuditScreen');
      },
      child: _ShieldBadge(audit: audit),
    );
  }
}

class _ShieldBadge extends StatelessWidget {
  final ShopifyAuditResult audit;
  const _ShieldBadge({required this.audit});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final int badgeCount;

    switch (audit.status) {
      case AuditStatus.idle:
        color = AppColors.textSecondary;
        icon = Icons.shield_outlined;
        badgeCount = 0;
      case AuditStatus.checking:
      case AuditStatus.fixing:
        color = const Color(0xFF7C3AED);
        icon = Icons.shield_outlined;
        badgeCount = 0;
      case AuditStatus.done:
        if (audit.criticalCount > 0) {
          color = AppColors.danger;
          icon = Icons.shield_rounded;
          badgeCount = audit.totalIssueItems;
        } else if (audit.warningCount > 0) {
          color = AppColors.accentOrange;
          icon = Icons.shield_rounded;
          badgeCount = audit.totalIssueItems;
        } else {
          color = AppColors.success;
          icon = Icons.verified_user_rounded;
          badgeCount = 0;
        }
      case AuditStatus.error:
        color = AppColors.danger;
        icon = Icons.shield_outlined;
        badgeCount = 0;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: audit.status == AuditStatus.checking ||
                  audit.status == AuditStatus.fixing
              ? SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon, color: color, size: 22),
        ),
        if (badgeCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(
                color: audit.criticalCount > 0
                    ? AppColors.danger
                    : AppColors.accentOrange,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : badgeCount.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// FULL-SCREEN AUDIT SCREEN
// ═══════════════════════════════════════════════════════════

class ShopifyAuditScreen extends ConsumerStatefulWidget {
  const ShopifyAuditScreen({super.key});

  @override
  ConsumerState<ShopifyAuditScreen> createState() => _ShopifyAuditScreenState();
}

class _ShopifyAuditScreenState extends ConsumerState<ShopifyAuditScreen> {
  int _selectedPeriodIndex = 3; // default: This Month
  DateTimeRange? _customRange;

  static final _df = DateFormat('MMM d');
  static final _dfYear = DateFormat('MMM d, yyyy');

  List<String> get _periods => [
        'Today',
        'Yesterday',
        'This Week',
        'This Month',
        'Last Month',
        'This Year',
        'Custom',
      ];

  (DateTime, DateTime) get _periodBounds {
    // Use the store timezone for period boundaries so they match Shopify.
    // TZDateTime objects preserve the offset so .toUtc().toIso8601String()
    // produces an explicit UTC timestamp that Shopify interprets correctly.
    late final DateTime now;
    tz.Location? loc;
    final shopTz =
        ref.read(shopifyConnectionProvider).value?.shopTimezone;
    if (shopTz != null) {
      try {
        loc = tz.getLocation(shopTz);
        now = tz.TZDateTime.now(loc);
      } catch (_) {
        now = DateTime.now();
      }
    } else {
      now = DateTime.now();
    }

    DateTime dt(int y, int m, int d, [int h = 0, int min = 0, int s = 0]) =>
        loc != null ? tz.TZDateTime(loc, y, m, d, h, min, s) : DateTime(y, m, d, h, min, s);

    switch (_selectedPeriodIndex) {
      case 0: // Today
        return (
          dt(now.year, now.month, now.day),
          dt(now.year, now.month, now.day, 23, 59, 59),
        );
      case 1: // Yesterday
        final y = now.subtract(const Duration(days: 1));
        return (
          dt(y.year, y.month, y.day),
          dt(y.year, y.month, y.day, 23, 59, 59),
        );
      case 2: // This Week
        final monday = now.subtract(Duration(days: now.weekday - 1));
        return (
          dt(monday.year, monday.month, monday.day),
          dt(now.year, now.month, now.day, 23, 59, 59),
        );
      case 3: // This Month
        return (
          dt(now.year, now.month, 1),
          dt(now.year, now.month, now.day, 23, 59, 59),
        );
      case 4: // Last Month
        final lastMonthStart = DateTime(now.year, now.month - 1, 1);
        final lastMonthEnd = DateTime(now.year, now.month, 0);
        return (
          dt(lastMonthStart.year, lastMonthStart.month, lastMonthStart.day),
          dt(lastMonthEnd.year, lastMonthEnd.month, lastMonthEnd.day, 23, 59, 59),
        );
      case 5: // This Year
        return (
          dt(now.year, 1, 1),
          dt(now.year, now.month, now.day, 23, 59, 59),
        );
      case 6: // Custom
        if (_customRange != null) {
          final s = _customRange!.start;
          final e = _customRange!.end;
          return (
            dt(s.year, s.month, s.day),
            dt(e.year, e.month, e.day, 23, 59, 59),
          );
        }
        return (
          dt(now.year, now.month, 1),
          dt(now.year, now.month, now.day, 23, 59, 59),
        );
      default:
        return (
          dt(now.year, now.month, 1),
          dt(now.year, now.month, now.day, 23, 59, 59),
        );
    }
  }

  void _selectPeriod(int index) {
    if (index == 6) {
      _pickCustomRange();
      return;
    }
    setState(() => _selectedPeriodIndex = index);
    _runAuditForPeriod();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primaryNavy,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        _customRange = picked;
        _selectedPeriodIndex = 6;
      });
      _runAuditForPeriod();
    }
  }

  void _runAuditForPeriod() {
    final (start, end) = _periodBounds;
    ref.read(shopifyAuditProvider.notifier).auditPeriod(start, end);
  }

  String _formatRange(DateTime start, DateTime end) {
    if (start.year != end.year) {
      return '${_dfYear.format(start)} – ${_dfYear.format(end)}';
    }
    return '${_df.format(start)} – ${_df.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final audit = ref.watch(shopifyAuditProvider);

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context, audit),
            _buildPeriodPills(),
            if (audit.periodStart != null && audit.periodEnd != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.date_range_rounded,
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 6),
                    Text(
                      _formatRange(audit.periodStart!, audit.periodEnd!),
                      style: AppTypography.captionSmall.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                    const Spacer(),
                    if (audit.lastCheckedAt != null)
                      Text(
                        _timeAgo(audit.lastCheckedAt!),
                        style: AppTypography.captionSmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
            Expanded(child: _buildBody(audit)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ShopifyAuditResult audit) {
    final Color statusColor;
    final IconData statusIcon;

    if (audit.status == AuditStatus.done && audit.allGood) {
      statusColor = AppColors.success;
      statusIcon = Icons.verified_user_rounded;
    } else if (audit.criticalCount > 0) {
      statusColor = AppColors.danger;
      statusIcon = Icons.error_rounded;
    } else if (audit.warningCount > 0) {
      statusColor = AppColors.accentOrange;
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = const Color(0xFF7C3AED);
      statusIcon = Icons.shield_outlined;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
              color: AppColors.borderLight.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.safePop(),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.primaryNavy,
          ),
          Icon(statusIcon, color: statusColor, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sync Audit',
              style: AppTypography.h1.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          IconButton(
            onPressed: _runAuditForPeriod,
            icon: const Icon(Icons.refresh_rounded, size: 22),
            color: AppColors.textSecondary,
            tooltip: 'Re-run audit',
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodPills() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
      child: SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _periods.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final selected = i == _selectedPeriodIndex;
            return GestureDetector(
              onTap: () => _selectPeriod(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryNavy
                      : AppColors.primaryNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _selectedPeriodIndex == 6 && i == 6 && _customRange != null
                      ? '${_df.format(_customRange!.start)} – ${_df.format(_customRange!.end)}'
                      : _periods[i],
                  style: TextStyle(
                    color:
                        selected ? Colors.white : AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(ShopifyAuditResult audit) {
    if (audit.status == AuditStatus.checking ||
        audit.status == AuditStatus.fixing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(height: 16),
            Text(
              audit.status == AuditStatus.fixing
                  ? (audit.fixProgress ?? 'Fixing…')
                  : 'Running audit checks…',
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (audit.status == AuditStatus.error) {
      return _ErrorView(
        message: audit.errorMessage ?? 'Unknown error',
        onRetry: _runAuditForPeriod,
      );
    }

    if (audit.status == AuditStatus.idle) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_outlined,
                size: 56, color: AppColors.textTertiary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'Select a period and run the audit',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _runAuditForPeriod,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: const Text('Run Audit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryNavy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    // Done — show results
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        _SummaryRow(audit: audit),
        const SizedBox(height: 20),
        ..._buildIssueCards(audit),
      ],
    );
  }

  List<Widget> _buildIssueCards(ShopifyAuditResult audit) {
    if (audit.issues.isEmpty) {
      return [
        const Padding(
          padding: EdgeInsets.only(top: 40),
          child: Center(
            child: Text('No checks run yet.',
                style: TextStyle(color: AppColors.textTertiary)),
          ),
        ),
      ];
    }

    final sorted = [...audit.issues]..sort((a, b) {
        const order = {
          IssueSeverity.critical: 0,
          IssueSeverity.warning: 1,
          IssueSeverity.ok: 2,
        };
        return order[a.severity]!.compareTo(order[b.severity]!);
      });

    return sorted.map((issue) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _IssueCard(issue: issue, ref: ref),
      );
    }).toList();
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 10) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ── Summary row ─────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final ShopifyAuditResult audit;
  const _SummaryRow({required this.audit});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SummaryCard(
          label: 'Shopify',
          value: audit.shopifyOrderCount.toString(),
          icon: Icons.shopping_bag_outlined,
          color: const Color(0xFF7C3AED),
        ),
        const SizedBox(width: 10),
        _SummaryCard(
          label: 'Synced',
          value: '${audit.localShopifyCount}/${audit.shopifyOrderCount}',
          icon: Icons.sync_rounded,
          color: audit.localShopifyCount == audit.shopifyOrderCount
              ? AppColors.success
              : AppColors.primaryNavy,
        ),
        const SizedBox(width: 10),
        _SummaryCard(
          label: 'Checks',
          value: '${audit.okCount}/${audit.issues.length}',
          icon: audit.allGood
              ? Icons.check_circle_outline_rounded
              : Icons.pending_outlined,
          color: audit.allGood ? AppColors.success : AppColors.accentOrange,
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.1)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTypography.h2.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTypography.captionSmall.copyWith(
                color: color.withValues(alpha: 0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Issue card ──────────────────────────────────────────

class _IssueCard extends StatefulWidget {
  final AuditIssue issue;
  final WidgetRef ref;

  const _IssueCard({required this.issue, required this.ref});

  @override
  State<_IssueCard> createState() => _IssueCardState();
}

class _IssueCardState extends State<_IssueCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  static const int _collapsedMax = 5;

  AuditIssue get issue => widget.issue;
  WidgetRef get ref => widget.ref;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final Color bgColor;
    final String badge;

    switch (issue.severity) {
      case IssueSeverity.ok:
        color = AppColors.success;
        bgColor = AppColors.success.withValues(alpha: 0.04);
        badge = 'OK';
      case IssueSeverity.warning:
        color = AppColors.accentOrange;
        bgColor = AppColors.accentOrange.withValues(alpha: 0.04);
        badge = 'Warning';
      case IssueSeverity.critical:
        color = AppColors.danger;
        bgColor = AppColors.danger.withValues(alpha: 0.04);
        badge = 'Critical';
    }

    final hasOrders = issue.orders.isNotEmpty;
    final canExpand = hasOrders && issue.severity != IssueSeverity.ok;

    return GestureDetector(
      onTap: canExpand
          ? () {
              HapticFeedback.selectionClick();
              setState(() => _expanded = !_expanded);
            }
          : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──
            Row(
              children: [
                Icon(issue.icon, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    issue.title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    issue.count > 0 ? '$badge · ${issue.count}' : badge,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (canExpand) ...[
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: color,
                      size: 20,
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 8),
            Text(
              issue.description,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),

            // ── Expanded order list ──
            if (_expanded && hasOrders) ...[
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: color.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < _visibleCount; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: AppColors.dividerLight,
                        ),
                      _buildOrderRow(issue.orders[i], color),
                    ],
                    if (issue.orders.length > _collapsedMax) ...[
                      Divider(
                        height: 1,
                        color: AppColors.dividerLight,
                      ),
                      _buildShowAllToggle(color),
                    ],
                  ],
                ),
              ),
            ],

            // ── Fix buttons ──
            if (issue.title == 'Missing Orders' &&
                issue.severity == IssueSeverity.critical) ...[
              const SizedBox(height: 12),
              _buildFixButton(
                label:
                    'Import ${issue.count} Missing Order${issue.count == 1 ? '' : 's'}',
                color: AppColors.danger,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(shopifyAuditProvider.notifier).fixMissingOrders();
                },
              ),
            ],
            if (issue.title == 'Status Mismatches' &&
                issue.severity == IssueSeverity.warning) ...[
              const SizedBox(height: 12),
              _buildFixButton(
                label: 'Re-sync ${issue.count} Mismatched Order${issue.count == 1 ? '' : 's'}',
                color: AppColors.accentOrange,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  ref.read(shopifyAuditProvider.notifier).fixStatusMismatches();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool _showAll = false;

  int get _visibleCount {
    if (_showAll || issue.orders.length <= _collapsedMax) {
      return issue.orders.length;
    }
    return _collapsedMax;
  }

  Widget _buildOrderRow(AuditOrderDetail order, Color color) {
    final canNavigate = order.sale != null;
    return InkWell(
      onTap: canNavigate
          ? () {
              HapticFeedback.selectionClick();
              context.pushNamed(
                'SaleDetailScreen',
                extra: {'sale': order.sale},
              );
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                canNavigate ? Icons.receipt_long_rounded : Icons.cloud_outlined,
                size: 14,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.label,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (order.subtitle.isNotEmpty)
                    Text(
                      order.subtitle,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                ],
              ),
            ),
            if (canNavigate)
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildShowAllToggle(Color color) {
    final remaining = issue.orders.length - _collapsedMax;
    return InkWell(
      onTap: () => setState(() => _showAll = !_showAll),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Text(
            _showAll
                ? 'Show less'
                : 'Show $remaining more order${remaining == 1 ? '' : 's'}',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFixButton({
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.sync_rounded, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

// ── Error view ──────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded,
              size: 48, color: AppColors.danger.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            'Audit Failed',
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryNavy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
