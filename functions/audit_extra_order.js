const admin = require("firebase-admin");
const path = require("path");
const https = require("https");
const crypto = require("crypto");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
function decrypt(s, k) {
  const [iv, tag, data] = s.split(":");
  const d = crypto.createDecipheriv("aes-256-gcm", Buffer.from(k, "hex"), Buffer.from(iv, "base64"));
  d.setAuthTag(Buffer.from(tag, "base64"));
  return d.update(Buffer.from(data, "base64")).toString("utf8") + d.final("utf8");
}
function get(shop, token, p) {
  return new Promise((res, rej) => {
    https.get({ hostname: shop, path: `/admin/api/2024-10${p}`, headers: { "X-Shopify-Access-Token": token } }, r => {
      let b = ""; r.on("data", c => b += c); r.on("end", () => { try { res(JSON.parse(b)); } catch { res({ err: b }); } });
    }).on("error", rej);
  });
}
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

(async () => {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const ms = new Date(2026, 3, 1), me = new Date(2026, 4, 1);
  const conn = (await db.collection("shopify_connections").where("user_id","==",uid).limit(1).get()).docs[0].data();
  const token = decrypt(conn.access_token, KEY);

  // Shopify orders in April (by created_at)
  const shopifyAprByExtId = new Map();
  const shopifyAprByNum = new Map();
  let sinceId = 0;
  while (true) {
    const d = await get(conn.shop_domain, token, `/orders.json?status=any&limit=250&since_id=${sinceId}`);
    if (!d.orders || d.orders.length === 0) break;
    for (const o of d.orders) {
      const dt = new Date(o.created_at);
      if (dt >= ms && dt < me) {
        shopifyAprByExtId.set(String(o.id), o);
        shopifyAprByNum.set(String(o.order_number), o);
      }
    }
    sinceId = d.orders[d.orders.length - 1].id;
    if (d.orders.length < 250) break;
    await sleep(400);
  }
  console.log(`Shopify April orders: ${shopifyAprByExtId.size}`);

  // Revvo sales in April
  const salesSnap = await db.collection("sales").where("user_id","==",uid).get();
  const revvoApr = [];
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    const dt = s.date?.toDate ? s.date.toDate() : null;
    if (!dt || dt < ms || dt >= me) continue;
    revvoApr.push({ id: doc.id, data: s });
  }
  console.log(`Revvo April sales: ${revvoApr.length}`);

  // Find Revvo sales without matching Shopify
  const missing = [];
  for (const r of revvoApr) {
    const extId = String(r.data.external_order_id || "");
    const num = String(r.data.shopify_order_number || r.data.order_number || "");
    if (shopifyAprByExtId.has(extId)) continue;
    if (shopifyAprByNum.has(num)) continue;
    missing.push(r);
  }
  console.log(`\nRevvo sales with no matching Shopify April order: ${missing.length}`);
  for (const r of missing) {
    console.log(`  saleId=${r.id}`);
    console.log(`    external_order_id=${r.data.external_order_id}`);
    console.log(`    shopify_order_number=${r.data.shopify_order_number}`);
    console.log(`    order_number=${r.data.order_number}`);
    console.log(`    date=${r.data.date?.toDate?.()?.toISOString()}`);
    console.log(`    created_at=${r.data.created_at?.toDate?.()?.toISOString()}`);
    console.log(`    order_status=${r.data.order_status}`);
    console.log(`    payment_status=${r.data.payment_status}`);
    console.log(`    total=${r.data.total || r.data.amount_paid}`);
    console.log(`    source=${r.data.source || r.data.platform || "?"}`);
    // Check if Shopify has this order at all
    if (r.data.external_order_id) {
      const d2 = await get(conn.shop_domain, token, `/orders/${r.data.external_order_id}.json?status=any`);
      if (d2.order) {
        console.log(`    → Shopify HAS this order, created_at=${d2.order.created_at}, cancelled_at=${d2.order.cancelled_at}`);
      } else {
        console.log(`    → Shopify does NOT have this order`);
      }
    }
  }
  process.exit(0);
})();
