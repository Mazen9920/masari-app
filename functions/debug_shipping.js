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

  // Filter April orders
  const aprilOrders = allOrders.filter(o => {
    const d = new Date(o.created_at);
    return d >= monthStart && d < monthEnd;
  });

  const active = aprilOrders.filter(o => !o.cancelled_at);
  const cancelled = aprilOrders.filter(o => !!o.cancelled_at);

  // Shopify shipping breakdown
  let activeShipFromLines = 0;      // sum of shipping_lines[].price
  let activeShipFromDiscLines = 0;  // sum of discount_allocations on shipping lines
  let activeShipFromTotal = 0;      // total_shipping_price_set (if available)

  console.log("=== Active April Orders Shipping ===\n");

  active.forEach(o => {
    const shipLines = o.shipping_lines || [];
    let lineShip = 0;
    let lineShipDisc = 0;
    let discountedPrice = 0;

    shipLines.forEach(sl => {
      lineShip += Number(sl.price) || 0;
      discountedPrice += Number(sl.discounted_price) || 0;
      const allocs = sl.discount_allocations || [];
      allocs.forEach(a => { lineShipDisc += Number(a.amount) || 0; });
    });

    activeShipFromLines += lineShip;
    activeShipFromDiscLines += lineShipDisc;

    // Check total_shipping_price_set
    const tsp = o.total_shipping_price_set;
    const shopShip = tsp ? Number(tsp.shop_money?.amount) : null;
    if (shopShip != null) activeShipFromTotal += shopShip;

    // Show orders where shipping is discounted
    if (lineShipDisc > 0 || lineShip !== discountedPrice) {
      console.log(`  #${o.order_number}: ship_lines.price=${lineShip} discounted_price=${discountedPrice} disc_alloc=${lineShipDisc} total_shipping=${shopShip}`);
    }
  });

  console.log(`\nActive orders: ${active.length}`);
  console.log(`shipping_lines.price sum:             ${round2(activeShipFromLines)}`);
  console.log(`shipping_lines.discounted_price sum:  (computed per order above)`);
  console.log(`discount_allocations on shipping sum:  ${round2(activeShipFromDiscLines)}`);
  console.log(`total_shipping_price_set sum:          ${round2(activeShipFromTotal)}`);
  console.log(`ship_lines - disc_alloc:               ${round2(activeShipFromLines - activeShipFromDiscLines)}`);

  // Also compute discounted_price sum for all active
  let activeDiscountedShip = 0;
  active.forEach(o => {
    (o.shipping_lines || []).forEach(sl => {
      activeDiscountedShip += Number(sl.discounted_price) || 0;
    });
  });
  console.log(`shipping_lines.discounted_price sum:   ${round2(activeDiscountedShip)}`);

  // Cancelled orders shipping
  let cancelledShip = 0;
  cancelled.forEach(o => {
    (o.shipping_lines || []).forEach(sl => {
      cancelledShip += Number(sl.price) || 0;
    });
  });
  console.log(`\nCancelled April orders shipping:       ${round2(cancelledShip)}`);

  // Revvo shipping transactions
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();
  let revvoShipPos = 0, revvoShipNeg = 0;
  const shipTxns = [];

  txnsSnap.docs.forEach(doc => {
    const d = doc.data();
    if (d.category_id !== "cat_shipping") return;
    let dt;
    if (d.date_time && d.date_time._seconds) {
      dt = new Date(d.date_time._seconds * 1000);
    } else if (d.date_time && typeof d.date_time === "string") {
      dt = new Date(d.date_time);
    } else { return; }
    if (dt < monthStart || dt >= monthEnd) return;

    const amt = Number(d.amount) || 0;
    if (amt >= 0) revvoShipPos += amt;
    else revvoShipNeg += amt;
    shipTxns.push({ id: doc.id, amt, title: d.title, saleId: d.sale_id });
  });

  console.log(`\n=== Revvo April Shipping ===`);
  console.log(`Positive: ${round2(revvoShipPos)}`);
  console.log(`Negative: ${round2(revvoShipNeg)}`);
  console.log(`Net:      ${round2(revvoShipPos + revvoShipNeg)}`);

  // What Shopify analytics likely shows:
  console.log(`\n=== Likely Shopify Analytics ===`);
  console.log(`Shopify "Shipping" in analytics uses total_shipping_price_set (net of shipping discounts)`);
  console.log(`shipping_lines.price (gross):           ${round2(activeShipFromLines)}`);
  console.log(`total_shipping_price_set (net):         ${round2(activeShipFromTotal)}`);
  console.log(`Difference (shipping discounts):        ${round2(activeShipFromLines - activeShipFromTotal)}`);

  // Cross-month cancellations impact
  let crossMonthCancelShip = 0;
  allOrders.forEach(o => {
    if (!o.cancelled_at) return;
    const created = new Date(o.created_at);
    const cancelled = new Date(o.cancelled_at);
    if (created < monthStart && cancelled >= monthStart && cancelled < monthEnd) {
      (o.shipping_lines || []).forEach(sl => {
        crossMonthCancelShip += Number(sl.price) || 0;
      });
    }
  });
  console.log(`\nCross-month cancel reversals in April:  -${round2(crossMonthCancelShip)}`);

  // Full reconciliation
  console.log(`\n=== RECONCILIATION ===`);
  console.log(`If Shopify reports shipping as total_shipping_price_set (net of shipping discounts):`);
  console.log(`  Shopify net shipping:                 ${round2(activeShipFromTotal)}`);
  console.log(`  Revvo net:                            ${round2(revvoShipPos + revvoShipNeg)}`);
  console.log(`  Cross-month cancel adj:               -${round2(crossMonthCancelShip)}`);
  console.log(`  Revvo adjusted:                       ${round2(revvoShipPos + revvoShipNeg + crossMonthCancelShip)}`);
  console.log(`  Gap:                                  ${round2((revvoShipPos + revvoShipNeg + crossMonthCancelShip) - activeShipFromTotal)}`);

  console.log(`\nIf Shopify reports as shipping_lines.price (gross):`);
  console.log(`  Shopify gross shipping:               ${round2(activeShipFromLines)}`);
  console.log(`  Revvo adjusted:                       ${round2(revvoShipPos + revvoShipNeg + crossMonthCancelShip)}`);
  console.log(`  Gap:                                  ${round2((revvoShipPos + revvoShipNeg + crossMonthCancelShip) - activeShipFromLines)}`);

  process.exit(0);
}

main().catch(console.error);
