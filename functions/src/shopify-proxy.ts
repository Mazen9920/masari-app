/**
 * Shopify API Proxy — Cloud Function (onCall)
 *
 * The Flutter app never talks to Shopify directly. Instead it calls this
 * proxy with `{ action, params }` and the proxy:
 *   1. Verifies the Firebase Auth token (automatic for onCall).
 *   2. Looks up the user's encrypted Shopify access token in Firestore.
 *   3. Decrypts the token with AES-256-GCM.
 *   4. Makes the Shopify Admin REST API request.
 *   5. Returns the JSON response to the app.
 *
 * This keeps the Shopify access token 100 % server-side.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {getFirestore} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {decrypt} from "./shopify-auth.js";

// ── Secrets ────────────────────────────────────────────────

const tokenEncryptionKey = defineSecret("SHOPIFY_TOKEN_ENCRYPTION_KEY");

// ── Constants ──────────────────────────────────────────────

const SHOPIFY_API_VERSION = "2024-01";

// Retry / rate-limit config
const MAX_RETRIES = 3;
const INITIAL_BACKOFF_MS = 1000;
// Shopify REST: 40 requests per app per store per minute (bucket leak)
const BUCKET_MAX = 40;
const BUCKET_REFILL_MS = 60_000; // 1 minute

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

// ── Rate-limit bucket (per-invocation, per-shop) ──────────

/** Simple in-memory leaky bucket for a single CF invocation. */
const rateBucket = {
  remaining: BUCKET_MAX,
  resetAt: Date.now() + BUCKET_REFILL_MS,
};

/** Wait if the bucket is depleted; auto-refills after the window. */
async function waitForBucket(): Promise<void> {
  const now = Date.now();
  if (now >= rateBucket.resetAt) {
    // Window expired — refill
    rateBucket.remaining = BUCKET_MAX;
    rateBucket.resetAt = now + BUCKET_REFILL_MS;
  }
  if (rateBucket.remaining <= 0) {
    const waitMs = rateBucket.resetAt - now;
    logger.info("Rate bucket empty, waiting", {waitMs});
    await new Promise((r) => setTimeout(r, waitMs));
    rateBucket.remaining = BUCKET_MAX;
    rateBucket.resetAt = Date.now() + BUCKET_REFILL_MS;
  }
  rateBucket.remaining--;
}

// ═══════════════════════════════════════════════════════════
//  shopifyProxy — onCall Cloud Function
// ═══════════════════════════════════════════════════════════

export const shopifyProxy = onCall(
  {
    secrets: [tokenEncryptionKey],
    region: "us-central1",
    // Allow up to 120 s for large paginated fetches
    timeoutSeconds: 120,
  },
  async (request) => {
    // ── 1. Auth check ──────────────────────────────────────
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in");
    }
    const uid = request.auth.uid;

    // ── 1b. Tier check ─────────────────────────────────────
    const userDoc = await getDb()
      .collection("users")
      .doc(uid)
      .get();
    const userTier = userDoc.data()?.subscription_tier as string | undefined;
    if (userTier !== "growth" && userTier !== "growthShopify" && userTier !== "pro") {
      throw new HttpsError(
        "permission-denied",
        "Shopify integration requires Growth plan or higher"
      );
    }

    const {action, params} = request.data as ProxyRequest;
    if (!action) {
      throw new HttpsError(
        "invalid-argument",
        "Missing required field: action"
      );
    }

    // ── 2. Look up Shopify connection ──────────────────────
    const connDoc = await getDb()
      .collection("shopify_connections")
      .doc(uid)
      .get();

    if (!connDoc.exists || connDoc.data()?.status !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "No active Shopify connection"
      );
    }

    const conn = connDoc.data();
    if (!conn) {
      throw new HttpsError(
        "failed-precondition",
        "No active Shopify connection"
      );
    }
    const shopDomain = conn.shop_domain as string;

    // Validate shop_domain format to prevent SSRF
    if (!/^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(shopDomain)) {
      throw new HttpsError(
        "failed-precondition",
        "Invalid Shopify shop domain"
      );
    }

    const encryptedToken = conn.access_token as string;
    const accessToken = decrypt(
      encryptedToken, tokenEncryptionKey.value().trim()
    );

    // ── 3. Dispatch action ─────────────────────────────────
    logger.info("Shopify proxy", {uid, action});

    switch (action) {
    case "fetchOrders":
      return await fetchOrders(
        shopDomain, accessToken, params, uid
      );
    case "updateOrder":
      return await updateOrder(
        shopDomain, accessToken, params, uid
      );
    case "cancelOrder":
      return await cancelOrder(
        shopDomain, accessToken, params, uid
      );
    case "markOrderPaid":
      return await markOrderPaid(
        shopDomain, accessToken, params, uid
      );
    case "fetchProducts":
      return await fetchProducts(
        shopDomain, accessToken, params, uid
      );
    case "updateProduct":
      return await updateProduct(
        shopDomain, accessToken, params, uid
      );
    case "updateInventoryLevel":
      return await updateInventoryLevel(
        shopDomain, accessToken, params, uid
      );
    case "getInventoryLevels":
      return await getInventoryLevels(
        shopDomain, accessToken, params, uid
      );
    case "getInventoryItems":
      return await getInventoryItems(
        shopDomain, accessToken, params, uid
      );
    case "createFulfillment":
      return await createFulfillment(
        shopDomain, accessToken, params, uid
      );
    case "fetchLocations":
      return await fetchLocations(
        shopDomain, accessToken, uid
      );
    default:
      throw new HttpsError(
        "invalid-argument",
        `Unknown action: ${action}`
      );
    }
  },
);

// ═══════════════════════════════════════════════════════════
//  Shopify Admin REST API helpers
// ═══════════════════════════════════════════════════════════

/**
 * Build the admin API base URL.
 * @param {string} shop  The shop domain.
 * @return {string} Base URL.
 */
function apiBase(shop: string): string {
  return `https://${shop}/admin/api/${SHOPIFY_API_VERSION}`;
}

/**
 * Common headers for Shopify requests.
 * @param {string} token  Decrypted access token.
 * @return {Record<string, string>} Headers object.
 */
function headers(token: string): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "X-Shopify-Access-Token": token,
  };
}

/**
 * Makes a request with exponential-backoff retry on 429 / 5xx.
 * Detects 401 → marks connection as "disconnected" in Firestore.
 * Respects rate-limit bucket.
 * @param {string} url  Full URL.
 * @param {RequestInit} init  Fetch options.
 * @param {string} uid  Firebase UID (for 401 handling).
 * @return {Promise<ApiResult>} Parsed response.
 */
async function shopifyFetch(
  url: string, init: RequestInit, uid?: string,
): Promise<ApiResult> {
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    await waitForBucket();

    const res = await fetch(url, init);

    // ── 401 — token revoked / app uninstalled ──────────
    if (res.status === 401 && uid) {
      logger.warn("Shopify 401 — marking connection disconnected", {
        uid, url,
      });
      try {
        await getDb()
          .collection("shopify_connections")
          .doc(uid)
          .update({status: "disconnected"});
      } catch (e) {
        logger.error("Failed to update connection status", {e});
      }
      throw new HttpsError(
        "unauthenticated",
        "Shopify token revoked. Please reconnect."
      );
    }

    // ── Retryable: 429 rate-limited or 5xx server error ──
    if (res.status === 429 || res.status >= 500) {
      const retryAfter = res.headers.get("retry-after");
      const backoff = retryAfter ?
        Number(retryAfter) * 1000 :
        INITIAL_BACKOFF_MS * Math.pow(2, attempt);

      lastError = new Error(
        `Shopify ${res.status} on attempt ${attempt + 1}`
      );
      logger.warn("Retryable Shopify error", {
        status: res.status, attempt, backoff, url,
      });

      if (attempt < MAX_RETRIES) {
        await new Promise((r) => setTimeout(r, backoff));
        continue;
      }
      // Exhausted retries — fall through to error
      const body = await res.text();
      throw new HttpsError(
        "unavailable",
        `Shopify API ${res.status} after ${MAX_RETRIES + 1} ` +
        `attempts: ${body.substring(0, 200)}`
      );
    }

    // ── Other non-OK status ────────────────────────────
    if (!res.ok) {
      const body = await res.text();
      logger.error("Shopify API error", {
        status: res.status, url, body,
      });
      throw new HttpsError(
        "internal",
        `Shopify API ${res.status}: ${body.substring(0, 200)}`
      );
    }

    // ── Success ────────────────────────────────────────
    if (res.status === 204) return {};
    return (await res.json()) as ApiResult;
  }

  // Should never reach here, but just in case
  throw lastError ?? new Error("shopifyFetch: unexpected exit");
}

/**
 * Like shopifyFetch but also returns the Link header for pagination.
 * @param {string} url  Full URL.
 * @param {RequestInit} init  Fetch options.
 * @param {string} uid  Firebase UID.
 * @return {Promise<object>} Object with data and nextUrl.
 */
async function shopifyFetchPaginated(
  url: string, init: RequestInit, uid: string,
): Promise<{ data: ApiResult; nextUrl: string | null }> {
  let lastError: Error | null = null;

  for (let attempt = 0; attempt <= MAX_RETRIES; attempt++) {
    await waitForBucket();

    const res = await fetch(url, init);

    if (res.status === 401 && uid) {
      logger.warn("401 — marking disconnected", {uid});
      try {
        await getDb()
          .collection("shopify_connections")
          .doc(uid)
          .update({status: "disconnected"});
      } catch (e) {
        logger.error("Failed to update status", {e});
      }
      throw new HttpsError(
        "unauthenticated",
        "Shopify token revoked. Please reconnect."
      );
    }

    if (res.status === 429 || res.status >= 500) {
      const retryAfter = res.headers.get("retry-after");
      const backoff = retryAfter ?
        Number(retryAfter) * 1000 :
        INITIAL_BACKOFF_MS * Math.pow(2, attempt);
      lastError = new Error(
        `Shopify ${res.status} attempt ${attempt + 1}`
      );
      logger.warn("Retryable error (paginated)", {
        status: res.status, attempt, backoff,
      });
      if (attempt < MAX_RETRIES) {
        await new Promise((r) => setTimeout(r, backoff));
        continue;
      }
      const body = await res.text();
      throw new HttpsError(
        "unavailable",
        `Shopify ${res.status} after retries: ` +
        body.substring(0, 200)
      );
    }

    if (!res.ok) {
      const body = await res.text();
      throw new HttpsError(
        "internal",
        `Shopify API ${res.status}: ${body.substring(0, 200)}`
      );
    }

    const nextUrl = parseLinkHeader(
      res.headers.get("link")
    );
    const data = (await res.json()) as ApiResult;
    return {data, nextUrl};
  }

  throw lastError ?? new Error("shopifyFetchPaginated: unexpected");
}

// ── fetchOrders ────────────────────────────────────────────

/**
 * GET /orders.json with optional `created_at_min`, `created_at_max`.
 * Paginates via Shopify's `Link` header.
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  Query parameters.
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Combined orders array.
 */
async function fetchOrders(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const qs = new URLSearchParams({
    status: "any",
    limit: "50",
  });
  if (params.since) {
    qs.set("created_at_min", String(params.since));
  }
  if (params.until) {
    qs.set("created_at_max", String(params.until));
  }

  let allOrders: ApiResult[] = [];
  let url: string | null =
    `${apiBase(shop)}/orders.json?${qs.toString()}`;

  // Paginate up to 10 pages (500 orders max — safety limit)
  for (let page = 0; page < 10 && url; page++) {
    const {data, nextUrl} = await shopifyFetchPaginated(
      url,
      {method: "GET", headers: headers(token)},
      uid,
    );
    const orders = (data as { orders?: ApiResult[] }).orders ?? [];
    allOrders = allOrders.concat(orders);
    url = nextUrl;
  }

  return {orders: allOrders, count: allOrders.length};
}

// ── updateOrder ────────────────────────────────────────────

/**
 * PUT /orders/{orderId}.json — partial update.
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  Must include `orderId`, `fields`.
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Updated order.
 */
async function updateOrder(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const orderId = params.orderId as string;
  const fields = params.fields as Record<string, unknown>;
  if (!orderId || !fields) {
    throw new HttpsError(
      "invalid-argument",
      "updateOrder requires orderId and fields"
    );
  }

  return shopifyFetch(
    `${apiBase(shop)}/orders/${orderId}.json`,
    {
      method: "PUT",
      headers: headers(token),
      body: JSON.stringify({order: fields}),
    },
    uid,
  );
}

// ── cancelOrder ────────────────────────────────────────────

/**
 * Cancel a Shopify order. If the order is paid, automatically issues
 * a full refund first (Shopify requires refund before cancellation
 * for paid orders).
 *
 * Flow:
 *   1. GET order → check financial_status
 *   2. If paid/partially_paid → POST refund (full amount)
 *   3. POST cancel
 *
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  Must include `orderId`.
 *   Optional: `reason` (customer|inventory|fraud|declined|other).
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Cancelled order.
 */
async function cancelOrder(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const orderId = params.orderId as string;
  if (!orderId) {
    throw new HttpsError(
      "invalid-argument",
      "cancelOrder requires orderId"
    );
  }

  const reason = (params.reason as string) || "other";
  const base = apiBase(shop);
  const hdrs = headers(token);

  // 1. Fetch current order to check financial status
  const orderResult = await shopifyFetch(
    `${base}/orders/${orderId}.json`,
    {method: "GET", headers: hdrs},
    uid,
  );

  const order = (orderResult as Record<string, unknown>)
    .order as Record<string, unknown> | undefined;
  const financialStatus = order?.financial_status as string | undefined;

  // 2. If paid → issue a full refund first
  const needsRefund =
    financialStatus === "paid" ||
    financialStatus === "partially_paid" ||
    financialStatus === "partially_refunded";

  if (needsRefund) {
    logger.info("Order is paid — issuing refund before cancel", {
      orderId, financialStatus,
    });

    // Calculate refund via Shopify's refund calculation endpoint
    const calcResult = await shopifyFetch(
      `${base}/orders/${orderId}/refunds/calculate.json`,
      {
        method: "POST",
        headers: hdrs,
        body: JSON.stringify({
          refund: {
            shipping: {full_refund: true},
            refund_line_items: ((order?.line_items as Array<Record<string, unknown>>) ?? [])
              .map((li) => ({
                line_item_id: li.id,
                quantity: Number(li.quantity) || 0,
                restock_type: "no_restock", // Masari handles stock locally
              })),
          },
        }),
      },
      uid,
    );

    const calcRefund = (calcResult as Record<string, unknown>)
      .refund as Record<string, unknown> | undefined;

    // Build the actual refund payload from the calculation response
    const transactions: Array<Record<string, unknown>> =
      (calcRefund?.transactions as Array<Record<string, unknown>>) ?? [];

    await shopifyFetch(
      `${base}/orders/${orderId}/refunds.json`,
      {
        method: "POST",
        headers: hdrs,
        body: JSON.stringify({
          refund: {
            notify: false, // Don't email the customer about the refund
            shipping: {full_refund: true},
            refund_line_items: ((order?.line_items as Array<Record<string, unknown>>) ?? [])
              .map((li) => ({
                line_item_id: li.id,
                quantity: Number(li.quantity) || 0,
                restock_type: "no_restock",
              })),
            transactions: transactions.map((t) => ({
              parent_id: t.parent_id,
              amount: t.amount,
              kind: "refund",
              gateway: t.gateway,
            })),
          },
        }),
      },
      uid,
    );

    logger.info("Refund created successfully, proceeding to cancel", {
      orderId,
    });
  }

  // 3. Cancel the order
  return shopifyFetch(
    `${base}/orders/${orderId}/cancel.json`,
    {
      method: "POST",
      headers: hdrs,
      body: JSON.stringify({reason}),
    },
    uid,
  );
}

// ── markOrderPaid ──────────────────────────────────────────

/**
 * POST /orders/{orderId}/transactions.json — create a transaction
 * to mark the order as paid on Shopify.
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  orderId, amount (optional).
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Created transaction.
 */
async function markOrderPaid(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const orderId = params.orderId as string;
  if (!orderId) {
    throw new HttpsError(
      "invalid-argument",
      "markOrderPaid requires orderId"
    );
  }

  // Fetch the current order to get the outstanding amount
  const orderData = await shopifyFetch(
    `${apiBase(shop)}/orders/${orderId}.json`,
    {method: "GET", headers: headers(token)},
    uid,
  );

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const order = (orderData as any).order;
  if (!order) {
    throw new HttpsError("not-found", "Order not found on Shopify");
  }

  const financialStatus = order.financial_status as string;
  if (financialStatus === "paid") {
    // Already paid — nothing to do
    return {order, already_paid: true};
  }

  // Calculate outstanding amount
  const totalPrice = Number(order.total_price) || 0;
  // Sum existing successful transactions
  const txnsData = await shopifyFetch(
    `${apiBase(shop)}/orders/${orderId}/transactions.json`,
    {method: "GET", headers: headers(token)},
    uid,
  );
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const txns = ((txnsData as any).transactions ?? []) as any[];
  const paidSoFar = txns
    .filter((t: Record<string, unknown>) =>
      t.kind === "capture" || t.kind === "sale")
    .filter((t: Record<string, unknown>) =>
      t.status === "success")
    .reduce((sum: number, t: Record<string, unknown>) =>
      sum + (Number(t.amount) || 0), 0);

  const outstanding = Math.max(0, totalPrice - paidSoFar);

  if (outstanding <= 0) {
    // Already fully paid via transactions
    return {order, already_paid: true};
  }

  // Create a capture transaction for the remaining amount
  const txn = {
    transaction: {
      kind: "capture",
      amount: outstanding.toFixed(2),
      currency: order.currency || "SAR",
    },
  };

  const result = await shopifyFetch(
    `${apiBase(shop)}/orders/${orderId}/transactions.json`,
    {
      method: "POST",
      headers: headers(token),
      body: JSON.stringify(txn),
    },
    uid,
  );

  return result;
}

// ── fetchProducts ──────────────────────────────────────────

/**
 * GET /products.json — returns all products with variants.
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  Optional filters.
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Products array.
 */
async function fetchProducts(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const qs = new URLSearchParams({limit: "50"});
  if (params.productIds) {
    qs.set("ids", String(params.productIds));
  }

  let allProducts: ApiResult[] = [];
  let url: string | null =
    `${apiBase(shop)}/products.json?${qs.toString()}`;

  for (let page = 0; page < 10 && url; page++) {
    const {data, nextUrl} = await shopifyFetchPaginated(
      url,
      {method: "GET", headers: headers(token)},
      uid,
    );
    const prods = (data as { products?: ApiResult[] }).products ?? [];
    allProducts = allProducts.concat(prods);
    url = nextUrl;
  }

  return {products: allProducts, count: allProducts.length};
}

// ── updateProduct ──────────────────────────────────────────

/**
 * PUT /products/{id}.json — update product title, variants (prices, SKUs).
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  productId + fields to update.
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Updated product.
 */
async function updateProduct(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const productId = params.productId as string;
  if (!productId) {
    throw new HttpsError(
      "invalid-argument",
      "updateProduct requires productId"
    );
  }

  // Build the product payload with only changed fields
  const product: Record<string, unknown> = {id: productId};

  if (params.title !== undefined) {
    product.title = params.title;
  }

  // Variant updates: array of { id, price?, sku?, compare_at_price? }
  if (Array.isArray(params.variants)) {
    product.variants = params.variants;
  }

  return shopifyFetch(
    `${apiBase(shop)}/products/${productId}.json`,
    {
      method: "PUT",
      headers: headers(token),
      body: JSON.stringify({product}),
    },
    uid,
  );
}

// ── updateInventoryLevel ───────────────────────────────────

/**
 * POST /inventory_levels/set.json — set absolute stock level.
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  inventory_item_id, location_id, qty.
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Updated inventory level.
 */
async function updateInventoryLevel(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const inventoryItemId = params.inventoryItemId as string;
  const locationId = params.locationId as string;
  const available = Number(params.available);

  if (!inventoryItemId || !locationId) {
    throw new HttpsError(
      "invalid-argument",
      "updateInventoryLevel requires inventoryItemId and locationId"
    );
  }

  return shopifyFetch(
    `${apiBase(shop)}/inventory_levels/set.json`,
    {
      method: "POST",
      headers: headers(token),
      body: JSON.stringify({
        location_id: locationId,
        inventory_item_id: inventoryItemId,
        available,
      }),
    },
    uid,
  );
}

// ── getInventoryLevels ─────────────────────────────────────

/**
 * GET /inventory_levels.json — fetch current stock for items.
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  Item/location IDs.
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Inventory levels array.
 */
async function getInventoryLevels(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const itemIds = params.inventoryItemIds as string[];
  const locationIds = params.locationIds as string[] | undefined;

  if (!itemIds || itemIds.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "getInventoryLevels requires inventoryItemIds"
    );
  }

  const qs = new URLSearchParams({
    inventory_item_ids: itemIds.join(","),
  });
  if (locationIds && locationIds.length > 0) {
    qs.set("location_ids", locationIds.join(","));
  }

  let allLevels: ApiResult[] = [];
  let url: string | null =
    `${apiBase(shop)}/inventory_levels.json?${qs.toString()}`;

  for (let page = 0; page < 10 && url; page++) {
    const {data, nextUrl} = await shopifyFetchPaginated(
      url,
      {method: "GET", headers: headers(token)},
      uid,
    );
    // eslint-disable-next-line max-len
    const levels = (data as { inventory_levels?: ApiResult[] }).inventory_levels ?? [];
    allLevels = allLevels.concat(levels);
    url = nextUrl;
  }

  return {inventory_levels: allLevels};
}

// ── getInventoryItems ───────────────────────────────────────

/**
 * GET /inventory_items.json — fetch inventory items (includes cost).
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  inventoryItemIds array.
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Inventory items array with cost.
 */
async function getInventoryItems(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const itemIds = params.inventoryItemIds as string[];

  if (!itemIds || itemIds.length === 0) {
    throw new HttpsError(
      "invalid-argument",
      "getInventoryItems requires inventoryItemIds"
    );
  }

  // Shopify allows max 100 IDs per request
  const allItems: ApiResult[] = [];
  for (let i = 0; i < itemIds.length; i += 100) {
    const batch = itemIds.slice(i, i + 100);
    const qs = new URLSearchParams({
      ids: batch.join(","),
    });
    const result = await shopifyFetch(
      `${apiBase(shop)}/inventory_items.json?${qs.toString()}`,
      {method: "GET", headers: headers(token)},
      uid,
    );
    const items =
      (result as { inventory_items?: ApiResult[] }).inventory_items ?? [];
    allItems.push(...items);
  }

  return {inventory_items: allItems};
}

// ── createFulfillment ──────────────────────────────────────

/**
 * POST /fulfillments.json — create a fulfilment (mark as shipped).
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {Record<string, unknown>} params  Order/tracking params.
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Created fulfillment.
 */
async function createFulfillment(
  shop: string,
  token: string,
  params: Record<string, unknown>,
  uid: string,
): Promise<ApiResult> {
  const orderId = params.orderId as string;
  if (!orderId) {
    throw new HttpsError(
      "invalid-argument",
      "createFulfillment requires orderId"
    );
  }

  // Build the fulfillment payload
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const fulfillment: Record<string, any> = {
    notify_customer: true,
  };

  if (params.trackingNumber) {
    fulfillment.tracking_info = {
      number: String(params.trackingNumber),
      company: params.trackingCompany ?
        String(params.trackingCompany) :
        undefined,
      url: params.trackingUrl ?
        String(params.trackingUrl) :
        undefined,
    };
  }

  if (params.lineItemIds) {
    fulfillment.line_items_by_fulfillment_order = [
      {
        fulfillment_order_id: orderId,
        fulfillment_order_line_items:
          (params.lineItemIds as string[]).map((id) => ({
            id,
            quantity: 1,
          })),
      },
    ];
  }

  return shopifyFetch(
    `${apiBase(shop)}/fulfillments.json`,
    {
      method: "POST",
      headers: headers(token),
      body: JSON.stringify({fulfillment}),
    },
    uid,
  );
}

// ── fetchLocations ─────────────────────────────────────────

/**
 * GET /locations.json — fetch all Shopify locations.
 * Returns an array of { id, name, active, primary } objects.
 * @param {string} shop  Shop domain.
 * @param {string} token  Decrypted access token.
 * @param {string} uid  Firebase UID for 401 detection.
 * @return {Promise<ApiResult>} Locations array.
 */
async function fetchLocations(
  shop: string,
  token: string,
  uid: string,
): Promise<ApiResult> {
  return shopifyFetch(
    `${apiBase(shop)}/locations.json`,
    {
      method: "GET",
      headers: headers(token),
    },
    uid,
  );
}

// ── Pagination helper ──────────────────────────────────────

/**
 * Parses Shopify's `Link` header and extracts the `rel="next"` URL.
 * @param {string | null} linkHeader  The raw Link header value.
 * @return {string | null} The next page URL, or null.
 */
function parseLinkHeader(linkHeader: string | null): string | null {
  if (!linkHeader) return null;
  const parts = linkHeader.split(",");
  for (const part of parts) {
    const match = part.match(/<([^>]+)>;\s*rel="next"/);
    if (match) return match[1];
  }
  return null;
}
