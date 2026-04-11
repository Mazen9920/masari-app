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
        matched: false,
        sale_id: null,
        estimated_fee: estimatedFeePerShipment,
        bosta_created_at: entry.createdAt
          ? Timestamp.fromDate(new Date(entry.createdAt))
          : FieldValue.serverTimestamp(),
        estimate_recorded: false,
        estimate_transaction_id: null,
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
      matched: false,
      sale_id: null,
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
  const depositDateKey = depositDate.toISOString().slice(0, 10); // YYYY-MM-DD

  // ── Try to match to Revvo sale (in-memory lookup) ────
  let saleId: string | null = null;
  let orderLabel = "";

  if (businessReference) {
    let rawRef = businessReference.trim();
    const colonHashIdx = rawRef.indexOf(":#");
    if (colonHashIdx >= 0) {
      rawRef = rawRef.substring(colonHashIdx + 2);
    } else {
      rawRef = rawRef.replace(/^#/, "");
    }

    // Strategy 1: exact match on full reference
    saleId = salesLookup.byOrderNumber.get(rawRef) ?? null;
    if (saleId) orderLabel = `#${rawRef}`;

    // Strategy 2: strip 1-4 digit prefix
    if (!saleId && rawRef.length > 4) {
      for (let prefixLen = 1; prefixLen <= 4; prefixLen++) {
        const stripped = rawRef.substring(prefixLen);
        if (stripped.length < 3) break;
        saleId = salesLookup.byOrderNumber.get(stripped) ?? null;
        if (saleId) {
          orderLabel = `#${stripped}`;
          break;
        }
      }
    }

    // Strategy 3: fallback — match by notes field
    if (!saleId) {
      saleId = salesLookup.byNotes.get(`#${rawRef} — Shopify`) ?? null;
      if (saleId) orderLabel = `#${rawRef}`;
    }
  }

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
