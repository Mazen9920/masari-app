import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../shared/models/product_model.dart';
import '../../shared/models/sale_model.dart';
import 'app_providers.dart';
import 'app_settings_provider.dart';
import 'notification_settings_provider.dart';
import '../../features/cash_flow/providers/scheduled_transactions_provider.dart';

// ═════════════════════════════════════════════════════════
//  Notification Model
// ═════════════════════════════════════════════════════════

enum NotificationType { alert, update }

class AppNotification {
  final String id;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String subtitle;
  final DateTime createdAt;
  final NotificationType type;
  final String? routeName;
  final Map<String, dynamic>? routeExtra;
  final Map<String, String> params;

  const AppNotification({
    required this.id,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.createdAt,
    required this.type,
    this.routeName,
    this.routeExtra,
    this.params = const {},
  });

  /// Returns the localized title based on notification kind (id prefix).
  String localizedTitle(AppLocalizations l10n) {
    if (id.startsWith('oos_')) return l10n.notifOutOfStockTitle(params['name'] ?? '');
    if (id.startsWith('low_')) return l10n.notifLowStockTitle(params['name'] ?? '');
    if (id.startsWith('purch_overdue_')) return l10n.notifOverdueTitle(params['name'] ?? '');
    if (id.startsWith('purch_due_')) return l10n.notifPaymentDueTitle(params['name'] ?? '');
    if (id.startsWith('sale_out_')) return l10n.notifUnpaidSaleTitle(params['name'] ?? '');
    if (id == 'sales_outstanding') return l10n.notifUnpaidSalesTitle(params['count'] ?? '');
    if (id.startsWith('sched_overdue_')) return l10n.notifScheduledOverdueTitle(params['title'] ?? '');
    if (id.startsWith('sched_soon_')) return l10n.notifScheduledUpcomingTitle(params['title'] ?? '');
    return title;
  }

  /// Returns the localized subtitle based on notification kind (id prefix).
  String localizedSubtitle(AppLocalizations l10n) {
    if (id.startsWith('oos_')) return l10n.notifOutOfStockSubtitle;
    if (id.startsWith('low_')) {
      final vNames = params['variantNames'];
      final vStocks = params['variantStocks'];
      if (vNames != null && vNames.isNotEmpty) {
        final names = vNames.split('|');
        final stocks = vStocks?.split('|') ?? [];
        final detail = List.generate(
          names.length,
          (i) => l10n.notifVariantStockLeft(names[i], i < stocks.length ? stocks[i] : '0'),
        ).join(', ');
        if (detail.isNotEmpty) return detail;
      }
      return l10n.notifUnitsRemaining(params['count'] ?? '0');
    }
    if (id.startsWith('purch_overdue_')) {
      return l10n.notifOverdueSubtitle(params['currency'] ?? '', params['amount'] ?? '', params['days'] ?? '', params['ref'] ?? '');
    }
    if (id.startsWith('purch_due_')) {
      return l10n.notifPaymentDueSubtitle(params['currency'] ?? '', params['amount'] ?? '', params['days'] ?? '', params['ref'] ?? '');
    }
    if (id.startsWith('sale_out_')) {
      return l10n.notifOutstandingFrom(params['currency'] ?? '', params['amount'] ?? '', params['date'] ?? '');
    }
    if (id == 'sales_outstanding') {
      return l10n.notifTotalOutstanding(params['currency'] ?? '', params['amount'] ?? '');
    }
    if (id.startsWith('sched_overdue_')) {
      final type = params['isIncome'] == 'true' ? l10n.income : l10n.expense;
      return l10n.notifScheduledOverdueSubtitle(type, params['currency'] ?? '', params['amount'] ?? '', params['date'] ?? '');
    }
    if (id.startsWith('sched_soon_')) {
      final type = params['isIncome'] == 'true' ? l10n.income : l10n.expense;
      if (params['daysUntil'] == '0') {
        return l10n.notifScheduledDueToday(type, params['currency'] ?? '', params['amount'] ?? '');
      }
      return l10n.notifScheduledDueInDays(type, params['currency'] ?? '', params['amount'] ?? '', params['daysUntil'] ?? '');
    }
    return subtitle;
  }
}

// ═════════════════════════════════════════════════════════
//  Derived Notifications Provider
// ═════════════════════════════════════════════════════════

final notificationsProvider = Provider<List<AppNotification>>((ref) {
  final settings = ref.watch(notificationSettingsProvider);
  final currency = ref.watch(appSettingsProvider).currency;
  final fmt = NumberFormat('#,##0', 'en');
  final now = DateTime.now();
  final notifications = <AppNotification>[];

  // ─── 1. Low stock alerts ────────────────────────────
  if (settings.lowStockAlerts) {
    final products = ref.watch(filteredInventoryProvider).value ?? [];
    for (final p in products) {
      if (p.status == StockStatus.outOfStock) {
        notifications.add(AppNotification(
          id: 'oos_${p.id}',
          icon: Icons.error_outline_rounded,
          iconColor: const Color(0xFFEF4444),
          iconBg: const Color(0xFFFEE2E2),
          title: '${p.name} — Out of Stock',
          subtitle: 'All variants are out of stock. Reorder now to avoid lost sales.',
          createdAt: now,
          type: NotificationType.alert,
          routeName: 'ProductDetailScreen',
          routeExtra: {'productId': p.id},
          params: {'name': p.name},
        ));
      } else if (p.status == StockStatus.lowStock) {
        final lowVariants = p.variants.where(
            (v) => v.status == StockStatus.lowStock || v.status == StockStatus.outOfStock);
        final detail = lowVariants.map((v) => '${v.displayName}: ${v.currentStock} left').join(', ');
        notifications.add(AppNotification(
          id: 'low_${p.id}',
          icon: Icons.inventory_2_outlined,
          iconColor: const Color(0xFFF59E0B),
          iconBg: const Color(0xFFFEF3C7),
          title: '${p.name} — Low Stock',
          subtitle: detail.isNotEmpty ? detail : '${p.currentStock} units remaining',
          createdAt: now,
          type: NotificationType.alert,
          routeName: 'ProductDetailScreen',
          routeExtra: {'productId': p.id},
          params: {
            'name': p.name,
            'count': '${p.currentStock}',
            'variantNames': lowVariants.map((v) => v.displayName).join('|'),
            'variantStocks': lowVariants.map((v) => '${v.currentStock}').join('|'),
          },
        ));
      }
    }
  }

  // ─── 2. Purchase payment reminders ──────────────────
  if (settings.paymentReminders) {
    final purchases = ref.watch(purchasesProvider).value ?? [];
    final suppliers = ref.watch(suppliersProvider).value ?? [];
    for (final p in purchases) {
      if (p.paymentStatus == 2) continue; // fully paid
      if (p.outstanding <= 0) continue;

      final supplier = suppliers.where((s) => s.id == p.supplierId).firstOrNull;

      final overdue = p.dueDate != null && p.dueDate!.isBefore(now);
      final dueSoon = p.dueDate != null &&
          !p.dueDate!.isBefore(now) &&
          p.dueDate!.difference(now).inDays <= 7;

      if (overdue) {
        final daysLate = now.difference(p.dueDate!).inDays;
        notifications.add(AppNotification(
          id: 'purch_overdue_${p.id}',
          icon: Icons.warning_amber_rounded,
          iconColor: const Color(0xFFEF4444),
          iconBg: const Color(0xFFFEE2E2),
          title: 'Overdue: ${p.supplierName}',
          subtitle:
              '$currency ${fmt.format(p.outstanding)} outstanding — $daysLate day${daysLate == 1 ? '' : 's'} past due (Ref: ${p.referenceNo})',
          createdAt: p.dueDate!,
          type: NotificationType.alert,
          routeName: 'PurchaseDetailScreen',
          routeExtra: {'purchase': p, 'supplier': ?supplier},
          params: {'name': p.supplierName, 'currency': currency, 'amount': fmt.format(p.outstanding), 'days': '$daysLate', 'ref': p.referenceNo},
        ));
      } else if (dueSoon) {
        final daysLeft = p.dueDate!.difference(now).inDays;
        notifications.add(AppNotification(
          id: 'purch_due_${p.id}',
          icon: Icons.payments_outlined,
          iconColor: const Color(0xFFF59E0B),
          iconBg: const Color(0xFFFEF3C7),
          title: 'Payment Due: ${p.supplierName}',
          subtitle:
              '$currency ${fmt.format(p.outstanding)} due in $daysLeft day${daysLeft == 1 ? '' : 's'} (Ref: ${p.referenceNo})',
          createdAt: now,
          type: NotificationType.alert,
          routeName: 'PurchaseDetailScreen',
          routeExtra: {'purchase': p, 'supplier': ?supplier},
          params: {'name': p.supplierName, 'currency': currency, 'amount': fmt.format(p.outstanding), 'days': '$daysLeft', 'ref': p.referenceNo},
        ));
      }
    }
  }

  // ─── 3. Outstanding sales ───────────────────────────
  {
    final sales = ref.watch(salesProvider).value ?? [];
    final outstandingSales = sales.where((s) =>
        s.orderStatus != OrderStatus.cancelled &&
        s.paymentStatus != PaymentStatus.paid &&
        s.paymentStatus != PaymentStatus.refunded &&
        s.outstanding > 0).toList();

    if (outstandingSales.length == 1) {
      final s = outstandingSales.first;
      notifications.add(AppNotification(
        id: 'sale_out_${s.id}',
        icon: Icons.receipt_long_outlined,
        iconColor: const Color(0xFF3B82F6),
        iconBg: const Color(0xFFDBEAFE),
        title: 'Unpaid Sale: ${s.customerName ?? 'Walk-in'}',
        subtitle: '$currency ${fmt.format(s.outstanding)} outstanding from ${DateFormat('dd MMM').format(s.date)}',
        createdAt: s.date,
        type: NotificationType.update,
        routeName: 'SaleDetailScreen',
        routeExtra: {'sale': s},
        params: {'name': s.customerName ?? 'Walk-in', 'currency': currency, 'amount': fmt.format(s.outstanding), 'date': DateFormat('dd MMM').format(s.date)},
      ));
    } else if (outstandingSales.length > 1) {
      final totalOutstanding =
          outstandingSales.fold<double>(0, (sum, s) => sum + s.outstanding);
      notifications.add(AppNotification(
        id: 'sales_outstanding',
        icon: Icons.receipt_long_outlined,
        iconColor: const Color(0xFF3B82F6),
        iconBg: const Color(0xFFDBEAFE),
        title: '${outstandingSales.length} Unpaid Sales',
        subtitle: '$currency ${fmt.format(totalOutstanding)} total outstanding',
        createdAt: now,
        type: NotificationType.update,
        params: {'count': '${outstandingSales.length}', 'currency': currency, 'amount': fmt.format(totalOutstanding)},
      ));
    }
  }

  // ─── 4. Upcoming scheduled transactions ─────────────
  {
    final scheduled = ref.watch(scheduledTransactionsProvider);
    for (final st in scheduled) {
      if (!st.isActive) continue;
      final daysUntil = st.nextDueDate.difference(now).inDays;
      if (daysUntil < 0) {
        // Overdue
        notifications.add(AppNotification(
          id: 'sched_overdue_${st.id}',
          icon: Icons.event_busy_rounded,
          iconColor: const Color(0xFFEF4444),
          iconBg: const Color(0xFFFEE2E2),
          title: 'Overdue: ${st.title}',
          subtitle:
              '${st.isIncome ? "Income" : "Expense"} of $currency ${fmt.format(st.amount)} was due ${DateFormat('dd MMM').format(st.nextDueDate)}',
          createdAt: st.nextDueDate,
          type: NotificationType.alert,
          routeName: 'ScheduledTransactionsScreen',
          params: {'title': st.title, 'isIncome': '${st.isIncome}', 'currency': currency, 'amount': fmt.format(st.amount), 'date': DateFormat('dd MMM').format(st.nextDueDate)},
        ));
      } else if (daysUntil <= 3) {
        notifications.add(AppNotification(
          id: 'sched_soon_${st.id}',
          icon: Icons.event_outlined,
          iconColor: const Color(0xFF8B5CF6),
          iconBg: const Color(0xFFEDE9FE),
          title: 'Upcoming: ${st.title}',
          subtitle: daysUntil == 0
              ? '${st.isIncome ? "Income" : "Expense"} of $currency ${fmt.format(st.amount)} due today'
              : '${st.isIncome ? "Income" : "Expense"} of $currency ${fmt.format(st.amount)} due in $daysUntil day${daysUntil == 1 ? '' : 's'}',
          createdAt: now,
          type: NotificationType.update,
          routeName: 'ScheduledTransactionsScreen',
          params: {'title': st.title, 'isIncome': '${st.isIncome}', 'currency': currency, 'amount': fmt.format(st.amount), 'daysUntil': '$daysUntil'},
        ));
      }
    }
  }

  // Sort: alerts first, then by date descending
  notifications.sort((a, b) {
    if (a.type == NotificationType.alert && b.type != NotificationType.alert) return -1;
    if (b.type == NotificationType.alert && a.type != NotificationType.alert) return 1;
    return b.createdAt.compareTo(a.createdAt);
  });

  return notifications;
});

// ═════════════════════════════════════════════════════════
//  Server Inbox — notifications/{uid}/items written by Cloud Functions
// ═════════════════════════════════════════════════════════
// Server items arrive pre-localized (built per users/{uid}.locale), so the
// title/body render as-is; `read` lives on the document, not in
// SharedPreferences, and survives reinstalls.

const _serverIdPrefix = 'srv_';

/// True for items backed by a Firestore inbox document.
bool isServerNotification(AppNotification n) => n.id.startsWith(_serverIdPrefix);

({IconData icon, Color color, Color bg}) _serverStyle(String category) {
  switch (category) {
    case 'low_stock':
      return (icon: Icons.inventory_2_outlined,
              color: const Color(0xFFEF4444), bg: const Color(0xFFFEF2F2));
    case 'payment_reminders':
      return (icon: Icons.payments_outlined,
              color: const Color(0xFFF59E0B), bg: const Color(0xFFFFFBEB));
    case 'deliveries':
      return (icon: Icons.local_shipping_outlined,
              color: const Color(0xFF6366F1), bg: const Color(0xFFEEF2FF));
    case 'insights':
      return (icon: Icons.insights_rounded,
              color: const Color(0xFF14B8A6), bg: const Color(0xFFF0FDFA));
    case 'weekly_digest':
      return (icon: Icons.summarize_outlined,
              color: const Color(0xFF22C55E), bg: const Color(0xFFF0FDF4));
    case 'data_integrity':
      return (icon: Icons.fact_check_outlined,
              color: const Color(0xFF64748B), bg: const Color(0xFFF8FAFC));
    default:
      return (icon: Icons.notifications_none_rounded,
              color: const Color(0xFF0EA5E9), bg: const Color(0xFFF0F9FF));
  }
}

/// Live stream of the persisted inbox (newest 100).
final serverNotificationsProvider =
    StreamProvider<List<AppNotification>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const []);
  return FirebaseFirestore.instance
      .collection('notifications')
      .doc(uid)
      .collection('items')
      .orderBy('created_at', descending: true)
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs.map((doc) {
            final d = doc.data();
            final category = d['category'] as String? ?? 'general';
            final style = _serverStyle(category);
            final created = d['created_at'];
            final urgent = const {
              'low_stock', 'payment_reminders', 'deliveries', 'data_integrity'
            }.contains(category);
            final data = (d['data'] as Map<String, dynamic>? ?? {});
            return AppNotification(
              id: '$_serverIdPrefix${doc.id}',
              icon: style.icon,
              iconColor: style.color,
              iconBg: style.bg,
              title: d['title'] as String? ?? '',
              subtitle: d['body'] as String? ?? '',
              createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
              type: urgent ? NotificationType.alert : NotificationType.update,
              params: {
                'serverType': d['type'] as String? ?? '',
                'read': (d['read'] as bool? ?? false) ? 'true' : 'false',
                for (final e in data.entries) e.key: e.value.toString(),
              },
            );
          }).toList());
});

/// Marks a server inbox item read (the only field clients may change).
Future<void> markServerNotificationRead(String prefixedId) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final docId = prefixedId.replaceFirst(_serverIdPrefix, '');
  try {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc(docId)
        .update({'read': true});
  } catch (_) {
    // Best-effort; the stream will resync on next snapshot anyway.
  }
}

/// Derived + server feeds merged, alerts first then newest.
final mergedNotificationsProvider = Provider<List<AppNotification>>((ref) {
  final derived = ref.watch(notificationsProvider);
  final server = ref.watch(serverNotificationsProvider).value ?? const [];
  final all = [...server, ...derived];
  all.sort((a, b) {
    if (a.type == NotificationType.alert && b.type != NotificationType.alert) return -1;
    if (b.type == NotificationType.alert && a.type != NotificationType.alert) return 1;
    return b.createdAt.compareTo(a.createdAt);
  });
  return all;
});

/// Count of unread notifications — used for badge on bell icon.
final notificationCountProvider = Provider<int>((ref) {
  final all = ref.watch(mergedNotificationsProvider);
  final readIds = ref.watch(readNotificationIdsProvider);
  return all.where((n) {
    // Server items carry their read state on the document.
    if (isServerNotification(n)) return n.params['read'] != 'true';
    return !readIds.contains(n.id);
  }).length;
});

// ═════════════════════════════════════════════════════════
//  Read State — persisted via SharedPreferences
// ═════════════════════════════════════════════════════════

final readNotificationIdsProvider =
    NotifierProvider<ReadNotificationIdsNotifier, Set<String>>(
        () => ReadNotificationIdsNotifier());

class ReadNotificationIdsNotifier extends Notifier<Set<String>> {
  static const _legacyKey = 'read_notification_ids';

  /// User-scoped, matching every other pref key — the legacy shared key let
  /// read state leak between accounts on a shared device.
  String get _key {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
    return '${uid}_$_legacyKey';
  }

  @override
  Set<String> build() {
    _load();
    return {};
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_key) ?? [];
    // One-time migration of the old unscoped key.
    final legacy = prefs.getStringList(_legacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      state = {...ids, ...legacy};
      await prefs.setStringList(_key, state.toList());
      await prefs.remove(_legacyKey);
      return;
    }
    state = ids.toSet();
  }

  void markRead(String id) {
    state = {...state, id};
    _save();
  }

  void markAllRead(List<String> ids) {
    state = {...state, ...ids};
    _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, state.toList());
  }
}
