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
  const monthStart = new Date(2026, 3, 1); // April
  const monthEnd = new Date(2026, 4, 1);

  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

  // Fetch all shopify orders
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

  // Build Shopify active order set for April (by order_number)
  const shopifyActiveApril = new Set();
  allOrders.forEach(o => {
    const d = new Date(o.created_at);
    if (d >= monthStart && d < monthEnd && !o.cancelled_at) {
      shopifyActiveApril.add(String(o.order_number));
    }
  });

  // Get all Revvo positive non-cancelled revenue txns in April
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  
  const salesMap = {};
  salesSnap.docs.forEach(d => {
    salesMap[d.id] = d.data();
  });

  const activeRevvoTxns = []; // positive, non-cancelled revenue txns in April
  txnsSnap.docs.forEach(doc => {
    const d = doc.data();
    if (d.category_id !== "cat_sales_revenue") return;
    const amt = Number(d.amount);
    if (amt <= 0) return;
    if (d.title && d.title.includes("[Cancelled]")) return;
    
    let dt;
    if (d.date_time && d.date_time._seconds) {
      dt = new Date(d.date_time._seconds * 1000);
    } else if (d.date_time && typeof d.date_time === "string") {
      dt = new Date(d.date_time);
    } else { return; }
    if (dt < monthStart || dt >= monthEnd) return;

    const sale = d.sale_id ? salesMap[d.sale_id] : null;
    const orderNum = sale ? (sale.shopify_order_number || sale.order_number || "???") : "???";
    activeRevvoTxns.push({ id: doc.id, amt, orderNum: String(orderNum), date: dt.toISOString().substring(0,10), saleId: d.sale_id });
  });

  console.log(`Shopify active April orders: ${shopifyActiveApril.size}`);
  console.log(`Revvo active positive revenue txns in April: ${activeRevvoTxns.length}`);
  console.log(`Revvo active total: ${round2(activeRevvoTxns.reduce((s, t) => s + t.amt, 0))}`);

  // Find Revvo txns not matching any Shopify active April order
  const unmatchedRevvo = activeRevvoTxns.filter(t => !shopifyActiveApril.has(t.orderNum));
  console.log(`\nUnmatched Revvo txns (in Revvo active but NOT in Shopify active April):`);
  unmatchedRevvo.forEach(t => {
    const sale = salesMap[t.saleId];
    const status = sale ? sale.status : "???";
    const cancelledAt = sale ? (sale.cancelled_at || "none") : "???";
    console.log(`  #${t.orderNum}: amt=${t.amt} date=${t.date} status=${status} cancelled_at=${cancelledAt} saleId=${t.saleId}`);
  });
  console.log(`  Total unmatched: ${round2(unmatchedRevvo.reduce((s, t) => s + t.amt, 0))}`);

  // Also check: Shopify active orders NOT in Revvo
  const revvoOrderNums = new Set(activeRevvoTxns.map(t => t.orderNum));
  const unmatchedShopify = [...shopifyActiveApril].filter(n => !revvoOrderNums.has(n));
  console.log(`\nShopify active orders not found in Revvo active txns: ${unmatchedShopify.length}`);
  unmatchedShopify.forEach(n => console.log(`  #${n}`));

  process.exit(0);
}

main().catch(console.error);
