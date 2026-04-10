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
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

  // Fetch ALL orders (paginate with since_id)
  const allOrders = [];
  let since_id = 0;
  let hasMore = true;
  while (hasMore) {
    const data = await shopifyGet(shop, token, `/orders.json?status=any&limit=250&since_id=${since_id}`);
    if (!data.orders || data.orders.length === 0) break;
    allOrders.push(...data.orders);
    since_id = data.orders[data.orders.length - 1].id;
    if (data.orders.length < 250) hasMore = false;
    await sleep(500);
  }

  console.log("Total Shopify orders:", allOrders.length);
  
  // Status distribution
  const fsCounts = {};
  const cancelCounts = { cancelled: 0, active: 0 };
  allOrders.forEach(o => {
    fsCounts[o.financial_status] = (fsCounts[o.financial_status] || 0) + 1;
    if (o.cancelled_at) cancelCounts.cancelled++;
    else cancelCounts.active++;
  });
  console.log("Financial status:", JSON.stringify(fsCounts));
  console.log("Cancel status:", JSON.stringify(cancelCounts));

  // Check voided orders for refund data
  console.log("\n=== Voided Orders ===");
  const voided = allOrders.filter(o => o.financial_status === "voided");
  let voidedTotal = 0;
  for (const o of voided) {
    const refunds = o.refunds || [];
    const total = Number(o.total_price) || 0;
    voidedTotal += total;
    if (refunds.length > 0) {
      console.log(`  #${o.order_number}: total=${total} refunds=${refunds.length} cancelled=${o.cancelled_at ? "yes" : "no"}`);
    }
  }
  console.log(`  Voided total: ${voidedTotal}`);

  // Check orders that have refunds array populated
  console.log("\n=== Orders with refunds[] populated ===");
  const withRefunds = allOrders.filter(o => o.refunds && o.refunds.length > 0);
  console.log(`Orders with refunds: ${withRefunds.length}`);
  let totalRefundAmount = 0;
  for (const o of withRefunds) {
    for (const r of o.refunds) {
      const items = r.refund_line_items || [];
      const adjs = r.order_adjustments || [];
      const txns = r.transactions || [];
      let itemTotal = 0;
      items.forEach(i => { itemTotal += (Number(i.subtotal)||0) + (Number(i.total_tax)||0); });
      let adjTotal = 0;
      adjs.forEach(a => { adjTotal += Math.abs(Number(a.amount)||0); });
      let txnTotal = 0;
      txns.forEach(t => { txnTotal += Number(t.amount)||0; });
      totalRefundAmount += itemTotal + adjTotal;
      console.log(`  #${o.order_number} fs=${o.financial_status} refund=${r.id}: items=${items.length} itemTotal=${itemTotal} adjTotal=${adjTotal} txnTotal=${txnTotal}`);
    }
  }
  console.log(`Total refund amount: ${totalRefundAmount}`);

  // Cross-reference: check Shopify cancelled orders vs Revvo
  console.log("\n=== Cancelled in Shopify ===");
  const cancelled = allOrders.filter(o => o.cancelled_at);
  console.log(`Shopify cancelled: ${cancelled.length}`);
  let cancelledTotalPrice = 0;
  cancelled.forEach(o => {
    cancelledTotalPrice += Number(o.total_price) || 0;
  });
  console.log(`Cancelled total_price sum: ${cancelledTotalPrice}`);

  // Check: which Shopify orders are NOT in Revvo?
  console.log("\n=== Missing from Revvo ===");
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const revvoShopifyIds = new Set();
  salesSnap.docs.forEach(d => {
    const sid = d.data().shopify_order_id;
    if (sid) revvoShopifyIds.add(String(sid));
  });
  console.log(`Revvo sales: ${salesSnap.size}, Shopify orders: ${allOrders.length}`);

  const missing = allOrders.filter(o => !revvoShopifyIds.has(String(o.id)));
  console.log(`Missing from Revvo: ${missing.length}`);
  let missingTotal = 0;
  missing.forEach(o => {
    const total = Number(o.total_price) || 0;
    missingTotal += total;
    console.log(`  #${o.order_number} id=${o.id} fs=${o.financial_status} total=${total} cancelled=${o.cancelled_at ? "yes" : "no"} created=${o.created_at}`);
  });
  console.log(`Missing total: ${missingTotal}`);

  process.exit(0);
}

main().catch(console.error);
