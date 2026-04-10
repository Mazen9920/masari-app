/**
 * migrate_missing_refunds.js  (v2)
 *
 * For each connected Shopify user:
 *   1. Fetch ALL orders from Shopify (paginated)
 *   2. Find active (non-cancelled) orders that have refunds
 *   3. Check if refund transactions already exist in Firestore
 *   4. Create missing refund transactions (revenue + shipping)
 *
 * Matching: Shopify order_number ↔ Revvo shopify_order_number
 *
 * Usage: node migrate_missing_refunds.js [--dry-run]
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

const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const DRY_RUN = process.argv.includes("--dry-run");

function decrypt(encryptedStr, key) {
  const [ivB64, tagB64, dataB64] = encryptedStr.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data).toString("utf8") + decipher.final("utf8");
}

function round2(n) { return Math.round(n * 100) / 100; }

function shopifyGet(shop, token, apiPath) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: shop,
      path: `/admin/api/2024-10${apiPath}`,
      headers: { "X-Shopify-Access-Token": token },
    };
    const req = https.get(options, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => {
        try { resolve(JSON.parse(body)); }
        catch { resolve({ error: body }); }
      });
    });
    req.on("error", reject);
  });
}

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function fetchAllOrders(shop, token) {
  const allOrders = [];
  let since_id = 0;
  let page = 0;
  while (true) {
    page++;
    const data = await shopifyGet(shop, token,
      `/orders.json?status=any&limit=250&since_id=${since_id}`);
    if (data.errors) {
      console.error("    Shopify API error:", data.errors);
      break;
    }
    if (!data.orders || data.orders.length === 0) break;
    allOrders.push(...data.orders);
    since_id = data.orders[data.orders.length - 1].id;
    console.log(`    Page ${page}: +${data.orders.length} orders (total: ${allOrders.length})`);
    if (data.orders.length < 250) break;
    await sleep(500);
  }
  return allOrders;
}

async function main() {
  console.log(`=== Migrate Missing Refunds v2 ${DRY_RUN ? "(DRY RUN)" : "(LIVE)"} ===\n`);

  const connSnap = await db.collection("shopify_connections")
    .where("status", "==", "active")
    .get();

  console.log(`Found ${connSnap.size} active Shopify connections\n`);

  let totalRevRefunds = 0, totalShipRefunds = 0;
  let totalRevAmount = 0, totalShipAmount = 0;

  for (const connDoc of connSnap.docs) {
    const conn = connDoc.data();
    const userId = conn.user_id;
    const shop = conn.shop_domain || conn.shop;
    const encryptedToken = conn.access_token;

    if (!encryptedToken || !shop) {
      console.log(`[${userId}] Missing token/shop, skip`);
      continue;
    }

    let token;
    try {
      token = decrypt(encryptedToken, ENCRYPTION_KEY);
    } catch (e) {
      console.error(`[${userId}] Decrypt failed:`, e.message);
      continue;
    }

    console.log(`[${userId}] Shop: ${shop}`);

    // Fetch ALL Shopify orders
    const allOrders = await fetchAllOrders(shop, token);
    console.log(`  Total Shopify orders: ${allOrders.length}`);

    // Filter: active (non-cancelled) orders that have refunds
    const ordersWithRefunds = allOrders.filter(
      o => !o.cancelled_at && o.refunds && o.refunds.length > 0
    );
    console.log(`  Active orders with refunds: ${ordersWithRefunds.length}`);

    if (ordersWithRefunds.length === 0) {
      console.log("  Nothing to migrate.\n");
      continue;
    }

    // Build Revvo map: order_number → { saleId, saleData }
    const salesSnap = await db.collection("sales")
      .where("user_id", "==", userId)
      .get();

    const salesByOrderNum = {};
    salesSnap.docs.forEach(d => {
      const data = d.data();
      const num = data.shopify_order_number;
      if (num) salesByOrderNum[String(num)] = { id: d.id, data };
    });

    for (const order of ordersWithRefunds) {
      const orderNum = String(order.order_number);
      const sale = salesByOrderNum[orderNum];

      if (!sale) {
        console.log(`  #${orderNum}: no matching Revvo sale, skip`);
        continue;
      }

      // Skip if cancelled in Revvo
      if (sale.data.status === 4 || sale.data.order_status === 4) {
        continue;
      }

      const saleId = sale.id;
      const now = admin.firestore.Timestamp.now();

      for (const refund of order.refunds) {
        const shopifyRefundId = String(refund.id || "");
        if (!shopifyRefundId) continue;

        const refundTxnId = `sale_refund_${saleId}_${shopifyRefundId}`;

        // Skip if exists
        const existing = await db.collection("transactions").doc(refundTxnId).get();
        if (existing.exists) continue;

        // Calculate revenue refund from line items
        const refundLineItems = refund.refund_line_items || [];
        let refundAmount = 0;
        let refundedQty = 0;
        for (const ri of refundLineItems) {
          refundAmount += Number(ri.subtotal) || 0;
          refundAmount += Number(ri.total_tax) || 0;
          refundedQty += Number(ri.quantity) || 0;
        }

        // Separate shipping refunds from other adjustments
        const orderAdjs = refund.order_adjustments || [];
        let shippingRefundAmount = 0;
        for (const adj of orderAdjs) {
          if (adj.kind === "shipping_refund") {
            shippingRefundAmount += Math.abs(Number(adj.amount) || 0);
          } else {
            refundAmount += Math.abs(Number(adj.amount) || 0);
          }
        }

        refundAmount = round2(refundAmount);
        shippingRefundAmount = round2(shippingRefundAmount);

        if (refundAmount <= 0 && shippingRefundAmount <= 0) continue;

        const isFullRefund = order.financial_status === "refunded";
        const refundNote = isFullRefund
          ? "Full refund from Shopify"
          : `Partial refund (${refundedQty} items)`;
        const refundDate = refund.created_at
          ? admin.firestore.Timestamp.fromDate(new Date(refund.created_at))
          : now;

        // Revenue refund
        if (refundAmount > 0) {
          if (DRY_RUN) {
            console.log(`  [DRY] #${orderNum}: revenue refund -${refundAmount} (${refundNote})`);
          } else {
            await db.collection("transactions").doc(refundTxnId).set({
              id: refundTxnId,
              user_id: userId,
              title: `Refund — #${orderNum} — Shopify`,
              amount: -refundAmount,
              date_time: refundDate,
              category_id: "cat_sales_revenue",
              note: refundNote,
              payment_method: "shopify",
              sale_id: saleId,
              shopify_refund_id: shopifyRefundId,
              exclude_from_pl: false,
              created_at: now,
            });
            console.log(`  CREATED #${orderNum}: revenue refund -${refundAmount}`);
          }
          totalRevRefunds++;
          totalRevAmount += refundAmount;
        }

        // Shipping refund
        if (shippingRefundAmount > 0) {
          const shippingTxnId = `sale_shipping_refund_${saleId}_${shopifyRefundId}`;
          const shipExists = await db.collection("transactions").doc(shippingTxnId).get();
          if (!shipExists.exists) {
            if (DRY_RUN) {
              console.log(`  [DRY] #${orderNum}: shipping refund -${shippingRefundAmount}`);
            } else {
              await db.collection("transactions").doc(shippingTxnId).set({
                id: shippingTxnId,
                user_id: userId,
                title: `Shipping Refund — #${orderNum} — Shopify`,
                amount: -shippingRefundAmount,
                date_time: refundDate,
                category_id: "cat_shipping",
                note: refundNote,
                payment_method: "shopify",
                sale_id: saleId,
                shopify_refund_id: shopifyRefundId,
                exclude_from_pl: false,
                created_at: now,
              });
              console.log(`  CREATED #${orderNum}: shipping refund -${shippingRefundAmount}`);
            }
            totalShipRefunds++;
            totalShipAmount += shippingRefundAmount;
          }
        }
      }
    }
    console.log();
  }

  console.log("=== Summary ===");
  console.log(`  Revenue refunds: ${totalRevRefunds} (${round2(totalRevAmount)} EGP)`);
  console.log(`  Shipping refunds: ${totalShipRefunds} (${round2(totalShipAmount)} EGP)`);
  console.log(`  Total: ${totalRevRefunds + totalShipRefunds} transactions`);

  process.exit(0);
}

main().catch(console.error);
