/**
 * notify.ts — sends FCM push notifications AND persists them to the user's
 * in-app inbox (`notifications/{uid}/items`).
 *
 * The inbox write happens BEFORE the token/prefs checks so a notification is
 * never lost just because the device is offline, the token is stale, or push
 * is switched off — the inbox is the durable record, push is best-effort.
 *
 * Message text is bilingual: pass `opts.msg = {type, params}` and the copy is
 * built from the template registry in the user's stored locale
 * (`users/{uid}.locale`, synced by the app). Legacy callers that pass raw
 * title/body strings keep working unchanged.
 */

import {FieldValue, getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";
import {alertMessage, toAlertLocale} from "./alerts/messages.js";

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
  | "deliveries"
  | "insights"
  | "weekly_digest"
  | "data_integrity"
  | "general";

export interface NotifyOptions {
  /**
   * Build title/body from the bilingual template registry instead of the raw
   * strings, in the user's stored locale. `params` fills `{token}`s.
   */
  msg?: {type: string; params: Record<string, string>};
}

/**
 * Sends a push notification to a single user by their Firestore UID and
 * records it in their inbox. Respects the user's notification preferences
 * when a category is provided (push only — the inbox item is always written).
 * Fails silently (logs error) — callers should not depend on delivery.
 */
export async function notifyUser(
  uid: string,
  title: string,
  body: string,
  data?: Record<string, string>,
  category?: NotificationCategory,
  opts?: NotifyOptions
): Promise<void> {
  let itemRef;
  try {
    const userDoc = await db().collection("users").doc(uid).get();
    const userData = userDoc.data();
    const token = userData?.fcm_token as string | undefined;

    // Localize when a template type is given.
    if (opts?.msg) {
      const locale = toAlertLocale(userData?.locale);
      const m = alertMessage(opts.msg.type, locale, opts.msg.params);
      title = m.title;
      body = m.body;
    }
    const type = opts?.msg?.type ?? data?.type ?? "general";

    // Durable inbox record — written before any bail-out below.
    const items = db().collection("notifications").doc(uid).collection("items");
    itemRef = await items.add({
      type,
      title,
      body,
      data: data ?? {},
      category: category ?? "general",
      created_at: FieldValue.serverTimestamp(),
      read: false,
      push_sent: false,
    });

    if (!token) {
      logger.info("notifyUser: no FCM token for user (inbox only)", {uid});
      return;
    }

    // Check global push kill-switch and per-category preference
    const prefs = (userData?.notification_prefs ?? {}) as Record<string, boolean>;
    if (prefs.push === false) {
      logger.info("notifyUser: push disabled by user (inbox only)", {uid});
      return;
    }
    if (category && prefs[category] === false) {
      logger.info("notifyUser: category disabled by user (inbox only)", {uid, category});
      return;
    }

    // Real unread count for the iOS badge (includes the item just written).
    let badge = 1;
    try {
      const agg = await items.where("read", "==", false).count().get();
      badge = agg.data().count;
    } catch {
      // Aggregate unavailable — a badge of 1 still signals "something new".
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
        payload: {aps: {sound: "default", badge}},
      },
    });

    await itemRef.update({push_sent: true});
    logger.info("notifyUser: sent", {uid, title, category: category ?? "general"});
  } catch (err: unknown) {
    // If token is stale / unregistered, clean it up
    const code = (err as {code?: string})?.code;
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      await db().collection("users").doc(uid).update({fcm_token: ""});
      logger.info("notifyUser: cleared stale token (inbox item kept)", {uid});
    } else {
      logger.error("notifyUser: failed", {uid, err});
    }
  }
}
