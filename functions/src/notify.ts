/**
 * notify.ts — lightweight helper to send FCM push notifications.
 *
 * Reads the user's `fcm_token` from Firestore and sends a data+notification
 * message via Firebase Admin Messaging. Respects per-category notification
 * preferences stored in `users/{uid}.notification_prefs`.
 */

import {getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

const db = () => getFirestore();

/**
 * Notification category → preference key mapping.
 * The key is stored in `users/{uid}.notification_prefs.{key}`.
 * If unset, the notification is sent (opt-out model).
 */
export type NotificationCategory =
  | "sales"
  | "shopify_orders"
  | "billing"
  | "low_stock"
  | "payment_reminders"
  | "recurring"
  | "general";

/**
 * Sends a push notification to a single user by their Firestore UID.
 * Respects the user's notification preferences when a category is provided.
 * Fails silently (logs error) — callers should not depend on delivery.
 */
export async function notifyUser(
  uid: string,
  title: string,
  body: string,
  data?: Record<string, string>,
  category?: NotificationCategory
): Promise<void> {
  try {
    const userDoc = await db().collection("users").doc(uid).get();
    const userData = userDoc.data();
    const token = userData?.fcm_token as string | undefined;

    if (!token) {
      logger.info("notifyUser: no FCM token for user", {uid});
      return;
    }

    // Check global push kill-switch and per-category preference
    const prefs = (userData?.notification_prefs ?? {}) as Record<string, boolean>;
    if (prefs.push === false) {
      logger.info("notifyUser: push disabled by user", {uid});
      return;
    }
    if (category && prefs[category] === false) {
      logger.info("notifyUser: category disabled by user", {uid, category});
      return;
    }

    await getMessaging().send({
      token,
      notification: {title, body},
      data: data ?? {},
      android: {
        priority: "high",
        notification: {channelId: "revvo_default"},
      },
      apns: {
        payload: {aps: {sound: "default", badge: 1}},
      },
    });

    logger.info("notifyUser: sent", {uid, title, category: category ?? "general"});
  } catch (err: unknown) {
    // If token is stale / unregistered, clean it up
    const code = (err as {code?: string})?.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      await db().collection("users").doc(uid).update({fcm_token: ""});
      logger.info("notifyUser: cleared stale token", {uid});
    } else {
      logger.error("notifyUser: failed", {uid, err});
    }
  }
}
