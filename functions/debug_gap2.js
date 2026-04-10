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

  // Month: April 2026
  const monthStart = new Date(2026, 3, 1);
  const monthEnd = new Date(2026, 4, 1);

  // Load Revvo data
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();

  // Build sale lookup and reverse lookup
  const saleById = {};
  const saleByOrderNum = {};
  salesSnap.docs.forEach(d => {
    const data = d.data();
    saleById[d.id] = data;
    if (data.shopify_order_number) {
      saleByOrderNum[String(data.shopify_order_number)] = { id: d.id, data };
    }
  });

  // Get all positive revenue txns for this month that are for ACTIVE (non-cancelled) orders
  const activePosTxns = [];
  txnsSnap.docs.forEach(d => {
    const data = d.data();
    if (data.exclude_from_pl) return;
    if (data.category_id !== "cat_sales_revenue") return;

    let dt;
    if (data.date_time && data.date_time._seconds) {
      dt = new Date(data.date_time._seconds * 1000);
    } else if (data.date_time && typeof data.date_time === "string") {
      dt = new Date(data.date_time);
    } else {
      return;
    }
    if (dt < monthStart || dt >= monthEnd) return;

    const amount = Number(data.amount) || 0;
    if (amount <= 0) return;

    const sale = saleById[data.sale_id];
    if (sale && sale.order_status === 4) return; // skip cancelled

    activePosTxns.push({
      txnId: d.id,
      amount,
      saleId: data.sale_id,
      orderNum: sale ? (sale.shopify_order_number || "?") : "NO_SALE",
      title: data.title,
      date: dt.toISOString().substring(0, 10),
      hasShopify: !!sale?.shopify_order_number,
    });
  });

  // Load Shopify orders
  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

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

  // Active Shopify orders this month
  const shopifyActive = {};
  allOrders.forEach(o => {
    const d = new Date(o.created_at);
    if (d >= monthStart && d < monthEnd && !o.cancelled_at) {
      shopifyActive[String(o.order_number)] = o;
    }
  });

  console.log(`Revvo active positive revenue txns: ${activePosTxns.length}`);
  console.log(`Shopify active orders this month: ${Object.keys(shopifyActive).length}`);

  // Find Revvo txns that DON'T match any Shopify active order
  console.log("\n=== Revvo Active Revenue Txns NOT in Shopify Active ===");
  let extraTotal = 0;
  const extraTxns = [];
  activePosTxns.forEach(t => {
    if (!shopifyActive[String(t.orderNum)]) {
      extraTotal += t.amount;
      extraTxns.push(t);
      const sale = saleById[t.saleId];
      console.log(`  order=#${t.orderNum} | amt=${t.amount} | status=${sale ? sale.order_status : '?'} | extSrc=${sale?.external_source || '?'} | ${t.title} | ${t.date}`);
    }
  });
  console.log(`Extra count: ${extraTxns.length}, total: ${round2(extraTotal)}`);

  // Check: do these orders exist in Shopify at all (maybe cancelled)?
  console.log("\n=== Checking if extra orders exist in Shopify (any status) ===");
  for (const t of extraTxns) {
    const shopOrder = allOrders.find(o => String(o.order_number) === String(t.orderNum));
    if (shopOrder) {
      console.log(`  #${t.orderNum}: Shopify status: cancelled=${!!shopOrder.cancelled_at}, financial=${shopOrder.financial_status}, created=${shopOrder.created_at.substring(0,10)}`);
    } else {
      console.log(`  #${t.orderNum}: NOT FOUND in Shopify at all`);
    }
  }

  // Also check: Shopify active orders not in Revvo
  console.log("\n=== Shopify Active NOT in Revvo ===");
  let shopMissingTotal = 0;
  Object.values(shopifyActive).forEach(o => {
    const num = String(o.order_number);
    if (!saleByOrderNum[num]) {
      const gross = (o.line_items || []).reduce((s, li) => s + (Number(li.quantity) || 0) * (Number(li.price) || 0), 0);
      const disc = Number(o.total_discounts) || 0;
      const rev = round2(gross - disc);
      shopMissingTotal += rev;
      console.log(`  #${num}: rev=${rev} created=${o.created_at.substring(0,10)}`);
    }
  });
  console.log(`Missing from Revvo: total revenue=${round2(shopMissingTotal)}`);

  process.exit(0);
}

main().catch(console.error);
