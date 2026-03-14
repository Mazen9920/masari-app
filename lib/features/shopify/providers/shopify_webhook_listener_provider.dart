import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'shopify_connection_provider.dart';

/// Represents a real-time webhook event for the UI.
class ShopifyWebhookEvent {
  final String topic;
  final String? shopifyOrderId;
  final String? message;
  final DateTime receivedAt;

  const ShopifyWebhookEvent({
    required this.topic,
    this.shopifyOrderId,
    this.message,
    required this.receivedAt,
  });
}

/// Listens to the `shopify_webhook_queue` collection for processed
/// webhooks and triggers provider refreshes + UI toasts.
///
/// Emits the latest [ShopifyWebhookEvent] whenever a new webhook is
/// processed. The UI can watch this to show real-time toast notifications
/// like "New Shopify order #1234 synced".
class ShopifyWebhookListenerNotifier extends Notifier<ShopifyWebhookEvent?> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  @override
  ShopifyWebhookEvent? build() {
    // Only listen when a Shopify connection is active
    final isConnected = ref.watch(isShopifyConnectedProvider);
    if (!isConnected) {
      _sub?.cancel();
      _sub = null;
      return null;
    }

    _startListening();

    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });

    return null; // initial state — no event yet
  }

  void _startListening() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    _sub?.cancel();

    // Listen for recently-processed webhooks (last 30 seconds)
    // to avoid replaying old events on provider rebuild.
    final cutoff = DateTime.now().subtract(const Duration(seconds: 30));

    _sub = FirebaseFirestore.instance
        .collection('shopify_webhook_queue')
        .where('user_id', isEqualTo: uid)
        .where('processed_at', isGreaterThan: Timestamp.fromDate(cutoff))
        .orderBy('processed_at', descending: true)
        .limit(5)
        .snapshots()
        .listen(
      (snapshot) {
        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.modified &&
              change.type != DocumentChangeType.added) {
            continue;
          }

          final data = change.doc.data();
          if (data == null) continue;

          // Only react to webhooks that just got processed
          final processedAt = data['processed_at'];
          if (processedAt == null) continue;

          final topic = data['topic'] as String? ?? '';
          final payload =
              data['payload'] as Map<String, dynamic>? ?? {};

          final event = ShopifyWebhookEvent(
            topic: topic,
            shopifyOrderId: payload['id']?.toString(),
            message: _buildMessage(topic, payload),
            receivedAt: DateTime.now(),
          );

          state = event;

          // Refresh the relevant providers
          _refreshProviders(topic);
        }
      },
      onError: (e) {
        // Silently fail — webhook listener is non-critical
      },
    );
  }

  /// Builds a human-readable message for the toast notification.
  String _buildMessage(String topic, Map<String, dynamic> payload) {
    final orderNumber =
        payload['order_number']?.toString() ?? payload['name']?.toString();

    switch (topic) {
      case 'orders/create':
        return orderNumber != null
            ? 'New Shopify order #$orderNumber synced'
            :  'New Shopify order synced';
      case 'orders/updated':
        return orderNumber != null
            ? 'Shopify order #$orderNumber updated'
            :  'Shopify order updated';
      case 'orders/cancelled':
        return orderNumber != null
            ? 'Shopify order #$orderNumber cancelled'
            :  'Shopify order cancelled';
      case 'products/update':
        final title = payload['title']?.toString();
        return title != null
            ? 'Shopify product "$title" updated'
            :  'Shopify product updated';
      case 'products/create':
        final title = payload['title']?.toString();
        return title != null
            ? 'New Shopify product "$title" imported'
            :  'New Shopify product imported';
      case 'inventory_levels/update':
        return  'Shopify inventory level updated';
      default:
        return  'Shopify webhook: $topic';
    }
  }

  /// After a webhook is processed, refresh the appropriate app providers
  /// so the UI reflects the latest data.
  void _refreshProviders(String topic) {
    switch (topic) {
      case 'orders/create':
      case 'orders/updated':
      case 'orders/cancelled':
        // Use refreshAll to reload ALL pages, not just page 1.
        // Plain refresh() would discard pages 2+ and break other screens.
        ref.read(salesProvider.notifier).refreshAll();
        ref.read(transactionsProvider.notifier).refreshAll();
      case 'products/update':
      case 'products/create':
      case 'inventory_levels/update':
        ref.read(inventoryProvider.notifier).refreshAll();
    }
  }

  /// Clears the current event (call after showing the toast).
  void dismiss() {
    state = null;
  }
}

// ── Provider ───────────────────────────────────────────────

final shopifyWebhookListenerProvider =
    NotifierProvider<ShopifyWebhookListenerNotifier, ShopifyWebhookEvent?>(
        () {
  return ShopifyWebhookListenerNotifier();
});
