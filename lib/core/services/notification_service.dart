import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Top-level handler for background messages (must be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) debugPrint('[FCM] Background message: ${message.messageId}');
}

/// Centralised FCM service — initialises messaging, requests permission,
/// persists the device token to Firestore, and listens for foreground messages.
class NotificationService {
  static final _messaging = FirebaseMessaging.instance;
  static final _db = FirebaseFirestore.instance;

  /// Call once after Firebase.initializeApp + user authentication.
  static Future<void> init() async {
    // Register the background handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Request permission (iOS shows a prompt; Android auto-grants)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      if (kDebugMode) debugPrint('[FCM] Permission denied');
      return;
    }

    if (kDebugMode) debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    // iOS: show notification banners even when app is in foreground
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Get and persist the device token
    await _saveToken();

    // Listen for token refresh (e.g. after app restore / new install)
    _messaging.onTokenRefresh.listen((_) => _saveToken());

    // Foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (kDebugMode) debugPrint('[FCM] Foreground: ${message.notification?.title}');
      // The app already uses local UI for in-app state; system notification
      // will appear automatically if the notification payload is present.
    });
  }

  /// Persists the current FCM token to the user's Firestore doc.
  static Future<void> _saveToken() async {
    try {
      // On iOS, getToken() requires the APNS token, which Apple can take a few
      // seconds to deliver after launch. The old 3s wait was too short, so on
      // cold starts getToken() threw and the FCM token never refreshed (tokens
      // went stale). Wait up to ~10s; if it's still not ready, onTokenRefresh
      // will save it later.
      if (!kIsWeb && Platform.isIOS) {
        String? apns = await _messaging.getAPNSToken();
        for (var i = 0; i < 20 && apns == null; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          apns = await _messaging.getAPNSToken();
        }
        if (apns == null) {
          if (kDebugMode) {
            debugPrint('[FCM] APNS token still unavailable; will save on refresh');
          }
          return;
        }
      }
      final token = await _messaging.getToken();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (token != null && uid != null) {
        await _db.collection('users').doc(uid).set(
          {
            'fcm_token': token,
            'fcm_updated_at': FieldValue.serverTimestamp(),
            'platform': kIsWeb
                ? 'web'
                : (Platform.isIOS ? 'ios' : 'android'),
          },
          SetOptions(merge: true),
        );
        if (kDebugMode) debugPrint('[FCM] Token saved for $uid');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] _saveToken error: $e');
    }
  }
}
