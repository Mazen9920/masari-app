#!/usr/bin/env node
/**
 * repair_reversal_dates.js — Fix reversal transactions that used Timestamp.now()
 * instead of the order's cancelled_at date.
 *
 * Strategy:
 *   1. Find ALL reversal transactions for the user (title starts with "[Reversal]")
 *   2. For each, look up the parent sale → get external_order_id (Shopify order ID)
 *   3. Fetch the Shopify order to get cancelled_at
 *   4. If the reversal's date_time ≠ cancelled_at (off by >5 min) AND
 *      date_time ≈ created_at (within 1 min), it was set by Timestamp.now()
 *   5. Update date_time → cancelled_at
 *
 * Usage:
 *   ENCRYPTION_KEY=<hex> node functions/repair_reversal_dates.js [--dry-run]
 *
 *   --dry-run: Show what would be changed without writing (default)
 *   --apply:   Actually write the changes to Firestore
 */

process.env.GOOGLE_APPLICATION_CREDENTIALS =
  "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json";

const admin = require("firebase-admin");
const crypto = require("crypto");

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();
const Timestamp = admin.firestore.Timestamp;

const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const SHOPIFY_API_VERSION = "2024-01";
const DRY_RUN = !process.argv.includes("--apply");

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

async function shopifyGet(shopDomain, token, path) {
  const url = `https://${shopDomain}/admin/api/${SHOPIFY_API_VERSION}/${path}`;
  const res = await fetch(url, {
    headers: {
      "X-Shopify-Access-Token": token,
      "Content-Type": "application/json",
    },
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Shopify API ${res.status}: ${text}`);
  }
  return res.json();
}

async function main() {
  const encKey = process.env.ENCRYPTION_KEY;
  if (!encKey) {
    console.error("ERROR: Set ENCRYPTION_KEY env var.");
    process.exit(1);
  }

  console.log(`\n${"═".repeat(60)}`);
  console.log(`  REPAIR REVERSAL DATES — ${DRY_RUN ? "DRY RUN" : "⚠ LIVE APPLY"}`);
  console.log(`${"═".repeat(60)}\n`);

  // 1. Get Shopify connection
  const connDoc = await db.collection("shopify_connections").doc(UID).get();
  const conn = connDoc.data();
  const shopDomain = conn.shop_domain;
  const accessToken = decrypt(conn.access_token, encKey.trim());
  console.log(`Shop: ${shopDomain}\n`);

  // 2. Find ALL reversal transactions for this user
  console.log("Finding all reversal transactions...");
  const allTxnSnap = await db
    .collection("transactions")
    .where("user_id", "==", UID)
    .get();

  const reversals = [];
  for (const doc of allTxnSnap.docs) {
    const data = doc.data();
    const title = data.title || "";
    if (title.startsWith("[Reversal]")) {
      reversals.push({
        id: doc.id,
        saleId: data.sale_id || "",
        category: data.category_id || "",
        amount: data.amount,
        title,
        dateTime: data.date_time?.toDate?.() || null,
        createdAt: data.created_at?.toDate?.() || null,
      });
    }
  }
  console.log(`  Found ${reversals.length} total reversal transactions\n`);

  // 3. Group by sale_id and look up each sale's Shopify order
  const saleIds = [...new Set(reversals.map((r) => r.saleId).filter(Boolean))];
  console.log(`  Across ${saleIds.length} unique sales\n`);

  // Fetch all sales in one go
  console.log("Looking up sales for Shopify order IDs...");
  const saleMap = {}; // saleId → { externalOrderId, ... }
  // Firestore "in" queries max 30 at a time
  for (let i = 0; i < saleIds.length; i += 30) {
    const batch = saleIds.slice(i, i + 30);
    const snap = await db
      .collection("sales")
      .where("user_id", "==", UID)
      .where(admin.firestore.FieldPath.documentId(), "in", batch)
      .get();
    for (const doc of snap.docs) {
      const d = doc.data();
      saleMap[doc.id] = {
        externalOrderId: d.external_order_id || "",
        orderNumber: d.shopify_order_number || d.order_number || "",
      };
    }
  }

  // Some sales use a different id field — also check by sale_id match
  // For sales with shopify_ prefix IDs, the doc ID IS the sale_id
  for (const sid of saleIds) {
    if (saleMap[sid]) continue;
    // Try direct doc get
    const doc = await db.collection("sales").doc(sid).get();
    if (doc.exists) {
      const d = doc.data();
      saleMap[sid] = {
        externalOrderId: d.external_order_id || "",
        orderNumber: d.shopify_order_number || d.order_number || "",
      };
    }
  }

  // 4. For each unique Shopify order, fetch cancelled_at
  const shopifyOrderIds = [
    ...new Set(
      Object.values(saleMap)
        .map((s) => s.externalOrderId)
        .filter(Boolean)
    ),
  ];
  console.log(`  Found ${shopifyOrderIds.length} unique Shopify order IDs\n`);

  console.log("Fetching Shopify orders for cancelled_at dates...");
  const cancelledAtMap = {}; // shopifyOrderId → Date
  for (const orderId of shopifyOrderIds) {
    try {
      const data = await shopifyGet(shopDomain, accessToken, `orders/${orderId}.json`);
      if (data.order && data.order.cancelled_at) {
        cancelledAtMap[orderId] = new Date(data.order.cancelled_at);
      }
    } catch (err) {
      console.warn(`  ⚠ Could not fetch order ${orderId}: ${err.message}`);
    }
    // Rate limit: small delay between API calls
    await new Promise((r) => setTimeout(r, 200));
  }

  const cancelledOrderCount = Object.keys(cancelledAtMap).length;
  console.log(
    `  ${cancelledOrderCount} orders have cancelled_at dates\n`
  );

  // 5. Identify reversals that need fixing
  const toFix = [];
  const alreadyCorrect = [];
  const noData = [];

  for (const rev of reversals) {
    const sale = saleMap[rev.saleId];
    if (!sale || !sale.externalOrderId) {
      noData.push(rev);
      continue;
    }

    const cancelledAt = cancelledAtMap[sale.externalOrderId];
    if (!cancelledAt) {
      // Order not cancelled — reversal might be from a refund, skip
      continue;
    }

    if (!rev.dateTime) {
      noData.push(rev);
      continue;
    }

    const dtDiff = Math.abs(rev.dateTime.getTime() - cancelledAt.getTime());
    const createdDiff = rev.createdAt
      ? Math.abs(rev.createdAt.getTime() - rev.dateTime.getTime())
      : Infinity;

    if (dtDiff <= 5 * 60 * 1000) {
      // Already within 5 min of cancelled_at — likely correct
      alreadyCorrect.push(rev);
    } else if (createdDiff < 2 * 60 * 1000) {
      // date_time ≈ created_at but ≠ cancelled_at → used Timestamp.now()
      toFix.push({
        ...rev,
        correctDate: cancelledAt,
        shopifyOrderId: sale.externalOrderId,
        orderNumber: sale.orderNumber,
        offByMinutes: Math.round(dtDiff / 60000),
      });
    } else {
      // date_time differs from both cancelled_at and created_at — unclear, skip
      noData.push(rev);
    }
  }

  console.log(`${"─".repeat(60)}`);
  console.log(`  NEED FIXING:      ${toFix.length} transactions`);
  console.log(`  Already correct:  ${alreadyCorrect.length} transactions`);
  console.log(`  Skipped (no data): ${noData.length} transactions`);
  console.log(`${"─".repeat(60)}\n`);

  if (toFix.length === 0) {
    console.log("✓ Nothing to fix!\n");
    process.exit(0);
  }

  // Group by order for readable output
  const byOrder = {};
  for (const fix of toFix) {
    const key = fix.orderNumber || fix.shopifyOrderId;
    if (!byOrder[key]) byOrder[key] = [];
    byOrder[key].push(fix);
  }

  console.log("Transactions to fix:\n");
  for (const [orderNum, fixes] of Object.entries(byOrder)) {
    console.log(
      `  Order #${orderNum} → correct date: ${fixes[0].correctDate.toISOString()}`
    );
    for (const f of fixes) {
      const catShort = f.category.replace("cat_", "");
      console.log(
        `    ${f.id} (${catShort}): ${f.dateTime.toISOString()} → ${f.correctDate.toISOString()} (off by ${f.offByMinutes} min)`
      );
    }
  }
  console.log("");

  // 6. Apply fixes
  if (DRY_RUN) {
    console.log("═══ DRY RUN — no changes written ═══");
    console.log("Run with --apply to write changes to Firestore.\n");
    process.exit(0);
  }

  console.log("Applying fixes to Firestore...\n");

  // Use batched writes (max 500 per batch)
  let batchCount = 0;
  let batch = db.batch();

  for (const fix of toFix) {
    const ref = db.collection("transactions").doc(fix.id);
    batch.update(ref, {
      date_time: Timestamp.fromDate(fix.correctDate),
    });
    batchCount++;

    if (batchCount >= 500) {
      await batch.commit();
      console.log(`  Committed batch of ${batchCount}`);
      batch = db.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
    console.log(`  Committed batch of ${batchCount}`);
  }

  console.log(`\n✓ Fixed ${toFix.length} reversal transactions across ${Object.keys(byOrder).length} orders.\n`);
  process.exit(0);
}

main().catch((err) => {
  console.error("FATAL:", err);
  process.exit(1);
});
