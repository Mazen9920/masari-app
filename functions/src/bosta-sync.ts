/**
 * Bosta Sync Engine — Cloud Functions (optimized for 20k+ orders)
 *
 * syncBostaShipments  — onCall: manual trigger from the app.
 * scheduledBostaSyncDaily — scheduled: runs daily at 02:00 UTC.
 *
 * Sync logic (state-agnostic — follows Cash Cycles):
 *   Phase 1 — Fast catalog: POST search pages, batch-check Firestore,
 *             store basic shipment info from search (no per-delivery GET).
 *   Phase 2 — Selective GET: only fetch full detail for shipments that
 *             need cashCycle resolution (unprocessed + terminal states).
 *   Parallel: GETs run in parallel batches of 5.
 *   Resumable: tracks page progress, stops before CF timeout,
 *              client can re-trigger with startPage to continue.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {
  getFirestore,
  FieldValue,
  Timestamp,
  AggregateField,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {decrypt, encrypt} from "./shopify-auth.js";

// ── Secrets ────────────────────────────────────────────────

const tokenEncryptionKey = defineSecret("SHOPIFY_TOKEN_ENCRYPTION_KEY");

// ── Constants ──────────────────────────────────────────────

const BOSTA_API_BASE = "https://app.bosta.co/api/v2";
const BOSTA_LOGIN_URL = "https://app.bosta.co/api/v0/users/login";
const MAX_RETRIES = 3;
const INITIAL_BACKOFF_MS = 1000;
const SEARCH_PAGE_LIMIT = 50;

/** Delay between parallel GET batches to avoid Bosta rate limits. */
const BATCH_DELAY_MS = 50;

/** Number of concurrent GET requests per batch. */
const PARALLEL_BATCH_SIZE = 20;

/** Max pages for daily incremental sync (50 items/page = 500 deliveries). */
const DAILY_MAX_PAGES = 10;

/** Max pages for manual full sync (50 items/page = 20k deliveries). */
const MANUAL_MAX_PAGES = 400;

/** Skip re-checking awaiting shipments checked within this window (ms). */
const SETTLEMENT_RECHECK_MS = 6 * 60 * 60 * 1000; // 6 hours

/** Stop processing 60s before CF timeout to save progress. */
const TIMEOUT_BUFFER_MS = 60_000;

/** How often to update sync progress in connection doc (in deliveries). */
const PROGRESS_UPDATE_INTERVAL = 100;

/** Default estimated Bosta fee per shipment when no history is available (EGP). */
const DEFAULT_ESTIMATED_FEE = 90;

/** Fee breakdown fields to extract from wallet.cashCycle. */
const FEE_BREAKDOWN_FIELDS = [
  "shipping_fees",
  "fulfillment_fees",
  "vat",
  "cod_fees",
  "insurance_fees",
  "expedite_fees",
  "opening_package_fees",
  "flex_ship_fees",
  "pos_fees",
  "collection_fees",
];

/**
 * Lazy Firestore accessor.
 * @return {FirebaseFirestore.Firestore} The Firestore instance.
 */
function getDb() {
  return getFirestore();
}

// ── Types ──────────────────────────────────────────────────

/* eslint-disable @typescript-eslint/no-explicit-any */
type ApiResult = Record<string, any>;
/* eslint-enable @typescript-eslint/no-explicit-any */

interface SyncResult {
  totalChecked: number;
  cataloged: number;
  newExpenses: number;
  awaitingSettlement: number;
  alreadyRecorded: number;
  errors: number;
  matchedToSale: number;
  unlinked: number;
  /** True when all pages have been processed. */
  complete: boolean;
  /** Page to resume from on next call (0 = N/A). */
  resumePage: number;
  /** Elapsed time in ms. */
  elapsedMs: number;
}

/** Basic delivery info from search (no per-delivery GET needed). */
interface CatalogEntry {
  trackingNumber: string;
  bostaDeliveryId: string;
  state: number;
  stateValue: string;
  type: string;
  businessReference: string | null;
  cod: number;
  createdAt: string | null;
}

/** Result from fetching a single delivery's settlement data. */
interface SettlementData {
  trackingNumber: string;
  bostaDeliveryId: string;
  businessReference: string | null;
  state: number;
  stateValue: string;
  type: string;
  cod: number;
  bostaFees: number;
  feeBreakdown: Record<string, number>;
  depositedAt: FirebaseFirestore.Timestamp;
  /** YYYY-MM-DD of deposit date, used as grouping key. */
  depositDateKey: string;
  saleId: string | null;
  matched: boolean;
  orderLabel: string;
  /** The estimated fee stored on the shipment doc at catalog time. */
  estimatedFee: number;
  /** YYYY-MM-DD of the Bosta createdAt (fulfillment date), for estimate grouping. */
  fulfillmentDateKey: string;
  /** Next cashout date from wallet.cashCycle (ISO string or null). */
  nextCashoutDate: string | null;
}

/** Info collected during Phase 1 catalog for writing estimate transactions. */
interface EstimateEntry {
  shipDocId: string;
  estimatedFee: number;
  /** YYYY-MM-DD of fulfillment (from Bosta createdAt). */
  fulfillmentDateKey: string;
}

/** Pre-loaded sales lookup for fast in-memory order matching. */
interface SalesLookup {
  byOrderNumber: Map<string, string>; // shopify_order_number → sale_id
  byNotes: Map<string, string>;       // notes → sale_id
}

/**
 * Extracts a sale_id from a businessReference using the salesLookup.
 * Centralizes the 3-strategy matching logic used in Phase 1, Phase 2,
 * and the AR summary computation.
 *
 * Returns { saleId, orderLabel } or null if no match.
 */
function matchSaleFromBusinessReference(
  businessReference: string | null | undefined,
  salesLookup: SalesLookup,
): {saleId: string; orderLabel: string} | null {
  if (!businessReference) return null;

  let rawRef = businessReference.trim();
  const colonHashIdx = rawRef.indexOf(":#");
  if (colonHashIdx >= 0) {
    rawRef = rawRef.substring(colonHashIdx + 2);
  } else {
    rawRef = rawRef.replace(/^#/, "");
  }
  if (!rawRef) return null;

  // Strategy 1: exact match on full reference
  let saleId = salesLookup.byOrderNumber.get(rawRef) ?? null;
  if (saleId) return {saleId, orderLabel: `#${rawRef}`};

  // Strategy 2: strip 1-4 digit prefix
  if (rawRef.length > 4) {
    for (let prefixLen = 1; prefixLen <= 4; prefixLen++) {
      const stripped = rawRef.substring(prefixLen);
      if (stripped.length < 3) break;
      saleId = salesLookup.byOrderNumber.get(stripped) ?? null;
      if (saleId) return {saleId, orderLabel: `#${stripped}`};
    }
  }

  // Strategy 3: fallback — match by notes field
  saleId = salesLookup.byNotes.get(`#${rawRef} — Shopify`) ?? null;
  if (saleId) return {saleId, orderLabel: `#${rawRef}`};

  return null;
}

// ── Pre-load helpers (eliminates per-delivery Firestore queries) ──

/**
 * Loads all user sales into memory for O(1) order matching.
 * Replaces per-delivery Firestore queries (up to 6 per delivery).
 */
async function buildSalesLookup(
  db: FirebaseFirestore.Firestore,
  userId: string,
): Promise<SalesLookup> {
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", userId)
    .select("shopify_order_number", "notes")
    .get();

  const byOrderNumber = new Map<string, string>();
  const byNotes = new Map<string, string>();

  for (const doc of salesSnap.docs) {
    const data = doc.data();
    const orderNum = data.shopify_order_number;
    if (orderNum) byOrderNumber.set(String(orderNum), doc.id);
    const notes = data.notes;
    if (notes && typeof notes === "string") byNotes.set(notes, doc.id);
  }

  return {byOrderNumber, byNotes};
}

/**
 * Pre-loads existing Bosta transaction IDs for fast idempotency checks.
 */
async function loadExistingTxnIds(
  db: FirebaseFirestore.Firestore,
  userId: string,
): Promise<Set<string>> {
  const txnSnap = await db.collection("transactions")
    .where("user_id", "==", userId)
    .where("payment_method", "==", "bosta")
    .select()
    .get();
  return new Set(txnSnap.docs.map((d) => d.id));
}

// ── Bosta fetch with retry ─────────────────────────────────

/**
 * Makes a request to Bosta API with exponential-backoff retry on 429 / 5xx.
 * @param {string} url  Full URL.
 * @param {RequestInit} init  Fetch options.
 * @return {Promise<ApiResult>} Parsed response.
 */
async function bostaFetch(
  url: string, init: RequestInit,
): Promise<ApiResult> {
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    const res = await fetch(url, init);

    if (res.status === 401) {
      throw new Error("Bosta API key invalid (401)");
    }

    if (res.status === 429 || res.status >= 500) {
      const retryAfter = res.headers.get("retry-after");
      const backoff = retryAfter
        ? Number(retryAfter) * 1000
        : INITIAL_BACKOFF_MS * Math.pow(2, attempt);

      lastError = new Error(
        `Bosta ${res.status} on attempt ${attempt + 1}`
      );

      if (attempt < MAX_RETRIES) {
        await new Promise((r) => setTimeout(r, backoff));
        continue;
      }
      throw lastError;
    }

    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Bosta API ${res.status}: ${body.substring(0, 200)}`);
    }

    const json = (await res.json()) as ApiResult;
    // Bosta wraps all responses in { success, message, data: {...} }
    if (json.data && typeof json.data === "object") {
      return json.data as ApiResult;
    }
    return json;
  }

  throw lastError ?? new Error("bostaFetch: unexpected exit");
}

/**
 * Common headers for Bosta requests.
 */
function bostaHeaders(apiKey: string): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "Authorization": apiKey,
  };
}

/**
 * Round to 2 decimal places.
 */
function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * Compute sale total from Firestore data (mirrors Dart Sale.total getter).
 * total = Σ(item.quantity * item.unit_price) + tax - discount + shipping
 * The 'total' field is NOT stored in Firestore — it's a Dart computed getter.
 */
function computeSaleTotal(
  saleData: FirebaseFirestore.DocumentData,
): number {
  const items = saleData.items as Array<{quantity?: number; unit_price?: number}> | undefined;
  if (!items || !Array.isArray(items)) return 0;
  const subtotal = items.reduce(
    (s, item) => s + (Number(item.quantity) || 0) * (Number(item.unit_price) || 0),
    0,
  );
  const tax = Number(saleData.tax_amount) || 0;
  const discount = Number(saleData.discount_amount) || 0;
  const shipping = Number(saleData.shipping_cost) || 0;
  return round2(subtotal + tax - discount + shipping);
}

// ═══════════════════════════════════════════════════════════
//  Bosta Dashboard Token Management
// ═══════════════════════════════════════════════════════════

/**
 * Logs in to the Bosta Dashboard API using encrypted credentials
 * stored in the user's `bosta_connections` document.
 *
 * Returns the JWT token (Bearer-prefixed, 14-day expiry).
 * On auth failure, sets `dashboard_status: "auth_failed"` on the
 * connection doc and throws.
 *
 * @param {string} userId Firestore user ID.
 * @param {string} encKey Encryption key for AES-256-GCM.
 * @return {Promise<string>} The Bosta dashboard JWT token.
 */
export async function getBostaDashboardToken(
  userId: string,
  encKey: string,
): Promise<string> {
  const db = getDb();
  const connRef = db.collection("bosta_connections").doc(userId);
  const connDoc = await connRef.get();

  if (!connDoc.exists) {
    throw new Error("No Bosta connection found for user");
  }

  const conn = connDoc.data()!;
  const emailEnc = conn.dashboard_email_encrypted as string | undefined;
  const passEnc = conn.dashboard_password_encrypted as string | undefined;

  if (!emailEnc || !passEnc) {
    throw new Error("No dashboard credentials stored for user");
  }

  const email = decrypt(emailEnc, encKey);
  const password = decrypt(passEnc, encKey);

  // Call Bosta login API
  const res = await fetch(BOSTA_LOGIN_URL, {
    method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({email, password}),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    logger.error("Bosta dashboard login failed", {
      userId, status: res.status, body: body.substring(0, 200),
    });

    // Mark auth failure so Flutter can show a warning banner
    await connRef.update({
      dashboard_status: "auth_failed",
      dashboard_status_updated_at: FieldValue.serverTimestamp(),
    });

    throw new Error(
      `Bosta dashboard login failed (${res.status}): ${body.substring(0, 100)}`
    );
  }

  const json = await res.json() as {
    data?: {token?: string; refreshToken?: string};
    token?: string;
  };

  // Bosta wraps response differently — handle both shapes
  const token = json.data?.token ?? json.token;
  if (!token || typeof token !== "string") {
    throw new Error("Bosta login succeeded but no token in response");
  }

  // Mark dashboard as active on successful login
  await connRef.update({
    dashboard_status: "active",
    dashboard_status_updated_at: FieldValue.serverTimestamp(),
  });

  logger.info("Bosta dashboard login successful", {userId});
  return token;
}

// ═══════════════════════════════════════════════════════════
//  Cashout Sync Engine — fetch, store, match, summarize
// ═══════════════════════════════════════════════════════════

/** Minimum time between cashout syncs (ms). */
const CASHOUT_SYNC_THROTTLE_MS = 5 * 60 * 1000; // 5 minutes

/** Bosta Dashboard API base (v2 for wallet endpoints). */
const BOSTA_DASHBOARD_API = "https://app.bosta.co/api/v2";

/** Shape of a single cashout from the Bosta /wallet/cashouts API. */
interface BostaCashout {
  transaction_id: string;
  amount: number;
  transaction_date: string; // ISO-8601 or YYYY-MM-DD
}

/** Result returned by syncCashoutsForUser. */
interface CashoutSyncResult {
  cashoutsFetched: number;
  cashoutsStored: number;
  shipmentsMatched: number;
  cfTotalCashouts: number;
  cfPendingAr: number;
  cfPendingArCount: number;
  cfLastCashoutDate: string | null;
}

/**
 * Fetches cashouts from the Bosta Dashboard API, stores them in
 * `bosta_cashouts/{transaction_id}`, matches pending shipments,
 * and updates the pre-computed summary on `bosta_connections`.
 *
 * @param userId - Firestore user ID.
 * @param dashboardToken - Bosta Dashboard JWT token (Bearer-prefixed).
 * @param sinceDate - ISO date string to fetch from (inclusive).
 *   If null, fetches from 2025-01-01.
 * @return Summary of what was synced.
 */
async function syncCashoutsForUser(
  userId: string,
  dashboardToken: string,
  sinceDate: string | null,
): Promise<CashoutSyncResult> {
  const db = getDb();
  const startDate = sinceDate || "2025-01-01";
  const endDate = new Date().toISOString().slice(0, 10);

  // ── Step 1: Fetch ALL cashouts (paginated) from Bosta Dashboard API ──

  const allCashouts: BostaCashout[] = [];
  let page = 1;
  let totalPages = 1; // Will be updated from first response.

  while (page <= totalPages) {
    const url =
      `${BOSTA_DASHBOARD_API}/wallet/cashouts?start_date=${startDate}&end_date=${endDate}&page=${page}`;

    const cashoutRes = await fetch(url, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        "Authorization": dashboardToken,
      },
    });

    if (!cashoutRes.ok) {
      const body = await cashoutRes.text().catch(() => "");
      throw new Error(
        `Cashout fetch failed (${cashoutRes.status}): ${body.substring(0, 200)}`
      );
    }

    const cashoutJson = await cashoutRes.json() as ApiResult;

    // Extract the list of cashouts from the response.
    let pageCashouts: BostaCashout[] = [];
    if (cashoutJson.data && Array.isArray((cashoutJson.data as Record<string, unknown>).list)) {
      const dataObj = cashoutJson.data as Record<string, unknown>;
      pageCashouts = dataObj.list as unknown as BostaCashout[];
      // Update total pages from response metadata.
      if (typeof dataObj.pages === "number") {
        totalPages = dataObj.pages;
      }
    } else if (Array.isArray(cashoutJson)) {
      pageCashouts = cashoutJson as unknown as BostaCashout[];
      totalPages = page; // No pagination metadata — stop after this.
    } else if (Array.isArray(cashoutJson.data)) {
      pageCashouts = cashoutJson.data as unknown as BostaCashout[];
      totalPages = page;
    } else if (cashoutJson.cashouts && Array.isArray(cashoutJson.cashouts)) {
      pageCashouts = cashoutJson.cashouts as unknown as BostaCashout[];
      totalPages = page;
    } else {
      logger.warn("Unexpected cashout response shape", {
        userId, keys: Object.keys(cashoutJson), page,
      });
      break;
    }

    allCashouts.push(...pageCashouts);

    // If this page returned no items, stop.
    if (pageCashouts.length === 0) break;
    page++;
  }

  logger.info("Fetched cashouts from Bosta", {
    userId, count: allCashouts.length, pages: page - 1, startDate, endDate,
  });

  // ── Step 2: Store cashouts (idempotent — doc ID = transaction_id) ──

  let stored = 0;
  // Firestore batch limit is 500 ops; chunk if needed.
  const BATCH_LIMIT = 499;
  let batch = db.batch();
  let batchOps = 0;

  for (const c of allCashouts) {
    if (!c.transaction_id) continue;

    const docRef = db.collection("bosta_cashouts").doc(c.transaction_id);
    batch.set(docRef, {
      user_id: userId,
      transaction_id: c.transaction_id,
      amount: Number(c.amount) || 0,
      transaction_date: c.transaction_date || null,
      synced_at: FieldValue.serverTimestamp(),
    }, {merge: true});
    stored++;
    batchOps++;

    if (batchOps >= BATCH_LIMIT) {
      await batch.commit();
      batch = db.batch();
      batchOps = 0;
    }
  }

  if (batchOps > 0) {
    await batch.commit();
  }

  logger.info("Stored cashouts", {userId, stored});

  // ── Step 3: Match shipments to cashouts ──────────────────

  const shipmentsMatched = await matchShipmentsToCashouts(db, userId);

  // ── Step 4: Compute and save summary ─────────────────────

  const summary = await computeAndSaveCashoutSummary(db, userId);

  return {
    cashoutsFetched: allCashouts.length,
    cashoutsStored: stored,
    shipmentsMatched,
    ...summary,
  };
}

/**
 * Matches pending shipments to cashouts by date range.
 *
 * For shipments with deposited_at set (settlement done in cashCycle)
 * and cashout_status not yet "paid": find the first cashout whose
 * transaction_date >= deposited_at. Mark as paid.
 *
 * This uses range matching (Case 4): deposited_at indicates Bosta
 * internally settled the order, and the next cashout after that date
 * is when the money actually hit the bank.
 */
async function matchShipmentsToCashouts(
  db: FirebaseFirestore.Firestore,
  userId: string,
): Promise<number> {
  // Load all user's cashouts ordered by date
  const cashoutsSnap = await db.collection("bosta_cashouts")
    .where("user_id", "==", userId)
    .orderBy("transaction_date", "asc")
    .get();

  if (cashoutsSnap.empty) return 0;

  const cashouts = cashoutsSnap.docs.map((d) => ({
    id: d.id,
    date: d.data().transaction_date as string,
  }));

  // Find shipments that are settled but not yet assigned to a cashout
  const pendingSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", userId)
    .where("deposited_at", "!=", null)
    .get();

  let matched = 0;
  let batch = db.batch();
  let batchOps = 0;

  for (const shipDoc of pendingSnap.docs) {
    const data = shipDoc.data();

    // Skip if already paid
    if (data.cashout_status === "paid") continue;

    const depositedAt = data.deposited_at?.toDate?.()
      ? (data.deposited_at.toDate() as Date)
      : null;
    if (!depositedAt) continue;

    const depositDateStr = depositedAt.toISOString().slice(0, 10);

    // Find earliest cashout on or after the deposit date
    const matchingCashout = cashouts.find((c) => c.date >= depositDateStr);

    if (matchingCashout) {
      batch.update(shipDoc.ref, {
        cashout_status: "paid",
        cashout_id: matchingCashout.id,
      });
      matched++;
      batchOps++;

      if (batchOps >= 490) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    }
  }

  if (batchOps > 0) {
    await batch.commit();
  }

  logger.info("Matched shipments to cashouts", {userId, matched});
  return matched;
}

/**
 * Computes the pre-computed summary fields and atomically
 * updates `bosta_connections/{userId}`.
 *
 * Summary fields:
 *   cf_total_cashouts — sum of ALL cashout amounts
 *   cf_pending_ar — sum of sale.total for COD orders not yet cashed out
 *   cf_pending_ar_count — count of such orders
 *   cf_last_cashout_date — most recent cashout date
 */
async function computeAndSaveCashoutSummary(
  db: FirebaseFirestore.Firestore,
  userId: string,
): Promise<{
  cfTotalCashouts: number;
  cfPendingAr: number;
  cfPendingArCount: number;
  cfLastCashoutDate: string | null;
}> {
  // ── Total cashouts ───────────────────────────────────────

  const cashoutsSnap = await db.collection("bosta_cashouts")
    .where("user_id", "==", userId)
    .get();

  let cfTotalCashouts = 0;
  let cfLastCashoutDate: string | null = null;

  for (const doc of cashoutsSnap.docs) {
    const data = doc.data();
    cfTotalCashouts += Number(data.amount) || 0;
    const txnDate = data.transaction_date as string | null;
    if (txnDate && (!cfLastCashoutDate || txnDate > cfLastCashoutDate)) {
      cfLastCashoutDate = txnDate;
    }
  }

  cfTotalCashouts = round2(cfTotalCashouts);

  // ── Pending AR: COD sales not yet cashed out ──────────────
  //
  // Approach: start from SALES (the correct direction).
  // 1. Get all COD sales for this user (payment_method == "Cash on Delivery (COD)")
  // 2. Filter: non-cancelled, after cutoff, total > 0
  // 3. For each, check if it has a "paid" bosta_shipment → NOT AR
  // 4. Check if it has an RTO/returned shipment → NOT AR
  // 5. Everything else → AR

  // ── Read AR cutoff date from connection doc ────────────
  const connSnap = await db.collection("bosta_connections").doc(userId).get();
  const connData = connSnap.data();
  const arCutoffDate: Date | null = connData?.cf_ar_cutoff_date
    ? (connData.cf_ar_cutoff_date.toDate
      ? connData.cf_ar_cutoff_date.toDate() as Date
      : new Date(String(connData.cf_ar_cutoff_date)))
    : null;

  // ── Build shipment lookup: saleId → best status ──────────
  const allShipmentsSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", userId)
    .get();

  // Map saleId → { hasPaid: bool, allRto: bool }
  // Also collect RTO shipment tracking numbers for re-ship detection.
  // Secondary: trackingNumber → shipment info (for unmatched shipments).
  const saleShipmentMap: Record<string, {hasPaid: boolean; allRto: boolean}> = {};
  const rtoTrackingBySale: Record<string, string[]> = {};
  const trackingShipmentMap: Record<string, {hasPaid: boolean; allRto: boolean; state: number}> = {};

  for (const doc of allShipmentsSnap.docs) {
    const data = doc.data();
    const state = Number(data.state) || 0;
    const isRtoOrReturned = state === 60 || state === 46;
    const isPaid = data.cashout_status === "paid";
    const tracking = (data.tracking_number ?? "").toString();

    // Primary lookup: by sale_id
    const saleId = data.sale_id as string | undefined;
    if (saleId) {
      if (!saleShipmentMap[saleId]) {
        saleShipmentMap[saleId] = {hasPaid: false, allRto: true};
      }
      if (isPaid) saleShipmentMap[saleId].hasPaid = true;
      if (!isRtoOrReturned) saleShipmentMap[saleId].allRto = false;

      // Collect tracking numbers of RTO/returned shipments for re-ship check
      if (isRtoOrReturned && tracking) {
        if (!rtoTrackingBySale[saleId]) rtoTrackingBySale[saleId] = [];
        rtoTrackingBySale[saleId].push(tracking);
      }
    }

    // Secondary lookup: by tracking_number (for unmatched shipments)
    if (tracking) {
      const prev = trackingShipmentMap[tracking];
      if (!prev) {
        trackingShipmentMap[tracking] = {hasPaid: isPaid, allRto: isRtoOrReturned, state};
      } else {
        trackingShipmentMap[tracking] = {
          hasPaid: prev.hasPaid || isPaid,
          allRto: prev.allRto && isRtoOrReturned,
          state: isRtoOrReturned ? prev.state : state,
        };
      }
    }
  }

  // ── Query COD sales ──────────────────────────────────────
  const codSalesSnap = await db.collection("sales")
    .where("user_id", "==", userId)
    .where("payment_method", "==", "Cash on Delivery (COD)")
    .get();

  let cfPendingAr = 0;
  let cfPendingArCount = 0;

  for (const saleDoc of codSalesSnap.docs) {
    const data = saleDoc.data();

    // order_status is numeric: 4 = cancelled
    const orderStatus = Number(data.order_status) || 0;
    if (orderStatus === 4) continue; // cancelled

    // AR cutoff: exclude sales before cutoff date
    if (arCutoffDate) {
      const saleDate: Date | null = data.date
        ? (data.date.toDate ? data.date.toDate() as Date : new Date(String(data.date)))
        : null;
      if (saleDate && saleDate < arCutoffDate) continue;
    }

    // Compute total from items (not stored in Firestore)
    const saleTotal = computeSaleTotal(data);
    if (saleTotal <= 0) continue; // Case 17

    // Check shipment status for this sale (primary: by sale_id)
    let shipInfo = saleShipmentMap[saleDoc.id] ?? null;

    // Fallback: if no shipment matched by sale_id, check by tracking_number
    if (!shipInfo) {
      const saleTracking = (data.tracking_number ?? "").toString();
      if (saleTracking) {
        const trackInfo = trackingShipmentMap[saleTracking];
        if (trackInfo) {
          shipInfo = {hasPaid: trackInfo.hasPaid, allRto: trackInfo.allRto};
        }
      }
    }

    if (shipInfo) {
      if (shipInfo.hasPaid) continue; // Cashout received → NOT AR
      if (shipInfo.allRto) {
        // Re-ship check: if the sale has a different tracking number than
        // all its RTO shipments, it was re-shipped and is still AR.
        const saleTracking = (data.tracking_number ?? "").toString();
        const rtoTrackings = rtoTrackingBySale[saleDoc.id] ?? [];
        const isReshipped = saleTracking !== "" &&
          rtoTrackings.length > 0 &&
          rtoTrackings.every((rt) => rt !== saleTracking);
        if (!isReshipped) continue; // Genuinely RTO → NOT AR
      }
    }
    // No shipment at all → AR (Case 1: no shipment = AR by default)

    cfPendingAr += saleTotal;
    cfPendingArCount++;
  }

  cfPendingAr = round2(cfPendingAr);

  // ── Write summary to connection doc ──────────────────────

  const connRef = db.collection("bosta_connections").doc(userId);
  await connRef.update({
    cf_total_cashouts: cfTotalCashouts,
    cf_pending_ar: cfPendingAr,
    cf_pending_ar_count: cfPendingArCount,
    cf_last_cashout_date: cfLastCashoutDate,
    cf_last_cashout_sync_at: FieldValue.serverTimestamp(),
  });

  logger.info("Cashout summary updated", {
    userId, cfTotalCashouts, cfPendingAr, cfPendingArCount, cfLastCashoutDate,
  });

  return {cfTotalCashouts, cfPendingAr, cfPendingArCount, cfLastCashoutDate};
}

// ═══════════════════════════════════════════════════════════
//  Core sync logic (optimized: two-phase, parallel, resumable)
// ═══════════════════════════════════════════════════════════

/**
 * Runs Bosta sync for a single user connection.
 *
 * Phase 1 — CATALOG: iterate search pages (POST only), batch-check
 *   Firestore for already-processed shipments, upsert basic info from
 *   search results (no per-delivery GET). Very fast: ~2 min for 20k.
 *
 * Phase 2 — SETTLEMENT: for shipments that need fee resolution
 *   (expense_recorded=false, state is terminal), fetch full detail via
 *   GET in parallel batches of 5. Create expense transactions.
 *
 * Timeout-aware: stops processing 60s before CF timeout, saves resume
 * page so client can re-trigger.
 *
 * @param {string} userId  Revvo user ID.
 * @param {string} apiKey  Decrypted Bosta API key.
 * @param {boolean} isIncremental  If true, only sync recent deliveries.
 * @param {number} maxPages  Max search pages to process.
 * @param {number} startPage  Page to resume from (1-based).
 * @param {number} timeoutMs  CF timeout in ms (default 540_000).
 * @param {string} [dateFrom]  Optional YYYY-MM-DD start date filter.
 * @param {string} [dateTo]    Optional YYYY-MM-DD end date filter.
 * @return {Promise<SyncResult>} Sync summary.
 */
async function syncForUser(
  userId: string,
  apiKey: string,
  isIncremental: boolean,
  maxPages: number,
  startPage: number = 1,
  timeoutMs: number = 540_000,
  inDateFrom?: string,
  dateTo?: string,
): Promise<SyncResult> {
  const db = getDb();
  const startTime = Date.now();
  const deadline = startTime + timeoutMs - TIMEOUT_BUFFER_MS;
  let dateFrom = inDateFrom;

  const result: SyncResult = {
    totalChecked: 0,
    cataloged: 0,
    newExpenses: 0,
    awaitingSettlement: 0,
    alreadyRecorded: 0,
    errors: 0,
    matchedToSale: 0,
    unlinked: 0,
    complete: false,
    resumePage: 0,
    elapsedMs: 0,
  };

  /** Checks if we should stop to save progress. */
  const isTimedOut = () => Date.now() >= deadline;

  /** Settlement tracking for progress. */
  let settlementTotal = 0;
  let settlementDone = 0;

  /** Update sync_progress in connection doc. */
  let lastProgressUpdate = 0;
  const updateProgress = async (
    phase: string, currentPage: number, totalPages: number,
  ) => {
    const now = Date.now();
    // Throttle updates to every 100 items or 2 seconds, except for phase boundaries
    if (result.totalChecked - lastProgressUpdate < PROGRESS_UPDATE_INTERVAL &&
        phase !== "done" && phase !== "settlement" && phase !== "stats") return;
    lastProgressUpdate = result.totalChecked;
    try {
      await db.collection("bosta_connections").doc(userId).update({
        sync_progress: {
          phase,
          current_page: currentPage,
          total_pages: totalPages || maxPages,
          processed_count: result.totalChecked,
          cataloged: result.cataloged,
          new_expenses: result.newExpenses,
          started_at: Timestamp.fromMillis(startTime),
          elapsed_ms: now - startTime,
          settlement_total: settlementTotal,
          settlement_done: settlementDone,
        },
      });
    } catch {
      // Non-critical — don't fail sync for progress update
    }
  };

  // ── Build date filter for incremental sync ────────
  /* eslint-disable @typescript-eslint/no-explicit-any */
  const searchBody: Record<string, any> = {
    page: 1,
    perPage: SEARCH_PAGE_LIMIT,
  };
  /* eslint-enable @typescript-eslint/no-explicit-any */

  // Apply date filter: explicit range > incremental fallback
  // NOTE: Bosta search API ignores date filter params (tested all formats).
  // Date filtering is done server-side after fetching results.
  // For incremental sync, we still set a conservative maxPages.
  if (!dateFrom && isIncremental) {
    // Incremental: look back 14 days worth of data
    const fromDate = new Date();
    fromDate.setDate(fromDate.getDate() - 14);
    dateFrom = fromDate.toISOString().split("T")[0];
  }

  // ── Pre-load lookup maps for fast in-memory matching ──
  const [salesLookup, existingTxnIds, connSnap] = await Promise.all([
    buildSalesLookup(db, userId),
    loadExistingTxnIds(db, userId),
    db.collection("bosta_connections").doc(userId).get(),
  ]);

  // Read running average fee for accrual estimates
  const connData = connSnap.data();
  const averageBostaFee = Number(connData?.average_bosta_fee) || 0;
  const estimatedFeePerShipment = averageBostaFee > 0
    ? round2(averageBostaFee)
    : DEFAULT_ESTIMATED_FEE;

  logger.info("Pre-loaded lookup maps", {
    userId,
    salesCount: salesLookup.byOrderNumber.size,
    txnCount: existingTxnIds.size,
    averageBostaFee,
    estimatedFeePerShipment,
  });

  // Track already-processed to avoid Phase 0 / Phase 2 overlap
  const processedTrackingNumbers = new Set<string>();

  // Collect estimate entries from Phase 1 for batch writing
  const newEstimates: EstimateEntry[] = [];

  // ── Phase 0: Re-check awaiting settlement (always) ──
  // Queries Firestore directly — no Bosta API calls, very fast.
  // Skips shipments checked within SETTLEMENT_RECHECK_MS.
  if (!isTimedOut()) {
    await recheckAwaitingSettlement(
      db, userId, apiKey, result, deadline,
      salesLookup, existingTxnIds, processedTrackingNumbers,
    );
  }

  // ── Phase 1: CATALOG — fast search scan ──────────────
  // Collect deliveries that need settlement processing.
  const needsProcessing: CatalogEntry[] = [];
  let lastPage = startPage;

  // Server-side date cutoff: Bosta API ignores date filters,
  // but results are ordered newest-first. Stop when we pass dateFrom.
  const dateFromCutoff = dateFrom ? new Date(dateFrom).getTime() : 0;
  const dateToCutoff = dateTo ? new Date(dateTo).getTime() + 86400000 : 0; // end of day
  let reachedDateCutoff = false;
  let consecutiveAllExistingPages = 0;
  const EARLY_EXIT_PAGES = 5; // Stop re-sync after N consecutive all-existing pages

  await updateProgress("catalog", startPage, maxPages);

  for (let page = startPage; page <= maxPages; page++) {
    if (isTimedOut()) {
      result.resumePage = page;
      logger.info("Catalog phase timeout, saving resume", {
        userId, page, totalChecked: result.totalChecked,
      });
      break;
    }

    searchBody.page = page;
    lastPage = page;

    let searchResult: ApiResult;
    try {
      searchResult = await bostaFetch(
        `${BOSTA_API_BASE}/deliveries/search`,
        {
          method: "POST",
          headers: bostaHeaders(apiKey),
          body: JSON.stringify(searchBody),
        },
      );
    } catch (err) {
      logger.error("Bosta search failed", {userId, page, error: String(err)});
      result.errors++;
      break;
    }

    const deliveries = searchResult.deliveries as ApiResult[] | undefined;
    if (!deliveries || deliveries.length === 0) break;

    // Extract catalog entries from search response
    const entries: CatalogEntry[] = deliveries.map((d) => ({
      trackingNumber: (d.trackingNumber as string) || "",
      bostaDeliveryId: (d._id as string) || "",
      state: Number(d.state?.code) || 0,
      stateValue: (d.state?.value as string) || "",
      type: (d.type?.value as string) || "",
      businessReference: (d.businessReference as string) || null,
      cod: Number(d.cod) || 0,
      createdAt: (d.createdAt as string) || null,
    })).filter((e) => e.trackingNumber);

    // Server-side date filtering (Bosta API ignores date params).
    // Results are newest-first, so when oldest entry on this page
    // is before dateFrom, we stop after processing in-range items.
    let filteredEntries = entries;
    if (dateFromCutoff || dateToCutoff) {
      filteredEntries = entries.filter((e) => {
        if (!e.createdAt) return true; // include if no date
        const ts = new Date(e.createdAt).getTime();
        if (dateFromCutoff && ts < dateFromCutoff) return false;
        if (dateToCutoff && ts > dateToCutoff) return false;
        return true;
      });
      // Check if oldest delivery on page is before dateFrom
      if (dateFromCutoff && entries.length > 0) {
        const oldestEntry = entries[entries.length - 1];
        const oldestTs = oldestEntry.createdAt ?
          new Date(oldestEntry.createdAt).getTime() : Infinity;
        if (oldestTs < dateFromCutoff) {
          reachedDateCutoff = true;
        }
      }
    }

    result.totalChecked += filteredEntries.length;

    // Batch-check which already exist as fully processed
    const docIds = filteredEntries.map(
      (e) => e.bostaDeliveryId || e.trackingNumber
    );
    const docRefs = docIds.map(
      (id) => db.collection("bosta_shipments").doc(id)
    );

    const existingDocs = docRefs.length > 0 ?
      await db.getAll(...docRefs) : [];

    const alreadyProcessedIds = new Set<string>();
    const existingAwaitingIds = new Set<string>();
    for (const doc of existingDocs) {
      if (!doc.exists) continue;
      const data = doc.data();
      if (data?.expense_recorded) {
        alreadyProcessedIds.add(doc.id);
      } else if (data?.awaiting_settlement) {
        existingAwaitingIds.add(doc.id);
      }
    }

    // Batch-write basic info for NEW deliveries (no GET needed)
    const batch = db.batch();
    let batchCount = 0;
    let pageNewItems = 0;

    for (const entry of filteredEntries) {
      const docId = entry.bostaDeliveryId || entry.trackingNumber;
      if (alreadyProcessedIds.has(docId)) {
        result.alreadyRecorded++;
        continue;
      }

      // Already awaiting — will be handled in Phase 2
      if (existingAwaitingIds.has(docId)) {
        // Terminal states need settlement check
        if (isTerminalState(entry.state)) {
          needsProcessing.push(entry);
        }
        continue;
      }

      // New delivery — write basic info from search + accrual estimate
      const shipDocId = docId;
      const fulfillmentDate = entry.createdAt
        ? new Date(entry.createdAt).toISOString().slice(0, 10)
        : new Date().toISOString().slice(0, 10);

      // Try to match sale at catalog time (Phase 1 early matching)
      const earlyMatch = matchSaleFromBusinessReference(
        entry.businessReference, salesLookup,
      );

      batch.set(docRefs[docIds.indexOf(docId)], {
        user_id: userId,
        bosta_delivery_id: entry.bostaDeliveryId,
        tracking_number: entry.trackingNumber,
        business_reference: entry.businessReference,
        state: entry.state,
        state_value: entry.stateValue,
        type: entry.type,
        total_fees: null,
        fee_breakdown: null,
        deposited_at: null,
        awaiting_settlement: true,
        cod: entry.cod,
        expense_recorded: false,
        expense_transaction_id: null,
        matched: earlyMatch !== null,
        sale_id: earlyMatch?.saleId ?? null,
        estimated_fee: estimatedFeePerShipment,
        bosta_created_at: entry.createdAt
          ? Timestamp.fromDate(new Date(entry.createdAt))
          : FieldValue.serverTimestamp(),
        estimate_recorded: false,
        estimate_transaction_id: null,
        cashout_status: "pending",
        cashout_id: null,
        next_cashout_date: null,
        synced_at: FieldValue.serverTimestamp(),
      }, {merge: true});

      // Collect for batch estimate transaction writing
      newEstimates.push({
        shipDocId,
        estimatedFee: estimatedFeePerShipment,
        fulfillmentDateKey: fulfillmentDate,
      });
      batchCount++;
      pageNewItems++;
      result.cataloged++;

      // Terminal states also need settlement check
      if (isTerminalState(entry.state)) {
        needsProcessing.push(entry);
      }

      // Firestore batch limit is 500
      if (batchCount >= 490) {
        await batch.commit();
        batchCount = 0;
      }
    }

    if (batchCount > 0) {
      await batch.commit();
    }

    // Track consecutive all-existing pages for early exit on re-syncs
    if (pageNewItems === 0 && filteredEntries.length > 0) {
      consecutiveAllExistingPages++;
    } else {
      consecutiveAllExistingPages = 0;
    }

    // Update progress periodically
    await updateProgress("catalog", page, maxPages);

    // If fewer than page limit, we've reached the end
    if (deliveries.length < SEARCH_PAGE_LIMIT) break;

    // Stop scanning if all remaining pages are before dateFrom
    if (reachedDateCutoff) {
      logger.info("Reached date cutoff, stopping catalog scan", {
        userId, page, dateFrom,
      });
      break;
    }

    // Early exit: if N consecutive pages had only existing items, stop
    if (consecutiveAllExistingPages >= EARLY_EXIT_PAGES) {
      logger.info("Early exit: all items already exist on recent pages", {
        userId, page, consecutiveAllExistingPages,
      });
      break;
    }
  }

  logger.info("Phase 1 catalog complete", {
    userId,
    pagesScanned: lastPage - startPage + 1,
    totalChecked: result.totalChecked,
    cataloged: result.cataloged,
    alreadyRecorded: result.alreadyRecorded,
    needsProcessing: needsProcessing.length,
    newEstimates: newEstimates.length,
    reachedDateCutoff,
    elapsedMs: Date.now() - startTime,
  });

  // ── Write estimate transactions BEFORE Phase 2 ──────
  // Ensures the P&L records the expense at fulfillment date
  // before any reconciliation adjustment at settlement date.
  if (newEstimates.length > 0 && !isTimedOut()) {
    await writeDailyEstimatedTransactions(
      db, userId, newEstimates, existingTxnIds,
    );
    logger.info("Estimate transactions written", {
      userId, estimates: newEstimates.length,
    });
  }

  // If catalog phase timed out, save and return
  if (result.resumePage > 0) {
    result.elapsedMs = Date.now() - startTime;
    await updateProgress("done", lastPage, maxPages);
    return result;
  }

  // ── Phase 2: SETTLEMENT — parallel GET for unprocessed ──
  settlementTotal = needsProcessing.length;
  settlementDone = 0;
  await updateProgress("settlement", lastPage, maxPages);

  logger.info("Phase 2: settlement check", {
    userId, needsProcessing: needsProcessing.length,
  });

  // Collect all settlement data, then write daily grouped transactions
  const allSettlements: SettlementData[] = [];

  // Process in parallel batches
  for (let i = 0; i < needsProcessing.length; i += PARALLEL_BATCH_SIZE) {
    if (isTimedOut()) {
      logger.info("Settlement phase timeout", {
        userId, processed: i, total: needsProcessing.length,
      });
      break;
    }

    const batchEntries = needsProcessing.slice(i, i + PARALLEL_BATCH_SIZE)
      .filter((e) => !processedTrackingNumbers.has(e.trackingNumber));
    if (batchEntries.length === 0) continue;
    const promises = batchEntries.map((entry) =>
      fetchDeliverySettlement(
        db, userId, apiKey, entry, result, salesLookup, existingTxnIds,
      )
        .catch((err: unknown) => {
          logger.error("Failed to process delivery", {
            userId,
            trackingNumber: entry.trackingNumber,
            error: String(err),
          });
          result.errors++;
          return null;
        }),
    );

    const batchResults = await Promise.all(promises);
    for (const s of batchResults) {
      if (s) allSettlements.push(s);
    }
    settlementDone = Math.min(i + PARALLEL_BATCH_SIZE, needsProcessing.length);

    // Pace between batches
    if (i + PARALLEL_BATCH_SIZE < needsProcessing.length) {
      await new Promise((r) => setTimeout(r, BATCH_DELAY_MS));
    }

    // Update progress every batch
    await updateProgress("settlement", lastPage, maxPages);
  }

  // Write daily grouped transactions for all collected settlements
  if (allSettlements.length > 0) {
    logger.info("Phase 2: writing reconciliation transactions", {
      userId, settlements: allSettlements.length,
    });
    await writeDailyReconciliationTransactions(
      db, userId, allSettlements, result, existingTxnIds,
    );
  }

  // ── Phase 3: Compute aggregate stats ─────────────────
  if (!isTimedOut()) {
    await updateProgress("stats", lastPage, maxPages);
    await computeAndSaveStats(db, userId);
  }

  result.complete = true;
  result.elapsedMs = Date.now() - startTime;
  await updateProgress("done", lastPage, maxPages);

  return result;
}

/**
 * Returns true for terminal delivery states (delivered, returned, RTO).
 */
function isTerminalState(state: number): boolean {
  // 45=Delivered, 46=Returned, 60=RTO
  return state === 45 || state === 46 || state === 60;
}

/**
 * Re-checks shipments that were previously stored as awaiting settlement.
 * Only rechecks terminal-state deliveries (those that could have cashCycle).
 * Skips deliveries checked within SETTLEMENT_RECHECK_MS.
 * Uses parallel batching and pre-loaded lookup maps for speed.
 */
async function recheckAwaitingSettlement(
  db: FirebaseFirestore.Firestore,
  userId: string,
  apiKey: string,
  result: SyncResult,
  deadline: number,
  salesLookup: SalesLookup,
  existingTxnIds: Set<string>,
  processedTrackingNumbers: Set<string>,
): Promise<void> {
  const awaitingSnap = await db
    .collection("bosta_shipments")
    .where("user_id", "==", userId)
    .where("awaiting_settlement", "==", true)
    .get();

  if (awaitingSnap.empty) return;

  const now = Date.now();
  // Only recheck terminal-state deliveries + skip recently checked
  const entries: CatalogEntry[] = awaitingSnap.docs
    .filter((doc) => {
      const d = doc.data();
      const state = Number(d.state) || 0;
      if (!isTerminalState(state)) return false;
      // Skip if checked within recheck window
      const lastCheck = d.last_settlement_check?.toMillis?.() ?? 0;
      return (now - lastCheck) > SETTLEMENT_RECHECK_MS;
    })
    .map((doc) => {
      const d = doc.data();
      return {
        trackingNumber: (d.tracking_number as string) || "",
        bostaDeliveryId: (d.bosta_delivery_id as string) || "",
        state: Number(d.state) || 0,
        stateValue: (d.state_value as string) || "",
        type: (d.type as string) || "",
        businessReference: (d.business_reference as string) || null,
        cod: Number(d.cod) || 0,
        createdAt: null,
      };
    })
    .filter((e) => e.trackingNumber);

  logger.info("Re-checking awaiting settlement (terminal, not recently checked)", {
    userId, total: awaitingSnap.size, eligible: entries.length,
  });

  const settlements: SettlementData[] = [];

  for (let i = 0; i < entries.length; i += PARALLEL_BATCH_SIZE) {
    if (Date.now() >= deadline) break;

    const batch = entries.slice(i, i + PARALLEL_BATCH_SIZE);
    const promises = batch.map((entry) => {
      processedTrackingNumbers.add(entry.trackingNumber);
      return fetchDeliverySettlement(
        db, userId, apiKey, entry, result, salesLookup, existingTxnIds,
      )
        .catch((err: unknown) => {
          logger.error("Failed to re-check delivery", {
            userId,
            trackingNumber: entry.trackingNumber,
            error: String(err),
          });
          result.errors++;
          return null;
        });
    });

    const results = await Promise.all(promises);
    for (const s of results) {
      if (s) settlements.push(s);
    }

    if (i + PARALLEL_BATCH_SIZE < entries.length) {
      await new Promise((r) => setTimeout(r, BATCH_DELAY_MS));
    }
  }

  // Write reconciliation transactions for Phase 0 settlements
  if (settlements.length > 0) {
    await writeDailyReconciliationTransactions(db, userId, settlements, result, existingTxnIds);
  }
}

/**
 * Fetches full delivery detail and returns settlement data if settled.
 * Returns null if not yet settled (awaiting_settlement).
 * Updates shipment doc in either case.
 */
async function fetchDeliverySettlement(
  db: FirebaseFirestore.Firestore,
  userId: string,
  apiKey: string,
  entry: CatalogEntry,
  result: SyncResult,
  salesLookup: SalesLookup,
  existingTxnIds: Set<string>,
): Promise<SettlementData | null> {
  const {trackingNumber, bostaDeliveryId} = entry;

  // Validate trackingNumber format
  if (!/^[a-zA-Z0-9_-]+$/.test(trackingNumber)) {
    logger.warn("Invalid tracking number format", {trackingNumber});
    return null;
  }

  // Fetch full delivery detail (includes wallet.cashCycle)
  const detail = await bostaFetch(
    `${BOSTA_API_BASE}/deliveries/business/${encodeURIComponent(trackingNumber)}`,
    {method: "GET", headers: bostaHeaders(apiKey)},
  );

  const detailId = (detail._id as string) || bostaDeliveryId;
  const state = Number(detail.state?.code) || entry.state;
  const stateValue = (detail.state?.value as string) || entry.stateValue;
  const type = (detail.type?.value as string) || entry.type;
  const businessReference =
    (detail.businessReference as string) || entry.businessReference;
  const cod = Number(detail.cod) || entry.cod;

  const cashCycle = detail.wallet?.cashCycle as ApiResult | null | undefined;
  const bostaFees = cashCycle ? Number(cashCycle.bosta_fees) || 0 : 0;

  const shipmentDocId = detailId || trackingNumber;
  const shipmentRef = db.collection("bosta_shipments").doc(shipmentDocId);

  if (!cashCycle || bostaFees <= 0) {
    // No settlement yet — update with latest state info + mark check time
    // Still try to match sale so AR dashboard can show correct shipment status
    const noSettleMatch = matchSaleFromBusinessReference(
      businessReference, salesLookup,
    );
    await shipmentRef.set({
      user_id: userId,
      bosta_delivery_id: detailId,
      tracking_number: trackingNumber,
      business_reference: businessReference,
      state: state,
      state_value: stateValue,
      type: type,
      total_fees: null,
      fee_breakdown: null,
      deposited_at: null,
      awaiting_settlement: true,
      cod: cod,
      expense_recorded: false,
      expense_transaction_id: null,
      matched: noSettleMatch !== null,
      sale_id: noSettleMatch?.saleId ?? null,
      cashout_status: "pending",
      cashout_id: null,
      next_cashout_date: null,
      last_settlement_check: FieldValue.serverTimestamp(),
      synced_at: FieldValue.serverTimestamp(),
    }, {merge: true});
    result.awaitingSettlement++;
    return null;
  }

  // ── cashCycle has fees — extract settlement data ─────

  const feeBreakdown: Record<string, number> = {};
  for (const field of FEE_BREAKDOWN_FIELDS) {
    const val = Number(cashCycle[field]) || 0;
    if (val > 0) feeBreakdown[field] = val;
  }

  const depositDate = cashCycle.deposited_at
    ? new Date(cashCycle.deposited_at as string)
    : new Date();
  const depositedAt = Timestamp.fromDate(depositDate);

  // Extract next_cashout_date if available from cashCycle
  const nextCashoutDate = cashCycle.next_cashout_date
    ? String(cashCycle.next_cashout_date)
    : null;
  const depositDateKey = depositDate.toISOString().slice(0, 10); // YYYY-MM-DD

  // ── Try to match to Revvo sale (in-memory lookup) ────
  const saleMatch = matchSaleFromBusinessReference(
    businessReference, salesLookup,
  );
  const saleId = saleMatch?.saleId ?? null;
  const orderLabel = saleMatch?.orderLabel ?? "";
  const matched = saleId !== null;

  // ── Read accrual estimate from shipment doc ──────────
  // For reconciliation: we need the estimated_fee that was recorded
  // at catalog time, and the fulfillment date for the estimate key.
  const shipSnap = await shipmentRef.get();
  const shipData = shipSnap.data();
  // For pre-migration shipments that have no estimate: use actual fee
  // to produce a zero adjustment (no P&L impact from reconciliation).
  const estimatedFee = Number(shipData?.estimated_fee) || round2(bostaFees);
  // Fulfillment date: prefer stored bosta_created_at, fall back to
  // entry.createdAt (from GET), then deposit date as last resort.
  let fulfillmentDateKey: string;
  if (shipData?.bosta_created_at?.toDate) {
    fulfillmentDateKey = (shipData.bosta_created_at.toDate() as Date)
      .toISOString().slice(0, 10);
  } else if (detail.createdAt) {
    fulfillmentDateKey = new Date(detail.createdAt as string)
      .toISOString().slice(0, 10);
  } else {
    fulfillmentDateKey = depositDateKey;
  }

  return {
    trackingNumber,
    bostaDeliveryId: detailId,
    businessReference,
    state,
    stateValue,
    type,
    cod,
    bostaFees: round2(bostaFees),
    feeBreakdown,
    depositedAt,
    depositDateKey,
    saleId,
    matched,
    orderLabel,
    estimatedFee,
    fulfillmentDateKey,
    nextCashoutDate,
  };
}

/**
 * Groups estimate entries by fulfillment date and writes (or upserts)
 * one daily estimate transaction per date at fulfillment time.
 * Transaction IDs: bosta_est_daily_{YYYY-MM-DD}
 */
async function writeDailyEstimatedTransactions(
  db: FirebaseFirestore.Firestore,
  userId: string,
  estimates: EstimateEntry[],
  existingTxnIds: Set<string>,
): Promise<void> {
  if (estimates.length === 0) return;

  // Group by fulfillment date
  const byDate = new Map<string, EstimateEntry[]>();
  for (const e of estimates) {
    const group = byDate.get(e.fulfillmentDateKey) || [];
    group.push(e);
    byDate.set(e.fulfillmentDateKey, group);
  }

  logger.info("Writing daily estimate transactions", {
    userId, dates: byDate.size, totalEstimates: estimates.length,
  });

  for (const [dateKey, items] of byDate.entries()) {
    const estTxnId = `bosta_est_daily_${dateKey}`;
    const estTxnRef = db.collection("transactions").doc(estTxnId);
    const txnDate = Timestamp.fromDate(new Date(`${dateKey}T12:00:00Z`));
    const dailyTotal = round2(
      items.reduce((sum, e) => sum + e.estimatedFee, 0)
    );
    const shipmentCount = items.length;

    let batch = db.batch();
    let batchOps = 0;

    const commitIfNeeded = async () => {
      if (batchOps >= 490) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    };

    // Check if estimate txn already exists (from previous sync)
    const existingSnap = existingTxnIds.has(estTxnId)
      ? await estTxnRef.get()
      : null;

    if (existingSnap?.exists) {
      // Merge: add to existing estimate total
      const existingAmount = Number(existingSnap.data()?.amount) || 0;
      const existingCount =
        (existingSnap.data()?.bosta_shipment_count as number) || 0;
      batch.update(estTxnRef, {
        amount: round2(existingAmount - dailyTotal), // more negative
        bosta_shipment_count: existingCount + shipmentCount,
        note: `Bosta shipping fees (est.) — ${existingCount + shipmentCount} shipments`,
        updated_at: FieldValue.serverTimestamp(),
      });
    } else {
      batch.set(estTxnRef, {
        id: estTxnId,
        user_id: userId,
        title: `Bosta Shipping (Est.) — ${dateKey}`,
        amount: -dailyTotal,
        date_time: txnDate,
        category_id: "cat_shipping_expense",
        note: `Bosta shipping fees (est.) — ${shipmentCount} shipment${shipmentCount > 1 ? "s" : ""}`,
        payment_method: "bosta",
        sale_id: null,
        exclude_from_pl: false,
        is_estimate: true,
        is_reconciliation: false,
        bosta_shipment_count: shipmentCount,
        created_at: FieldValue.serverTimestamp(),
      });
    }
    existingTxnIds.add(estTxnId);
    batchOps++;

    // Update each shipment doc with estimate info
    for (const e of items) {
      batch.update(db.collection("bosta_shipments").doc(e.shipDocId), {
        estimate_recorded: true,
        estimate_transaction_id: estTxnId,
      });
      batchOps++;
      await commitIfNeeded();
    }

    if (batchOps > 0) {
      await batch.commit();
    }
  }
}

/**
 * Reconciliation: computes the adjustment (actual - estimated) per shipment,
 * groups by deposit date, and writes one daily reconciliation transaction.
 * If the net adjustment for a date is zero, no transaction is created.
 * Also updates the rolling average fee on the connection doc.
 *
 * Transaction IDs: bosta_rec_daily_{YYYY-MM-DD}
 */
async function writeDailyReconciliationTransactions(
  db: FirebaseFirestore.Firestore,
  userId: string,
  settlements: SettlementData[],
  result: SyncResult,
  existingTxnIds: Set<string>,
): Promise<void> {
  if (settlements.length === 0) return;

  // Group by deposit date
  const byDate = new Map<string, SettlementData[]>();
  for (const s of settlements) {
    const group = byDate.get(s.depositDateKey) || [];
    group.push(s);
    byDate.set(s.depositDateKey, group);
  }

  logger.info("Writing daily reconciliation transactions", {
    userId, dates: byDate.size, totalSettlements: settlements.length,
  });

  // Track totals for rolling average update
  let batchSettledFees = 0;
  let batchSettledCount = 0;

  for (const [dateKey, items] of byDate.entries()) {
    const recTxnId = `bosta_rec_daily_${dateKey}`;
    const recTxnRef = db.collection("transactions").doc(recTxnId);
    const txnDate = Timestamp.fromDate(new Date(`${dateKey}T12:00:00Z`));

    // Calculate adjustment per shipment: actual - estimated
    // Positive adjustment = actual was MORE than estimated (extra expense)
    // Negative adjustment = actual was LESS than estimated (credit back)
    const adjustments = items.map((s) => ({
      ...s,
      adjustment: round2(s.bostaFees - s.estimatedFee),
    }));
    const netAdjustment = round2(
      adjustments.reduce((sum, a) => sum + a.adjustment, 0)
    );

    // Track for rolling average
    batchSettledFees += items.reduce((sum, s) => sum + s.bostaFees, 0);
    batchSettledCount += items.length;

    // Firestore batch: reconciliation txn + shipment docs + sales
    let batch = db.batch();
    let batchOps = 0;

    const commitIfNeeded = async () => {
      if (batchOps >= 490) {
        await batch.commit();
        batch = db.batch();
        batchOps = 0;
      }
    };

    // Only create/update reconciliation transaction if net adjustment != 0
    if (Math.abs(netAdjustment) >= 0.01) {
      const shipmentCount = items.length;
      const existingSnap = existingTxnIds.has(recTxnId)
        ? await recTxnRef.get()
        : null;

      if (existingSnap?.exists) {
        const existingAmount = Number(existingSnap.data()?.amount) || 0;
        const existingCount =
          (existingSnap.data()?.bosta_shipment_count as number) || 0;
        batch.update(recTxnRef, {
          amount: round2(existingAmount - netAdjustment),
          bosta_shipment_count: existingCount + shipmentCount,
          note: `Bosta shipping adjustment — ${existingCount + shipmentCount} shipments`,
          updated_at: FieldValue.serverTimestamp(),
        });
      } else {
        batch.set(recTxnRef, {
          id: recTxnId,
          user_id: userId,
          title: `Bosta Shipping (Adj.) — ${dateKey}`,
          amount: -netAdjustment, // negative adj = extra expense, positive adj = credit
          date_time: txnDate,
          category_id: "cat_shipping_expense",
          note: `Bosta shipping adjustment — ${shipmentCount} shipment${shipmentCount > 1 ? "s" : ""}`,
          payment_method: "bosta",
          sale_id: null,
          exclude_from_pl: false,
          is_estimate: false,
          is_reconciliation: true,
          bosta_shipment_count: shipmentCount,
          created_at: FieldValue.serverTimestamp(),
        });
      }
      existingTxnIds.add(recTxnId);
      batchOps++;
    }

    // Update each shipment doc with settlement + reconciliation info
    for (const s of items) {
      const shipDocId = s.bostaDeliveryId || s.trackingNumber;
      const estTxnId = `bosta_est_daily_${s.fulfillmentDateKey}`;
      batch.set(db.collection("bosta_shipments").doc(shipDocId), {
        user_id: userId,
        bosta_delivery_id: s.bostaDeliveryId,
        tracking_number: s.trackingNumber,
        business_reference: s.businessReference,
        state: s.state,
        state_value: s.stateValue,
        type: s.type,
        total_fees: s.bostaFees,
        fee_breakdown: s.feeBreakdown,
        deposited_at: s.depositedAt,
        awaiting_settlement: false,
        cod: s.cod,
        expense_recorded: true,
        expense_transaction_id: estTxnId,
        estimate_transaction_id: estTxnId,
        reconciliation_transaction_id:
          Math.abs(netAdjustment) >= 0.01 ? recTxnId : null,
        reconciled: true,
        matched: s.matched,
        sale_id: s.saleId,
        cashout_status: "pending",
        cashout_id: null,
        next_cashout_date: s.nextCashoutDate || null,
        synced_at: FieldValue.serverTimestamp(),
      }, {merge: true});
      batchOps++;
      await commitIfNeeded();

      if (s.saleId) {
        batch.update(db.collection("sales").doc(s.saleId), {
          bosta_delivery_id: s.bostaDeliveryId,
          bosta_state: s.state,
          bosta_state_value: s.stateValue,
          bosta_fees: s.bostaFees,
          bosta_fee_breakdown: s.feeBreakdown,
          bosta_synced_at: FieldValue.serverTimestamp(),
          updated_at: FieldValue.serverTimestamp(),
        });
        batchOps++;
        await commitIfNeeded();
      }

      result.newExpenses++;
      if (s.matched) {
        result.matchedToSale++;
      } else {
        result.unlinked++;
      }
    }

    if (batchOps > 0) {
      await batch.commit();
    }
  }

  // Update rolling average fee on connection doc
  if (batchSettledCount > 0) {
    try {
      const connRef = db.collection("bosta_connections").doc(userId);
      const connSnap = await connRef.get();
      const connData = connSnap.data();
      const prevTotalFees = Number(connData?.total_settled_fees) || 0;
      const prevTotalCount = Number(connData?.total_settled_count) || 0;
      const newTotalFees = round2(prevTotalFees + batchSettledFees);
      const newTotalCount = prevTotalCount + batchSettledCount;
      const newAverage = round2(newTotalFees / newTotalCount);

      await connRef.update({
        average_bosta_fee: newAverage,
        total_settled_fees: newTotalFees,
        total_settled_count: newTotalCount,
      });

      logger.info("Updated rolling average Bosta fee", {
        userId, newAverage, newTotalFees, newTotalCount,
      });
    } catch (err) {
      logger.error("Failed to update rolling average", {
        userId, error: String(err),
      });
    }
  }
}

/**
 * Computes aggregate stats for a user's shipments and saves to
 * the connection doc. Uses Firestore count/sum aggregation.
 */
async function computeAndSaveStats(
  db: FirebaseFirestore.Firestore,
  userId: string,
): Promise<void> {
  try {
    const baseQuery = db.collection("bosta_shipments")
      .where("user_id", "==", userId);

    const [totalSnap, matchedSnap, settledSnap, awaitingSnap, feesSnap] =
      await Promise.all([
        baseQuery.count().get(),
        baseQuery.where("matched", "==", true).count().get(),
        baseQuery.where("expense_recorded", "==", true).count().get(),
        baseQuery.where("awaiting_settlement", "==", true).count().get(),
        baseQuery.where("expense_recorded", "==", true)
          .aggregate({totalFees: AggregateField.sum("total_fees")})
          .get(),
      ]);

    await db.collection("bosta_connections").doc(userId).update({
      stats: {
        total_shipments: totalSnap.data().count,
        matched_count: matchedSnap.data().count,
        unlinked_count: totalSnap.data().count - matchedSnap.data().count,
        settled_count: settledSnap.data().count,
        awaiting_count: awaitingSnap.data().count,
        total_fees: round2(feesSnap.data().totalFees as number || 0),
        computed_at: FieldValue.serverTimestamp(),
      },
    });
  } catch (err) {
    logger.error("Failed to compute stats", {userId, error: String(err)});
  }
}

// ═══════════════════════════════════════════════════════════
//  syncBostaShipments — onCall (manual trigger)
// ═══════════════════════════════════════════════════════════

export const syncBostaShipments = onCall(
  {
    secrets: [tokenEncryptionKey],
    region: "us-central1",
    timeoutSeconds: 540,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const uid = request.auth.uid;
    const db = getDb();

    // Load Bosta connection
    const connDoc = await db
      .collection("bosta_connections")
      .doc(uid)
      .get();

    if (!connDoc.exists || connDoc.data()?.status !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "No active Bosta connection"
      );
    }

    const conn = connDoc.data()!;
    const apiKey = decrypt(
      conn.api_key_encrypted as string,
      tokenEncryptionKey.value().trim(),
    );

    const isFullSync = request.data?.fullSync === true;
    const startPage = Number(request.data?.startPage) || 1;
    const dateFrom = typeof request.data?.dateFrom === "string"
      ? request.data.dateFrom : undefined;
    const dateTo = typeof request.data?.dateTo === "string"
      ? request.data.dateTo : undefined;

    logger.info("Manual Bosta sync started", {
      uid, isFullSync, startPage, dateFrom, dateTo,
    });

    const result = await syncForUser(
      uid,
      apiKey,
      !isFullSync && !dateFrom && !dateTo,
      isFullSync || dateFrom || dateTo ? MANUAL_MAX_PAGES : DAILY_MAX_PAGES,
      startPage,
      540_000,
      dateFrom,
      dateTo,
    );

    // Update connection doc with last sync time
    await db.collection("bosta_connections").doc(uid).update({
      last_sync_at: FieldValue.serverTimestamp(),
      last_sync_result: result,
    });

    // Write sync log
    await db.collection("bosta_sync_log").add({
      user_id: uid,
      trigger: "manual",
      full_sync: isFullSync,
      start_page: startPage,
      date_from: dateFrom ?? null,
      date_to: dateTo ?? null,
      result: result,
      created_at: FieldValue.serverTimestamp(),
    });

    logger.info("Manual Bosta sync completed", {uid, result});

    return result;
  },
);

// ═══════════════════════════════════════════════════════════
//  scheduledBostaSyncDaily — Scheduled (daily 02:00 UTC)
// ═══════════════════════════════════════════════════════════

export const scheduledBostaSyncDaily = onSchedule(
  {
    schedule: "59 21 * * *",
    timeZone: "UTC",
    secrets: [tokenEncryptionKey],
    region: "us-central1",
    timeoutSeconds: 540,
  },
  async () => {
    const db = getDb();

    // Load all active Bosta connections
    const connectionsSnap = await db
      .collection("bosta_connections")
      .where("status", "==", "active")
      .get();

    if (connectionsSnap.empty) {
      logger.info("No active Bosta connections, skipping scheduled sync");
      return;
    }

    for (const connDoc of connectionsSnap.docs) {
      const userId = connDoc.id;
      const conn = connDoc.data();

      // Check if auto-sync is enabled (defaults to true)
      if (conn.auto_sync_enabled === false) {
        logger.info("Auto-sync disabled, skipping", {userId});
        continue;
      }

      try {
        const apiKey = decrypt(
          conn.api_key_encrypted as string,
          tokenEncryptionKey.value().trim(),
        );

        logger.info("Scheduled Bosta sync started", {userId});
        const result = await syncForUser(
          userId, apiKey, true, DAILY_MAX_PAGES,
        );

        // Update connection doc
        await db.collection("bosta_connections").doc(userId).update({
          last_sync_at: FieldValue.serverTimestamp(),
          last_sync_result: result,
        });

        // Write sync log
        await db.collection("bosta_sync_log").add({
          user_id: userId,
          trigger: "scheduled",
          full_sync: false,
          result: result,
          created_at: FieldValue.serverTimestamp(),
        });

        logger.info("Scheduled Bosta sync completed", {userId, result});

        // ── Cashout sync (after delivery sync) ─────────────
        // Only for users with dashboard credentials configured.
        if (conn.dashboard_email_encrypted && conn.dashboard_password_encrypted) {
          try {
            const encKey = tokenEncryptionKey.value().trim();
            const dashToken = await getBostaDashboardToken(userId, encKey);

            // Fetch since last cashout sync or last 30 days
            const lastSync = conn.cf_last_cashout_sync_at?.toDate?.()
              ? (conn.cf_last_cashout_sync_at.toDate() as Date)
              : null;
            const sinceDate = lastSync
              ? new Date(lastSync.getTime() - 7 * 24 * 60 * 60 * 1000)
                  .toISOString().slice(0, 10) // overlap 7 days for safety
              : null; // null → fetches from 2025-01-01

            const cashoutResult = await syncCashoutsForUser(
              userId, dashToken, sinceDate,
            );

            logger.info("Scheduled cashout sync completed", {
              userId, cashoutResult,
            });
          } catch (cashoutErr) {
            // Cashout sync failure should NOT fail the whole sync
            logger.error("Scheduled cashout sync failed", {
              userId, error: String(cashoutErr),
            });
          }
        }
      } catch (err) {
        logger.error("Scheduled Bosta sync failed", {
          userId, error: String(err),
        });

        // Mark connection as error if auth fails
        if (String(err).includes("401")) {
          await db.collection("bosta_connections").doc(userId).update({
            status: "error",
          });
        }

        // Log the failure
        await db.collection("bosta_sync_log").add({
          user_id: userId,
          trigger: "scheduled",
          full_sync: false,
          result: {error: String(err)},
          created_at: FieldValue.serverTimestamp(),
        });
      }
    }
  },
);

// ═══════════════════════════════════════════════════════════
//  connectBosta — onCall (save encrypted API key)
// ═══════════════════════════════════════════════════════════

export const connectBosta = onCall(
  {
    secrets: [tokenEncryptionKey],
    region: "us-central1",
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const uid = request.auth.uid;

    const {apiKey, businessId} = request.data as {
      apiKey?: string;
      businessId?: string;
    };

    if (!apiKey || typeof apiKey !== "string" || apiKey.length < 10) {
      throw new HttpsError("invalid-argument", "Invalid API key");
    }

    // Test the API key first
    try {
      const testResult = await bostaFetch(
        `${BOSTA_API_BASE}/deliveries/search`,
        {
          method: "POST",
          headers: bostaHeaders(apiKey),
          body: JSON.stringify({page: 1, perPage: 50}),
        },
      );
      if (testResult.error) {
        throw new Error(testResult.error as string);
      }
    } catch (err) {
      throw new HttpsError(
        "invalid-argument",
        `Bosta API key test failed: ${String(err)}`
      );
    }

    // Encrypt and store
    const encryptedKey = encrypt(apiKey, tokenEncryptionKey.value().trim());

    await getDb().collection("bosta_connections").doc(uid).set({
      user_id: uid,
      api_key_encrypted: encryptedKey,
      bosta_business_id: businessId || null,
      status: "active",
      auto_sync_enabled: true,
      last_sync_at: null,
      connected_at: FieldValue.serverTimestamp(),
    });

    logger.info("Bosta connection saved", {uid});

    return {success: true};
  },
);

// ═══════════════════════════════════════════════════════════
//  connectBostaDashboard — onCall (save dashboard credentials)
// ═══════════════════════════════════════════════════════════

export const connectBostaDashboard = onCall(
  {
    secrets: [tokenEncryptionKey],
    region: "us-central1",
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const uid = request.auth.uid;

    const {email, password} = request.data as {
      email?: string;
      password?: string;
    };

    if (!email || typeof email !== "string" || !email.includes("@")) {
      throw new HttpsError("invalid-argument", "Invalid email");
    }
    if (!password || typeof password !== "string" || password.length < 4) {
      throw new HttpsError("invalid-argument", "Invalid password");
    }

    // Verify credentials by attempting a login
    const loginRes = await fetch(BOSTA_LOGIN_URL, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({email, password}),
    });

    if (!loginRes.ok) {
      const body = await loginRes.text().catch(() => "");
      throw new HttpsError(
        "invalid-argument",
        `Bosta dashboard login failed (${loginRes.status}): ${body.substring(0, 100)}`
      );
    }

    const loginJson = await loginRes.json() as {
      data?: {token?: string};
      token?: string;
    };

    const token = loginJson.data?.token ?? loginJson.token;
    if (!token) {
      throw new HttpsError(
        "internal",
        "Bosta login succeeded but no token returned"
      );
    }

    // Encrypt credentials
    const encKey = tokenEncryptionKey.value().trim();
    const encryptedEmail = encrypt(email, encKey);
    const encryptedPassword = encrypt(password, encKey);

    // Ensure bosta_connections doc exists
    const db = getDb();
    const connRef = db.collection("bosta_connections").doc(uid);
    const connDoc = await connRef.get();

    if (!connDoc.exists) {
      throw new HttpsError(
        "failed-precondition",
        "Connect Bosta API key first before adding dashboard credentials"
      );
    }

    // Store encrypted dashboard credentials
    await connRef.update({
      dashboard_email_encrypted: encryptedEmail,
      dashboard_password_encrypted: encryptedPassword,
      dashboard_status: "active",
      dashboard_status_updated_at: FieldValue.serverTimestamp(),
    });

    logger.info("Bosta dashboard credentials saved", {uid});

    return {success: true};
  },
);

// ═══════════════════════════════════════════════════════════
//  syncBostaCashouts — onCall (on-demand cashout sync)
// ═══════════════════════════════════════════════════════════

export const syncBostaCashouts = onCall(
  {
    secrets: [tokenEncryptionKey],
    region: "us-central1",
    timeoutSeconds: 120,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const uid = request.auth.uid;
    const db = getDb();

    // Optional: caller can supply a custom date range.
    const {startDate: reqStart} = (request.data ?? {}) as {
      startDate?: string;
    };
    const hasCustomRange = typeof reqStart === "string" && reqStart.length >= 10;

    // Load connection
    const connDoc = await db
      .collection("bosta_connections")
      .doc(uid)
      .get();

    if (!connDoc.exists || connDoc.data()?.status !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "No active Bosta connection"
      );
    }

    const conn = connDoc.data()!;

    if (!conn.dashboard_email_encrypted || !conn.dashboard_password_encrypted) {
      throw new HttpsError(
        "failed-precondition",
        "No dashboard credentials configured"
      );
    }

    // Throttle: skip if synced < 5 minutes ago (bypass for custom range).
    const lastSync = conn.cf_last_cashout_sync_at?.toDate?.()
      ? (conn.cf_last_cashout_sync_at.toDate() as Date)
      : null;

    if (!hasCustomRange && lastSync && (Date.now() - lastSync.getTime()) < CASHOUT_SYNC_THROTTLE_MS) {
      logger.info("Cashout sync throttled — returning cached", {uid});
      return {
        throttled: true,
        cfTotalCashouts: conn.cf_total_cashouts ?? 0,
        cfPendingAr: conn.cf_pending_ar ?? 0,
        cfPendingArCount: conn.cf_pending_ar_count ?? 0,
        cfLastCashoutDate: conn.cf_last_cashout_date ?? null,
      };
    }

    // Login to dashboard
    const encKey = tokenEncryptionKey.value().trim();
    let dashToken: string;
    try {
      dashToken = await getBostaDashboardToken(uid, encKey);
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      const msg = err instanceof Error ? err.message : String(err);
      logger.error("Dashboard login failed in syncBostaCashouts", {uid, error: msg});
      throw new HttpsError(
        "unavailable",
        msg.includes("login failed") ? "Dashboard login failed — please re-authenticate" : msg,
      );
    }

    // Determine date range.
    let sinceDate: string | null;
    if (hasCustomRange) {
      sinceDate = reqStart!.slice(0, 10); // YYYY-MM-DD
    } else if (lastSync) {
      sinceDate = new Date(lastSync.getTime() - 7 * 24 * 60 * 60 * 1000)
        .toISOString().slice(0, 10);
    } else {
      sinceDate = null; // Falls back to 2025-01-01 inside syncCashoutsForUser.
    }

    let result: CashoutSyncResult;
    try {
      result = await syncCashoutsForUser(uid, dashToken, sinceDate);
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      const msg = err instanceof Error ? err.message : String(err);
      logger.error("syncCashoutsForUser failed", {uid, error: msg});
      throw new HttpsError("internal", `Cashout sync failed: ${msg}`);
    }

    logger.info("On-demand cashout sync completed", {uid, result});

    return result;
  },
);

// ═══════════════════════════════════════════════════════════
//  disconnectBosta — onCall
// ═══════════════════════════════════════════════════════════

export const disconnectBosta = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const uid = request.auth.uid;

    await getDb().collection("bosta_connections").doc(uid).update({
      status: "disconnected",
      api_key_encrypted: FieldValue.delete(),
    });

    logger.info("Bosta connection disconnected", {uid});

    return {success: true};
  },
);

// ═══════════════════════════════════════════════════════════
//  migrateBostaToDaily — onCall (one-time migration)
//  Consolidates individual bosta_fee_* transactions into
//  daily bosta_daily_YYYY-MM-DD grouped transactions.
// ═══════════════════════════════════════════════════════════

export const migrateBostaToDaily = onCall(
  {
    region: "us-central1",
    timeoutSeconds: 540,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const uid = request.auth.uid;
    const db = getDb();

    // Find all old-style individual bosta transactions
    const oldTxnSnap = await db.collection("transactions")
      .where("user_id", "==", uid)
      .where("payment_method", "==", "bosta")
      .get();

    if (oldTxnSnap.empty) {
      return {migrated: 0, dailyCreated: 0, message: "No Bosta transactions found"};
    }

    // Separate old individual txns (bosta_fee_*) from new daily txns (bosta_daily_*)
    const oldIndividualTxns = oldTxnSnap.docs.filter(
      (d) => d.id.startsWith("bosta_fee_")
    );
    const existingDailyIds = new Set(
      oldTxnSnap.docs.filter((d) => d.id.startsWith("bosta_daily_")).map((d) => d.id)
    );

    if (oldIndividualTxns.length === 0) {
      return {migrated: 0, dailyCreated: existingDailyIds.size, message: "Already migrated"};
    }

    // Group old txns by date
    const byDate = new Map<string, typeof oldIndividualTxns>();
    for (const doc of oldIndividualTxns) {
      const data = doc.data();
      const dt = data.date_time?.toDate?.() as Date | undefined;
      const dateKey = dt ? dt.toISOString().slice(0, 10) : "unknown";
      const group = byDate.get(dateKey) || [];
      group.push(doc);
      byDate.set(dateKey, group);
    }

    logger.info("Migrating Bosta transactions to daily", {
      uid, oldTxns: oldIndividualTxns.length, dates: byDate.size,
    });

    let totalMigrated = 0;
    let dailyCreated = 0;

    for (const [dateKey, txnDocs] of byDate.entries()) {
      if (dateKey === "unknown") continue;

      const dailyTxnId = `bosta_daily_${dateKey}`;
      const dailyTxnRef = db.collection("transactions").doc(dailyTxnId);

      // Sum all fees for the day
      const dailyTotal = round2(
        txnDocs.reduce((sum, d) => sum + Math.abs(Number(d.data().amount) || 0), 0)
      );
      const shipmentCount = txnDocs.length;
      const txnDate = Timestamp.fromDate(new Date(`${dateKey}T12:00:00Z`));

      // Write in batches (delete old + create daily)
      let batch = db.batch();
      let ops = 0;

      if (!existingDailyIds.has(dailyTxnId)) {
        batch.set(dailyTxnRef, {
          id: dailyTxnId,
          user_id: uid,
          title: `Bosta Shipping — ${dateKey}`,
          amount: -dailyTotal,
          date_time: txnDate,
          category_id: "cat_shipping_expense",
          note: `Bosta shipping fees — ${shipmentCount} shipment${shipmentCount > 1 ? "s" : ""}`,
          payment_method: "bosta",
          sale_id: null,
          exclude_from_pl: false,
          bosta_shipment_count: shipmentCount,
          created_at: FieldValue.serverTimestamp(),
        });
        ops++;
        dailyCreated++;
      }

      // Delete old individual transactions
      for (const doc of txnDocs) {
        batch.delete(doc.ref);
        ops++;
        if (ops >= 490) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }

      // Update shipment docs to point to daily txn
      const shipmentSnap = await db.collection("bosta_shipments")
        .where("user_id", "==", uid)
        .where("expense_transaction_id", "in",
          txnDocs.map((d) => d.id).slice(0, 30)) // Firestore 'in' limit
        .get();

      for (const shipDoc of shipmentSnap.docs) {
        batch.update(shipDoc.ref, {
          expense_transaction_id: dailyTxnId,
        });
        ops++;
        if (ops >= 490) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }

      if (ops > 0) {
        await batch.commit();
      }

      totalMigrated += txnDocs.length;
    }

    logger.info("Bosta daily migration complete", {
      uid, totalMigrated, dailyCreated,
    });

    return {
      migrated: totalMigrated,
      dailyCreated,
      message: `Consolidated ${totalMigrated} transactions into ${dailyCreated} daily entries`,
    };
  },
);
