/// notification_routes.dart — maps a push notification's `data.type` to the
/// screen that answers it.
///
/// The server attaches `{type, ...hints}` to every push; tapping should land
/// the user on the screen where they can ACT (pay, reorder, review) — not on
/// a generic home screen. Kept as a pure function so it's unit-testable
/// without Firebase.
library;

/// A resolved navigation target: a GoRouter path plus optional `extra`.
typedef NotificationRoute = ({String path, Object? extra});

/// Resolves [type] (+ payload [data]) to a route, or null to stay put.
///
/// Unknown types fall back to the notifications inbox, so a NEW server alert
/// type never dead-ends an OLD app version — worst case the user lands on the
/// inbox where the item is readable.
NotificationRoute? notificationRouteFor(
    String? type, Map<String, dynamic> data) {
  switch (type) {
    // ── Inventory ──
    case 'low_stock':
    case 'stockout_forecast':
    case 'margin_erosion':
    case 'dead_capital':
      final productId = data['product_id'] as String?;
      if (productId != null && productId.isNotEmpty) {
        return (path: '/inventory/detail', extra: {'productId': productId});
      }
      return (path: '/manage/inventory', extra: null);

    // ── Cash flow ──
    case 'cash_crunch':
      return (path: '/reports/cash-bank', extra: null);
    case 'accrued_due':
      return (path: '/reports/accrued-expenses', extra: null);
    case 'gateway_overdue':
    case 'cashout_gap':
      return (path: '/reports/gateway-receivables', extra: null);
    case 'salary_unpaid':
      return (path: '/reports/salaries', extra: null);
    case 'supplier_due':
      return (path: '/manage/suppliers', extra: null);

    // ── Deliveries ──
    case 'repeat_refuser':
    case 'rto_spike':
      return (path: '/manage/bosta/rto-orders', extra: null);
    case 'payout_overdue':
      return (path: '/manage/bosta/dashboard', extra: null);

    // ── Sales / orders ──
    case 'sale_created':
    case 'shopify_order_created':
    case 'shopify_order_cancelled':
    case 'vip_customer':
    case 'no_orders':
      return (path: '/sales', extra: null);

    // ── Billing ──
    case 'payment_success':
    case 'auto_renewal_success':
    case 'subscription_expired':
    case 'subscription_grace':
    case 'pre_expiry_3d':
    case 'pre_expiry_1d':
      return (path: '/profile/subscription', extra: null);

    case null:
      return null;

    // Digest, integrity nudges, and anything this app version doesn't know.
    default:
      return (path: '/notifications', extra: null);
  }
}
