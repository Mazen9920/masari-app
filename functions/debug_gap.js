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

  // Load all transactions
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();

  // Month: April 2026
  const monthStart = new Date(2026, 3, 1); // April = month 3
  const monthEnd = new Date(2026, 4, 1);

  // Build sale lookup
  const saleById = {};
  salesSnap.docs.forEach(d => { saleById[d.id] = d.data(); });

  // Find ALL revenue transactions in this month
  console.log("=== ALL Revenue Transactions This Month ===");
  let posTotal = 0, negTotal = 0;
  const negTxns = [];
  const posTxns = [];

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
    if (amount < 0) {
      negTotal += amount;
      negTxns.push({ id: d.id, amount, saleId: data.sale_id, title: data.title, date: dt.toISOString().substring(0, 10) });
    } else {
      posTotal += amount;
      posTxns.push({ id: d.id, amount, saleId: data.sale_id, title: data.title, date: dt.toISOString().substring(0, 10) });
    }
  });

  console.log(`Positive revenue txns: ${posTxns.length}, total: ${round2(posTotal)}`);
  console.log(`Negative revenue txns: ${negTxns.length}, total: ${round2(negTotal)}`);
  console.log(`Net: ${round2(posTotal + negTotal)}`);

  console.log(`\n--- Negative Revenue Transactions ---`);
  negTxns.forEach(t => {
    const sale = saleById[t.saleId];
    const orderNum = sale ? (sale.shopify_order_number || "?") : "NO_SALE";
    const orderStatus = sale ? sale.order_status : "?";
    console.log(`  ${t.id} | amt=${t.amount} | sale=${t.saleId} | order=#${orderNum} | status=${orderStatus} | ${t.title} | ${t.date}`);
  });

  // Also check: are there positive revenue txns for cancelled orders?
  console.log(`\n--- Positive Revenue for Cancelled Orders (status=4) ---`);
  let cancelledPosTotal = 0;
  posTxns.forEach(t => {
    const sale = saleById[t.saleId];
    if (sale && sale.order_status === 4) {
      cancelledPosTotal += t.amount;
      const num = sale.shopify_order_number || "?";
      console.log(`  ${t.id} | amt=${t.amount} | #${num} | ${t.title} | ${t.date}`);
    }
  });
  console.log(`Total cancelled positive revenue: ${round2(cancelledPosTotal)}`);

  // How many positive revenue txns for ACTIVE orders?
  let activePosCount = 0, activePosTotal = 0;
  posTxns.forEach(t => {
    const sale = saleById[t.saleId];
    if (!sale || sale.order_status !== 4) {
      activePosCount++;
      activePosTotal += t.amount;
    }
  });
  console.log(`\nActive positive revenue: ${activePosCount} txns, total: ${round2(activePosTotal)}`);

  // Now compare: Shopify active count vs Revvo active positive revenue count
  // Fetch Shopify orders for this month
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

  const tmActive = allOrders.filter(o => {
    const d = new Date(o.created_at);
    return d >= monthStart && d < monthEnd && !o.cancelled_at;
  });

  let shopifyGross = 0;
  tmActive.forEach(o => {
    shopifyGross += (o.line_items || []).reduce((s, li) => s + (Number(li.quantity) || 0) * (Number(li.price) || 0), 0);
    shopifyGross -= Number(o.total_discounts) || 0;
  });

  console.log(`\nShopify active orders: ${tmActive.length}, revenue: ${round2(shopifyGross)}`);
  console.log(`Revvo active positive revenue: ${activePosCount}, total: ${round2(activePosTotal)}`);
  console.log(`Diff (revvo active pos - shopify): ${round2(activePosTotal - shopifyGross)}`);
  console.log();
  console.log(`So the gap of ${round2(activePosTotal + negTotal - shopifyGross)} is:`);
  console.log(`  Active pos excess: ${round2(activePosTotal - shopifyGross)}`);
  console.log(`  Negative txns: ${round2(negTotal)}`);
  console.log(`  Combined: ${round2((activePosTotal - shopifyGross) + negTotal)}`);

  process.exit(0);
}

main().catch(console.error);
