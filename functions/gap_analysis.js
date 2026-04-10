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
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

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

  // Get Revvo sales
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const revvoOrderNums = new Set();
  let minRevvoOrderNum = 99999, maxRevvoOrderNum = 0;
  salesSnap.docs.forEach(d => {
    const num = d.data().shopify_order_number;
    if (num) {
      revvoOrderNums.add(String(num));
      if (Number(num) < minRevvoOrderNum) minRevvoOrderNum = Number(num);
      if (Number(num) > maxRevvoOrderNum) maxRevvoOrderNum = Number(num);
    }
  });
  console.log(`Revvo order range: #${minRevvoOrderNum} - #${maxRevvoOrderNum}`);
  console.log(`Revvo sales: ${salesSnap.size}`);

  // Shopify order range
  const shopifyNums = allOrders.map(o => o.order_number);
  console.log(`Shopify order range: #${Math.min(...shopifyNums)} - #${Math.max(...shopifyNums)}`);
  console.log(`Shopify orders: ${allOrders.length}`);

  // Missing from Revvo (within Revvo's range)
  const missingInRange = allOrders.filter(o =>
    o.order_number >= minRevvoOrderNum &&
    o.order_number <= maxRevvoOrderNum &&
    !revvoOrderNums.has(String(o.order_number))
  );
  console.log(`\nMissing from Revvo (within range): ${missingInRange.length}`);
  missingInRange.forEach(o => {
    console.log(`  #${o.order_number} total=${o.total_price} fs=${o.financial_status} cancelled=${!!o.cancelled_at} date=${o.created_at.substring(0, 10)}`);
  });

  // The 4 refunded orders detail
  console.log("\n=== 4 Refunded Orders Detail ===");
  const refOrders = [18336, 18394, 18415, 18476];
  for (const num of refOrders) {
    const order = allOrders.find(o => o.order_number === num);
    if (!order) { console.log(`  #${num}: NOT FOUND`); continue; }
    console.log(`\n  #${num}: total=${order.total_price} fs=${order.financial_status} date=${order.created_at.substring(0, 10)}`);
    for (const r of (order.refunds || [])) {
      const items = r.refund_line_items || [];
      let itemTotal = 0, qty = 0;
      items.forEach(i => {
        itemTotal += (Number(i.subtotal)||0) + (Number(i.total_tax)||0);
        qty += Number(i.quantity) || 0;
      });
      const adjs = r.order_adjustments || [];
      let adjAmt = 0;
      adjs.forEach(a => { adjAmt += Math.abs(Number(a.amount)||0); });
      console.log(`    Refund ${r.id}: qty=${qty} itemRefund=${round2(itemTotal)} adjRefund=${adjAmt} date=${r.created_at.substring(0, 10)}`);
    }
    console.log(`    In Revvo range? ${order.order_number >= minRevvoOrderNum && order.order_number <= maxRevvoOrderNum}`);
  }

  // Shopify this month only
  console.log("\n=== April 2025 Shopify Summary ===");
  const monthStart = new Date("2025-04-01T00:00:00Z");
  const monthEnd = new Date("2025-05-01T00:00:00Z");
  const thisMonth = allOrders.filter(o => {
    const d = new Date(o.created_at);
    return d >= monthStart && d < monthEnd;
  });
  console.log(`This month Shopify orders: ${thisMonth.length}`);

  const activeThisMonth = thisMonth.filter(o => !o.cancelled_at);
  let aTotalPrice = 0, aShipping = 0;
  activeThisMonth.forEach(o => {
    aTotalPrice += Number(o.total_price) || 0;
    aShipping += (o.shipping_lines || []).reduce((s, l) => s + (Number(l.price) || 0), 0);
  });
  console.log(`Active: ${activeThisMonth.length}, total=${round2(aTotalPrice)}, shipping=${round2(aShipping)}`);
  console.log(`Revenue (total - shipping): ${round2(aTotalPrice - aShipping)}`);

  // Missing in this month
  const missingThisMonth = thisMonth.filter(o => !revvoOrderNums.has(String(o.order_number)));
  let missingActiveTM = 0, missingActiveTotal = 0, missingActiveShipping = 0;
  missingThisMonth.forEach(o => {
    if (!o.cancelled_at) {
      missingActiveTM++;
      missingActiveTotal += Number(o.total_price) || 0;
      missingActiveShipping += (o.shipping_lines || []).reduce((s, l) => s + (Number(l.price) || 0), 0);
    }
  });
  console.log(`\nMissing this month: ${missingThisMonth.length} (${missingActiveTM} active)`);
  console.log(`Missing active total: ${round2(missingActiveTotal)}, shipping: ${round2(missingActiveShipping)}`);
  missingThisMonth.filter(o => !o.cancelled_at).forEach(o => {
    console.log(`  #${o.order_number} total=${o.total_price} date=${o.created_at.substring(0, 10)}`);
  });

  process.exit(0);
}

main().catch(console.error);
