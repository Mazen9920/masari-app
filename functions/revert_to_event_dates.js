#!/usr/bin/env node
/**
 * revert_to_event_dates.js
 *
 * Restores reversal/refund transaction dates back to event dates
 * (cancelled_at / refund.created_at) instead of original order dates.
 *
 * For each sale-linked transaction whose date_time == parent sale.date,
 * looks up the correct event date:
 *   - Reversals (*_reversal): order.cancelled_at from Shopify
 *   - Refunds (sale_refund_*): refund.created_at from Shopify
 *
 * Usage:
 *   ENCRYPTION_KEY=... node functions/revert_to_event_dates.js          # dry-run
 *   ENCRYPTION_KEY=... node functions/revert_to_event_dates.js apply    # apply
 */

const admin = require("firebase-admin");
const crypto = require("crypto");
const https = require("https");

const SERVICE_ACCOUNT = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
const USER_ID = "EGYQnP7ughdUtTbn04UwUET534i1";
const ENCRYPTION_KEY = process.env.ENCRYPTION_KEY;
const SHOPIFY_API_VERSION = "2024-01";

if (!ENCRYPTION_KEY) {
  console.error("Set ENCRYPTION_KEY env var");
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(SERVICE_ACCOUNT) });
const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

const DRY_RUN = process.argv[2] !== "apply";

// ── Encryption helpers ──
function decrypt(encryptedStr) {
  const [ivB64, tagB64, dataB64] = encryptedStr.split(":");
  const keyBuf = Buffer.from(ENCRYPTION_KEY, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data).toString("utf8") + decipher.final("utf8");
}

// ── Shopify REST helper ──
function shopifyGet(domain, token, path) {
  return new Promise((resolve, reject) => {
    const url = `https://${domain}/admin/api/${SHOPIFY_API_VERSION}/${path}`;
    https.get(url, { headers: { "X-Shopify-Access-Token": token } }, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => {
        if (res.statusCode !== 200) {
          reject(new Error(`Shopify ${res.statusCode}: ${body.slice(0, 200)}`));
          return;
        }
        resolve(JSON.parse(body));
      });
    }).on("error", reject);
  });
}

async function main() {
  console.log(`Mode: ${DRY_RUN ? "DRY-RUN" : "APPLY"}\n`);

  // ── 1. Get Shopify credentials ──
  const connSnap = await db.collection("shopify_connections").doc(USER_ID).get();
  const conn = connSnap.data();
  const domain = conn.shop_domain;
  const token = decrypt(conn.access_token);
  console.log(`Shop: ${domain}\n`);

  // ── 2. Load all sales ──
  const salesSnap = await db
    .collection("sales")
    .where("user_id", "==", USER_ID)
    .get();

  const salesById = new Map();
  for (const doc of salesSnap.docs) {
    const d = doc.data();
    const saleId = d.id || doc.id;
    salesById.set(saleId, d);
  }
  console.log(`Loaded ${salesById.size} sales.\n`);

  // ── 3. Load all sale-linked transactions ──
  const txnSnap = await db
    .collection("transactions")
    .where("user_id", "==", USER_ID)
    .get();

  const candidates = [];
  for (const doc of txnSnap.docs) {
    const t = doc.data();
    if (!t.sale_id) continue;
    const cat = t.category_id || "";
    if (cat !== "cat_sales_revenue" && cat !== "cat_shipping" && cat !== "cat_cogs") continue;

    const docId = doc.id;
    const isReversal = docId.endsWith("_reversal");
    const isRefund = docId.includes("sale_refund_");

    // Only process reversals and refunds — originals should stay at order date
    if (!isReversal && !isRefund) continue;

    const sale = salesById.get(t.sale_id);
    if (!sale) continue;

    // Check if txn date == sale date (meaning it was moved by our repair)
    const txnSec = t.date_time?._seconds ?? t.date_time?.seconds;
    const saleSec = sale.date?._seconds ?? sale.date?.seconds;

    if (txnSec !== saleSec) continue; // Already at a different date, skip

    candidates.push({
      docId,
      ref: doc.ref,
      saleId: t.sale_id,
      externalOrderId: sale.external_order_id,
      isReversal,
      isRefund,
      shopifyRefundId: t.shopify_refund_id || null,
      title: t.title || "",
      amount: t.amount,
      currentDateTime: t.date_time,
    });
  }

  console.log(`Found ${candidates.length} reversal/refund txns currently at sale date.\n`);

  if (candidates.length === 0) {
    console.log("Nothing to fix!");
    process.exit(0);
  }

  // ── 4. Group by Shopify order to minimize API calls ──
  const byOrder = new Map();
  for (const c of candidates) {
    if (!c.externalOrderId) continue;
    if (!byOrder.has(c.externalOrderId)) byOrder.set(c.externalOrderId, []);
    byOrder.get(c.externalOrderId).push(c);
  }

  console.log(`Fetching ${byOrder.size} orders from Shopify...\n`);

  const fixes = [];
  let fetchCount = 0;

  for (const [shopifyOrderId, txns] of byOrder) {
    fetchCount++;
    let order;
    try {
      const resp = await shopifyGet(domain, token, `orders/${shopifyOrderId}.json`);
      order = resp.order;
    } catch (err) {
      console.warn(`  ⚠ Could not fetch order ${shopifyOrderId}: ${err.message}`);
      continue;
    }

    // Build refund date map: refundId -> created_at Timestamp
    const refundDateMap = new Map();
    if (order.refunds) {
      for (const r of order.refunds) {
        if (r.id && r.created_at) {
          refundDateMap.set(String(r.id), Timestamp.fromDate(new Date(r.created_at)));
        }
      }
    }

    const cancelledTs = order.cancelled_at
      ? Timestamp.fromDate(new Date(order.cancelled_at))
      : null;

    for (const txn of txns) {
      let correctDate = null;

      if (txn.isReversal && cancelledTs) {
        correctDate = cancelledTs;
      } else if (txn.isRefund && txn.shopifyRefundId) {
        correctDate = refundDateMap.get(String(txn.shopifyRefundId));
      } else if (txn.isRefund && !txn.shopifyRefundId) {
        // Legacy refund without shopify_refund_id — use first refund date or cancelled_at
        if (refundDateMap.size > 0) {
          correctDate = [...refundDateMap.values()][0];
        } else if (cancelledTs) {
          correctDate = cancelledTs;
        }
      }

      if (!correctDate) {
        console.warn(`  ⚠ No event date for ${txn.docId} (order ${shopifyOrderId})`);
        continue;
      }

      // Only fix if it would actually change
      const currentSec = txn.currentDateTime?._seconds ?? txn.currentDateTime?.seconds;
      const correctSec = correctDate._seconds ?? correctDate.seconds;
      if (currentSec === correctSec) continue;

      fixes.push({
        docId: txn.docId,
        ref: txn.ref,
        title: txn.title,
        amount: txn.amount,
        currentDate: txn.currentDateTime?.toDate
          ? txn.currentDateTime.toDate().toISOString()
          : "unknown",
        correctDate: correctDate.toDate().toISOString(),
        correctTs: correctDate,
      });
    }

    if (fetchCount % 20 === 0) {
      console.log(`  Fetched ${fetchCount}/${byOrder.size} orders...`);
    }
  }

  console.log(`\nTransactions to update: ${fixes.length}\n`);

  if (fixes.length === 0) {
    console.log("Nothing to fix!");
    process.exit(0);
  }

  // Show details
  console.log("Fixes:");
  console.log("─".repeat(100));
  for (const f of fixes) {
    console.log(`  ${f.docId}  amount=${f.amount}  "${f.title}"`);
    console.log(`    ${f.currentDate}  →  ${f.correctDate}`);
  }
  console.log("");

  if (DRY_RUN) {
    console.log("DRY-RUN complete. Run with 'apply' to make changes.");
    process.exit(0);
  }

  // ── 5. Apply in batches ──
  const BATCH_SIZE = 500;
  let applied = 0;
  for (let i = 0; i < fixes.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = fixes.slice(i, i + BATCH_SIZE);
    for (const f of chunk) {
      batch.update(f.ref, { date_time: f.correctTs });
    }
    await batch.commit();
    applied += chunk.length;
    console.log(`Applied batch: ${applied}/${fixes.length}`);
  }

  console.log(`\nDone! Updated ${applied} transactions.`);
  process.exit(0);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
