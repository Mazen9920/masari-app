/**
 * Bosta API Proxy — Cloud Function (onCall)
 *
 * The Flutter app never talks to Bosta directly. Instead it calls this
 * proxy with `{ action, params }` and the proxy:
 *   1. Verifies the Firebase Auth token (automatic for onCall).
 *   2. Looks up the user's encrypted Bosta API key in Firestore.
 *   3. Decrypts the key with AES-256-GCM.
 *   4. Makes the Bosta API request.
 *   5. Returns the JSON response to the app.
 *
 * This keeps the Bosta API key 100 % server-side.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getFirestore} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {decrypt} from "./shopify-auth.js";

// ── Secrets ────────────────────────────────────────────────

const tokenEncryptionKey = defineSecret("SHOPIFY_TOKEN_ENCRYPTION_KEY");

// ── Constants ──────────────────────────────────────────────

const BOSTA_API_BASE = "https://app.bosta.co/api/v2";

// Retry config
const MAX_RETRIES = 3;
const INITIAL_BACKOFF_MS = 1000;

/**
 * Lazy Firestore accessor.
 * @return {FirebaseFirestore.Firestore} The Firestore instance.
 */
function getDb() {
  return getFirestore();
}

// ── Types ──────────────────────────────────────────────────

interface ProxyRequest {
  action: string;
  params: Record<string, unknown>;
}

/* eslint-disable @typescript-eslint/no-explicit-any */
type ApiResult = Record<string, any>;
/* eslint-enable @typescript-eslint/no-explicit-any */

// ── Bosta fetch with retry ─────────────────────────────────

/**
 * Makes a request to Bosta API with exponential-backoff retry on 429 / 5xx.
 * Detects 401 → marks connection as "error" in Firestore.
 * @param {string} url  Full URL.
 * @param {RequestInit} init  Fetch options.
 * @param {string} uid  Firebase UID (for 401 handling).
 * @return {Promise<ApiResult>} Parsed response.
 */
async function bostaFetch(
  url: string, init: RequestInit, uid?: string,
): Promise<ApiResult> {
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    const res = await fetch(url, init);

    // ── 401 — API key revoked / invalid ────────────────
    if (res.status === 401 && uid) {
      logger.warn("Bosta 401 — marking connection error", {uid, url});
      try {
        await getDb()
          .collection("bosta_connections")
          .doc(uid)
          .update({status: "error"});
      } catch (e) {
        logger.error("Failed to update bosta connection status", {e});
      }
      throw new HttpsError(
        "unauthenticated",
        "Bosta API key invalid. Please reconnect."
      );
    }

    // ── Retryable: 429 rate-limited or 5xx server error ──
    if (res.status === 429 || res.status >= 500) {
      const retryAfter = res.headers.get("retry-after");
      const backoff = retryAfter
        ? Number(retryAfter) * 1000
        : INITIAL_BACKOFF_MS * Math.pow(2, attempt);

      lastError = new Error(
        `Bosta ${res.status} on attempt ${attempt + 1}`
      );
      logger.warn("Retryable Bosta error", {
        status: res.status, attempt, backoff, url,
      });

      if (attempt < MAX_RETRIES) {
        await new Promise((r) => setTimeout(r, backoff));
        continue;
      }
      const body = await res.text();
      throw new HttpsError(
        "unavailable",
        `Bosta API ${res.status} after ${MAX_RETRIES + 1} ` +
        `attempts: ${body.substring(0, 200)}`
      );
    }

    // ── Other non-OK status ────────────────────────────
    if (!res.ok) {
      const body = await res.text();
      logger.error("Bosta API error", {status: res.status, url, body});
      throw new HttpsError(
        "internal",
        `Bosta API ${res.status}: ${body.substring(0, 200)}`
      );
    }

    // ── Success ────────────────────────────────────────
    if (res.status === 204) return {};
    const json = (await res.json()) as ApiResult;
    // Bosta wraps all responses in { success, message, data: {...} }
    if (json.data && typeof json.data === "object") {
      return json.data as ApiResult;
    }
    return json;
  }

  throw lastError ?? new Error("bostaFetch: unexpected exit");
}

// ═══════════════════════════════════════════════════════════
//  bostaProxy — onCall Cloud Function
// ═══════════════════════════════════════════════════════════

export const bostaProxy = onCall(
  {
    secrets: [tokenEncryptionKey],
    region: "us-central1",
    timeoutSeconds: 120,
  },
  async (request) => {
    // ── 1. Auth check ──────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const uid = request.auth.uid;

    const {action, params} = request.data as ProxyRequest;
    if (!action) {
      throw new HttpsError(
        "invalid-argument",
        "Missing required field: action"
      );
    }

    // ── 2. Look up Bosta connection ────────────────────────
    const connDoc = await getDb()
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
    const encryptedApiKey = conn.api_key_encrypted as string;
    const apiKey = decrypt(
      encryptedApiKey, tokenEncryptionKey.value().trim()
    );

    // ── 3. Dispatch action ─────────────────────────────────
    logger.info("Bosta proxy", {uid, action});

    switch (action) {
    case "getDelivery":
      return await getDelivery(apiKey, params, uid);
    case "searchDeliveries":
      return await searchDeliveries(apiKey, params, uid);
    case "testConnection":
      return await testConnection(apiKey, uid);
    default:
      throw new HttpsError(
        "invalid-argument",
        `Unknown action: ${action}`
      );
    }
  },
);

// ═══════════════════════════════════════════════════════════
//  Bosta API action handlers
// ═══════════════════════════════════════════════════════════

/**
 * Common headers for Bosta requests.
 * @param {string} apiKey  Decrypted Bosta API key.
 * @return {Record<string, string>} Headers object.
 */
function bostaHeaders(apiKey: string): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "Authorization": apiKey,
  };
}

/**
 * GET /deliveries/business/{trackingNumber} — full delivery detail
 * including wallet.cashCycle (the source of truth for fees).
 */
async function getDelivery(
  apiKey: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const trackingNumber = params.trackingNumber as string | undefined;
  if (!trackingNumber) {
    throw new HttpsError(
      "invalid-argument",
      "Missing trackingNumber"
    );
  }

  // Validate trackingNumber format to prevent path traversal
  if (!/^[a-zA-Z0-9_-]+$/.test(trackingNumber)) {
    throw new HttpsError(
      "invalid-argument",
      "Invalid trackingNumber format"
    );
  }

  const url = `${BOSTA_API_BASE}/deliveries/business/${encodeURIComponent(trackingNumber)}`;
  return await bostaFetch(
    url,
    {method: "GET", headers: bostaHeaders(apiKey)},
    uid,
  );
}

/**
 * POST /deliveries/search — paginated search.
 * Search results do NOT include wallet.cashCycle data.
 */
async function searchDeliveries(
  apiKey: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const pageNumber = Number(params.pageNumber) || 1;
  const pageLimit = Math.min(Number(params.pageLimit) || 50, 50);

  // Build search body
  /* eslint-disable @typescript-eslint/no-explicit-any */
  const body: Record<string, any> = {
    pageNumber,
    pageLimit,
  };
  /* eslint-enable @typescript-eslint/no-explicit-any */

  if (params.state) {
    body.state = params.state;
  }
  if (params.dateFrom || params.dateTo) {
    body.date = {};
    if (params.dateFrom) body.date.from = params.dateFrom;
    if (params.dateTo) body.date.to = params.dateTo;
  }

  const url = `${BOSTA_API_BASE}/deliveries/search`;
  return await bostaFetch(
    url,
    {
      method: "POST",
      headers: bostaHeaders(apiKey),
      body: JSON.stringify(body),
    },
    uid,
  );
}

/**
 * Test connection by fetching page 1 with limit 1.
 * Returns success + business info if valid.
 */
async function testConnection(
  apiKey: string,
  uid: string,
): Promise<ApiResult> {
  const url = `${BOSTA_API_BASE}/deliveries/search`;
  const result = await bostaFetch(
    url,
    {
      method: "POST",
      headers: bostaHeaders(apiKey),
      body: JSON.stringify({pageNumber: 1, pageLimit: 1}),
    },
    uid,
  );

  return {
    success: true,
    totalCount: result.count ?? 0,
  };
}
