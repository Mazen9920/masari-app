/**
 * Admin Cloud Functions — server-side admin operations
 *
 * All functions verify admin custom claim before proceeding.
 *
 * Exports:
 *  - adminListUsers   (onCall) — paginated user query with filters
 *  - adminUpdateUser  (onCall) — modify subscription fields
 */

import {onCall, HttpsError, CallableRequest} from "firebase-functions/v2/https";
import {getFirestore, Timestamp} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import * as logger from "firebase-functions/logger";

const db = () => getFirestore();
const auth = () => getAuth();

/** Verify the caller has admin: true custom claim */
function assertAdmin(request: CallableRequest) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  if (!(request.auth.token as Record<string, unknown>).admin) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }
}

// ────────────────────────────────────────────────────────────────────────────
// adminListUsers — paginated user listing with search + filters
// ────────────────────────────────────────────────────────────────────────────
export const adminListUsers = onCall(
  {region: "us-central1", maxInstances: 5},
  async (request) => {
    assertAdmin(request);

    const {
      page = 1,
      pageSize = 25,
      search,
      tier,
      status,
      paymentSource,
      sortBy = "created_at",
      sortDir = "desc",
    } = request.data as {
      page?: number;
      pageSize?: number;
      search?: string;
      tier?: string;
      status?: string;
      paymentSource?: string;
      sortBy?: string;
      sortDir?: "asc" | "desc";
    };

    const validPageSize = Math.min(Math.max(pageSize, 10), 100);

    // Build base query
    let query: FirebaseFirestore.Query = db().collection("users");

    // Apply filters
    if (tier && tier !== "all") {
      query = query.where("subscription_tier", "==", tier);
    }
    if (status && status !== "all") {
      query = query.where("subscription_status", "==", status);
    }
    if (paymentSource && paymentSource !== "all") {
      query = query.where("payment_source", "==", paymentSource);
    }

    // Sort
    const validSortFields = ["created_at", "name", "email", "subscription_tier", "subscription_status"];
    const field = validSortFields.includes(sortBy) ? sortBy : "created_at";
    query = query.orderBy(field, sortDir);

    // Get total count (with same filters)
    const countSnap = await query.count().get();
    const total = countSnap.data().count;

    // Paginate
    const offset = (page - 1) * validPageSize;
    const snapshot = await query.offset(offset).limit(validPageSize).get();

    const users = snapshot.docs.map((doc) => {
      const d = doc.data();
      return {
        id: doc.id,
        email: d.email ?? "",
        name: d.name ?? "",
        business_name: d.business_name ?? "",
        phone: d.phone ?? "",
        country: d.country ?? "",
        tier: d.subscription_tier ?? "launch",
        subscription_status: d.subscription_status ?? "free",
        subscription_plan: d.subscription_plan ?? "",
        subscription_expires_at: d.subscription_expires_at?.toDate?.()?.toISOString?.() ??
          (typeof d.subscription_expires_at === "string" ? d.subscription_expires_at : null),
        payment_source: d.payment_source ?? "",
        created_at: d.created_at?.toDate?.()?.toISOString?.() ??
          (typeof d.created_at === "string" ? d.created_at : null),
        last_active: d.last_active?.toDate?.()?.toISOString?.() ??
          (typeof d.last_active === "string" ? d.last_active : null),
      };
    });

    // If search is provided, do client-side filtering
    // (Firestore doesn't support multi-field text search natively)
    let filtered = users;
    if (search && search.trim()) {
      const q = search.trim().toLowerCase();
      filtered = users.filter(
        (u) =>
          u.email.toLowerCase().includes(q) ||
          u.name.toLowerCase().includes(q) ||
          u.business_name.toLowerCase().includes(q)
      );
    }

    return {
      users: filtered,
      total: search ? filtered.length : total,
      page,
      pageSize: validPageSize,
      totalPages: Math.ceil((search ? filtered.length : total) / validPageSize),
    };
  }
);

// ────────────────────────────────────────────────────────────────────────────
// adminUpdateUser — modify user subscription fields
// ────────────────────────────────────────────────────────────────────────────
export const adminUpdateUser = onCall(
  {region: "us-central1", maxInstances: 5},
  async (request) => {
    assertAdmin(request);

    const {uid, updates} = request.data as {
      uid: string;
      updates: {
        tier?: "launch" | "growth" | "pro";
        subscription_status?: "free" | "active" | "expired" | "cancelled" | "grace_period";
        subscription_plan?: string;
        subscription_expires_at?: string; // ISO string
        payment_source?: string;
      };
    };

    if (!uid) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }

    // Verify user exists
    const userDoc = await db().collection("users").doc(uid).get();
    if (!userDoc.exists) {
      throw new HttpsError("not-found", "User not found.");
    }

    // Build safe update object (only allowed fields)
    const safeUpdate: Record<string, unknown> = {};
    const allowedFields = [
      "subscription_tier", "subscription_status", "subscription_plan",
      "subscription_expires_at", "payment_source",
    ];

    for (const key of allowedFields) {
      // Accept "tier" in the request body, map it to "subscription_tier"
      const inputKey = key === "subscription_tier" ? "tier" : key;
      if (updates[inputKey as keyof typeof updates] !== undefined) {
        if (key === "subscription_expires_at" && updates[inputKey as keyof typeof updates]) {
          safeUpdate[key] = Timestamp.fromDate(new Date(updates[inputKey as keyof typeof updates] as string));
        } else {
          safeUpdate[key] = updates[inputKey as keyof typeof updates];
        }
      }
    }

    if (Object.keys(safeUpdate).length === 0) {
      throw new HttpsError("invalid-argument", "No valid fields to update.");
    }

    safeUpdate.updated_at = Timestamp.now();

    await db().collection("users").doc(uid).update(safeUpdate);

    logger.info(`Admin ${request.auth?.uid} updated user ${uid}`, {updates: safeUpdate});

    return {success: true, uid, updatedFields: Object.keys(safeUpdate)};
  }
);

// ────────────────────────────────────────────────────────────────────────────
// adminGetUser — get detailed user info + related data
// ────────────────────────────────────────────────────────────────────────────
export const adminGetUser = onCall(
  {region: "us-central1", maxInstances: 5},
  async (request) => {
    assertAdmin(request);

    const {uid} = request.data as {uid: string};
    if (!uid) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }

    // Fetch user doc + Auth record + related data in parallel
    const [userDoc, authRecord, paymentLogsSnap, shopifyDoc, transactionCountSnap, productCountSnap, saleCountSnap] =
      await Promise.all([
        db().collection("users").doc(uid).get(),
        auth().getUser(uid).catch(() => null),
        db().collection("payment_logs")
          .where("user_id", "==", uid)
          .orderBy("created_at", "desc")
          .limit(20)
          .get(),
        db().collection("shopify_connections").doc(uid).get(),
        db().collection("transactions").where("user_id", "==", uid).count().get(),
        db().collection("products").where("user_id", "==", uid).count().get(),
        db().collection("sales").where("user_id", "==", uid).count().get(),
      ]);

    if (!userDoc.exists) {
      throw new HttpsError("not-found", "User not found.");
    }

    const d = userDoc.data()!;
    const toISO = (v: unknown) => {
      if (!v) return null;
      if (typeof v === "object" && v !== null && "toDate" in v) {
        return (v as {toDate: () => Date}).toDate().toISOString();
      }
      if (typeof v === "string") return v;
      return null;
    };

    const user = {
      id: uid,
      email: d.email ?? "",
      name: d.name ?? "",
      business_name: d.business_name ?? "",
      phone: d.phone ?? "",
      industry: d.industry ?? "",
      business_stage: d.business_stage ?? "",
      country: d.country ?? "",
      currency: d.currency ?? "",
      language: d.language ?? "",
      tier: d.subscription_tier ?? "launch",
      subscription_status: d.subscription_status ?? "free",
      subscription_plan: d.subscription_plan ?? "",
      subscription_expires_at: toISO(d.subscription_expires_at),
      payment_source: d.payment_source ?? "",
      paymob_subscription_id: d.paymob_subscription_id ?? "",
      paymob_auto_renew: d.paymob_auto_renew ?? false,
      created_at: toISO(d.created_at),
      updated_at: toISO(d.updated_at),
      last_active: toISO(d.last_active),
    };

    // Auth info
    const authInfo = authRecord ? {
      emailVerified: authRecord.emailVerified,
      disabled: authRecord.disabled,
      lastSignInTime: authRecord.metadata.lastSignInTime ?? null,
      creationTime: authRecord.metadata.creationTime ?? null,
      providers: authRecord.providerData.map((p) => p.providerId),
    } : null;

    // Payment history
    const payments = paymentLogsSnap.docs.map((doc) => {
      const pd = doc.data();
      return {
        id: doc.id,
        plan: pd.plan ?? "",
        success: pd.success ?? false,
        amount_cents: pd.amount_cents ?? 0,
        currency: pd.currency ?? "EGP",
        is_renewal: pd.is_renewal ?? false,
        paymob_transaction_id: pd.paymob_transaction_id ?? "",
        created_at: toISO(pd.created_at),
      };
    });

    // Shopify
    const shopify = shopifyDoc.exists ? {
      shop_domain: shopifyDoc.data()!.shop_domain ?? "",
      sync_inventory: shopifyDoc.data()!.sync_inventory ?? false,
      sync_orders: shopifyDoc.data()!.sync_orders ?? false,
      auto_sync_enabled: shopifyDoc.data()!.auto_sync_enabled ?? false,
      last_sync_at: toISO(shopifyDoc.data()!.last_sync_at),
      connected_at: toISO(shopifyDoc.data()!.connected_at),
    } : null;

    // Activity counts
    const activity = {
      transactions: transactionCountSnap.data().count,
      products: productCountSnap.data().count,
      sales: saleCountSnap.data().count,
    };

    return {user, authInfo, payments, shopify, activity};
  }
);

// ────────────────────────────────────────────────────────────────────────────
// adminResetPassword — send password reset email
// ────────────────────────────────────────────────────────────────────────────
export const adminResetPassword = onCall(
  {region: "us-central1", maxInstances: 5},
  async (request) => {
    assertAdmin(request);

    const {email} = request.data as {email: string};
    if (!email) {
      throw new HttpsError("invalid-argument", "email is required.");
    }

    const link = await auth().generatePasswordResetLink(email);
    logger.info(`Admin ${request.auth?.uid} generated password reset for ${email}`);
    return {success: true, link};
  }
);

// ────────────────────────────────────────────────────────────────────────────
// adminDisableUser — disable/enable a Firebase Auth account
// ────────────────────────────────────────────────────────────────────────────
export const adminDisableUser = onCall(
  {region: "us-central1", maxInstances: 5},
  async (request) => {
    assertAdmin(request);

    const {uid, disabled} = request.data as {uid: string; disabled: boolean};
    if (!uid) {
      throw new HttpsError("invalid-argument", "uid is required.");
    }

    await auth().updateUser(uid, {disabled});
    logger.info(`Admin ${request.auth?.uid} ${disabled ? "disabled" : "enabled"} user ${uid}`);
    return {success: true, uid, disabled};
  }
);
