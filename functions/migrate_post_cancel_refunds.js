/**
 * Migration: fix Shopify-cancelled-order returns accounting.
 *
 * Two related fixes in one pass:
 *
 *   (A) Re-date existing cancellation reversals to `cancelled_at`.
 *       Legacy code dated reversals at `order.created_at`, which made
 *       cancellations of older orders "disappear" from the Returns
 *       column of the month they actually happened. Applies to:
 *         - sale_rev_{saleId}_reversal
 *         - sale_cogs_{saleId}_reversal
 *         - sale_ship_{saleId}_reversal
 *
 *   (B) Back-fill missing per-refund txns (product & shipping) for
 *       refunds that arrived AFTER a cancellation. Creates each txn
 *       at refund.created_at and reduces the cancellation reversal
 *       by the same amount so net P&L is unchanged.
 *
 * Usage:
 *   node migrate_post_cancel_refunds.js           # DRY-RUN (default)
 *   node migrate_post_cancel_refunds.js --apply   # actually write
 *   node migrate_post_cancel_refunds.js --apply --user <uid>
 *
 * Safe to run multiple times — idempotent on txn IDs.
 */

const admin = require("firebase-admin");
const path = require("path");
const https = require("https");
const crypto = require("crypto");

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(
      "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
    ))
  ),
});
const db = admin.firestore();

const APPLY = process.argv.includes("--apply");
const userFilterIdx = process.argv.indexOf("--user");
const USER_FILTER = userFilterIdx >= 0 ? process.argv[userFilterIdx + 1] : null;

// NOTE: same key used in other scripts; required to decrypt access_token
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";

function decrypt(s, k) {
  const [iv, tag, data] = s.split(":");
  const d = crypto.createDecipheriv(
    "aes-256-gcm",
    Buffer.from(k, "hex"),
    Buffer.from(iv, "base64"),
  );
  d.setAuthTag(Buffer.from(tag, "base64"));
  return d.update(Buffer.from(data, "base64")).toString("utf8") + d.final("utf8");
}

function r2(n) {
  return Math.round(n * 100) / 100;
}

function shopifyGet(shop, token, p) {
  return new Promise((resolve, reject) => {
    https
      .get(
        {
          hostname: shop,
          path: `/admin/api/2024-10${p}`,
          headers: { "X-Shopify-Access-Token": token },
        },
        (r) => {
          let b = "";
          r.on("data", (c) => (b += c));
          r.on("end", () => {
            try {
              resolve(JSON.parse(b));
            } catch {
              resolve({ err: b });
            }
          });
        },
      )
      .on("error", reject);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Fetch ALL Shopify orders (status=any) for a shop via since_id paging.
 */
async function fetchAllOrders(shop, token) {
  const all = [];
  let sinceId = 0;
  while (true) {
    const d = await shopifyGet(
      shop,
      token,
      `/orders.json?status=any&limit=250&since_id=${sinceId}`,
    );
    if (!d.orders || d.orders.length === 0) break;
    all.push(...d.orders);
    sinceId = d.orders[d.orders.length - 1].id;
    if (d.orders.length < 250) break;
    await sleep(400);
  }
  return all;
}

/**
 * Compute per-refund amounts matching the webhook handler.
 */
function computeRefundAmounts(refund) {
  const refundLineItems = refund.refund_line_items || [];
  let productRefundAmount = 0;
  let refundedQty = 0;
  for (const ri of refundLineItems) {
    productRefundAmount += Number(ri.subtotal) || 0;
    refundedQty += Number(ri.quantity) || 0;
  }
  const orderAdjs = refund.order_adjustments || [];
  let shippingRefundAmount = 0;
  for (const adj of orderAdjs) {
    if (adj.kind === "shipping_refund") {
      shippingRefundAmount += Math.abs(Number(adj.amount) || 0);
    } else {
      productRefundAmount += Math.abs(Number(adj.amount) || 0);
    }
  }
  if (productRefundAmount <= 0 && shippingRefundAmount <= 0) {
    const txns = refund.transactions || [];
    for (const tx of txns) {
      productRefundAmount += Number(tx.amount) || 0;
    }
  }
  return {
    productRefundAmount: r2(productRefundAmount),
    shippingRefundAmount: r2(shippingRefundAmount),
    refundedQty,
  };
}

async function processUser(userId, shop, token) {
  console.log(`\n════ User ${userId} @ ${shop} ════`);

  // Fetch Shopify orders once
  const orders = await fetchAllOrders(shop, token);
  console.log(`   Fetched ${orders.length} Shopify orders`);

  // Focus: ALL cancelled orders (re-date reversals) — refund
  // back-fill only applies to those with refunds[] entries.
  const candidates = orders.filter((o) => !!o.cancelled_at);
  console.log(
    `   ${candidates.length} cancelled orders ` +
      `(of which ${candidates.filter((o) => (o.refunds || []).length > 0).length} have refunds)`,
  );

  let newRefundTxns = 0;
  let newShipRefundTxns = 0;
  let reversalsAdjusted = 0;
  let shipReversalsAdjusted = 0;
  let reversalsRedated = 0;
  let ordersTouched = 0;
  const affectedOrderNumbers = [];

  for (const order of candidates) {
    const shopifyOrderId = String(order.id);

    // Find Revvo sale
    const saleSnap = await db
      .collection("sales")
      .where("user_id", "==", userId)
      .where("external_order_id", "==", shopifyOrderId)
      .limit(1)
      .get();
    if (saleSnap.empty) continue;
    const saleId = saleSnap.docs[0].id;

    const txnCol = db.collection("transactions");
    let totalNewProductRefund = 0;
    let totalNewShippingRefund = 0;
    let touchedThisOrder = false;

    // ── (A) Re-date reversal txns to cancelled_at ────────
    // Old code dated reversals at order.created_at. We want the
    // reversal to land in the cancellation month to match Shopify's
    // Sales report (Returns appear on the refund/cancel date).
    const cancelDate = order.cancelled_at || order.created_at;
    const targetReversalTs = admin.firestore.Timestamp.fromDate(
      new Date(cancelDate),
    );
    const reversalIds = [
      `sale_rev_${saleId}_reversal`,
      `sale_cogs_${saleId}_reversal`,
      `sale_ship_${saleId}_reversal`,
    ];
    for (const rid of reversalIds) {
      const rsnap = await txnCol.doc(rid).get();
      if (!rsnap.exists) continue;
      const cur = rsnap.data();
      const curDt = cur.date_time && cur.date_time.toDate ?
        cur.date_time.toDate() : null;
      if (!curDt) continue;
      // Only re-date if it's currently at (or near) order.created_at
      // and the cancellation date differs by more than 1 day. This
      // avoids churn on already-correct data.
      const orderCreatedMs = new Date(order.created_at).getTime();
      const cancelMs = new Date(cancelDate).getTime();
      const curMs = curDt.getTime();
      const diffOrderCreated = Math.abs(curMs - orderCreatedMs);
      const diffCancel = Math.abs(curMs - cancelMs);
      // Re-date only if current txn date is closer to created_at
      // than to cancelled_at AND they're meaningfully different.
      if (
        diffCancel > 24 * 60 * 60 * 1000 &&
        diffOrderCreated < diffCancel
      ) {
        if (APPLY) {
          await txnCol.doc(rid).update({
            date_time: targetReversalTs,
            updated_at: admin.firestore.Timestamp.now(),
          });
        }
        reversalsRedated++;
        touchedThisOrder = true;
      }
    }

    for (const refund of (order.refunds || [])) {
      const refundId = String(refund.id);
      const productTxnId = `sale_refund_${saleId}_${refundId}`;
      const shipTxnId = `sale_ship_refund_${saleId}_${refundId}`;

      const [productExists, shipExists, legacyRefundMatches] =
        await Promise.all([
          txnCol.doc(productTxnId).get(),
          txnCol.doc(shipTxnId).get(),
          // Safety: legacy/alternate txns referencing this refund ID.
          // If ANY txn already records this shopify_refund_id for this
          // sale, we treat it as already-processed and skip to avoid
          // double-counting.
          txnCol
            .where("sale_id", "==", saleId)
            .where("shopify_refund_id", "==", refundId)
            .get(),
        ]);

      if (
        !legacyRefundMatches.empty &&
        !productExists.exists &&
        !shipExists.exists
      ) {
        // Some other doc already captured this refund under a different
        // ID scheme. Skip to be safe.
        continue;
      }

      const { productRefundAmount, shippingRefundAmount, refundedQty } =
        computeRefundAmounts(refund);

      if (productRefundAmount <= 0 && shippingRefundAmount <= 0) continue;

      const refundCreatedAt = refund.created_at || order.created_at;
      const refundDate = admin.firestore.Timestamp.fromDate(
        new Date(refundCreatedAt),
      );

      if (productRefundAmount > 0 && !productExists.exists) {
        if (APPLY) {
          await txnCol.doc(productTxnId).set({
            id: productTxnId,
            user_id: userId,
            title: `Refund — #${order.order_number || order.name || ""} — Shopify`,
            amount: -productRefundAmount,
            date_time: refundDate,
            category_id: "cat_sales_revenue",
            note: `Refund issued after cancellation (${refundedQty} items) [backfill]`,
            payment_method: "shopify",
            sale_id: saleId,
            shopify_refund_id: refundId,
            exclude_from_pl: false,
            created_at: admin.firestore.Timestamp.now(),
          });
        }
        totalNewProductRefund += productRefundAmount;
        newRefundTxns++;
        touchedThisOrder = true;
      }

      if (shippingRefundAmount > 0 && !shipExists.exists) {
        if (APPLY) {
          await txnCol.doc(shipTxnId).set({
            id: shipTxnId,
            user_id: userId,
            title: `Shipping Refund — #${order.order_number || order.name || ""} — Shopify`,
            amount: -shippingRefundAmount,
            date_time: refundDate,
            category_id: "cat_shipping",
            note: "Shipping refund after cancellation [backfill]",
            payment_method: "shopify",
            sale_id: saleId,
            shopify_refund_id: refundId,
            exclude_from_pl: false,
            created_at: admin.firestore.Timestamp.now(),
          });
        }
        totalNewShippingRefund += shippingRefundAmount;
        newShipRefundTxns++;
        touchedThisOrder = true;
      }
    }

    // Adjust reversals so net P&L stays the same
    if (totalNewProductRefund > 0) {
      const ref = txnCol.doc(`sale_rev_${saleId}_reversal`);
      const snap = await ref.get();
      if (snap.exists) {
        const cur = Number(snap.data().amount) || 0;
        const next = r2(cur + totalNewProductRefund);
        if (APPLY) {
          await ref.update({
            amount: next,
            note:
              "Auto-reversal — Shopify order cancelled " +
              "(adjusted for post-cancellation refunds) [backfill]",
            updated_at: admin.firestore.Timestamp.now(),
          });
        }
        reversalsAdjusted++;
      }
    }
    if (totalNewShippingRefund > 0) {
      const ref = txnCol.doc(`sale_ship_${saleId}_reversal`);
      const snap = await ref.get();
      if (snap.exists) {
        const cur = Number(snap.data().amount) || 0;
        const next = r2(cur + totalNewShippingRefund);
        if (APPLY) {
          await ref.update({
            amount: next,
            note:
              "Auto-reversal — Shopify order cancelled " +
              "(adjusted for post-cancellation shipping refund) [backfill]",
            updated_at: admin.firestore.Timestamp.now(),
          });
        }
        shipReversalsAdjusted++;
      }
    }

    if (touchedThisOrder) {
      ordersTouched++;
      affectedOrderNumbers.push(
        `#${order.order_number} (prod=${r2(totalNewProductRefund)}, ship=${r2(totalNewShippingRefund)})`,
      );
    }
  }

  console.log(
    `   Orders touched: ${ordersTouched}\n` +
      `   Reversal txns re-dated to cancelled_at: ${reversalsRedated}\n` +
      `   New product refund txns: ${newRefundTxns}\n` +
      `   New shipping refund txns: ${newShipRefundTxns}\n` +
      `   Reversal txns adjusted: ${reversalsAdjusted}\n` +
      `   Shipping reversal txns adjusted: ${shipReversalsAdjusted}`,
  );
  if (affectedOrderNumbers.length > 0 && affectedOrderNumbers.length <= 50) {
    console.log("   Affected orders:");
    affectedOrderNumbers.forEach((l) => console.log(`     • ${l}`));
  } else if (affectedOrderNumbers.length > 50) {
    console.log(`   (${affectedOrderNumbers.length} affected orders — list suppressed)`);
  }

  return { ordersTouched, newRefundTxns, newShipRefundTxns };
}

(async () => {
  console.log(
    `Migration: post-cancellation refund backfill  [${APPLY ? "APPLY" : "DRY-RUN"}]`,
  );
  if (USER_FILTER) console.log(`Filter: user=${USER_FILTER}`);

  const connsSnap = await db.collection("shopify_connections").get();
  const conns = connsSnap.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .filter((c) => c.access_token && c.shop_domain)
    .filter((c) => !USER_FILTER || c.user_id === USER_FILTER);

  console.log(`Found ${conns.length} Shopify connection(s) to process.`);

  let totalTouched = 0;
  let totalNewProduct = 0;
  let totalNewShip = 0;

  for (const conn of conns) {
    try {
      const token = decrypt(conn.access_token, KEY);
      const res = await processUser(conn.user_id, conn.shop_domain, token);
      totalTouched += res.ordersTouched;
      totalNewProduct += res.newRefundTxns;
      totalNewShip += res.newShipRefundTxns;
    } catch (err) {
      console.error(`   ERROR for ${conn.user_id}:`, err.message || err);
    }
  }

  console.log(
    `\n════ SUMMARY [${APPLY ? "APPLIED" : "DRY-RUN"}] ════\n` +
      `   Total orders touched: ${totalTouched}\n` +
      `   New product refund txns: ${totalNewProduct}\n` +
      `   New shipping refund txns: ${totalNewShip}`,
  );
  if (!APPLY) {
    console.log("\nRun again with --apply to actually write changes.");
  }
  process.exit(0);
})();
