/**
 * Shopify Webhook Processor — Firestore-triggered Cloud Function
 *
 * Triggers on `shopify_webhook_queue/{docId}` creation and routes
 * to the correct handler based on the `topic` field.
 *
 * Handles:
 *  - orders/create   → create Revvo Sale + Revenue/COGS txns + stock
 *  - orders/updated  → update existing Sale fields (Shopify wins)
 *  - orders/cancelled → cancel sale, reverse stock & transactions
 *  - products/update → sync title, image, variants, options, prices, SKUs
 *  - products/create → auto-import new Shopify product with mappings
 *  - products/delete → unlink Revvo product, remove mappings
 *  - inventory_levels/update → update Revvo variant stock level
 */

import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {
  getFirestore,
  FieldValue,
  Timestamp,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {decrypt} from "./shopify-auth.js";
import {notifyUser} from "./notify.js";

// ── Secrets ────────────────────────────────────────────────

const tokenEncryptionKey = defineSecret("SHOPIFY_TOKEN_ENCRYPTION_KEY");

const SHOPIFY_API_VERSION = "2024-01";

// ── Helpers ────────────────────────────────────────────────

/**
 * Lazy Firestore accessor.
 * @return {FirebaseFirestore.Firestore} Firestore instance.
 */
function getDb() {
  return getFirestore();
}

// ── Cost layer helpers ─────────────────────────────────────

interface CostLayer {
  date: string;
  unit_cost: number;
  remaining_qty: number;
}

/**
 * Returns effective cost layers for a variant. If the variant has no
 * cost_layers but has stock and cost, synthesizes a single legacy layer.
 */
function effectiveCostLayers(
  variant: Record<string, unknown>,
): CostLayer[] {
  const layers = variant.cost_layers as CostLayer[] | undefined;
  if (layers && layers.length > 0) return layers;
  const stock = Number(variant.current_stock) || 0;
  const cost = Number(variant.cost_price) || 0;
  if (stock > 0 && cost > 0) {
    return [{date: "2000-01-01T00:00:00.000Z", unit_cost: cost, remaining_qty: stock}];
  }
  return [];
}

/**
 * Consumes cost layers for a given quantity using the specified method.
 * Returns { layers, unitCost } where layers is the updated array and
 * unitCost is the actual COGS per unit consumed.
 */
function consumeCostLayers(
  layers: CostLayer[],
  qty: number,
  method: string,
  fallbackCost: number,
): {layers: CostLayer[]; unitCost: number} {
  if (qty <= 0 || layers.length === 0) {
    return {layers, unitCost: fallbackCost};
  }

  if (method === "average") {
    // Proportional reduction, COGS = WAC (fallbackCost)
    const totalLayerQty = layers.reduce((s, l) => s + l.remaining_qty, 0);
    if (totalLayerQty <= 0) return {layers: [], unitCost: fallbackCost};
    const updated: CostLayer[] = [];
    // Accumulator pattern: track cumulative assigned count
    // to guarantee the sum of all takes == qty exactly.
    let cumulativeAssigned = 0;
    for (let idx = 0; idx < layers.length; idx++) {
      const layer = layers[idx];
      const isLast = idx === layers.length - 1;
      const take = isLast
        ? Math.min(qty - cumulativeAssigned, layer.remaining_qty)
        : Math.min(
            Math.round(layer.remaining_qty * qty / totalLayerQty),
            layer.remaining_qty,
          );
      cumulativeAssigned += take;
      const newQty = layer.remaining_qty - take;
      if (newQty > 0) updated.push({...layer, remaining_qty: newQty});
    }
    return {layers: updated, unitCost: fallbackCost};
  }

  // FIFO or LIFO
  const sorted = [...layers];
  if (method === "lifo") {
    sorted.sort((a, b) => b.date.localeCompare(a.date));
  } else {
    sorted.sort((a, b) => a.date.localeCompare(b.date));
  }

  let remaining = qty;
  let totalCost = 0;
  const updated: CostLayer[] = [];
  for (const layer of sorted) {
    if (remaining <= 0) {
      updated.push(layer);
      continue;
    }
    const take = Math.min(remaining, layer.remaining_qty);
    totalCost += take * layer.unit_cost;
    remaining -= take;
    const newQty = layer.remaining_qty - take;
    if (newQty > 0) updated.push({...layer, remaining_qty: newQty});
  }
  if (remaining > 0) totalCost += remaining * fallbackCost;

  const unitCost = qty > 0
    ? Math.round(totalCost / qty * 100) / 100
    : fallbackCost;
  return {layers: updated, unitCost};
}

/**
 * Recalculates weighted-average cost from remaining layers.
 */
function wacFromLayers(
  layers: CostLayer[],
  fallbackCost: number,
): number {
  const totalQty = layers.reduce((s, l) => s + l.remaining_qty, 0);
  if (totalQty <= 0) return fallbackCost;
  const totalValue = layers.reduce(
    (s, l) => s + l.remaining_qty * l.unit_cost, 0,
  );
  return Math.round(totalValue / totalQty * 100) / 100;
}

/**
 * Reads the user's valuation method from their Firestore user doc.
 * Falls back to 'fifo' if not set.
 */
async function getUserValuationMethod(
  db: FirebaseFirestore.Firestore,
  userId: string,
): Promise<string> {
  try {
    const userDoc = await db.collection("users").doc(userId).get();
    if (userDoc.exists) {
      return (userDoc.data()?.valuation_method as string) || "fifo";
    }
  } catch (err) {
    logger.warn("Failed to read valuation method, defaulting to fifo", {
      userId, error: String(err),
    });
  }
  return "fifo";
}


// ── Type helpers for Shopify payloads ──────────────────────

/* eslint-disable @typescript-eslint/no-explicit-any */
type ShopifyOrder = Record<string, any>;
type ShopifyLineItem = Record<string, any>;
type ShopifyProduct = Record<string, any>;
type InventoryLevel = Record<string, any>;
/* eslint-enable @typescript-eslint/no-explicit-any */

// ── Shopify API cost fetch ─────────────────────────────────

/**
 * Batch-fetches inventory item costs from Shopify REST API.
 * @param {string} shopDomain  Shopify shop domain.
 * @param {string} accessToken  Decrypted Shopify access token.
 * @param {string[]} inventoryItemIds  IDs to fetch.
 * @return {Promise<Map<string, number>>} Map of invItemId → cost.
 */
async function fetchShopifyInventoryItemCosts(
  shopDomain: string,
  accessToken: string,
  inventoryItemIds: string[],
): Promise<Map<string, number>> {
  const costMap = new Map<string, number>();
  if (inventoryItemIds.length === 0) return costMap;

  try {
    // Shopify allows max 100 IDs per request
    for (let i = 0; i < inventoryItemIds.length; i += 100) {
      const batch = inventoryItemIds.slice(i, i + 100);
      const qs = new URLSearchParams({ids: batch.join(",")});
      const url =
        `https://${shopDomain}/admin/api/${SHOPIFY_API_VERSION}` +
        `/inventory_items.json?${qs.toString()}`;
      const res = await fetch(url, {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
          "X-Shopify-Access-Token": accessToken,
        },
      });
      if (!res.ok) continue;
      const data = await res.json() as {
        inventory_items?: Array<{id: number; cost: string | null}>;
      };
      for (const item of data.inventory_items ?? []) {
        const cost = Number(item.cost) || 0;
        if (cost > 0) {
          costMap.set(String(item.id), cost);
        }
      }
    }
  } catch (e) {
    logger.warn("Failed to fetch Shopify inventory costs", {
      error: String(e),
    });
  }

  return costMap;
}

// ── Payment / Order status mapping ─────────────────────────

/**
 * Maps Shopify financial_status to Revvo PaymentStatus index.
 * @param {string} status  Shopify financial_status.
 * @return {number} PaymentStatus index (0=unpaid,1=partial,2=paid).
 */
function mapPaymentStatus(status: string | null): number {
  switch (status) {
  case "paid":
    return 2; // PaymentStatus.paid
  case "refunded":
    return 3; // PaymentStatus.refunded
  case "partially_paid":
  case "partially_refunded":
    return 1; // PaymentStatus.partial
  default: // pending, authorized, voided
    return 0; // PaymentStatus.unpaid
  }
}

/**
 * Maps Shopify fulfillment_status to Revvo FulfillmentStatus index.
 * @param {string|null} status Shopify fulfillment_status.
 * @return {number} FulfillmentStatus index (0=unfulfilled,1=partial,2=fulfilled).
 */
function mapFulfillmentStatus(status: string | null): number {
  switch (status) {
  case "fulfilled":
    return 2; // FulfillmentStatus.fulfilled
  case "partial":
    return 1; // FulfillmentStatus.partial
  default: // null = unfulfilled
    return 0; // FulfillmentStatus.unfulfilled
  }
}

/**
 * Derives Revvo OrderStatus from payment, fulfillment, and cancel state.
 * "completed" (3) only when BOTH fully paid AND fully fulfilled.
 * @param {number} paymentStatus Revvo PaymentStatus index.
 * @param {number} fulfillmentStatus Revvo FulfillmentStatus index.
 * @param {string|null} cancelReason Shopify cancel_reason.
 * @param {string|null} cancelledAt Shopify cancelled_at timestamp.
 * @return {number} OrderStatus index.
 */
function deriveOrderStatus(
  paymentStatus: number,
  fulfillmentStatus: number,
  cancelReason?: string | null,
  cancelledAt?: string | null,
): number {
  // Cancelled if cancelled_at is set OR cancel_reason indicates rejection
  if (cancelledAt || cancelReason === "declined" || cancelReason === "fraud") {
    return 4; // OrderStatus.cancelled
  }
  // Completed only when fully paid AND fully fulfilled
  if (paymentStatus === 2 && fulfillmentStatus === 2) {
    return 3; // OrderStatus.completed
  }
  // Any progress (partial payment or partial fulfillment) → processing
  if (paymentStatus >= 1 || fulfillmentStatus >= 1) {
    return 2; // OrderStatus.processing
  }
  return 1; // OrderStatus.confirmed
}

/**
 * Maps Shopify fulfillment details to a delivery status string.
 * Uses the latest fulfillment's shipment_status for granular tracking.
 * @param {string|null} fulfillmentStatus Shopify fulfillment_status.
 * @param {ShopifyOrder} order Full order payload for fulfillment details.
 * @return {string} Delivery status label.
 */
function mapDeliveryStatus(
  fulfillmentStatus: string | null,
  order?: ShopifyOrder,
): string {
  // Check latest fulfillment's shipment_status for granular status
  if (order) {
    const fulfillments = order.fulfillments ?? [];
    if (fulfillments.length > 0) {
      const latest = fulfillments[fulfillments.length - 1];
      const shipmentStatus = latest.shipment_status as string | null;
      if (shipmentStatus) {
        switch (shipmentStatus) {
        case "confirmed":
          return "confirmed";
        case "in_transit":
          return "in_transit";
        case "out_for_delivery":
          return "out_for_delivery";
        case "delivered":
          return "delivered";
        case "attempted_delivery":
          return "attempted_delivery";
        case "ready_for_pickup":
          return "ready_for_pickup";
        case "failure":
          return "delivery_failed";
        case "label_printed":
          return "label_printed";
        case "label_purchased":
          return "label_purchased";
        default:
          break;
        }
      }
      // If status is "success" on the fulfillment itself
      if (latest.status === "success" && !shipmentStatus) {
        return "shipped";
      }
    }
  }

  switch (fulfillmentStatus) {
  case "fulfilled":
    return "delivered";
  case "partial":
    return "partially_shipped";
  default:
    return "pending";
  }
}

/**
 * Round to 2 decimal places (match Revvo's roundMoney).
 * @param {number} n Value to round.
 * @return {number} Rounded value.
 */
function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * Converts an ISO-8601 string (or fallback "now") to a Firestore Timestamp.
 * Firestore Timestamps sort properly across all SDK clients.
 * @param {string|null} isoOrNow ISO date string or null/undefined.
 * @return {Timestamp} Firestore Timestamp.
 */
function toTs(isoOrNow?: string | null): Timestamp {
  if (isoOrNow) {
    try {
      return Timestamp.fromDate(new Date(isoOrNow));
    } catch (err) {
      logger.warn("Invalid ISO date, falling back to now", {
        isoOrNow, error: String(err),
      });
    }
  }
  return Timestamp.now();
}

// ═══════════════════════════════════════════════════════════
// TRIGGER — shopify_webhook_queue/{docId} onCreate
// ═══════════════════════════════════════════════════════════

export const processShopifyWebhook = onDocumentCreated(
  {
    document: "shopify_webhook_queue/{docId}",
    region: "us-central1",
    secrets: [tokenEncryptionKey],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const topic = data.topic as string;
    const userId = data.user_id as string;
    const payload = data.payload as Record<string, unknown>;
    const docRef = snap.ref;

    logger.info("Processing webhook", {topic, userId});

    try {
      switch (topic) {
      case "orders/create":
        await handleOrderCreate(userId, payload as ShopifyOrder);
        break;
      case "orders/updated":
        await handleOrderUpdated(userId, payload as ShopifyOrder);
        break;
      case "orders/cancelled":
        await handleOrderCancelled(
          userId, payload as ShopifyOrder
        );
        break;
      case "products/update":
      case "products/create":
        await handleProductUpdate(
          userId, payload as ShopifyProduct
        );
        break;
      case "products/delete":
        await handleProductDelete(
          userId, payload as ShopifyProduct
        );
        break;
      case "inventory_levels/update":
        await handleInventoryUpdate(
          userId, payload as InventoryLevel
        );
        break;
      case "app/uninstalled":
        await handleAppUninstalled(userId);
        break;
      case "customers/data_request":
        await handleCustomersDataRequest(userId, payload);
        break;
      case "customers/redact":
        await handleCustomersRedact(userId, payload);
        break;
      case "shop/redact":
        await handleShopRedact(userId, payload);
        break;
      default:
        logger.warn("Unhandled webhook topic", {topic});
      }

      // Mark as processed
      await docRef.update({
        processed_at: FieldValue.serverTimestamp(),
      });
    } catch (err) {
      logger.error("Webhook processing failed", {topic, userId, err});
      // Mark error so we can inspect / retry
      await docRef.update({
        error: String(err),
        processed_at: FieldValue.serverTimestamp(),
      });
    }
  },
);

// ═══════════════════════════════════════════════════════════
//  orders/create
// ═══════════════════════════════════════════════════════════

/**
 * Handles a new Shopify order → creates a Revvo Sale.
 * @param {string} userId Revvo user ID.
 * @param {ShopifyOrder} order Shopify order payload.
 */
async function handleOrderCreate(
  userId: string,
  order: ShopifyOrder,
): Promise<void> {
  const db = getDb();
  const shopifyOrderId = String(order.id);

  // ── Deterministic doc ID to prevent duplicates from race conditions
  // If two concurrent function executions pass the query check,
  // they'll both write to the same doc (idempotent).
  const deterministicSaleId = `shopify_${userId}_${shopifyOrderId}`;

  // ── Idempotency check: skip if already imported ────────
  const existingSaleDoc = await db
    .collection("sales")
    .doc(deterministicSaleId)
    .get();

  if (existingSaleDoc.exists) {
    logger.info("Order already imported, skipping", {shopifyOrderId});
    return;
  }

  // Also check by query in case the sale was created with a
  // non-deterministic ID (e.g. by historical import)
  const existing = await db
    .collection("sales")
    .where("user_id", "==", userId)
    .where("external_order_id", "==", shopifyOrderId)
    .limit(1)
    .get();

  if (!existing.empty) {
    logger.info("Order already imported (query match), skipping", {
      shopifyOrderId,
    });
    return;
  }

  // ── Get user's connection for sync preferences ─────────
  const connDoc = await db
    .collection("shopify_connections")
    .doc(userId)
    .get();
  const conn = connDoc.exists ? connDoc.data() : null;

  // ── Gate: ignore orders created before Shopify was connected ──
  // Webhooks (orders/create, orders/updated) may fire for old orders
  // after connecting. Only manual historical import (client-side)
  // should bring in pre-connection orders.
  const connectedAt = conn?.connected_at?.toDate?.() as Date | undefined;
  const orderCreatedAt = order.created_at ?
    new Date(order.created_at as string) : null;
  if (connectedAt && orderCreatedAt && orderCreatedAt < connectedAt) {
    logger.info("Skipping pre-connection order from webhook", {
      shopifyOrderId,
      orderCreatedAt: orderCreatedAt.toISOString(),
      connectedAt: connectedAt.toISOString(),
    });
    return;
  }

  const inventorySyncEnabled = conn?.sync_inventory_enabled === true;
  const valMethod = await getUserValuationMethod(db, userId);

  // Decrypt Shopify token for inventory cost lookups
  let shopDomain = "";
  let shopifyToken = "";
  if (conn) {
    shopDomain = (conn.shop_domain as string) || "";
    const encryptedToken = (conn.access_token as string) || "";
    if (encryptedToken) {
      try {
        shopifyToken = decrypt(
          encryptedToken, tokenEncryptionKey.value().trim()
        );
      } catch {
        logger.warn("Could not decrypt Shopify token for cost lookup");
      }
    }
  }

  // ── Map line items ─────────────────────────────────────
  const lineItems: ShopifyLineItem[] = order.line_items ?? [];
  const saleItems: Record<string, unknown>[] = [];
  let totalCogs = 0;

  for (const li of lineItems) {
    const qty = Number(li.quantity) || 1;
    const mapped = await resolveMapping(
      db, userId, li, inventorySyncEnabled, qty, valMethod,
      shopDomain, shopifyToken,
    );
    const unitPrice = Number(li.price) || 0;
    const costPrice = mapped.costPrice;
    const lineCogs = round2(qty * costPrice);
    totalCogs += lineCogs;

    const saleItem: Record<string, unknown> = {
      product_name: li.title || "Unknown",
      quantity: qty,
      unit_price: unitPrice,
      cost_price: costPrice,
      shopify_line_item_id: String(li.id),
    };
    if (mapped.productId) saleItem.product_id = mapped.productId;
    if (mapped.variantId) saleItem.variant_id = mapped.variantId;
    if (mapped.variantName) {
      saleItem.variant_name = mapped.variantName;
    }

    saleItems.push(saleItem);
  }

  // ── Build Sale document ────────────────────────────────
  const customer = order.customer ?? {};
  const shipping = order.shipping_address ?? {};
  const fulfillment = (order.fulfillments ?? [])[0];

  const subtotal = round2(
    saleItems.reduce(
      (s: number, i) =>
        s + (Number(i.quantity) * Number(i.unit_price)),
      0,
    )
  );
  const taxAmount = Number(order.total_tax) || 0;
  const discountAmount = Number(order.total_discounts) || 0;
  // Use discounted_price (net of shipping discounts) — what the customer
  // actually paid for shipping.  Falls back to price if unavailable.
  const shippingCost = round2(
    ((order.shipping_lines ?? []) as Array<Record<string, unknown>>).reduce(
      (s, sl) => s + (Number(sl.discounted_price ?? sl.price) || 0), 0,
    )
  );
  // shipping discounts are included in total_discounts but should only
  // reduce shipping revenue, not product revenue.  Subtract them out.
  const shippingDiscount = round2(
    ((order.shipping_lines ?? []) as Array<Record<string, unknown>>).reduce(
      (s, sl) => {
        const gross = Number(sl.price) || 0;
        const net = Number(sl.discounted_price ?? sl.price) || 0;
        return s + (gross - net);
      }, 0,
    )
  );
  const productDiscount = round2(discountAmount - shippingDiscount);
  const total = round2(
    subtotal + taxAmount - discountAmount + shippingCost + shippingDiscount
  );

  const paymentStatus = mapPaymentStatus(
    order.financial_status as string | null
  );
  const fulfillmentStatus = mapFulfillmentStatus(
    order.fulfillment_status as string | null
  );
  const orderStatus = deriveOrderStatus(
    paymentStatus,
    fulfillmentStatus,
    order.cancel_reason as string | null,
    order.cancelled_at as string | null,
  );

  // Build order number label for display
  const shopifyOrderNumber = String(
    order.order_number ||
    (order.name ? String(order.name).replace("#", "") : "")
  );
  const orderLabel = `#${shopifyOrderNumber} — Shopify`;

  const saleRef = db.collection("sales").doc(deterministicSaleId);
  const saleId = saleRef.id;
  const now = Timestamp.now();
  const saleDate = toTs(order.created_at as string | null);

  const saleDoc: Record<string, unknown> = {
    id: saleId,
    user_id: userId,
    customer_name: [
      customer.first_name,
      customer.last_name,
    ]
      .filter(Boolean)
      .join(" ") || null,
    customer_email: customer.email || null,
    customer_phone: customer.phone || null,
    shopify_customer_id: customer.id ? String(customer.id) : null,
    date: saleDate,
    items: saleItems,
    tax_amount: taxAmount,
    discount_amount: discountAmount,
    payment_method: (order.payment_gateway_names ?? [
    ])[0] || "Shopify",
    payment_status: paymentStatus,
    amount_paid: paymentStatus === 2 ? total : 0,
    order_status: orderStatus,
    fulfillment_status: fulfillmentStatus,
    external_order_id: shopifyOrderId,
    external_source: "shopify",
    shipping_address: [
      shipping.address1,
      shipping.city,
      shipping.country,
    ]
      .filter(Boolean)
      .join(", ") || null,
    shipping_cost: shippingCost,
    tracking_number: fulfillment?.tracking_number || null,
    delivery_status: mapDeliveryStatus(
      order.fulfillment_status as string | null,
      order,
    ),
    shopify_order_number: shopifyOrderNumber,
    notes: orderLabel,
    created_at: now,
    updated_at: now,
  };

  // ── Revenue + COGS transactions ────────────────────────
  const revId = `sale_rev_${saleId}`;
  const cogsId = `sale_cogs_${saleId}`;

  // netRevenue = subtotal − product discount only (excludes tax & shipping
  // per GAAP/IFRS).  Shipping discounts reduce shipping revenue, not this.
  const netRevenue = round2(subtotal - productDiscount);

  // Accrual accounting: revenue is recognised at point of sale,
  // regardless of payment status. Never exclude from P&L.
  const revTxn: Record<string, unknown> = {
    id: revId,
    user_id: userId,
    title: `${orderLabel}${saleDoc.customer_name ?
      ` — ${saleDoc.customer_name}` :
      ""}`,
    amount: netRevenue,
    date_time: saleDate,
    category_id: "cat_sales_revenue",
    note: orderLabel,
    payment_method: saleDoc.payment_method,
    sale_id: saleId,
    exclude_from_pl: false,
    created_at: now,
  };

  const cogsTxn: Record<string, unknown> = {
    id: cogsId,
    user_id: userId,
    title: `COGS - ${orderLabel}`,
    amount: -round2(totalCogs),
    date_time: saleDate,
    category_id: "cat_cogs",
    note: `Auto-generated from ${orderLabel}`,
    payment_method: "shopify",
    sale_id: saleId,
    exclude_from_pl: false,
    created_at: now,
  };

  // ── Atomic write: sale + transactions + stock in single transaction ──
  // All writes happen atomically — if any part fails, nothing is committed.
  // This prevents orphaned stock movements (stock deducted but sale missing)
  // and provides true idempotency against concurrent webhook deliveries.
  await db.runTransaction(async (txn) => {
    // Re-check idempotency inside transaction (atomic guard)
    const saleSnap = await txn.get(saleRef);
    if (saleSnap.exists) {
      logger.info("Order already imported (atomic check), skipping", {
        shopifyOrderId,
      });
      return;
    }

    // Read product docs for stock adjustment (inside txn for atomicity)
    const productSnapshots = new Map<
      string,
      FirebaseFirestore.DocumentSnapshot
    >();
    if (inventorySyncEnabled) {
      const uniqueProductIds = new Set<string>();
      for (const item of saleItems) {
        const pid = item.product_id as string | undefined;
        if (pid) uniqueProductIds.add(pid);
      }
      for (const pid of uniqueProductIds) {
        productSnapshots.set(
          pid,
          await txn.get(db.collection("products").doc(pid)),
        );
      }
    }

    // Write sale
    txn.set(saleRef, saleDoc);

    // Skip financial transactions for already-cancelled orders —
    // they have no P&L impact and don't need reversals.
    if (orderStatus !== 4) {
      txn.set(db.collection("transactions").doc(revId), revTxn);
      txn.set(db.collection("transactions").doc(cogsId), cogsTxn);

      // Shipping revenue transaction (customer-paid shipping = income)
      if (shippingCost > 0) {
        const shipId = `sale_ship_${saleId}`;
        txn.set(db.collection("transactions").doc(shipId), {
          id: shipId,
          user_id: userId,
          title: `Shipping — ${orderLabel}`,
          amount: round2(shippingCost),
          date_time: saleDate,
          category_id: "cat_shipping",
          note: `Auto-generated from ${orderLabel}`,
          payment_method: "shopify",
          sale_id: saleId,
          exclude_from_pl: false,
          created_at: now,
        });
      }
    }

    // Stock deduction (skip for cancelled orders — no inventory impact)
    if (inventorySyncEnabled && orderStatus !== 4) {
      applyStockInTransaction(
        txn, saleItems, productSnapshots, "deduct", valMethod,
      );
    }
  });

  // ── Sync log ───────────────────────────────────────────
  await writeSyncLog(db, userId, {
    action: "order_import",
    direction: "shopify_to_masari",
    status: "success",
    shopify_order_id: shopifyOrderId,
    masari_sale_id: saleId,
    item_count: saleItems.length,
  });

  await notifyUser(
    userId,
    "New Shopify Order",
    `Order #${shopifyOrderId} synced — ${saleItems.length} item${saleItems.length === 1 ? "" : "s"}`,
    {type: "shopify_order_created", sale_id: saleId},
    "shopify_orders"
  );

  logger.info("Order created in Revvo", {
    saleId,
    shopifyOrderId,
    items: saleItems.length,
  });
}

// ═══════════════════════════════════════════════════════════
//  orders/updated
// ═══════════════════════════════════════════════════════════

/**
 * Handles an updated Shopify order — updates changed Sale fields.
 * @param {string} userId Revvo user ID.
 * @param {ShopifyOrder} order Shopify order payload.
 */
async function handleOrderUpdated(
  userId: string,
  order: ShopifyOrder,
): Promise<void> {
  const db = getDb();
  const shopifyOrderId = String(order.id);

  // Find the existing sale
  const snap = await db
    .collection("sales")
    .where("user_id", "==", userId)
    .where("external_order_id", "==", shopifyOrderId)
    .limit(1)
    .get();

  if (snap.empty) {
    // Order not in Revvo. Only create if the order was placed AFTER
    // the shop was connected (handleOrderCreate also has this gate,
    // but checking here avoids a redundant Firestore read).
    const connDoc = await db
      .collection("shopify_connections")
      .doc(userId)
      .get();
    const connectedAt = connDoc.data()?.connected_at?.toDate?.() as
      Date | undefined;
    const orderCreatedAt = order.created_at ?
      new Date(order.created_at as string) : null;

    if (connectedAt && orderCreatedAt && orderCreatedAt < connectedAt) {
      logger.info(
        "Ignoring update for pre-connection order (not imported)",
        {shopifyOrderId,
          orderDate: orderCreatedAt.toISOString(),
          connectedAt: connectedAt.toISOString()},
      );
      return;
    }

    // Genuine out-of-order delivery: create arrived before update
    logger.warn("Order not found for update, creating", {
      shopifyOrderId,
    });
    await handleOrderCreate(userId, order);
    return;
  }

  const saleDoc = snap.docs[0];
  const saleData = saleDoc.data();
  const saleId = saleData.id as string;

  // ── Self-heal: if Revvo says cancelled but Shopify says not ──
  const cancelReason = order.cancel_reason as string | null;
  const shopifyCancelledAt = order.cancelled_at as string | null;
  const isShopifyCancelled = !!(cancelReason || shopifyCancelledAt);

  if (saleData.order_status === 4 && !isShopifyCancelled) {
    // Data corruption — Revvo was incorrectly cancelled.
    // Shopify is truth: un-cancel and continue processing updates.
    logger.warn("Self-healing: order incorrectly cancelled in Revvo, " +
      "Shopify says active. Un-cancelling.", {shopifyOrderId});
  }

  // ── Compute updated fields (Shopify wins) ──────────────
  const updates: Record<string, unknown> = {};
  const now = Timestamp.now();

  const newPaymentStatus = mapPaymentStatus(
    order.financial_status as string | null
  );
  if (saleData.payment_status !== newPaymentStatus) {
    updates.payment_status = newPaymentStatus;
  }

  // Fulfillment status (separate from order status)
  const newFulfillmentStatus = mapFulfillmentStatus(
    order.fulfillment_status as string | null
  );
  if (saleData.fulfillment_status !== newFulfillmentStatus) {
    updates.fulfillment_status = newFulfillmentStatus;
  }

  // Check for cancelled / rejected → auto-cancel
  const newOrderStatus = deriveOrderStatus(
    newPaymentStatus,
    newFulfillmentStatus,
    cancelReason,
    order.cancelled_at as string | null,
  );

  // If Shopify says cancelled (has cancel_reason or cancelled_at),
  // delegate to the full cancellation handler
  if (isShopifyCancelled && saleData.order_status !== 4) {
    logger.info("Order cancelled on Shopify (reason: " +
      `${cancelReason || "manual"})`, {shopifyOrderId});
    await handleOrderCancelled(userId, order);
    return; // handleOrderCancelled handles everything
  }

  // ── ALREADY CANCELLED — only update payment_status ─────
  // When an order is already cancelled in Revvo, we ONLY update
  // payment_status (e.g., "refunded"). We MUST NOT create refund
  // transactions, adjust stock, or modify line items — the cancel
  // handler already zeroed everything with exclude_from_pl reversals.
  // NOTE: We rely on Revvo's order_status (source of truth), NOT on
  // Shopify's cancelled_at/cancel_reason which may be absent in
  // refund-triggered orders/updated webhooks.
  if (saleData.order_status === 4) {
    if (Object.keys(updates).length > 0) {
      updates.updated_at = now;
      await saleDoc.ref.update(updates);
      logger.info("Cancelled order: payment_status updated only", {
        shopifyOrderId, saleId,
        newPaymentStatus,
        financialStatus: order.financial_status,
      });
    } else {
      logger.info("Cancelled order: no changes needed", {
        shopifyOrderId,
      });
    }
    return;
  }

  if (saleData.order_status !== newOrderStatus) {
    updates.order_status = newOrderStatus;
  }

  const newDelivery = mapDeliveryStatus(
    order.fulfillment_status as string | null,
    order,
  );
  if (saleData.delivery_status !== newDelivery) {
    updates.delivery_status = newDelivery;
  }

  // Tracking number — get from latest fulfillment
  const fulfillments = order.fulfillments ?? [];
  const latestFulfillment = fulfillments.length > 0 ?
    fulfillments[fulfillments.length - 1] : null;
  const newTracking = latestFulfillment?.tracking_number || null;
  if (newTracking && saleData.tracking_number !== newTracking) {
    updates.tracking_number = newTracking;
  }

  // Shipping address
  const shipping = order.shipping_address ?? {};
  const newAddr = [
    shipping.address1,
    shipping.city,
    shipping.country,
  ]
    .filter(Boolean)
    .join(", ") || null;
  if (newAddr && saleData.shipping_address !== newAddr) {
    updates.shipping_address = newAddr;
  }

  // Customer info
  const customer = order.customer ?? {};
  const newName = [
    customer.first_name,
    customer.last_name,
  ]
    .filter(Boolean)
    .join(" ") || null;
  if (newName && saleData.customer_name !== newName) {
    updates.customer_name = newName;
  }
  if (
    customer.email &&
    saleData.customer_email !== customer.email
  ) {
    updates.customer_email = customer.email;
  }
  if (
    customer.phone &&
    saleData.customer_phone !== customer.phone
  ) {
    updates.customer_phone = customer.phone;
  }

  // ════════════════════════════════════════════════════════
  //  LINE ITEM / FINANCIAL EDIT DETECTION
  //  Detect changes to: items, quantities, prices, discounts,
  //  shipping, and tax. Recompute COGS, revenue, inventory.
  // ════════════════════════════════════════════════════════

  // Debug: log raw Shopify financial fields for troubleshooting
  logger.info("Shopify order raw financials", {
    shopifyOrderId,
    total_tax: order.total_tax,
    total_discounts: order.total_discounts,
    total_shipping_price_set: order.total_shipping_price_set,
    shipping_lines: (order.shipping_lines ?? []).map(
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (sl: any) => ({
        title: sl.title,
        price: sl.price,
        discounted_price: sl.discounted_price,
      })
    ),
    line_items_count: (order.line_items ?? []).length,
  });
  const connDoc = await db
    .collection("shopify_connections")
    .doc(userId)
    .get();
  const conn = connDoc.exists ? connDoc.data() : null;
  const inventorySyncEnabled = conn?.sync_inventory_enabled === true;
  const valMethod = await getUserValuationMethod(db, userId);

  const shopifyLineItems: ShopifyLineItem[] =
    order.line_items ?? [];
  const oldItems =
    (saleData.items as Record<string, unknown>[]) ?? [];

  // Build a lookup of old items by shopify_line_item_id for delta COGS
  const oldItemMap = new Map<string, Record<string, unknown>>();
  for (const oi of oldItems) {
    const key = String(oi.shopify_line_item_id ?? "");
    if (key) oldItemMap.set(key, oi);
  }

  // Rebuild new items from Shopify line items, using delta-based COGS
  // to avoid re-consuming already-consumed cost layers (FIFO/LIFO).
  const newSaleItems: Record<string, unknown>[] = [];
  let newTotalCogs = 0;

  for (const li of shopifyLineItems) {
    const qty = Number(li.quantity) || 1;
    const lineItemId = String(li.id);
    const oldItem = oldItemMap.get(lineItemId);
    const oldQty = oldItem ? (Number(oldItem.quantity) || 0) : 0;
    const oldCostPrice = oldItem ? (Number(oldItem.cost_price) || 0) : 0;

    let costPrice: number;
    let lineCogs: number;
    let mappedProductId: string | undefined;
    let mappedVariantId: string | undefined;
    let mappedVariantName: string | null = null;

    if (oldItem && qty === oldQty) {
      // Unchanged quantity — keep the stored cost_price
      costPrice = oldCostPrice;
      lineCogs = round2(qty * costPrice);
      mappedProductId = oldItem.product_id as string | undefined;
      mappedVariantId = oldItem.variant_id as string | undefined;
      mappedVariantName = (li.variant_title || oldItem.variant_name || null) as string | null;
    } else if (oldItem && qty < oldQty) {
      // Quantity decreased — use stored cost_price for remaining
      costPrice = oldCostPrice;
      lineCogs = round2(qty * costPrice);
      mappedProductId = oldItem.product_id as string | undefined;
      mappedVariantId = oldItem.variant_id as string | undefined;
      mappedVariantName = (li.variant_title || oldItem.variant_name || null) as string | null;
    } else if (oldItem && qty > oldQty) {
      // Quantity increased — keep old COGS + compute delta cost
      const deltaQty = qty - oldQty;
      const deltaMapped = await resolveMapping(
        db, userId, li, inventorySyncEnabled, deltaQty, valMethod
      );
      // Total COGS = old portion + delta portion
      lineCogs = round2(oldQty * oldCostPrice + deltaQty * deltaMapped.costPrice);
      // Blended cost_price for the sale item record
      costPrice = qty > 0 ? round2(lineCogs / qty) : 0;
      mappedProductId = oldItem.product_id as string | undefined;
      mappedVariantId = oldItem.variant_id as string | undefined;
      mappedVariantName = (li.variant_title || oldItem.variant_name || null) as string | null;
    } else {
      // New item (not in old order) — compute full cost
      const mapped = await resolveMapping(
        db, userId, li, inventorySyncEnabled, qty, valMethod
      );
      costPrice = mapped.costPrice;
      lineCogs = round2(qty * costPrice);
      mappedProductId = mapped.productId ?? undefined;
      mappedVariantId = mapped.variantId ?? undefined;
      mappedVariantName = mapped.variantName;
    }

    newTotalCogs += lineCogs;

    const unitPrice = Number(li.price) || 0;

    const saleItem: Record<string, unknown> = {
      product_name: li.title || "Unknown",
      quantity: qty,
      unit_price: unitPrice,
      cost_price: costPrice,
      shopify_line_item_id: String(li.id),
    };
    if (mappedProductId) saleItem.product_id = mappedProductId;
    if (mappedVariantId) saleItem.variant_id = mappedVariantId;
    if (mappedVariantName) {
      saleItem.variant_name = mappedVariantName;
    }
    newSaleItems.push(saleItem);
  }

  // Compute new financial totals from Shopify
  const newSubtotal = round2(
    newSaleItems.reduce(
      (s, i) =>
        s + (Number(i.quantity) * Number(i.unit_price)),
      0,
    )
  );
  const newTaxAmount = Number(order.total_tax) || 0;
  const newDiscountAmount = Number(order.total_discounts) || 0;
  // Use discounted_price (net of shipping discounts)
  const newShippingCost = round2(
    ((order.shipping_lines ?? []) as Array<Record<string, unknown>>).reduce(
      (s, sl) => s + (Number(sl.discounted_price ?? sl.price) || 0), 0,
    )
  );
  const newTotal = round2(
    newSubtotal + newTaxAmount - newDiscountAmount + newShippingCost
  );

  // Fingerprint old vs new items to detect changes
  const oldItemKeys = oldItems
    .map((i: Record<string, unknown>) =>
      `${i.shopify_line_item_id}:${i.quantity}:${i.unit_price}`)
    .sort()
    .join("|");
  const newItemKeys = newSaleItems
    .map((i) =>
      `${i.shopify_line_item_id}:${i.quantity}:${i.unit_price}`)
    .sort()
    .join("|");

  // Idempotency guard: if the sale already has the same fingerprint,
  // a concurrent webhook already processed this exact edit — skip
  // item/stock changes to prevent double-adjustment.
  const storedFingerprint = saleData._item_fingerprint as string | undefined;
  const itemsChanged = oldItemKeys !== newItemKeys &&
    newItemKeys !== storedFingerprint;
  const oldTaxAmount = Number(saleData.tax_amount) || 0;
  const oldDiscountAmount = Number(saleData.discount_amount) || 0;
  const oldShippingCost = Number(saleData.shipping_cost) || 0;
  const financialsChanged =
    newTaxAmount !== oldTaxAmount ||
    newDiscountAmount !== oldDiscountAmount ||
    newShippingCost !== oldShippingCost;

  if (itemsChanged || financialsChanged) {
    logger.info("Order edit detected — syncing line items & " +
      "financials", {
      shopifyOrderId,
      itemsChanged,
      financialsChanged,
      oldItemCount: oldItems.length,
      newItemCount: newSaleItems.length,
      oldSubtotal: round2(
        oldItems.reduce(
          (s: number, i: Record<string, unknown>) =>
            s + (Number(i.quantity) * Number(i.unit_price)),
          0,
        )
      ),
      newSubtotal,
      newDiscountAmount,
      newShippingCost,
      newTaxAmount,
    });

    // Update sale items and financial fields
    updates.items = newSaleItems;
    updates.tax_amount = newTaxAmount;
    updates.discount_amount = newDiscountAmount;
    updates.shipping_cost = newShippingCost;
    // Note: _item_fingerprint is set atomically inside the stock
    // transaction below to prevent double stock adjustments.

    // ── Update Revenue transaction ──────────────────────
    const revTxnId = `sale_rev_${saleId}`;
    const revTxnSnap = await db
      .collection("transactions")
      .doc(revTxnId)
      .get();

    if (revTxnSnap.exists) {
      const revData = revTxnSnap.data()!;
      const oldRevAmount = Number(revData.amount) || 0;
      // Only update if not already cancelled/reversed.
      // Exclude shipping discounts from product revenue deduction.
      const newShippingDiscount = round2(
        ((order.shipping_lines ?? []) as Array<Record<string, unknown>>)
          .reduce((s, sl) => {
            const gross = Number(sl.price) || 0;
            const net = Number(sl.discounted_price ?? sl.price) || 0;
            return s + (gross - net);
          }, 0)
      );
      const newProductDiscount = round2(
        newDiscountAmount - newShippingDiscount
      );
      const newNetRevenue = round2(newSubtotal - newProductDiscount);
      if (!revData.exclude_from_pl && oldRevAmount !== newNetRevenue) {
        await db.collection("transactions").doc(revTxnId).update({
          amount: newNetRevenue,
          updated_at: now,
        });
        logger.info("Revenue txn updated", {
          revTxnId,
          oldAmount: oldRevAmount,
          newAmount: newNetRevenue,
        });
      }
    }

    // ── Update COGS transaction ─────────────────────────
    const cogsTxnId = `sale_cogs_${saleId}`;
    const cogsTxnSnap = await db
      .collection("transactions")
      .doc(cogsTxnId)
      .get();

    if (cogsTxnSnap.exists) {
      const cogsData = cogsTxnSnap.data()!;
      const oldCogsAmount = Number(cogsData.amount) || 0;
      const newCogsAmount = -round2(newTotalCogs);
      if (!cogsData.exclude_from_pl &&
          oldCogsAmount !== newCogsAmount) {
        await db.collection("transactions").doc(cogsTxnId).update({
          amount: newCogsAmount,
          updated_at: now,
        });
        logger.info("COGS txn updated", {
          cogsTxnId,
          oldAmount: oldCogsAmount,
          newAmount: newCogsAmount,
        });
      }
    }

    // ── Update / create / delete Shipping transaction ───
    const shipTxnId = `sale_ship_${saleId}`;
    const shipTxnSnap = await db
      .collection("transactions")
      .doc(shipTxnId)
      .get();
    const newShipAmount = round2(newShippingCost);

    if (newShippingCost > 0) {
      if (shipTxnSnap.exists) {
        const shipData = shipTxnSnap.data()!;
        const oldShipAmount = Number(shipData.amount) || 0;
        if (!shipData.exclude_from_pl && oldShipAmount !== newShipAmount) {
          await db.collection("transactions").doc(shipTxnId).update({
            amount: newShipAmount,
            updated_at: now,
          });
          logger.info("Shipping txn updated", {shipTxnId, newShipAmount});
        }
      } else {
        // Shipping added to an order that didn't have it before
        const orderNum = saleData.shopify_order_number || "";
        const label = `#${orderNum} — Shopify`;
        await db.collection("transactions").doc(shipTxnId).set({
          id: shipTxnId,
          user_id: userId,
          title: `Shipping — ${label}`,
          amount: newShipAmount,
          date_time: toTs(order.created_at as string | null),
          category_id: "cat_shipping",
          note: `Auto-generated from ${label}`,
          payment_method: "shopify",
          sale_id: saleId,
          created_at: now,
        });
        logger.info("Shipping txn created", {shipTxnId, newShipAmount});
      }
    } else if (shipTxnSnap.exists) {
      // Shipping removed from order
      await db.collection("transactions").doc(shipTxnId).delete();
      logger.info("Shipping txn deleted (shipping removed)", {shipTxnId});
    }

    // ── Adjust inventory for the delta ──────────────────
    // Wrapped in a transaction with atomic fingerprint check to prevent
    // double stock adjustments from concurrent webhooks.
    if (inventorySyncEnabled && itemsChanged) {
      // Build quantity maps: key = "productId::variantId"
      const oldQtyMap = new Map<string, number>();
      for (const item of oldItems) {
        const key = `${item.product_id}::${item.variant_id}`;
        if (item.product_id && item.variant_id) {
          oldQtyMap.set(
            key, (oldQtyMap.get(key) || 0) +
              (Number(item.quantity) || 0)
          );
        }
      }
      const newQtyMap = new Map<string, number>();
      for (const item of newSaleItems) {
        const key = `${item.product_id}::${item.variant_id}`;
        if (item.product_id && item.variant_id) {
          newQtyMap.set(
            key, (newQtyMap.get(key) || 0) +
              (Number(item.quantity) || 0)
          );
        }
      }

      // Items to restore (removed or reduced quantity)
      const restoreItems: Record<string, unknown>[] = [];
      for (const [key, oldQty] of oldQtyMap) {
        const newQty = newQtyMap.get(key) || 0;
        if (newQty < oldQty) {
          const [productId, variantId] = key.split("::");
          restoreItems.push({
            product_id: productId,
            variant_id: variantId,
            quantity: oldQty - newQty,
          });
        }
      }

      // Items to deduct (added or increased quantity)
      const deductItems: Record<string, unknown>[] = [];
      for (const [key, newQty] of newQtyMap) {
        const oldQty = oldQtyMap.get(key) || 0;
        if (newQty > oldQty) {
          const [productId, variantId] = key.split("::");
          deductItems.push({
            product_id: productId,
            variant_id: variantId,
            quantity: newQty - oldQty,
          });
        }
      }

      if (restoreItems.length > 0 || deductItems.length > 0) {
        // Atomic: re-read sale → check fingerprint → claim → adjust stock
        await db.runTransaction(async (txn) => {
          const freshSnap = await txn.get(saleDoc.ref);
          if (!freshSnap.exists) return;
          const currentFingerprint =
            freshSnap.data()!._item_fingerprint as string | undefined;

          // If fingerprint already matches, another execution handled this
          if (currentFingerprint === newItemKeys) {
            logger.info(
              "Fingerprint race: skipping duplicate stock adjustment",
              {shopifyOrderId},
            );
            return;
          }

          // Claim the fingerprint atomically
          txn.update(saleDoc.ref, {_item_fingerprint: newItemKeys});

          // Read all product docs needed for stock adjustments
          const allStockItems = [...restoreItems, ...deductItems];
          const uniquePids = new Set<string>();
          for (const it of allStockItems) {
            const pid = it.product_id as string | undefined;
            if (pid) uniquePids.add(pid);
          }
          const snapshots = new Map<
            string,
            FirebaseFirestore.DocumentSnapshot
          >();
          for (const pid of uniquePids) {
            snapshots.set(
              pid,
              await txn.get(db.collection("products").doc(pid)),
            );
          }

          if (restoreItems.length > 0) {
            applyStockInTransaction(
              txn, restoreItems, snapshots, "restore", valMethod,
              "Shopify order edited (item removed/reduced)",
            );
          }
          if (deductItems.length > 0) {
            applyStockInTransaction(
              txn, deductItems, snapshots, "deduct", valMethod,
              "Shopify order edited (item added/increased)",
            );
          }
        });

        logger.info("Inventory adjusted for order edit", {
          shopifyOrderId,
          restoredKeys: restoreItems.length,
          deductedKeys: deductItems.length,
        });
      }
    } else if (itemsChanged) {
      // Inventory sync disabled but items changed — still claim fingerprint
      await saleDoc.ref.update({_item_fingerprint: newItemKeys});
    }
  }

  // ── Amount paid — use effective total (may be updated) ─
  const effectiveTotal = (itemsChanged || financialsChanged) ?
    newTotal : round2(
      round2(
        oldItems.reduce(
          (s: number, i: Record<string, unknown>) =>
            s + (Number(i.quantity) * Number(i.unit_price)),
          0,
        )
      ) +
      (Number(saleData.tax_amount) || 0) -
      (Number(saleData.discount_amount) || 0) +
      (Number(saleData.shipping_cost) || 0)
    );

  if (newPaymentStatus === 2) {
    // Fully paid — amount_paid = total
    if (saleData.amount_paid !== effectiveTotal) {
      updates.amount_paid = effectiveTotal;
    }
  } else if (newPaymentStatus === 0) {
    // Unpaid — amount_paid = 0
    if (saleData.amount_paid !== 0) {
      updates.amount_paid = 0;
    }
  }
  // For partial (1), keep existing amount_paid — we don't know the exact
  // partial amount from Shopify's financial_status alone.

  // ── Refund handling ────────────────────────────────────
  // Process each Shopify refund individually with its own
  // idempotent transaction ID. This prevents:
  //  - Double-counting when multiple refund webhooks arrive
  //  - Collisions between partial refund #1 and #2
  //  - Duplicate stock restores
  const financialStatus = order.financial_status as string | null;
  const wasRefunded =
    financialStatus === "refunded" ||
    financialStatus === "partially_refunded";
  let refundsCreated = 0;

  if (wasRefunded) {
    const refunds: Record<string, unknown>[] =
      (order.refunds as Record<string, unknown>[]) ?? [];

    // Use the connection check that was already loaded above
    // (connDoc exists from line-item edit section)
    const invSyncForRefund = inventorySyncEnabled;
    // Get current sale items for stock matching
    // (use updated items if we just changed them, else original)
    const currentItems = (updates.items as
      Record<string, unknown>[] | undefined) ??
      (saleData.items as Record<string, unknown>[]) ?? [];

    for (const refund of refunds) {
      const shopifyRefundId = String(
        (refund as Record<string, unknown>).id || ""
      );
      if (!shopifyRefundId) continue;

      // Per-refund deterministic ID → guarantees idempotency
      const refundTxnId =
        `sale_refund_${saleId}_${shopifyRefundId}`;

      // Skip if already processed
      const existingRefund = await db
        .collection("transactions")
        .doc(refundTxnId)
        .get();
      if (existingRefund.exists) continue;

      // Sum this individual refund's monetary amount.
      // Primary source: refund_line_items (subtotal + total_tax)
      // plus order_adjustments (e.g. shipping refunds).
      // Fallback: refund.transactions (may be empty in webhooks).
      const refundLineItems = (
        refund.refund_line_items as Record<string, unknown>[]
      ) ?? [];
      let refundAmount = 0;
      let refundedQty = 0;
      for (const ri of refundLineItems) {
        refundAmount += Number(ri.subtotal) || 0;
        refundAmount += Number(ri.total_tax) || 0;
        refundedQty += Number(ri.quantity) || 0;
      }
      // Add order adjustments (shipping refunds, etc.)
      const orderAdjs = (
        refund.order_adjustments as Record<string, unknown>[]
      ) ?? [];
      for (const adj of orderAdjs) {
        refundAmount += Math.abs(Number(adj.amount) || 0);
      }
      // Fallback to refund.transactions if line items gave 0
      if (refundAmount <= 0) {
        const txns = (
          refund.transactions as Record<string, unknown>[]
        ) ?? [];
        for (const tx of txns) {
          refundAmount += Number(tx.amount) || 0;
        }
      }
      refundAmount = round2(refundAmount);
      if (refundAmount <= 0) continue;

      // Determine note
      const isFullRefund = financialStatus === "refunded";
      const refundNote = isFullRefund ?
        "Full refund from Shopify" :
        `Partial refund (${refundedQty} items)`;

      // Create the refund transaction
      await db.collection("transactions").doc(refundTxnId).set({
        id: refundTxnId,
        user_id: userId,
        title: `Refund — #${
          order.order_number || order.name || ""
        } — Shopify`,
        amount: -refundAmount,
        date_time: toTs(refund.created_at as string | null),
        category_id: "cat_sales_revenue",
        note: refundNote,
        payment_method: "shopify",
        sale_id: saleId,
        shopify_refund_id: shopifyRefundId,
        exclude_from_pl: false,
        created_at: now,
      });
      refundsCreated++;

      // Restore stock for this refund's items
      if (invSyncForRefund && refundLineItems.length > 0) {
        for (const ri of refundLineItems) {
          const liId = String(ri.line_item_id || "");
          const matched = currentItems.find(
            (si) => String(si.shopify_line_item_id) === liId
          );
          if (matched?.product_id && matched?.variant_id) {
            await adjustStockForItems(
              db, userId,
              [{
                product_id: matched.product_id,
                variant_id: matched.variant_id,
                quantity: Number(ri.quantity) || 0,
              }],
              "restore",
              `Shopify refund #${shopifyRefundId}`,
              valMethod
            );
          }
        }
      }

      logger.info("Per-refund transaction created", {
        saleId,
        shopifyRefundId,
        refundTxnId,
        refundAmount,
        refundedQty,
      });
    }
  }

  if (Object.keys(updates).length === 0 && refundsCreated === 0) {
    logger.info("No changes detected for order", {shopifyOrderId});
    return;
  }

  updates.updated_at = now;
  await saleDoc.ref.update(updates);

  await writeSyncLog(db, userId, {
    action: "order_update",
    direction: "shopify_to_masari",
    status: "success",
    shopify_order_id: shopifyOrderId,
    masari_sale_id: saleId,
    changed_fields: Object.keys(updates).join(", "),
  });

  logger.info("Order updated in Revvo", {
    saleId,
    shopifyOrderId,
    changed: Object.keys(updates),
  });
}

// ═══════════════════════════════════════════════════════════
//  orders/cancelled
// ═══════════════════════════════════════════════════════════

/**
 * Handles a cancelled Shopify order.
 * @param {string} userId Revvo user ID.
 * @param {ShopifyOrder} order Shopify order payload.
 */
async function handleOrderCancelled(
  userId: string,
  order: ShopifyOrder,
): Promise<void> {
  const db = getDb();
  const valMethod = await getUserValuationMethod(db, userId);
  const shopifyOrderId = String(order.id);

  const snap = await db
    .collection("sales")
    .where("user_id", "==", userId)
    .where("external_order_id", "==", shopifyOrderId)
    .limit(1)
    .get();

  if (snap.empty) {
    logger.warn("Order not found for cancellation", {
      shopifyOrderId,
    });
    return;
  }

  const saleDoc = snap.docs[0];
  const saleData = saleDoc.data();
  const saleId = saleData.id as string;
  const now = Timestamp.now();
  // Use the Shopify cancelled_at date for reversals so they land in the
  // same period Shopify attributes the return to (event-date attribution).
  const reversalDate = toTs(order.cancelled_at as string | null);

  // Already cancelled — idempotent guard
  if (saleData.order_status === 4) {
    logger.info("Order already cancelled, skipping", {
      saleId, shopifyOrderId,
    });
    return;
  }

  // ── Update sale status ─────────────────────────────────
  await saleDoc.ref.update({
    order_status: 4, // OrderStatus.cancelled
    fulfillment_status: mapFulfillmentStatus(
      order.fulfillment_status as string | null
    ),
    payment_status: mapPaymentStatus(
      order.financial_status as string | null
    ),
    delivery_status: "cancelled",
    updated_at: now,
  });

  // ── Mark originals as cancelled + create reversal entries ─
  // First, find any existing refund transactions so we don't
  // double-deduct amounts that were already refunded.
  const batch = db.batch();
  const txnCol = db.collection("transactions");

  // Sum already-refunded revenue amount from per-refund transactions
  const perRefundSnap = await txnCol
    .where("sale_id", "==", saleId)
    .where("category_id", "==", "cat_sales_revenue")
    .get();
  let alreadyRefundedRevenue = 0;
  let hasExistingRefunds = false;
  for (const doc of perRefundSnap.docs) {
    const docId = doc.id;
    if (docId.startsWith(`sale_refund_${saleId}_`) &&
        !doc.data().exclude_from_pl) {
      // Refund amounts are negative — sum their absolute value
      alreadyRefundedRevenue += Math.abs(Number(doc.data().amount) || 0);
      hasExistingRefunds = true;
      // Mark the refund txn as cancelled (keep visible for audit trail)
      batch.update(doc.ref, {
        title: `[Cancelled] ${doc.data().title || "Refund"}`,
        exclude_from_pl: false,
        updated_at: now,
      });
    }
  }

  // Also check legacy single-ID refund format
  const legacyRefundSnap = await txnCol
    .doc(`sale_refund_${saleId}`)
    .get();
  if (legacyRefundSnap.exists && !legacyRefundSnap.data()!.exclude_from_pl) {
    const refundData = legacyRefundSnap.data()!;
    alreadyRefundedRevenue += Math.abs(Number(refundData.amount) || 0);
    hasExistingRefunds = true;
    batch.update(legacyRefundSnap.ref, {
      title: `[Cancelled] ${refundData.title || "Refund"}`,
      exclude_from_pl: false,
      updated_at: now,
    });
  }

  const revTxnSnap = await txnCol.doc(`sale_rev_${saleId}`).get();
  const cogsTxnSnap = await txnCol.doc(`sale_cogs_${saleId}`).get();

  if (revTxnSnap.exists) {
    const revData = revTxnSnap.data()!;
    const origAmount = Number(revData.amount) || 0;

    // Mark original as cancelled (keep visible for audit trail)
    batch.update(revTxnSnap.ref, {
      title: `[Cancelled] ${revData.title || "Revenue"}`,
      exclude_from_pl: false,
      updated_at: now,
    });

    // Create reversal entry with negated amount
    // but REDUCE by any amount already refunded to avoid double-deduction
    if (origAmount !== 0) {
      const netToReverse = origAmount - alreadyRefundedRevenue;
      const reversalId = `sale_rev_${saleId}_reversal`;
      batch.set(txnCol.doc(reversalId), {
        id: reversalId,
        user_id: userId,
        title: `[Reversal] ${revData.title || "Revenue"}`,
        amount: netToReverse !== 0 ? -netToReverse : 0,
        date_time: reversalDate,
        category_id: revData.category_id || "cat_sales_revenue",
        note: alreadyRefundedRevenue > 0
          ? `Auto-reversal — Shopify order cancelled (adjusted for refund of ${alreadyRefundedRevenue})`
          : "Auto-reversal — Shopify order cancelled",
        sale_id: saleId,
        exclude_from_pl: false,
        created_at: now,
        updated_at: now,
      });
    }
  }

  if (cogsTxnSnap.exists) {
    const cogsData = cogsTxnSnap.data()!;
    const origAmount = Number(cogsData.amount) || 0;

    // Mark original as cancelled (keep visible for audit trail)
    batch.update(cogsTxnSnap.ref, {
      title: `[Cancelled] ${cogsData.title || "COGS"}`,
      exclude_from_pl: false,
      updated_at: now,
    });

    // Create COGS reversal
    if (origAmount !== 0) {
      const reversalId = `sale_cogs_${saleId}_reversal`;
      batch.set(txnCol.doc(reversalId), {
        id: reversalId,
        user_id: userId,
        title: `[Reversal] ${cogsData.title || "COGS"}`,
        amount: -origAmount,
        date_time: reversalDate,
        category_id: cogsData.category_id || "cat_cogs",
        note: "Auto-reversal — Shopify order cancelled",
        sale_id: saleId,
        exclude_from_pl: false,
        created_at: now,
        updated_at: now,
      });
    }
  }

  // Cancel shipping transaction if present
  const shipTxnSnap = await txnCol.doc(`sale_ship_${saleId}`).get();
  if (shipTxnSnap.exists) {
    const shipData = shipTxnSnap.data()!;
    const origAmount = Number(shipData.amount) || 0;

    batch.update(shipTxnSnap.ref, {
      title: `[Cancelled] ${shipData.title || "Shipping"}`,
      exclude_from_pl: false,
      updated_at: now,
    });

    if (origAmount !== 0) {
      const reversalId = `sale_ship_${saleId}_reversal`;
      batch.set(txnCol.doc(reversalId), {
        id: reversalId,
        user_id: userId,
        title: `[Reversal] ${shipData.title || "Shipping"}`,
        amount: -origAmount,
        date_time: reversalDate,
        category_id: "cat_shipping",
        note: "Auto-reversal — Shopify order cancelled",
        sale_id: saleId,
        exclude_from_pl: false,
        created_at: now,
        updated_at: now,
      });
    }
  }

  await batch.commit();

  // ── Reverse stock ──────────────────────────────────────
  // If refunds already restored SOME items, only restore the
  // remaining items/quantities that were NOT part of refunds.
  // This prevents both double-restore and missed-restore scenarios.
  const connDoc = await db
    .collection("shopify_connections")
    .doc(userId)
    .get();
  const conn = connDoc.exists ? connDoc.data() : null;
  if (conn?.sync_inventory_enabled === true) {
    const items = saleData.items as Record<string, unknown>[];

    // Build map of quantities already restored by prior refunds
    const restoredQtyMap = new Map<string, number>();
    if (hasExistingRefunds) {
      const refunds: Record<string, unknown>[] =
        (order.refunds as Record<string, unknown>[]) ?? [];
      for (const refund of refunds) {
        const refundLineItems = (
          refund.refund_line_items as Record<string, unknown>[]
        ) ?? [];
        for (const ri of refundLineItems) {
          const liId = String(ri.line_item_id || "");
          const matched = items.find(
            (si) => String(si.shopify_line_item_id) === liId
          );
          if (matched?.product_id && matched?.variant_id) {
            const key = `${matched.product_id}::${matched.variant_id}`;
            restoredQtyMap.set(
              key,
              (restoredQtyMap.get(key) || 0) + (Number(ri.quantity) || 0),
            );
          }
        }
      }
    }

    // Restore only the delta: saleItemQty − alreadyRestoredQty
    const itemsToRestore: Record<string, unknown>[] = [];
    for (const item of items) {
      if (!item.product_id || !item.variant_id) continue;
      const key = `${item.product_id}::${item.variant_id}`;
      const saleQty = Number(item.quantity) || 0;
      const alreadyRestored = restoredQtyMap.get(key) || 0;
      const remaining = saleQty - alreadyRestored;
      if (remaining > 0) {
        itemsToRestore.push({
          product_id: item.product_id,
          variant_id: item.variant_id,
          quantity: remaining,
          cost_price: item.cost_price,
        });
      }
    }

    if (itemsToRestore.length > 0) {
      await adjustStockForItems(
        db, userId, itemsToRestore, "restore", undefined, valMethod,
      );
    }
  }

  await writeSyncLog(db, userId, {
    action: "order_cancel",
    direction: "shopify_to_masari",
    status: "success",
    shopify_order_id: shopifyOrderId,
    masari_sale_id: saleId,
  });

  await notifyUser(
    userId,
    "Order Cancelled",
    `Shopify order #${shopifyOrderId} was cancelled. Stock restored.`,
    {type: "shopify_order_cancelled", sale_id: saleId},
    "shopify_orders"
  );

  logger.info("Order cancelled in Revvo", {
    saleId,
    shopifyOrderId,
  });
}

// ═══════════════════════════════════════════════════════════
//  Auto-import a new Shopify product into Revvo
// ═══════════════════════════════════════════════════════════

/**
 * Creates a new Revvo product + variants + mappings from a Shopify
 * product payload. Called when products/create fires (or products/update
 * for a product that has no mappings yet).
 */
async function autoImportShopifyProduct(
  db: FirebaseFirestore.Firestore,
  userId: string,
  product: ShopifyProduct,
  shopDomain?: string,
  shopifyToken?: string,
): Promise<void> {
  const shopifyProductId = String(product.id);
  const shopifyVariants: ShopifyLineItem[] = product.variants ?? [];
  if (shopifyVariants.length === 0) {
    logger.info("Shopify product has no variants, skipping import", {
      shopifyProductId,
    });
    return;
  }

  // ── Check for existing Revvo product with same shopify_product_id ──
  const existingSnap = await db
    .collection("products")
    .where("user_id", "==", userId)
    .where("shopify_product_id", "==", shopifyProductId)
    .get();

  if (!existingSnap.empty) {
    // Product already exists — recreate mappings instead of duplicating
    const existingDoc = existingSnap.docs[0];
    const existingData = existingDoc.data();
    const prodId = existingDoc.id;
    const existingVariants =
      (existingData.variants as Record<string, unknown>[]) || [];
    const now = new Date().toISOString();

    // Delete duplicate copies if multiple exist (keep first)
    for (let d = 1; d < existingSnap.docs.length; d++) {
      await existingSnap.docs[d].ref.delete();
    }

    // Atomic batch: create all mappings pointing to existing product
    const relinkBatch = db.batch();
    for (let i = 0; i < shopifyVariants.length; i++) {
      const sv = shopifyVariants[i];
      const svId = String(sv.id);

      // Match variant by shopify_variant_id, sku, or index
      const matched =
        existingVariants.find(
          (v) =>
            (v as Record<string, unknown>).shopify_variant_id === svId ||
            ((v as Record<string, unknown>).sku &&
              sv.sku &&
              (v as Record<string, unknown>).sku === sv.sku)
        ) || existingVariants[i];

      if (!matched) continue;
      const varId = (matched as Record<string, unknown>).id as string;
      const variantTitle = sv.title || sv.option1 || "Default";

      const mappingRef = db.collection("shopify_product_mappings").doc();
      relinkBatch.set(mappingRef, {
        id: mappingRef.id,
        user_id: userId,
        masari_product_id: prodId,
        masari_variant_id: varId,
        shopify_product_id: shopifyProductId,
        shopify_variant_id: svId,
        shopify_inventory_item_id: String(sv.inventory_item_id || ""),
        shopify_sku: sv.sku || "",
        shopify_title: `${product.title || ""} — ${variantTitle}`,
        auto_imported: true,
        created_at: now,
      });
    }
    await relinkBatch.commit();

    logger.info("Relinked existing Revvo product to Shopify", {
      shopifyProductId,
      revvoProductId: prodId,
    });
    return;
  }

  // ── No existing product — create new with deterministic ID ──

  // Batch-fetch costs for all variants from Shopify
  const costMap = new Map<string, number>();
  if (shopDomain && shopifyToken) {
    const invItemIds = shopifyVariants
      .filter((sv) => sv.inventory_item_id)
      .map((sv) => String(sv.inventory_item_id));
    if (invItemIds.length > 0) {
      const fetched = await fetchShopifyInventoryItemCosts(
        shopDomain, shopifyToken, invItemIds,
      );
      for (const [k, v] of fetched) costMap.set(k, v);
    }
  }

  // Use deterministic ID to prevent duplicates on reconnect
  const prodId = `shopify_${shopifyProductId}`;
  const prodRef = db.collection("products").doc(prodId);
  const now = new Date().toISOString();

  // Build Revvo variants from Shopify variants
  const revvoVariants: Record<string, unknown>[] = [];
  const mappingDocs: {ref: FirebaseFirestore.DocumentReference;
    data: Record<string, unknown>}[] = [];

  for (let i = 0; i < shopifyVariants.length; i++) {
    const sv = shopifyVariants[i];
    const varId = `${prodId}_v${i}`;
    const svId = String(sv.id);

    const optionValues: Record<string, string> = {};
    if (sv.option1) optionValues["Option 1"] = sv.option1;
    if (sv.option2) optionValues["Option 2"] = sv.option2;
    if (sv.option3) optionValues["Option 3"] = sv.option3;

    const variantCost = costMap.get(
      String(sv.inventory_item_id || "")
    ) || 0;

    revvoVariants.push({
      id: varId,
      option_values: optionValues,
      sku: sv.sku || "",
      cost_price: variantCost,
      selling_price: Number(sv.price) || 0,
      current_stock: 0,
      reorder_point: 10,
      movements: [],
      cost_layers: [],
      shopify_variant_id: svId,
      shopify_inventory_item_id: String(sv.inventory_item_id || ""),
    });

    const mappingRef = db.collection("shopify_product_mappings").doc();
    const variantTitle = sv.title || sv.option1 || "Default";
    mappingDocs.push({
      ref: mappingRef,
      data: {
        id: mappingRef.id,
        user_id: userId,
        masari_product_id: prodId,
        masari_variant_id: varId,
        shopify_product_id: shopifyProductId,
        shopify_variant_id: svId,
        shopify_inventory_item_id: String(sv.inventory_item_id || ""),
        shopify_sku: sv.sku || "",
        shopify_title: `${product.title || ""} — ${variantTitle}`,
        auto_imported: true,
        created_at: now,
      },
    });
  }

  // Build Revvo options from Shopify product options
  const revvoOptions: Record<string, unknown>[] = [];
  if (Array.isArray(product.options)) {
    for (const opt of product.options) {
      revvoOptions.push({
        name: opt.name || `Option ${opt.position || 1}`,
        values: Array.isArray(opt.values) ? opt.values : [],
      });
    }
  }

  const productDoc: Record<string, unknown> = {
    id: prodId,
    user_id: userId,
    name: product.title || "Shopify Product",
    category: "shopify_import",
    supplier: "",
    unit_of_measure: "pcs",
    icon_code: 0xe59c,
    color: 4288585374,
    is_material: false,
    shopify_product_id: shopifyProductId,
    image_url: product.image?.src || null,
    variants: revvoVariants,
    options: revvoOptions,
    created_at: now,
    updated_at: now,
    _last_modified_by: "shopify_webhook",
  };

  // Atomic write: product + all mappings in a single batch
  const importBatch = db.batch();
  importBatch.set(prodRef, productDoc);
  for (const m of mappingDocs) {
    importBatch.set(m.ref, m.data);
  }
  await importBatch.commit();

  await writeSyncLog(db, userId, {
    action: "product_create",
    direction: "shopify_to_masari",
    status: "success",
    shopify_product_id: shopifyProductId,
    masari_product_id: prodId,
    variants_created: revvoVariants.length,
  });

  logger.info("Auto-imported Shopify product", {
    shopifyProductId,
    revvoProductId: prodId,
    variantCount: revvoVariants.length,
  });
}

// ═══════════════════════════════════════════════════════════
//  products/update
// ═══════════════════════════════════════════════════════════

/**
 * Handles a Shopify product update — syncs mapped Revvo product.
 *
 * Syncs: product title, variant prices, variant SKUs, new variants
 * added on Shopify (auto-creates Revvo variant + mapping).
 *
 * @param {string} userId Revvo user ID.
 * @param {ShopifyProduct} product Shopify product payload.
 */
async function handleProductUpdate(
  userId: string,
  product: ShopifyProduct,
): Promise<void> {
  const db = getDb();
  const shopifyProductId = String(product.id);

  // Find all variant mappings for this product
  const mappingSnap = await db
    .collection("shopify_product_mappings")
    .where("user_id", "==", userId)
    .where("shopify_product_id", "==", shopifyProductId)
    .get();

  if (mappingSnap.empty) {
    // No existing mappings — could be a new product or a reconnect scenario.
    // autoImportShopifyProduct handles both: it checks for existing products
    // by shopify_product_id before creating, so duplicates are prevented.
    let shopDomain = "";
    let shopifyToken = "";
    const connDoc = await db
      .collection("shopify_connections").doc(userId).get();
    const conn = connDoc.exists ? connDoc.data() : null;
    if (conn) {
      shopDomain = (conn.shop_domain as string) || "";
      const encryptedToken = (conn.access_token as string) || "";
      if (encryptedToken) {
        try {
          shopifyToken = decrypt(
            encryptedToken, tokenEncryptionKey.value().trim()
          );
        } catch {
          logger.warn("Could not decrypt Shopify token for cost lookup");
        }
      }
    }
    await autoImportShopifyProduct(
      db, userId, product, shopDomain, shopifyToken,
    );
    return;
  }

  const shopifyVariants: ShopifyLineItem[] =
    product.variants ?? [];
  const shopifyVariantMap = new Map(
    shopifyVariants.map(
      (v: ShopifyLineItem) => [String(v.id), v]
    )
  );

  // Build lookup: shopify_variant_id → mapping doc data
  const mappingByShopifyVariant = new Map<string, Record<string, unknown>>();
  let revvoProductId: string | null = null;
  for (const doc of mappingSnap.docs) {
    const m = doc.data();
    mappingByShopifyVariant.set(
      m.shopify_variant_id as string,
      m
    );
    revvoProductId = m.masari_product_id as string;
  }

  if (!revvoProductId) return;

  const prodRef = db.collection("products").doc(revvoProductId);
  const prodSnap = await prodRef.get();
  if (!prodSnap.exists) return;

  const prodData = prodSnap.data();
  if (!prodData) return;

  // Echo prevention: skip if recently modified by Revvo
  const lastModBy = prodData._last_modified_by as string | undefined;
  if (lastModBy === "masari") {
    const updatedAt = prodData.updated_at as string | undefined;
    if (updatedAt) {
      const elapsed = Date.now() - new Date(updatedAt).getTime();
      if (elapsed < 30_000) {
        logger.info("Skipping product webhook — echo from Revvo push", {
          revvoProductId,
          elapsed,
        });
        await prodRef.update({_last_modified_by: "echo_cleared"});
        return;
      }
    }
  }

  const revvoVariants: Record<string, unknown>[] =
    prodData.variants ?? [];
  let changed = false;
  const now = new Date().toISOString();

  // ── 1. Update product name / image if changed ────────────
  if (product.title && prodData.name !== product.title) {
    changed = true;
  }

  // Sync product image
  const shopifyImageUrl = product.image?.src || null;
  if (shopifyImageUrl && prodData.image_url !== shopifyImageUrl) {
    changed = true;
  }

  // ── 2. Update existing mapped variants (price, SKU, option values) ──
  const updatedVariants = revvoVariants.map(
    (v: Record<string, unknown>) => {
      // Find the mapping for this Revvo variant
      for (const [shopVarId, mapping] of mappingByShopifyVariant) {
        if (
          (mapping as Record<string, unknown>).masari_variant_id === v.id
        ) {
          const sv = shopifyVariantMap.get(shopVarId);
          if (!sv) break;

          let variantChanged = false;
          const updates: Record<string, unknown> = {};

          // Sync selling price
          const newPrice = Number(sv.price) || 0;
          if (newPrice > 0 && v.selling_price !== newPrice) {
            updates.selling_price = newPrice;
            variantChanged = true;
          }

          // Sync SKU
          const newSku = sv.sku as string || "";
          if (newSku && v.sku !== newSku) {
            updates.sku = newSku;
            variantChanged = true;
          }

          // Sync option values (variant title)
          const newOptionValues: Record<string, string> = {};
          if (sv.option1) newOptionValues["Option 1"] = sv.option1;
          if (sv.option2) newOptionValues["Option 2"] = sv.option2;
          if (sv.option3) newOptionValues["Option 3"] = sv.option3;
          const oldOpts = v.option_values as Record<string, string> | undefined;
          const optsChanged = JSON.stringify(oldOpts ?? {}) !== JSON.stringify(newOptionValues);
          if (optsChanged && Object.keys(newOptionValues).length > 0) {
            updates.option_values = newOptionValues;
            variantChanged = true;
          }

          if (variantChanged) {
            changed = true;
            return {...v, ...updates};
          }
          break;
        }
      }
      return v;
    }
  );

  // ── 3a. Detect removed Shopify variants (deleted on Shopify) ──
  const removedMappingDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  const removedRevvoVarIds = new Set<string>();
  for (const doc of mappingSnap.docs) {
    const m = doc.data();
    const svId = m.shopify_variant_id as string;
    if (!shopifyVariantMap.has(svId)) {
      // This Shopify variant no longer exists
      removedMappingDocs.push(doc);
      removedRevvoVarIds.add(m.masari_variant_id as string);
      changed = true;
    }
  }

  // ── 3b. Detect new Shopify variants (not yet mapped) ─────
  const newVariants: Record<string, unknown>[] = [];
  const newMappings: Record<string, unknown>[] = [];

  for (const sv of shopifyVariants) {
    const svId = String(sv.id);
    if (mappingByShopifyVariant.has(svId)) continue;

    // This Shopify variant has no mapping — create a new Revvo variant
    const newVarId = `${revvoProductId}_v${updatedVariants.length + newVariants.length}`;
    const variantTitle = sv.title || sv.option1 || "Default";

    const optionValues: Record<string, string> = {};
    if (sv.option1) optionValues["Option 1"] = sv.option1;
    if (sv.option2) optionValues["Option 2"] = sv.option2;
    if (sv.option3) optionValues["Option 3"] = sv.option3;

    newVariants.push({
      id: newVarId,
      option_values: optionValues,
      sku: sv.sku || "",
      cost_price: 0,
      selling_price: Number(sv.price) || 0,
      current_stock: 0,
      reorder_point: 10,
      movements: [],
      cost_layers: [],
      shopify_variant_id: svId,
      shopify_inventory_item_id: String(sv.inventory_item_id || ""),
    });

    // Create mapping document
    const mappingRef = db.collection("shopify_product_mappings").doc();
    newMappings.push({
      id: mappingRef.id,
      ref: mappingRef,
      user_id: userId,
      masari_product_id: revvoProductId,
      masari_variant_id: newVarId,
      shopify_product_id: shopifyProductId,
      shopify_variant_id: svId,
      shopify_inventory_item_id: String(sv.inventory_item_id || ""),
      shopify_sku: sv.sku || "",
      shopify_title:
        `${product.title || ""} — ${variantTitle}`,
      auto_imported: true,
      created_at: now,
    });

    changed = true;
  }

  // ── 4. Persist changes ───────────────────────────────────
  if (changed) {
    // Filter out removed variants
    const keptVariants = updatedVariants.filter(
      (v: Record<string, unknown>) => !removedRevvoVarIds.has(v.id as string)
    );
    const finalVariants = [
      ...keptVariants,
      ...newVariants,
    ];

    const updatePayload: Record<string, unknown> = {
      variants: finalVariants,
      updated_at: now,
      _last_modified_by: "shopify_webhook",
    };

    // Update name only if it changed
    if (product.title && prodData.name !== product.title) {
      updatePayload.name = product.title;
    }

    // Update product image if changed
    if (shopifyImageUrl && prodData.image_url !== shopifyImageUrl) {
      updatePayload.image_url = shopifyImageUrl;
    }

    // Sync product-level options array
    if (Array.isArray(product.options)) {
      const revvoOptions: Record<string, unknown>[] = [];
      for (const opt of product.options) {
        revvoOptions.push({
          name: opt.name || `Option ${opt.position || 1}`,
          values: Array.isArray(opt.values) ? opt.values : [],
        });
      }
      updatePayload.options = revvoOptions;
    }

    await prodRef.update(updatePayload);

    // Update existing mapping docs with latest SKU/title from Shopify
    for (const doc of mappingSnap.docs) {
      const m = doc.data();
      const svId = m.shopify_variant_id as string;
      const sv = shopifyVariantMap.get(svId);
      if (!sv) continue;
      const variantTitle = sv.title || sv.option1 || "Default";
      const newTitle = `${product.title || ""} — ${variantTitle}`;
      const newSku = sv.sku || "";
      const mappingUpdates: Record<string, unknown> = {};
      if (m.shopify_title !== newTitle) mappingUpdates.shopify_title = newTitle;
      if (m.shopify_sku !== newSku) mappingUpdates.shopify_sku = newSku;
      if (Object.keys(mappingUpdates).length > 0) {
        await doc.ref.update(mappingUpdates);
      }
    }

    // Write new mapping documents
    for (const m of newMappings) {
      const ref = m.ref as FirebaseFirestore.DocumentReference;
      const data = {...m};
      delete data.ref;
      await ref.set(data);
    }

    // Delete mappings for removed Shopify variants
    for (const doc of removedMappingDocs) {
      await doc.ref.delete();
    }

    await writeSyncLog(db, userId, {
      action: "product_update",
      direction: "shopify_to_masari",
      status: "success",
      shopify_product_id: shopifyProductId,
      variants_updated: keptVariants.length,
      variants_added: newVariants.length,
      variants_removed: removedMappingDocs.length,
    });
  } else {
    logger.info("Product update processed — no changes detected", {
      shopifyProductId,
    });
  }

  logger.info("Product update processed", {
    shopifyProductId,
    changed,
    existingUpdated: updatedVariants.length,
    newAdded: newVariants.length,
    variantsRemoved: removedMappingDocs.length,
  });
}

// ═══════════════════════════════════════════════════════════
//  products/delete
// ═══════════════════════════════════════════════════════════

/**
 * Handles a Shopify product deletion — removes mappings and optionally
 * marks the Revvo product as deleted (soft-archive via category flag).
 *
 * We don't hard-delete the Revvo product because historical COGS /
 * cost-layer data should be preserved.
 *
 * @param {string} userId Revvo user ID.
 * @param {ShopifyProduct} product Shopify product payload (may only contain id).
 */
async function handleProductDelete(
  userId: string,
  product: ShopifyProduct,
): Promise<void> {
  const db = getDb();
  const shopifyProductId = String(product.id);

  // Find all variant mappings for this product
  const mappingSnap = await db
    .collection("shopify_product_mappings")
    .where("user_id", "==", userId)
    .where("shopify_product_id", "==", shopifyProductId)
    .get();

  if (mappingSnap.empty) {
    logger.info("Product delete — no mappings found, nothing to do", {
      shopifyProductId,
    });
    return;
  }

  let revvoProductId: string | null = null;
  for (const doc of mappingSnap.docs) {
    revvoProductId = doc.data().masari_product_id as string;
    await doc.ref.delete();
  }

  // Clear Shopify IDs from the Revvo product (soft unlink)
  if (revvoProductId) {
    const prodRef = db.collection("products").doc(revvoProductId);
    const prodSnap = await prodRef.get();
    if (prodSnap.exists) {
      const prodData = prodSnap.data();
      const variants = (prodData?.variants as Record<string, unknown>[]) ?? [];
      const cleanedVariants = variants.map((v) => {
        const cleaned = {...v};
        delete cleaned.shopify_variant_id;
        delete cleaned.shopify_inventory_item_id;
        return cleaned;
      });

      await prodRef.update({
        shopify_product_id: null,
        variants: cleanedVariants,
        updated_at: new Date().toISOString(),
        _last_modified_by: "shopify_webhook",
      });
    }
  }

  await writeSyncLog(db, userId, {
    action: "product_delete",
    direction: "shopify_to_masari",
    status: "success",
    shopify_product_id: shopifyProductId,
    masari_product_id: revvoProductId,
    mappings_removed: mappingSnap.size,
  });

  logger.info("Product delete processed — unlinked Revvo product", {
    shopifyProductId,
    revvoProductId,
    mappingsRemoved: mappingSnap.size,
  });
}

// ═══════════════════════════════════════════════════════════
//  inventory_levels/update
// ═══════════════════════════════════════════════════════════

/**
 * Handles inventory level change from Shopify.
 * @param {string} userId Revvo user ID.
 * @param {InventoryLevel} level Shopify inventory_level payload.
 */
async function handleInventoryUpdate(
  userId: string,
  level: InventoryLevel,
): Promise<void> {
  const db = getDb();

  // Check if user has inventory sync enabled
  const connDoc = await db
    .collection("shopify_connections")
    .doc(userId)
    .get();
  const conn = connDoc.exists ? connDoc.data() : null;

  if (conn?.sync_inventory_enabled !== true) {
    return; // inventory sync not enabled; skip
  }

  const inventoryItemId = String(level.inventory_item_id);
  const newQuantity = Number(level.available) || 0;

  // Find the mapping
  const mappingSnap = await db
    .collection("shopify_product_mappings")
    .where("user_id", "==", userId)
    .where(
      "shopify_inventory_item_id",
      "==",
      inventoryItemId
    )
    .limit(1)
    .get();

  if (mappingSnap.empty) {
    logger.info("No mapping for inventory item", {
      inventoryItemId,
    });
    return;
  }

  const mapping = mappingSnap.docs[0].data();
  const prodRef = db
    .collection("products")
    .doc(mapping.masari_product_id);

  // Use a transaction for atomic read-modify-write (prevents race with Flutter)
  await db.runTransaction(async (txn) => {
    const prodSnap = await txn.get(prodRef);
    if (!prodSnap.exists) return;

    const prodData = prodSnap.data();
    if (!prodData) return;

    // Echo prevention: if this product was recently modified by Revvo
    // (within 120s), this webhook is likely the echo of our own push.
    const lastModBy = prodData._last_modified_by as string | undefined;
    if (lastModBy === "masari") {
      const updatedAt = prodData.updated_at as string | undefined;
      if (updatedAt) {
        const elapsed =
          Date.now() - new Date(updatedAt).getTime();
        if (elapsed < 120_000) {
          logger.info("Skipping inventory webhook — echo from Revvo push (time)", {
            inventoryItemId,
            elapsed,
          });
          // Clear the flag so next real webhook isn't blocked
          txn.update(prodRef, {_last_modified_by: "echo_cleared"});
          return;
        }
      }
    }

    // Stronger echo detection: check if the incoming stock matches
    // the value we just pushed (regardless of timing).
    const lastPush = prodData._last_inventory_push as
      {variant_id?: string; stock?: number; at?: string} | undefined;
    if (lastPush && lastPush.variant_id === mapping.masari_variant_id) {
      if (lastPush.stock === newQuantity) {
        const pushAt = lastPush.at ? new Date(lastPush.at).getTime() : 0;
        const pushElapsed = Date.now() - pushAt;
        if (pushElapsed < 120_000) {
          logger.info("Skipping inventory webhook — echo matches pushed stock", {
            inventoryItemId,
            pushed: lastPush.stock,
            received: newQuantity,
            pushElapsed,
          });
          // Clear push metadata
          txn.update(prodRef, {
            _last_modified_by: "echo_cleared",
            _last_inventory_push: null,
          });
          return;
        }
      }
    }

    const variants: Record<string, unknown>[] =
      prodData.variants ?? [];
    const now = new Date().toISOString();
    const valMethod = await getUserValuationMethod(db, userId);

    const updatedVariants = variants.map(
      (v: Record<string, unknown>) => {
        if (v.id === mapping.masari_variant_id) {
          const curStock = Number(v.current_stock) || 0;
          if (curStock === newQuantity) return v; // no change
          const delta = newQuantity - curStock;
          const movements: Record<string, unknown>[] =
            (v.movements as Record<string, unknown>[]) ?? [];
          const fallbackCost = Number(v.cost_price) || 0;
          let layers = effectiveCostLayers(v);
          let costPrice = fallbackCost;

          if (delta > 0) {
            // Stock increased — add a correction layer at current WAC
            const layerCost = wacFromLayers(layers, fallbackCost);
            layers = [
              ...layers,
              {
                date: now,
                unit_cost: layerCost,
                remaining_qty: delta,
              },
            ];
            costPrice = wacFromLayers(layers, fallbackCost);
          } else {
            // Stock decreased — consume layers
            const consumed = consumeCostLayers(
              layers, Math.abs(delta), valMethod, fallbackCost
            );
            layers = consumed.layers;
            costPrice = wacFromLayers(layers, fallbackCost);
          }

          return {
            ...v,
            current_stock: newQuantity,
            cost_layers: layers,
            cost_price: costPrice,
            movements: [
              ...movements,
              {
                date_time: now,
                quantity: delta,
                note: "Shopify inventory webhook",
                type: "Correction",
                unit_cost: delta > 0 ?
                  wacFromLayers(
                    layers.slice(0, -1), fallbackCost
                  ) : undefined,
              },
            ],
          };
        }
        return v;
      }
    );

    txn.update(prodRef, {
      variants: updatedVariants,
      updated_at: now,
      _last_modified_by: "shopify_webhook",
    });
  });

  await writeSyncLog(db, userId, {
    action: "inventory_sync",
    direction: "shopify_to_masari",
    status: "success",
    shopify_inventory_item_id: inventoryItemId,
    masari_product_id: mapping.masari_product_id,
    masari_variant_id: mapping.masari_variant_id,
    new_quantity: newQuantity,
  });

  logger.info("Inventory updated", {
    inventoryItemId,
    newQuantity,
  });
}

// ═══════════════════════════════════════════════════════════
//  Shared utilities
// ═══════════════════════════════════════════════════════════

interface ResolvedMapping {
  productId: string | null;
  variantId: string | null;
  variantName: string | null;
  costPrice: number;
}

/**
 * Resolves a Shopify line item to a Revvo product/variant.
 * If no mapping exists, auto-creates the product + mapping.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} userId Revvo user ID.
 * @param {ShopifyLineItem} li Shopify line item.
 * @param {boolean} syncStock Whether to enable stock tracking.
 * @return {Promise<ResolvedMapping>} Mapped IDs and cost price.
 */
async function resolveMapping(
  db: FirebaseFirestore.Firestore,
  userId: string,
  li: ShopifyLineItem,
  syncStock: boolean,
  qty?: number,
  valuationMethod?: string,
  shopDomain?: string,
  shopifyToken?: string,
): Promise<ResolvedMapping> {
  const shopifyVariantId = String(li.variant_id || li.product_id);

  // Try to find existing mapping
  const snap = await db
    .collection("shopify_product_mappings")
    .where("user_id", "==", userId)
    .where("shopify_variant_id", "==", shopifyVariantId)
    .limit(1)
    .get();

  if (!snap.empty) {
    const m = snap.docs[0].data();
    // Look up Revvo cost price using valuation method
    let cost = await getRevvoCostPrice(
      db, m.masari_product_id, m.masari_variant_id,
      qty, valuationMethod,
    );

    // Fall back to Shopify inventory item cost if Revvo cost is 0
    if (cost <= 0 && shopDomain && shopifyToken) {
      const invItemId = (m.shopify_inventory_item_id as string) || "";
      if (invItemId) {
        const costs = await fetchShopifyInventoryItemCosts(
          shopDomain, shopifyToken, [invItemId],
        );
        cost = costs.get(invItemId) || 0;
      }
    }

    return {
      productId: m.masari_product_id,
      variantId: m.masari_variant_id,
      variantName: li.variant_title || null,
      costPrice: cost,
    };
  }

  // ── Auto-create product + variant + mapping ────────────
  const prodRef = db.collection("products").doc();
  const prodId = prodRef.id;
  const variantId = `${prodId}_v0`;
  const now = new Date().toISOString();

  // Fetch cost from Shopify if possible
  let variantCost = 0;
  if (shopDomain && shopifyToken && li.inventory_item_id) {
    const costs = await fetchShopifyInventoryItemCosts(
      shopDomain, shopifyToken, [String(li.inventory_item_id)],
    );
    variantCost = costs.get(String(li.inventory_item_id)) || 0;
  }

  const productDoc: Record<string, unknown> = {
    id: prodId,
    user_id: userId,
    name: li.title || "Shopify Product",
    category: "shopify_import",
    supplier: "",
    unit_of_measure: "pcs",
    icon_code: 0xe59c, // Icons.shopping_bag
    color: 4288585374, // Colors.blue
    is_material: false,
    shopify_product_id: String(li.product_id || ""),
    variants: [
      {
        id: variantId,
        option_values: {},
        sku: li.sku || "",
        cost_price: variantCost,
        selling_price: Number(li.price) || 0,
        current_stock: syncStock ?
          (Number(li.quantity) || 0) :
          0,
        reorder_point: 10,
        movements: [],
        shopify_variant_id: shopifyVariantId,
        shopify_inventory_item_id:
          String(li.inventory_item_id || ""),
      },
    ],
    options: [],
    created_at: now,
    updated_at: now,
  };

  // Atomic write: product + mapping in a single batch
  const batch = db.batch();
  batch.set(prodRef, productDoc);

  const mappingRef = db
    .collection("shopify_product_mappings")
    .doc();
  batch.set(mappingRef, {
    id: mappingRef.id,
    user_id: userId,
    masari_product_id: prodId,
    masari_variant_id: variantId,
    shopify_product_id: String(li.product_id || ""),
    shopify_variant_id: shopifyVariantId,
    shopify_inventory_item_id:
      String(li.inventory_item_id || ""),
    shopify_sku: li.sku || "",
    shopify_title: `${li.title || ""} — ${
      li.variant_title || "Default"
    }`,
    auto_imported: true,
    created_at: now,
  });
  await batch.commit();

  logger.info("Auto-created product + mapping", {
    prodId,
    shopifyVariantId,
    costPrice: variantCost,
  });

  return {
    productId: prodId,
    variantId: variantId,
    variantName: li.variant_title || null,
    costPrice: variantCost,
  };
}

/**
 * Looks up Revvo cost price for a product variant.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} productId Revvo product ID.
 * @param {string} variantId Revvo variant ID.
 * @return {Promise<number>} Cost price (0 if not found).
 */
/**
 * Returns the COGS per unit for a variant, consuming cost layers if FIFO/LIFO.
 * For 'average', returns the WAC (cost_price). For FIFO/LIFO, simulates
 * layer consumption without writing (read-only preview for COGS calculation).
 */
async function getRevvoCostPrice(
  db: FirebaseFirestore.Firestore,
  productId: string,
  variantId: string,
  qty?: number,
  valuationMethod?: string,
): Promise<number> {
  const snap = await db.collection("products").doc(productId).get();
  if (!snap.exists) return 0;
  const variants: Record<string, unknown>[] =
    (snap.data()?.variants as Record<string, unknown>[]) ?? [];
  const variant = variants.find(
    (v: Record<string, unknown>) => v.id === variantId
  );
  if (!variant) return 0;
  const fallbackCost = Number(variant.cost_price) || 0;

  if (!qty || qty <= 0 || !valuationMethod || valuationMethod === "average") {
    return fallbackCost;
  }

  const layers = effectiveCostLayers(variant);
  if (layers.length === 0) return fallbackCost;

  const result = consumeCostLayers(layers, qty, valuationMethod, fallbackCost);
  return result.unitCost;
}

/**
 * Applies stock adjustments within an existing Firestore transaction.
 * Groups items by product_id to handle multiple variants per product.
 * All product docs must already be read via txn.get() and passed in.
 */
function applyStockInTransaction(
  txn: FirebaseFirestore.Transaction,
  items: Record<string, unknown>[],
  productSnapshots: Map<string, FirebaseFirestore.DocumentSnapshot>,
  mode: "deduct" | "restore",
  valuationMethod: string,
  customReason?: string,
): void {
  const method = valuationMethod || "fifo";

  // Group items by product → variant, accumulating qty
  const grouped = new Map<
    string,
    Map<string, {qty: number; costPrice: number}>
  >();
  for (const item of items) {
    const productId = item.product_id as string | undefined;
    const variantId = item.variant_id as string | undefined;
    const qty = Number(item.quantity) || 0;
    if (!productId || !variantId || qty === 0) continue;
    if (!grouped.has(productId)) grouped.set(productId, new Map());
    const variants = grouped.get(productId)!;
    const existing = variants.get(variantId);
    if (existing) {
      existing.qty += qty;
    } else {
      variants.set(variantId, {
        qty,
        costPrice: Number(item.cost_price) || 0,
      });
    }
  }

  const now = new Date().toISOString();

  for (const [productId, variantChanges] of grouped) {
    const prodSnap = productSnapshots.get(productId);
    if (!prodSnap?.exists) continue;
    const prodData = prodSnap.data()!;
    const variants: Record<string, unknown>[] =
      prodData.variants ?? [];

    const updatedVariants = variants.map(
      (v: Record<string, unknown>) => {
        const change = variantChanges.get(v.id as string);
        if (!change) return v;

        const curStock = Number(v.current_stock) || 0;
        const delta = mode === "deduct" ? -change.qty : change.qty;
        const newStock = Math.max(0, curStock + delta);
        const fallbackCost = Number(v.cost_price) || 0;
        const movements: Record<string, unknown>[] =
          (v.movements as Record<string, unknown>[]) ?? [];

        let layers = effectiveCostLayers(v);
        let movementUnitCost = fallbackCost;

        if (mode === "deduct") {
          const result = consumeCostLayers(
            layers, change.qty, method, fallbackCost,
          );
          layers = result.layers;
          movementUnitCost = result.unitCost;
        } else {
          const itemCost = change.costPrice || fallbackCost;
          if (itemCost > 0) {
            layers = [
              ...layers,
              {
                date: now,
                unit_cost: itemCost,
                remaining_qty: change.qty,
              },
            ];
            movementUnitCost = itemCost;
          }
        }

        const newCostPrice = wacFromLayers(layers, fallbackCost);

        return {
          ...v,
          current_stock: newStock,
          cost_price: newCostPrice,
          cost_layers: layers,
          movements: [
            ...movements,
            {
              date_time: now,
              quantity: delta,
              unit_cost: movementUnitCost,
              note: customReason || (mode === "deduct" ?
                "Shopify order" :
                "Shopify order cancelled"),
              type: mode === "deduct" ? "Sale" : "Return",
            },
          ],
        };
      },
    );

    txn.update(prodSnap.ref, {
      variants: updatedVariants,
      updated_at: now,
      _last_modified_by: "shopify_order",
    });
  }
}

/**
 * Adjusts stock for sale items (deduct or restore).
 * Cost-layer aware: consumes layers on deduct, adds layers on restore.
 * Groups all items by product and processes in a single transaction
 * (chunked by 25 products to limit contention).
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} userId Revvo user ID.
 * @param {Record<string, unknown>[]} items Sale items.
 * @param {string} mode "deduct" or "restore".
 * @param {string} [customReason] Optional custom reason for movement log.
 * @param {string} [valuationMethod] 'fifo', 'lifo', or 'average'.
 */
async function adjustStockForItems(
  db: FirebaseFirestore.Firestore,
  userId: string,
  items: Record<string, unknown>[],
  mode: "deduct" | "restore",
  customReason?: string,
  valuationMethod?: string,
): Promise<void> {
  // Collect unique product IDs
  const uniqueProductIds = new Set<string>();
  for (const item of items) {
    const pid = item.product_id as string | undefined;
    if (pid) uniqueProductIds.add(pid);
  }
  if (uniqueProductIds.size === 0) return;

  // Process in chunks to limit transaction contention
  const productIds = [...uniqueProductIds];
  const CHUNK_SIZE = 25;

  for (let i = 0; i < productIds.length; i += CHUNK_SIZE) {
    const chunk = productIds.slice(i, i + CHUNK_SIZE);
    const chunkItems = items.filter((it) =>
      chunk.includes(it.product_id as string),
    );

    await db.runTransaction(async (txn) => {
      const snapshots = new Map<
        string,
        FirebaseFirestore.DocumentSnapshot
      >();
      for (const pid of chunk) {
        snapshots.set(
          pid,
          await txn.get(db.collection("products").doc(pid)),
        );
      }

      applyStockInTransaction(
        txn, chunkItems, snapshots, mode,
        valuationMethod || "fifo", customReason,
      );
    });
  }
}

/**
 * Writes an entry to shopify_sync_log.
 * @param {FirebaseFirestore.Firestore} db Firestore instance.
 * @param {string} userId Revvo user ID.
 * @param {Record<string, unknown>} entry Log data.
 */
async function writeSyncLog(
  db: FirebaseFirestore.Firestore,
  userId: string,
  entry: Record<string, unknown>,
): Promise<void> {
  try {
    await db.collection("shopify_sync_log").add({
      user_id: userId,
      ...entry,
      created_at: FieldValue.serverTimestamp(),
    });
  } catch (err) {
    // Logging failure should not break processing
    logger.warn("Failed to write sync log", {err});
  }
}

// ═══════════════════════════════════════════════════════════
// app/uninstalled — merchant uninstalled the app from Shopify
// ═══════════════════════════════════════════════════════════

/**
 * When the Shopify app is uninstalled by the merchant, mark the
 * connection as disconnected so the Flutter app shows the
 * reconnection banner.
 * @param {string} userId Revvo user ID.
 */
async function handleAppUninstalled(userId: string): Promise<void> {
  const db = getDb();
  const connRef = db.collection("shopify_connections").doc(userId);

  await connRef.update({
    status: "disconnected",
    access_token: null,
    webhook_ids: {},
    updated_at: FieldValue.serverTimestamp(),
  });

  await writeSyncLog(db, userId, {
    type: "app_uninstalled",
    action: "disconnect",
    message: "Shopify app was uninstalled by the merchant",
  });

  logger.info("App uninstalled — connection deactivated", {userId});

  await notifyUser(
    userId,
    "Shopify Disconnected",
    "Your Shopify app was uninstalled. Reconnect from Settings to resume sync.",
    {type: "shopify_disconnected"},
    "shopify_orders"
  );
}

// ═══════════════════════════════════════════════════════════
//  customers/data_request — GDPR data export request
// ═══════════════════════════════════════════════════════════

/**
 * Handles the `customers/data_request` mandatory compliance webhook.
 * Shopify sends this when a merchant requests customer data. Our app
 * does not store end-customer PII beyond order data already synced
 * from Shopify, so we log the request for audit purposes.
 * @param {string} userId Revvo user ID.
 * @param {Record<string, unknown>} payload Webhook payload.
 */
async function handleCustomersDataRequest(
  userId: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const db = getDb();
  await writeSyncLog(db, userId, {
    type: "compliance",
    action: "customers_data_request",
    message: "Customer data request received from Shopify",
    shopDomain: payload.shop_domain as string || "",
    ordersRequested: JSON.stringify(
      (payload as {orders_requested?: unknown[]}).orders_requested || []
    ),
  });
  logger.info("customers/data_request processed", {userId});
}

// ═══════════════════════════════════════════════════════════
//  customers/redact — GDPR customer data deletion
// ═══════════════════════════════════════════════════════════

/**
 * Handles the `customers/redact` mandatory compliance webhook.
 * Shopify sends this when a merchant's customer requests data erasure.
 * We remove any customer-identifying info from our synced order records.
 * @param {string} userId Revvo user ID.
 * @param {Record<string, unknown>} payload Webhook payload.
 */
async function handleCustomersRedact(
  userId: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const db = getDb();
  const customer = payload.customer as {id?: number; email?: string} | undefined;
  const shopifyCustomerId = customer?.id ? String(customer.id) : null;

  if (shopifyCustomerId) {
    // Redact customer PII from any synced sales that reference this customer
    const salesSnap = await db
      .collection("sales")
      .where("user_id", "==", userId)
      .where("external_source", "==", "shopify")
      .where("shopify_customer_id", "==", shopifyCustomerId)
      .get();

    if (!salesSnap.empty) {
      const batch = db.batch();
      for (const doc of salesSnap.docs) {
        batch.update(doc.ref, {
          customer_name: "[redacted]",
          customer_email: null,
          customer_phone: null,
          shopify_customer_id: null,
          updated_at: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      logger.info("Redacted customer data from sales", {
        userId, customerId: shopifyCustomerId, count: salesSnap.size,
      });
    }
  }

  // Fallback: also redact by email in case shopify_customer_id was missing
  const customerEmail = customer?.email as string | undefined;
  if (customerEmail) {
    const emailSnap = await db
      .collection("sales")
      .where("user_id", "==", userId)
      .where("external_source", "==", "shopify")
      .where("customer_email", "==", customerEmail)
      .get();

    if (!emailSnap.empty) {
      const batch = db.batch();
      for (const doc of emailSnap.docs) {
        batch.update(doc.ref, {
          customer_name: "[redacted]",
          customer_email: null,
          customer_phone: null,
          shopify_customer_id: null,
          updated_at: FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      logger.info("Redacted customer data by email fallback", {
        userId, email: customerEmail, count: emailSnap.size,
      });
    }
  }

  await writeSyncLog(db, userId, {
    type: "compliance",
    action: "customers_redact",
    message: `Customer data redacted (${shopifyCustomerId || "unknown"})`,
    shopDomain: payload.shop_domain as string || "",
  });
  logger.info("customers/redact processed", {userId});
}

// ═══════════════════════════════════════════════════════════
//  shop/redact — GDPR shop data deletion
// ═══════════════════════════════════════════════════════════

/**
 * Handles the `shop/redact` mandatory compliance webhook.
 * Shopify sends this 48 hours after app uninstall. We must
 * delete all data associated with the shop.
 * @param {string} userId Revvo user ID.
 * @param {Record<string, unknown>} payload Webhook payload.
 */
async function handleShopRedact(
  userId: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const db = getDb();
  const shopDomain = payload.shop_domain as string || "";

  // Delete shopify_product_mappings for this user
  const mappingsSnap = await db
    .collection("shopify_product_mappings")
    .where("user_id", "==", userId)
    .get();
  if (!mappingsSnap.empty) {
    const batch = db.batch();
    for (const doc of mappingsSnap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  // Delete shopify_sync_log for this user
  const logsSnap = await db
    .collection("shopify_sync_log")
    .where("user_id", "==", userId)
    .get();
  if (!logsSnap.empty) {
    const batch = db.batch();
    for (const doc of logsSnap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  // Delete shopify_webhook_queue for this user
  const queueSnap = await db
    .collection("shopify_webhook_queue")
    .where("user_id", "==", userId)
    .get();
  if (!queueSnap.empty) {
    const batch = db.batch();
    for (const doc of queueSnap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }

  // Delete the connection record itself
  await db.collection("shopify_connections").doc(userId).delete();

  await writeSyncLog(db, userId, {
    type: "compliance",
    action: "shop_redact",
    message: `Shop data fully purged for ${shopDomain}`,
    shopDomain,
  });
  logger.info("shop/redact processed — all shop data deleted", {
    userId, shopDomain,
  });
}

// ═══════════════════════════════════════════════════════════
//  REFRESH: Pull latest order state from Shopify and re-sync
// ═══════════════════════════════════════════════════════════

/**
 * Callable Cloud Function that fetches the latest state of a single
 * Shopify order and feeds it through the existing handleOrderUpdated
 * (or handleOrderCancelled) pipeline so Revvo is 100 % in sync.
 *
 * Params:
 *  - saleId: the Revvo sale document ID
 */
export const refreshShopifyOrder = onCall(
  {
    region: "us-central1",
    secrets: [tokenEncryptionKey],
    timeoutSeconds: 60,
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Must be authenticated");
    }

    const {saleId} = request.data as {saleId?: string};
    if (!saleId) {
      throw new HttpsError("invalid-argument", "Missing saleId");
    }

    const db = getDb();

    // 1. Load the sale doc to get the external_order_id
    const saleDoc = await db.collection("sales").doc(saleId).get();
    if (!saleDoc.exists) {
      throw new HttpsError("not-found", "Sale not found");
    }
    const saleData = saleDoc.data()!;
    if (saleData.user_id !== userId) {
      throw new HttpsError("permission-denied", "Not your sale");
    }
    const externalOrderId = saleData.external_order_id as string | undefined;
    if (!externalOrderId) {
      throw new HttpsError(
        "failed-precondition",
        "This sale is not linked to a Shopify order",
      );
    }

    // 2. Get the Shopify connection
    const connDoc = await db
      .collection("shopify_connections")
      .doc(userId)
      .get();
    if (!connDoc.exists || connDoc.data()?.status !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "No active Shopify connection",
      );
    }
    const conn = connDoc.data()!;
    const shopDomain = conn.shop_domain as string;

    // Validate shop domain to prevent SSRF
    if (!/^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(shopDomain)) {
      throw new HttpsError(
        "failed-precondition",
        "Invalid Shopify shop domain",
      );
    }

    const encryptedToken = conn.access_token as string;
    const accessToken = decrypt(
      encryptedToken,
      tokenEncryptionKey.value().trim(),
    );

    // 3. Fetch the single order from Shopify REST Admin API
    const url =
      `https://${shopDomain}/admin/api/${SHOPIFY_API_VERSION}` +
      `/orders/${externalOrderId}.json`;

    const res = await fetch(url, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        "X-Shopify-Access-Token": accessToken,
      },
    });

    if (res.status === 401) {
      await db
        .collection("shopify_connections")
        .doc(userId)
        .update({status: "disconnected"});
      throw new HttpsError(
        "unauthenticated",
        "Shopify token revoked. Please reconnect.",
      );
    }
    if (!res.ok) {
      const body = await res.text();
      logger.error("Shopify API error during order refresh", {
        status: res.status,
        externalOrderId,
        body: body.substring(0, 300),
      });
      throw new HttpsError(
        "internal",
        `Shopify API ${res.status}: ${body.substring(0, 200)}`,
      );
    }

    const json = (await res.json()) as {order?: Record<string, unknown>};
    const order = json.order;
    if (!order) {
      throw new HttpsError(
        "not-found",
        "Order no longer exists on Shopify",
      );
    }

    // 4. Route through the appropriate handler directly
    //    (same logic the webhook processor uses)
    const shopifyOrder = order as unknown as ShopifyOrder;
    const isCancelled = !!(
      shopifyOrder.cancel_reason || shopifyOrder.cancelled_at
    );

    if (isCancelled && saleData.order_status !== 4) {
      await handleOrderCancelled(userId, shopifyOrder);
    } else {
      await handleOrderUpdated(userId, shopifyOrder);
    }

    logger.info("Manual order refresh completed", {
      userId,
      saleId,
      externalOrderId,
      wasCancelled: isCancelled,
    });

    return {success: true};
  },
);

// ═══════════════════════════════════════════════════════════
//  REFRESH ALL: Pull latest state of all Shopify orders
// ═══════════════════════════════════════════════════════════

/**
 * Callable Cloud Function that fetches the latest state of ALL Shopify
 * orders linked to the user and re-syncs each through the existing
 * handleOrderUpdated / handleOrderCancelled pipeline.
 *
 * Uses Shopify's `ids` query parameter to batch-fetch orders efficiently
 * (up to 50 per page), respecting rate limits.
 *
 * Returns: { total, synced, failed }
 */
export const refreshAllShopifyOrders = onCall(
  {
    region: "us-central1",
    secrets: [tokenEncryptionKey],
    timeoutSeconds: 300,
  },
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError("unauthenticated", "Must be authenticated");
    }

    const db = getDb();

    // 1. Get the Shopify connection
    const connDoc = await db
      .collection("shopify_connections")
      .doc(userId)
      .get();
    if (!connDoc.exists || connDoc.data()?.status !== "active") {
      throw new HttpsError(
        "failed-precondition",
        "No active Shopify connection",
      );
    }
    const conn = connDoc.data()!;
    const shopDomain = conn.shop_domain as string;

    if (!/^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(shopDomain)) {
      throw new HttpsError(
        "failed-precondition",
        "Invalid Shopify shop domain",
      );
    }

    const encryptedToken = conn.access_token as string;
    const accessToken = decrypt(
      encryptedToken,
      tokenEncryptionKey.value().trim(),
    );

    // 2. Load all Shopify sales for this user
    const salesSnap = await db
      .collection("sales")
      .where("user_id", "==", userId)
      .where("external_source", "==", "shopify")
      .select("external_order_id", "order_status")
      .get();

    if (salesSnap.empty) {
      return {total: 0, synced: 0, failed: 0};
    }

    // Collect external order IDs
    const orderIdToSaleData = new Map<
      string,
      {saleDocId: string; orderStatus: number}
    >();
    for (const doc of salesSnap.docs) {
      const data = doc.data();
      const extId = data.external_order_id as string | undefined;
      if (extId) {
        orderIdToSaleData.set(extId, {
          saleDocId: doc.id,
          orderStatus: (data.order_status as number) ?? 1,
        });
      }
    }

    const allExternalIds = Array.from(orderIdToSaleData.keys());
    const total = allExternalIds.length;
    let synced = 0;
    let failed = 0;

    // 3. Batch-fetch from Shopify in chunks of 50 (Shopify ids filter limit)
    const CHUNK = 50;
    const apiBase =
      `https://${shopDomain}/admin/api/${SHOPIFY_API_VERSION}`;

    for (let i = 0; i < allExternalIds.length; i += CHUNK) {
      const chunk = allExternalIds.slice(i, i + CHUNK);
      const qs = new URLSearchParams({
        ids: chunk.join(","),
        status: "any",
        limit: String(CHUNK),
      });
      const url = `${apiBase}/orders.json?${qs.toString()}`;

      let orders: Array<Record<string, unknown>>;
      try {
        const res = await fetch(url, {
          method: "GET",
          headers: {
            "Content-Type": "application/json",
            "X-Shopify-Access-Token": accessToken,
          },
        });

        if (res.status === 401) {
          await db
            .collection("shopify_connections")
            .doc(userId)
            .update({status: "disconnected"});
          throw new HttpsError(
            "unauthenticated",
            "Shopify token revoked. Please reconnect.",
          );
        }
        if (!res.ok) {
          const body = await res.text();
          logger.error("Shopify bulk fetch error", {
            status: res.status,
            body: body.substring(0, 300),
          });
          failed += chunk.length;
          continue;
        }

        const json = (await res.json()) as {
          orders?: Array<Record<string, unknown>>;
        };
        orders = json.orders ?? [];
      } catch (e) {
        if (e instanceof HttpsError) throw e;
        logger.error("Shopify bulk fetch exception", {error: String(e)});
        failed += chunk.length;
        continue;
      }

      // 4. Process each order through the existing handlers
      for (const order of orders) {
        try {
          const shopifyOrder = order as unknown as ShopifyOrder;
          const extId = String(shopifyOrder.id);
          const saleInfo = orderIdToSaleData.get(extId);
          const isCancelled = !!(
            shopifyOrder.cancel_reason || shopifyOrder.cancelled_at
          );

          if (isCancelled && saleInfo && saleInfo.orderStatus !== 4) {
            await handleOrderCancelled(userId, shopifyOrder);
          } else {
            await handleOrderUpdated(userId, shopifyOrder);
          }
          synced++;
        } catch (e) {
          logger.error("Failed to sync individual order", {
            orderId: order.id,
            error: String(e),
          });
          failed++;
        }
      }

      // Small delay between Shopify API batches to respect rate limits
      if (i + CHUNK < allExternalIds.length) {
        await new Promise((r) => setTimeout(r, 500));
      }
    }

    logger.info("Bulk Shopify order refresh completed", {
      userId,
      total,
      synced,
      failed,
    });

    return {total, synced, failed};
  },
);

// ═══════════════════════════════════════════════════════════
//  SCHEDULED: Reconcile Shopify orders every 5 minutes
// ═══════════════════════════════════════════════════════════

/**
 * Scheduled Cloud Function that runs every 5 minutes and syncs
 * recently-updated Shopify orders for all active connections.
 *
 * For each user with an active Shopify connection:
 *  1. Read `last_reconciled_at` from the connection doc
 *  2. Fetch orders from Shopify with `updated_at_min` (delta only)
 *  3. Process each through handleOrderUpdated / handleOrderCancelled
 *  4. Update `last_reconciled_at` on the connection doc
 *
 * This ensures missed/failed webhooks are caught automatically
 * without needing to re-fetch all 100k+ orders every time.
 */
export const reconcileShopifyOrders = onSchedule(
  {
    schedule: "every 5 minutes",
    timeZone: "UTC",
    secrets: [tokenEncryptionKey],
    timeoutSeconds: 300,
    memory: "512MiB",
  },
  async () => {
    const db = getDb();

    // 1. Find all active Shopify connections
    const connSnap = await db
      .collection("shopify_connections")
      .where("status", "==", "active")
      .get();

    if (connSnap.empty) {
      logger.info("reconcileShopifyOrders: no active connections");
      return;
    }

    for (const connDoc of connSnap.docs) {
      const userId = connDoc.id;
      const conn = connDoc.data();

      try {
        const shopDomain = conn.shop_domain as string;

        // Validate shop domain to prevent SSRF
        if (!/^[a-z0-9][a-z0-9-]*\.myshopify\.com$/.test(shopDomain)) {
          logger.warn("reconcileShopifyOrders: invalid shop domain", {
            userId,
            shopDomain,
          });
          continue;
        }

        const encryptedToken = conn.access_token as string;
        const accessToken = decrypt(
          encryptedToken,
          tokenEncryptionKey.value().trim(),
        );

        // 2. Determine the time window
        //    Default to 10 minutes ago if no last_reconciled_at
        //    (slightly overlapping with schedule to avoid gaps)
        const now = new Date();
        const lastReconciled = conn.last_reconciled_at?.toDate?.() ??
          new Date(now.getTime() - 10 * 60 * 1000);

        // Subtract 1 minute overlap for safety against clock skew
        const updatedAtMin = new Date(
          lastReconciled.getTime() - 60 * 1000,
        );
        const updatedAtMinISO = updatedAtMin.toISOString();

        // 3. Fetch recently-updated orders from Shopify
        const apiBaseUrl =
          `https://${shopDomain}/admin/api/${SHOPIFY_API_VERSION}`;

        let allOrders: Array<Record<string, unknown>> = [];
        const qs = new URLSearchParams({
          updated_at_min: updatedAtMinISO,
          status: "any",
          limit: "250",
        });
        let url: string | null =
          `${apiBaseUrl}/orders.json?${qs.toString()}`;

        // Paginate (up to 20 pages = 5000 orders per 5-min window max)
        for (let page = 0; page < 20 && url; page++) {
          const res: Response = await fetch(url, {
            method: "GET",
            headers: {
              "Content-Type": "application/json",
              "X-Shopify-Access-Token": accessToken,
            },
          });

          if (res.status === 401) {
            logger.warn("reconcileShopifyOrders: token revoked", {userId});
            await connDoc.ref.update({status: "disconnected"});
            break;
          }
          if (!res.ok) {
            const body = await res.text();
            logger.error("reconcileShopifyOrders: Shopify API error", {
              userId,
              status: res.status,
              body: body.substring(0, 300),
            });
            break;
          }

          const json = (await res.json()) as {
            orders?: Array<Record<string, unknown>>;
          };
          const orders = json.orders ?? [];
          allOrders = allOrders.concat(orders);

          // Parse Link header for pagination
          const linkHeader: string | null = res.headers.get("link");
          url = null;
          if (linkHeader) {
            const nextMatch: RegExpMatchArray | null = linkHeader.match(
              /<([^>]+)>;\s*rel="next"/,
            );
            if (nextMatch) {
              url = nextMatch[1];
            }
          }

          // Respect rate limits
          if (url) {
            await new Promise((r) => setTimeout(r, 500));
          }
        }

        // 4. Process each order
        let synced = 0;
        let failed = 0;
        for (const order of allOrders) {
          try {
            const shopifyOrder = order as unknown as ShopifyOrder;
            const isCancelled = !!(
              shopifyOrder.cancel_reason || shopifyOrder.cancelled_at
            );

            if (isCancelled) {
              await handleOrderCancelled(userId, shopifyOrder);
            } else {
              await handleOrderUpdated(userId, shopifyOrder);
            }
            synced++;
          } catch (e) {
            logger.error("reconcileShopifyOrders: order sync failed", {
              userId,
              orderId: order.id,
              error: String(e),
            });
            failed++;
          }
        }

        // 5. Update last_reconciled_at
        await connDoc.ref.update({
          last_reconciled_at: Timestamp.fromDate(now),
        });

        if (allOrders.length > 0) {
          logger.info("reconcileShopifyOrders: user synced", {
            userId,
            fetched: allOrders.length,
            synced,
            failed,
            updatedAtMin: updatedAtMinISO,
          });
        }
      } catch (e) {
        logger.error("reconcileShopifyOrders: user failed", {
          userId,
          error: String(e),
        });
      }
    }
  },
);

// ═══════════════════════════════════════════════════════════
//  MIGRATION: Backfill fulfillment_status for existing Shopify sales
// ═══════════════════════════════════════════════════════════

/**
 * Callable Cloud Function that backfills the `fulfillment_status` field
 * for existing Shopify sales that were created before we added it.
 * Derives fulfillment from delivery_status and order_status.
 */
export const backfillFulfillmentStatus = onCall(
  {region: "us-central1", invoker: "public"},
  async (request) => {
    const userId = request.auth?.uid;
    if (!userId) {
      throw new HttpsError(
        "unauthenticated",
        "Must be authenticated",
      );
    }

    const db = getDb();
    const snap = await db
      .collection("sales")
      .where("user_id", "==", userId)
      .where("external_source", "==", "shopify")
      .get();

    let updated = 0;
    const batch = db.batch();

    for (const doc of snap.docs) {
      const data = doc.data();
      // Skip if already has fulfillment_status
      if (data.fulfillment_status !== undefined &&
          data.fulfillment_status !== null) {
        continue;
      }

      // Derive from existing fields
      const orderStatus = data.order_status as number ?? 1;
      const deliveryStatus = data.delivery_status as string ?? "pending";
      let fulfillmentStatus: number;

      if (deliveryStatus === "delivered" || orderStatus === 3) {
        fulfillmentStatus = 2; // fulfilled
      } else if (deliveryStatus === "partially_shipped" ||
                 orderStatus === 2) {
        fulfillmentStatus = 1; // partial
      } else {
        fulfillmentStatus = 0; // unfulfilled
      }

      // Also re-derive order_status using the new logic
      const paymentStatus = data.payment_status as number ?? 0;
      const cancelReason = data.cancel_reason as string | null;
      let newOrderStatus: number;

      if (orderStatus === 4 || cancelReason === "declined" ||
          cancelReason === "fraud") {
        newOrderStatus = 4; // keep cancelled
      } else if (paymentStatus === 2 && fulfillmentStatus === 2) {
        newOrderStatus = 3; // completed
      } else if (paymentStatus >= 1 || fulfillmentStatus >= 1) {
        newOrderStatus = 2; // processing
      } else {
        newOrderStatus = 1; // confirmed
      }

      batch.update(doc.ref, {
        fulfillment_status: fulfillmentStatus,
        order_status: newOrderStatus,
        updated_at: Timestamp.now(),
      });
      updated++;
    }

    if (updated > 0) {
      await batch.commit();
    }

    logger.info("Backfilled fulfillment_status", {
      userId,
      total: snap.size,
      updated,
    });

    return {total: snap.size, updated};
  },
);
