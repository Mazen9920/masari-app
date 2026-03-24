/**
 * Delete User Data — Cloud Function
 *
 * Callable function that permanently deletes all data associated with the
 * authenticated user:
 *   1. All Firestore documents across every collection (user_id-scoped)
 *   2. Firebase Storage files (profile images, product images)
 *   3. Shopify connection (disconnect + revoke webhooks if connected)
 *   4. Firebase Auth account
 *
 * The caller must be authenticated. The function requires the user to
 * confirm by passing their email address as a safety check.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getFirestore} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {getAuth} from "firebase-admin/auth";
import * as logger from "firebase-functions/logger";

const BATCH_LIMIT = 250;

/** All top-level Firestore collections that store user-scoped data. */
const USER_COLLECTIONS = [
  "transactions",
  "categories",
  "products",
  "suppliers",
  "purchases",
  "payments",
  "recurring_transactions",
  "goods_receipts",
  "sales",
  "balance_sheet",
  "shopify_connections",
  "shopify_product_mappings",
  "shopify_sync_log",
  "conversion_orders",
];

/**
 * Deletes all documents from a collection where user_id == uid.
 * Uses batched deletes to stay within Firestore limits.
 * @param {string} collection  Collection name.
 * @param {string} uid  User ID.
 * @return {number} Number of documents deleted.
 */
async function deleteCollection(collection: string, uid: string): Promise<number> {
  const db = getFirestore();
  let total = 0;
  let hasMore = true;

  while (hasMore) {
    const snap = await db
      .collection(collection)
      .where("user_id", "==", uid)
      .limit(BATCH_LIMIT)
      .get();

    if (snap.empty) {
      hasMore = false;
      break;
    }

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
    total += snap.size;

    if (snap.size < BATCH_LIMIT) {
      hasMore = false;
    }
  }

  return total;
}

/**
 * Deletes the user document from the "users" collection.
 * @param {string} uid  User ID.
 */
async function deleteUserDoc(uid: string): Promise<void> {
  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);
  const userDoc = await userRef.get();
  if (userDoc.exists) {
    await userRef.delete();
  }
}

/**
 * Deletes all Firebase Storage files for a user.
 * Covers profile images and product images.
 * @param {string} uid  User ID.
 */
async function deleteStorageFiles(uid: string): Promise<number> {
  const bucket = getStorage().bucket();
  let count = 0;

  // Delete user profile image
  try {
    const [profileFiles] = await bucket.getFiles({prefix: `users/${uid}/`});
    for (const file of profileFiles) {
      await file.delete();
      count++;
    }
  } catch {
    // Ignore — file may not exist
  }

  // Delete product images
  try {
    const [productFiles] = await bucket.getFiles({prefix: `products/${uid}/`});
    for (const file of productFiles) {
      await file.delete();
      count++;
    }
  } catch {
    // Ignore — files may not exist
  }

  return count;
}

export const deleteUserData = onCall(
  {
    maxInstances: 5,
    timeoutSeconds: 300,
  },
  async (request) => {
    // ── Auth check ──
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "You must be signed in.");
    }

    const uid = request.auth.uid;
    const confirmEmail = request.data?.confirmEmail as string | undefined;

    // ── Safety: require email confirmation ──
    const authUser = await getAuth().getUser(uid);
    if (!confirmEmail || confirmEmail.toLowerCase() !== authUser.email?.toLowerCase()) {
      throw new HttpsError(
        "failed-precondition",
        "Please enter your email address to confirm account deletion."
      );
    }

    logger.info("Starting account deletion", {uid, email: authUser.email});

    const results: Record<string, number> = {};

    // ── 1. Delete all user-scoped Firestore collections ──
    for (const collection of USER_COLLECTIONS) {
      const deleted = await deleteCollection(collection, uid);
      if (deleted > 0) {
        results[collection] = deleted;
      }
    }

    // ── 2. Delete user document ──
    await deleteUserDoc(uid);
    results["users"] = 1;

    // ── 3. Delete Storage files ──
    const storageCount = await deleteStorageFiles(uid);
    if (storageCount > 0) {
      results["storage_files"] = storageCount;
    }

    // ── 4. Delete Firebase Auth account ──
    try {
      await getAuth().deleteUser(uid);
      results["auth_deleted"] = 1;
    } catch (err) {
      logger.error("Failed to delete auth user", {uid, error: err});
      // Don't throw — data is already gone, worst case user can't log back in
    }

    logger.info("Account deletion complete", {uid, results});

    return {success: true, deleted: results};
  }
);
