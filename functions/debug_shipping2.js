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

  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

  const allOrders = [];
  let since_id = 0;
  while (true) {
    const data = await shopifyGet(shop, token, `/orders.json?status=any&limit=250&since_id=${since_id}&fields=id,order_number,created_at,cancelled_at,shipping_lines,refunds,financial_status,total_shipping_price_set`);
    if (!data.orders || data.orders.length === 0) break;
    allOrders.push(...data.orders);
    since_id = data.orders[data.orders.length - 1].id;
    if (data.orders.length < 250) break;
    await sleep(500);
  }

  const aprilOrders = allOrders.filter(o => {
    const d = new Date(o.created_at);
    return d >= monthStart && d < monthEnd;
  });
  const active = aprilOrders.filter(o => !o.cancelled_at);

  // Check for refunded shipping in active orders
  let totalShippingCharged = 0;
  let totalShippingRefunded = 0;
  let ordersWithShippingRefund = 0;

  console.log("=== Checking Active April Orders for Shipping Refunds ===\n");

  for (const o of active) {
    const shipCharged = (o.shipping_lines || []).reduce((s, sl) => s + (Number(sl.price) || 0), 0);
    totalShippingCharged += shipCharged;

    // Check refunds for shipping adjustments
    let shipRefunded = 0;
    (o.refunds || []).forEach(refund => {
      // Check order_adjustments for shipping refunds
      (refund.order_adjustments || []).forEach(adj => {
        if (adj.kind === "shipping_refund") {
          shipRefunded += Math.abs(Number(adj.amount) || 0);
        }
      });
      // Also check refund shipping lines
      if (refund.shipping) {
        shipRefunded += Math.abs(Number(refund.shipping.amount) || 0);
      }
    });

    if (shipRefunded > 0) {
      ordersWithShippingRefund++;
      console.log(`  #${o.order_number}: charged=${shipCharged} refunded=${shipRefunded} net=${round2(shipCharged - shipRefunded)} status=${o.financial_status}`);
    }

    totalShippingRefunded += shipRefunded;
  }

  console.log(`\nActive orders: ${active.length}`);
  console.log(`Orders with shipping refunds: ${ordersWithShippingRefund}`);
  console.log(`Total shipping charged:  ${round2(totalShippingCharged)}`);
  console.log(`Total shipping refunded: ${round2(totalShippingRefunded)}`);
  console.log(`Net shipping:            ${round2(totalShippingCharged - totalShippingRefunded)}`);
  console.log(`Your Shopify figure:     16656`);
  console.log(`Diff from net:           ${round2((totalShippingCharged - totalShippingRefunded) - 16656)}`);

  // Deep-dive: look at all refunds to find shipping-related adjustments
  console.log("\n=== All Refund Shipping Details ===");
  for (const o of active) {
    if (!o.refunds || o.refunds.length === 0) continue;
    for (const refund of o.refunds) {
      // Print all order adjustments
      if (refund.order_adjustments && refund.order_adjustments.length > 0) {
        for (const adj of refund.order_adjustments) {
          console.log(`  #${o.order_number} adjustment: kind=${adj.kind} amount=${adj.amount} tax=${adj.tax_amount}`);
        }
      }
    }
  }

  // Also check: discounted_price vs price for active shipping
  let totalDiscountedShip = 0;
  active.forEach(o => {
    (o.shipping_lines || []).forEach(sl => {
      totalDiscountedShip += Number(sl.discounted_price) || 0;
    });
  });
  console.log(`\nshipping_lines.discounted_price sum: ${round2(totalDiscountedShip)}`);
  console.log(`If Shopify uses discounted_price: ${round2(totalDiscountedShip)}`);
  console.log(`Diff from 16656: ${round2(totalDiscountedShip - 16656)}`);

  // What about cancelled orders that Shopify might be netting?
  let cancelledShip = 0;
  const cancelledApril = aprilOrders.filter(o => !!o.cancelled_at);
  cancelledApril.forEach(o => {
    (o.shipping_lines || []).forEach(sl => {
      cancelledShip += Number(sl.price) || 0;
    });
  });
  console.log(`\nCancelled April orders shipping: ${round2(cancelledShip)}`);
  console.log(`Active shipping - cancelled: ${round2(totalShippingCharged - cancelledShip)}`);
  console.log(`Diff from 16656: ${round2((totalShippingCharged - cancelledShip) - 16656)}`);

  console.log(`\n=== Other Possible Interpretations ===`);
  console.log(`active.discounted_price - cancelled.price = ${round2(totalDiscountedShip - cancelledShip)}`);
  console.log(`Diff from 16656: ${round2((totalDiscountedShip - cancelledShip) - 16656)}`);

  // Check: does Shopify maybe net cancelled shipping?
  // active_ship - cancelled_ship = 17303 - 1598 = 15705 (too low)
  // So maybe Shopify includes cancelled but nets them...
  // All orders (active + cancelled) shipping
  let allAprilShip = 0;
  aprilOrders.forEach(o => {
    (o.shipping_lines || []).forEach(sl => {
      allAprilShip += Number(sl.price) || 0;
    });
  });
  console.log(`\nAll April orders (incl cancelled) shipping: ${round2(allAprilShip)}`);
  console.log(`Diff from 16656: ${round2(allAprilShip - 16656)}`);

  process.exit(0);
}

main().catch(console.error);
