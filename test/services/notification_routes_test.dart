import 'package:flutter_test/flutter_test.dart';
import 'package:revvo_app/core/services/notification_routes.dart';

void main() {
  group('notifications land on the screen that answers them', () {
    test('stock alerts deep-link to the product when an id is given', () {
      final r = notificationRouteFor(
          'stockout_forecast', {'product_id': 'p123'});
      expect(r!.path, '/inventory/detail');
      expect((r.extra as Map)['productId'], 'p123');
    });

    test('stock alerts fall back to the inventory list without an id', () {
      // Aggregated alerts ("3 items low") name no single product.
      final r = notificationRouteFor('low_stock', {});
      expect(r!.path, '/manage/inventory');
      expect(r.extra, isNull);
    });

    test('cash crunch opens Cash & Bank', () {
      expect(notificationRouteFor('cash_crunch', {})!.path,
          '/reports/cash-bank');
    });

    test('each due-type opens its own dashboard', () {
      expect(notificationRouteFor('accrued_due', {})!.path,
          '/reports/accrued-expenses');
      expect(notificationRouteFor('gateway_overdue', {})!.path,
          '/reports/gateway-receivables');
      expect(notificationRouteFor('salary_unpaid', {})!.path,
          '/reports/salaries');
      expect(notificationRouteFor('supplier_due', {})!.path,
          '/manage/suppliers');
    });

    test('delivery alerts open the RTO list, payout opens Bosta', () {
      expect(notificationRouteFor('repeat_refuser', {})!.path,
          '/manage/bosta/rto-orders');
      expect(notificationRouteFor('rto_spike', {})!.path,
          '/manage/bosta/rto-orders');
      expect(notificationRouteFor('payout_overdue', {})!.path,
          '/manage/bosta/dashboard');
    });

    test('cashout gap opens gateway receivables', () {
      expect(notificationRouteFor('cashout_gap', {})!.path,
          '/reports/gateway-receivables');
    });
  });

  group('graceful fallbacks', () {
    test('an unknown type opens the inbox rather than dead-ending', () {
      // Forward compatibility: a NEW server alert on an OLD app build.
      final r = notificationRouteFor('some_future_alert', {});
      expect(r!.path, '/notifications');
    });

    test('digest and integrity nudges open the inbox', () {
      expect(notificationRouteFor('weekly_digest', {})!.path, '/notifications');
      expect(
          notificationRouteFor('integrity_nudge', {})!.path, '/notifications');
    });

    test('a missing type navigates nowhere', () {
      expect(notificationRouteFor(null, {}), isNull);
    });

    test('an empty product_id does not build a broken detail route', () {
      final r = notificationRouteFor('low_stock', {'product_id': ''});
      expect(r!.path, '/manage/inventory');
    });
  });

  group('existing notification types keep working', () {
    test('sales and shopify orders', () {
      expect(notificationRouteFor('sale_created', {})!.path, '/sales');
      expect(
          notificationRouteFor('shopify_order_created', {})!.path, '/sales');
    });

    test('billing types open the subscription screen', () {
      for (final t in [
        'payment_success',
        'subscription_expired',
        'pre_expiry_3d',
      ]) {
        expect(notificationRouteFor(t, {})!.path, '/profile/subscription',
            reason: t);
      }
    });
  });
}
