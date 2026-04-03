/**
 * notify.ts — lightweight helper to send FCM push notifications.
 *
 * Reads the user's `fcm_token` from Firestore and sends a data+notification
 * message via Firebase Admin Messaging.
 */

import {getFirestore} from "firebase-admin/firestore";
import {getMessaging} from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";

const db = () => getFirestore();

/**
 * Sends a push notification to a single user by their Firestore UID.
 * Fails silently (logs error) — callers should not depend on delivery.
 */
export async function notifyUser(
  uid: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  try {
    const userDoc = await db().collection("users").doc(uid).get();
    const token = userDoc.data()?.fcm_token as string | undefined;

    if (!token) {
      logger.info("notifyUser: no FCM token for user", {uid});
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

    logger.info("notifyUser: sent", {uid, title});
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
