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

  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();

  // Build maps
  const revvoSalesByOrderNum = {};
  salesSnap.docs.forEach(d => {
    const data = d.data();
    const num = String(data.shopify_order_number || data.order_number || "");
    if (num) revvoSalesByOrderNum[num] = { id: d.id, data };
  });

  const txnsBySaleId = {};
  txnsSnap.docs.forEach(d => {
    const data = d.data();
    if (!data.sale_id) return;
    if (!txnsBySaleId[data.sale_id]) txnsBySaleId[data.sale_id] = [];
    txnsBySaleId[data.sale_id].push(data);
  });

  // Build Shopify order map
  const shopifyByNum = {};
  allOrders.forEach(o => { shopifyByNum[String(o.order_number)] = o; });

  // Compare ALL orders that exist in both systems (not just one month)
  // For each order in Revvo, check if Shopify agrees on revenue
  let totalMatchedRev = 0;
  let totalMatchedShip = 0;
  let matchCount = 0;
  let diffCount = 0;
  let shopifyActiveRevForMatched = 0;
  let shopifyActiveShipForMatched = 0;

  const diffs = [];

  for (const [num, sale] of Object.entries(revvoSalesByOrderNum)) {
    const order = shopifyByNum[num];
    if (!order) continue; // order not in Shopify (shouldn't happen)

    // Skip cancelled orders — we handle them separately via reversals
    if (order.cancelled_at) continue;

    matchCount++;

    // Shopify revenue
    const gross = (order.line_items || []).reduce((s, li) => s + (Number(li.quantity) || 0) * (Number(li.price) || 0), 0);
    const disc = Number(order.total_discounts) || 0;
    const shopifyRev = round2(gross - disc);
    const shopifyShip = (order.shipping_lines || []).reduce((s, l) => s + (Number(l.price) || 0), 0);

    shopifyActiveRevForMatched += shopifyRev;
    shopifyActiveShipForMatched += shopifyShip;

    // Revvo revenue (sum of revenue txns for this sale)
    const txns = txnsBySaleId[sale.id] || [];
    let revRev = 0, revShip = 0;
    txns.forEach(t => {
      const amt = Number(t.amount) || 0;
      if (t.category_id === "cat_sales_revenue") revRev += amt;
      else if (t.category_id === "cat_shipping") revShip += amt;
    });

    totalMatchedRev += revRev;
    totalMatchedShip += revShip;

    const revDiff = round2(revRev - shopifyRev);
    const shipDiff = round2(revShip - shopifyShip);
    if (Math.abs(revDiff) > 0.01 || Math.abs(shipDiff) > 0.01) {
      diffCount++;
      diffs.push({ num, shopifyRev, revRev: round2(revRev), revDiff, shopifyShip, revShip: round2(revShip), shipDiff });
    }
  }

  console.log("=== GLOBAL Order-by-Order Comparison (Active Orders Only) ===");
  console.log(`Matched active orders: ${matchCount}`);
  console.log(`Shopify active revenue (matched): ${round2(shopifyActiveRevForMatched)}`);
  console.log(`Revvo active revenue (matched):   ${round2(totalMatchedRev)}`);
  console.log(`Revenue gap: ${round2(totalMatchedRev - shopifyActiveRevForMatched)}`);
  console.log();
  console.log(`Shopify active shipping (matched): ${round2(shopifyActiveShipForMatched)}`);
  console.log(`Revvo active shipping (matched):   ${round2(totalMatchedShip)}`);
  console.log(`Shipping gap: ${round2(totalMatchedShip - shopifyActiveShipForMatched)}`);

  if (diffs.length > 0) {
    console.log(`\n${diffs.length} orders with differences:`);
    diffs.forEach(d => {
      console.log(`  #${d.num}: shopRev=${d.shopifyRev} revRev=${d.revRev} diff=${d.revDiff} | shopShip=${d.shopifyShip} revShip=${d.revShip} diff=${d.shipDiff}`);
    });
  } else {
    console.log("\nAll matched active orders have IDENTICAL revenue and shipping!");
  }

  // Count unmatched
  const revvoNums = new Set(Object.keys(revvoSalesByOrderNum));
  const activeShopifyNotInRevvo = allOrders.filter(o => !o.cancelled_at && !revvoNums.has(String(o.order_number)));
  console.log(`\nShopify active orders NOT in Revvo: ${activeShopifyNotInRevvo.length} (these were outside import range)`);

  // Cancelled order check
  const cancelledInRevvo = Object.entries(revvoSalesByOrderNum)
    .filter(([num]) => shopifyByNum[num] && shopifyByNum[num].cancelled_at)
    .length;
  console.log(`Cancelled Shopify orders that ARE in Revvo: ${cancelledInRevvo} (should have reversals)`);

  // Check that all cancelled orders in Revvo have status=4
  let cancelledCorrect = 0, cancelledWrong = 0;
  for (const [num, sale] of Object.entries(revvoSalesByOrderNum)) {
    const order = shopifyByNum[num];
    if (!order || !order.cancelled_at) continue;
    if (sale.data.order_status === 4) cancelledCorrect++;
    else cancelledWrong++;
  }
  console.log(`  Status=4 (correct): ${cancelledCorrect}, Status≠4 (wrong): ${cancelledWrong}`);

  process.exit(0);
}

main().catch(console.error);
