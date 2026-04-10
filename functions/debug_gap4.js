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
  const monthStart = new Date(2026, 3, 1);
  const monthEnd = new Date(2026, 4, 1);

  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();

  const saleById = {};
  const saleByOrderNum = {};
  salesSnap.docs.forEach(d => {
    const data = d.data();
    saleById[d.id] = data;
    if (data.shopify_order_number) {
      saleByOrderNum[String(data.shopify_order_number)] = { id: d.id, data };
    }
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

  // Build Shopify active orders this month
  const shopifyActive = {};
  allOrders.forEach(o => {
    const d = new Date(o.created_at);
    if (d >= monthStart && d < monthEnd && !o.cancelled_at) {
      shopifyActive[String(o.order_number)] = o;
    }
  });

  // For each Revvo active positive revenue txn, match with Shopify
  const matched = [];  // {orderNum, revvoAmt, shopifyAmt}
  const unmatched = [];

  txnsSnap.docs.forEach(d => {
    const data = d.data();
    if (data.exclude_from_pl) return;
    if (data.category_id !== "cat_sales_revenue") return;

    let dt;
    if (data.date_time && data.date_time._seconds) {
      dt = new Date(data.date_time._seconds * 1000);
    } else if (data.date_time && typeof data.date_time === "string") {
      dt = new Date(data.date_time);
    }
    if (!dt || dt < monthStart || dt >= monthEnd) return;

    const amount = Number(data.amount) || 0;
    if (amount <= 0) return;

    const sale = saleById[data.sale_id];
    if (sale && sale.order_status === 4) return;

    const orderNum = sale ? String(sale.shopify_order_number || "") : "";
    const shopOrder = shopifyActive[orderNum];

    if (shopOrder) {
      const gross = (shopOrder.line_items || []).reduce((s, li) => s + (Number(li.quantity) || 0) * (Number(li.price) || 0), 0);
      const disc = Number(shopOrder.total_discounts) || 0;
      matched.push({ orderNum, revvoAmt: amount, shopifyAmt: round2(gross - disc) });
    } else {
      unmatched.push({ orderNum: orderNum || "NO_NUM", revvoAmt: amount, saleId: data.sale_id, txnId: d.id });
    }
  });

  console.log(`Matched: ${matched.length}, Unmatched: ${unmatched.length}`);
  
  // Check matched for differences
  let matchedRevvoTotal = 0, matchedShopifyTotal = 0;
  let diffCount = 0;
  matched.forEach(m => {
    matchedRevvoTotal += m.revvoAmt;
    matchedShopifyTotal += m.shopifyAmt;
    const diff = round2(m.revvoAmt - m.shopifyAmt);
    if (Math.abs(diff) > 0.01) {
      diffCount++;
      console.log(`  DIFF #${m.orderNum}: revvo=${m.revvoAmt} shopify=${m.shopifyAmt} diff=${diff}`);
    }
  });

  console.log(`\nMatched totals: Revvo=${round2(matchedRevvoTotal)} Shopify=${round2(matchedShopifyTotal)} diff=${round2(matchedRevvoTotal - matchedShopifyTotal)}`);
  console.log(`Differences found: ${diffCount}`);

  console.log(`\nUnmatched Revvo revenue txns (not in Shopify active):`);
  let unmatchedTotal = 0;
  unmatched.forEach(u => {
    unmatchedTotal += u.revvoAmt;
    // Check if it exists in Shopify at all
    const shopOrder = allOrders.find(o => String(o.order_number) === u.orderNum);
    const shopStatus = shopOrder ? `cancelled=${!!shopOrder.cancelled_at} financial=${shopOrder.financial_status}` : "NOT_IN_SHOPIFY";
    console.log(`  #${u.orderNum} | amt=${u.revvoAmt} | ${shopStatus}`);
  });
  console.log(`Unmatched total: ${round2(unmatchedTotal)}`);

  console.log(`\nSummary:`);
  console.log(`  Matched Revvo: ${round2(matchedRevvoTotal)}`);
  console.log(`  Matched Shopify: ${round2(matchedShopifyTotal)}`);
  console.log(`  Per-order diff: ${round2(matchedRevvoTotal - matchedShopifyTotal)}`);
  console.log(`  Unmatched Revvo: ${round2(unmatchedTotal)}`);
  console.log(`  Full gap: ${round2(matchedRevvoTotal - matchedShopifyTotal + unmatchedTotal)}`);

  // Also check shipping for the 6 unmatched
  console.log("\n=== Shipping Analysis ===");
  let revvoShipMatched = 0, shopShipMatched = 0, revvoShipUnmatched = 0;
  txnsSnap.docs.forEach(d => {
    const data = d.data();
    if (data.exclude_from_pl) return;
    if (data.category_id !== "cat_shipping") return;

    let dt;
    if (data.date_time && data.date_time._seconds) {
      dt = new Date(data.date_time._seconds * 1000);
    } else if (data.date_time && typeof data.date_time === "string") {
      dt = new Date(data.date_time);
    }
    if (!dt || dt < monthStart || dt >= monthEnd) return;

    const amount = Number(data.amount) || 0;
    if (amount <= 0) return;  // Only positive shipping (income)

    const sale = saleById[data.sale_id];
    if (sale && sale.order_status === 4) return;

    const orderNum = sale ? String(sale.shopify_order_number || "") : "";
    if (shopifyActive[orderNum]) {
      revvoShipMatched += amount;
      const shopOrder = shopifyActive[orderNum];
      shopShipMatched += (shopOrder.shipping_lines || []).reduce((s, l) => s + (Number(l.price) || 0), 0);
    } else {
      revvoShipUnmatched += amount;
    }
  });

  console.log(`Matched shipping: revvo=${round2(revvoShipMatched)} shopify=${round2(shopShipMatched)} diff=${round2(revvoShipMatched - shopShipMatched)}`);
  console.log(`Unmatched shipping: ${round2(revvoShipUnmatched)}`);
  console.log(`Total shipping gap: ${round2((revvoShipMatched - shopShipMatched) + revvoShipUnmatched)}`);

  process.exit(0);
}

main().catch(console.error);
