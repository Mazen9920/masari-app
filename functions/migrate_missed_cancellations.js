/**
 * migrate_missed_cancellations.js
 * 
 * Finds ALL Revvo sales whose corresponding Shopify orders are cancelled
 * (cancelled_at is set) but whose Revvo order_status is NOT 4 (cancelled).
 * 
 * For each such sale:
 * 1. Updates sale doc: order_status → 4, delivery_status → "cancelled"
 * 2. Marks original revenue/COGS/shipping txns as "[Cancelled]"
 * 3. Creates reversal txns that negate the financial impact
 * 
 * GLOBAL: processes ALL users with Shopify connections.
 * DRY RUN by default — set DRY_RUN=false to apply.
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
const DRY_RUN = process.argv.includes("--apply") ? false : true;

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

async function main() {
  console.log(`MODE: ${DRY_RUN ? "DRY RUN" : "APPLYING CHANGES"}`);
  console.log();

  // Get all users with Shopify connections
  const connSnap = await db.collection("shopify_connections").get();
  console.log(`Found ${connSnap.size} Shopify connections`);

  let totalFixed = 0;
  let totalRevenue = 0;
  let totalShipping = 0;
  let totalCogs = 0;

  for (const connDoc of connSnap.docs) {
    const conn = connDoc.data();
    const uid = conn.user_id;
    const shop = conn.shop_domain;

    if (!conn.access_token || !shop) {
      console.log(`  Skipping ${uid}: no token or shop`);
      continue;
    }

    let token;
    try {
      token = decrypt(conn.access_token, ENCRYPTION_KEY);
    } catch {
      console.log(`  Skipping ${uid}: token decrypt failed`);
      continue;
    }

    console.log(`\nProcessing user ${uid} (${shop})...`);

    // Fetch ALL Shopify orders
    const allOrders = [];
    let since_id = 0;
    while (true) {
      const data = await shopifyGet(shop, token, `/orders.json?status=any&limit=250&since_id=${since_id}`);
      if (!data.orders || data.orders.length === 0) break;
      allOrders.push(...data.orders);
      since_id = data.orders[data.orders.length - 1].id;
      if (data.orders.length < 250) break;
      await sleep(500);
    }

    // Build cancelled orders map by order_number
    const cancelledByNum = {};
    allOrders.forEach(o => {
      if (o.cancelled_at) {
        cancelledByNum[String(o.order_number)] = {
          cancel_reason: o.cancel_reason,
          cancelled_at: o.cancelled_at,
          financial_status: o.financial_status,
        };
      }
    });

    // Get all Revvo sales for this user
    const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
    const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();

    // Build txn lookup by sale_id
    const txnsBySaleId = {};
    txnsSnap.docs.forEach(d => {
      const data = d.data();
      const saleId = data.sale_id;
      if (saleId) {
        if (!txnsBySaleId[saleId]) txnsBySaleId[saleId] = [];
        txnsBySaleId[saleId].push({ ref: d.ref, id: d.id, data });
      }
    });

    let userFixed = 0;

    for (const saleDoc of salesSnap.docs) {
      const sale = saleDoc.data();
      const orderNum = String(sale.shopify_order_number || "");
      if (!orderNum) continue;

      const shopCancel = cancelledByNum[orderNum];
      if (!shopCancel) continue;

      // Already cancelled in Revvo?
      if (sale.order_status === 4) continue;

      // This sale needs to be cancelled
      const saleId = saleDoc.id;
      const saleTxns = txnsBySaleId[saleId] || [];
      const now = admin.firestore.Timestamp.now();
      // Use cancellation date for reversals (proper accrual timing)
      const cancelDate = new Date(shopCancel.cancelled_at);
      const cancelTs = admin.firestore.Timestamp.fromDate(cancelDate);

      let revAmt = 0, cogsAmt = 0, shipAmt = 0;
      const batch = db.batch();

      // 1. Update sale status
      batch.update(saleDoc.ref, {
        order_status: 4,
        delivery_status: "cancelled",
        updated_at: now,
      });

      // 2. Process each transaction
      for (const txn of saleTxns) {
        const amt = Number(txn.data.amount) || 0;
        const cat = txn.data.category_id;
        const isReversal = txn.id.includes("_reversal");

        // Skip if already a reversal or already excluded
        if (isReversal) continue;

        // Mark original as cancelled
        batch.update(txn.ref, {
          title: `[Cancelled] ${txn.data.title || "Transaction"}`,
          updated_at: now,
        });

        // Create reversal
        if (amt !== 0) {
          const reversalId = `${txn.id}_reversal`;
          batch.set(db.collection("transactions").doc(reversalId), {
            id: reversalId,
            user_id: uid,
            title: `[Reversal] ${txn.data.title || "Transaction"}`,
            amount: -amt,
            date_time: cancelTs,
            category_id: cat,
            note: "Auto-reversal — Shopify order was cancelled (migration fix)",
            sale_id: saleId,
            exclude_from_pl: false,
            created_at: now,
            updated_at: now,
          });

          if (cat === "cat_sales_revenue") revAmt += amt;
          else if (cat === "cat_shipping") shipAmt += amt;
          else if (cat === "cat_cogs") cogsAmt += amt;
        }
      }

      console.log(`  #${orderNum}: saleId=${saleId} rev=${round2(revAmt)} ship=${round2(shipAmt)} cogs=${round2(cogsAmt)} reason=${shopCancel.cancel_reason}`);

      if (!DRY_RUN) {
        await batch.commit();
      }

      userFixed++;
      totalRevenue += revAmt;
      totalShipping += shipAmt;
      totalCogs += cogsAmt;
    }

    if (userFixed > 0) {
      console.log(`  → Fixed ${userFixed} orders for ${uid}`);
      totalFixed += userFixed;
    }
  }

  console.log(`\n========================================`);
  console.log(`TOTAL: ${totalFixed} orders fixed`);
  console.log(`  Revenue reversed: ${round2(totalRevenue)}`);
  console.log(`  Shipping reversed: ${round2(totalShipping)}`);
  console.log(`  COGS reversed: ${round2(totalCogs)}`);
  console.log(`MODE: ${DRY_RUN ? "DRY RUN (use --apply to execute)" : "APPLIED"}`);

  process.exit(0);
}

main().catch(console.error);
