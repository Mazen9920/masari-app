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

  // Fetch ALL orders
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

  // Revvo sales
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const revvoShopifyIds = new Set();
  salesSnap.docs.forEach(d => {
    const sid = d.data().shopify_order_id;
    if (sid) revvoShopifyIds.add(String(sid));
  });
  console.log("Revvo sales:", salesSnap.size);

  // Missing from Revvo
  const missing = allOrders.filter(o => !revvoShopifyIds.has(String(o.id)));
  console.log("\n=== Missing from Revvo:", missing.length, "===");
  let missingActive = 0, missingCancelled = 0, missingActiveTotal = 0;
  missing.forEach(o => {
    const total = Number(o.total_price) || 0;
    const isCancelled = !!o.cancelled_at;
    if (isCancelled) missingCancelled++;
    else { missingActive++; missingActiveTotal += total; }
    console.log(`  #${o.order_number} total=${total} fs=${o.financial_status} cancelled=${isCancelled} date=${o.created_at.substring(0, 10)}`);
  });
  console.log(`  ${missingActive} active (total: ${missingActiveTotal}), ${missingCancelled} cancelled`);

  // Paid orders with refunds (actual returns, not cancellations)
  console.log("\n=== PAID Orders with Refunds (ACTUAL RETURNS) ===");
  const paidWithRefunds = allOrders.filter(o =>
    o.financial_status === "paid" && o.refunds && o.refunds.length > 0
  );
  let totalReturnAmount = 0;
  for (const o of paidWithRefunds) {
    for (const r of o.refunds) {
      const items = r.refund_line_items || [];
      let itemTotal = 0;
      items.forEach(i => { itemTotal += (Number(i.subtotal)||0) + (Number(i.total_tax)||0); });
      const adjs = r.order_adjustments || [];
      let adjTotal = 0;
      adjs.forEach(a => { adjTotal += Math.abs(Number(a.amount)||0); });
      totalReturnAmount += itemTotal;
      console.log(`  #${o.order_number} refund=${r.id}: itemRefund=${round2(itemTotal)} shippingRefund=${adjTotal} date=${r.created_at.substring(0, 10)}`);
    }
  }
  console.log(`  Total return amount (items): ${round2(totalReturnAmount)}`);

  // This month filter (April 2025)
  console.log("\n=== THIS MONTH ANALYSIS (2025-04) ===");
  const monthStart = new Date("2025-04-01T00:00:00Z");
  const monthEnd = new Date("2025-05-01T00:00:00Z");
  
  const thisMonth = allOrders.filter(o => {
    const d = new Date(o.created_at);
    return d >= monthStart && d < monthEnd;
  });
  
  console.log(`This month orders: ${thisMonth.length}`);
  let mGross = 0, mCancelled = 0, mCancelledTotal = 0, mActiveTotal = 0;
  let mShipping = 0;
  const mFsCounts = {};
  thisMonth.forEach(o => {
    const total = Number(o.total_price) || 0;
    const shipping = (o.shipping_lines || []).reduce((s, l) => s + (Number(l.price) || 0), 0);
    mFsCounts[o.financial_status] = (mFsCounts[o.financial_status] || 0) + 1;
    if (o.cancelled_at) {
      mCancelled++;
      mCancelledTotal += total;
    } else {
      mActiveTotal += total;
      mShipping += shipping;
    }
    mGross += total;
  });
  console.log(`  FS: ${JSON.stringify(mFsCounts)}`);
  console.log(`  Gross (all): ${round2(mGross)}`);
  console.log(`  Cancelled: ${mCancelled} orders, total=${round2(mCancelledTotal)}`);
  console.log(`  Active total: ${round2(mActiveTotal)}`);
  console.log(`  Active shipping: ${round2(mShipping)}`);
  console.log(`  Active net (total - shipping): ${round2(mActiveTotal - mShipping)}`);

  // This month refunds on active orders
  const thisMonthPaidRefunds = thisMonth.filter(o =>
    o.financial_status === "paid" && o.refunds && o.refunds.length > 0
  );
  let thisMonthRefundAmt = 0;
  thisMonthPaidRefunds.forEach(o => {
    o.refunds.forEach(r => {
      (r.refund_line_items || []).forEach(i => {
        thisMonthRefundAmt += (Number(i.subtotal)||0) + (Number(i.total_tax)||0);
      });
    });
  });
  console.log(`  This month returns on active: ${round2(thisMonthRefundAmt)}`);

  // Check all refunds created this month regardless of order date
  console.log("\n=== REFUNDS CREATED THIS MONTH (any order date) ===");
  let refundsThisMonth = 0;
  let refundAmtThisMonth = 0;
  allOrders.forEach(o => {
    (o.refunds || []).forEach(r => {
      const rd = new Date(r.created_at);
      if (rd >= monthStart && rd < monthEnd) {
        const items = r.refund_line_items || [];
        let itemTotal = 0;
        items.forEach(i => { itemTotal += (Number(i.subtotal)||0) + (Number(i.total_tax)||0); });
        const adjs = r.order_adjustments || [];
        let adjTotal = 0;
        adjs.forEach(a => { adjTotal += Math.abs(Number(a.amount)||0); });
        refundsThisMonth++;
        refundAmtThisMonth += itemTotal + adjTotal;
        const isCancelled = !!o.cancelled_at;
        if (!isCancelled) {
          console.log(`  ACTIVE #${o.order_number} refund=${r.id}: items=${round2(itemTotal)} adj=${adjTotal} date=${r.created_at.substring(0, 10)}`);
        }
      }
    });
  });
  console.log(`  Total refunds this month: ${refundsThisMonth}, amount: ${round2(refundAmtThisMonth)}`);

  process.exit(0);
}

main().catch(console.error);
