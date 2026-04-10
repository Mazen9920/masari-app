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
  const monthEnd = new Date(2026, 4, 1);   // May

  // Get Shopify credentials
  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

  // Fetch ALL orders
  const allOrders = [];
  let since_id = 0;
  while (true) {
    const data = await shopifyGet(shop, token, `/orders.json?status=any&limit=250&since_id=${since_id}&fields=id,order_number,created_at,cancelled_at,shipping_lines,refunds,financial_status`);
    if (!data.orders || data.orders.length === 0) break;
    allOrders.push(...data.orders);
    since_id = data.orders[data.orders.length - 1].id;
    if (data.orders.length < 250) break;
    await sleep(500);
  }

  // April orders
  const aprilOrders = allOrders.filter(o => {
    const d = new Date(o.created_at);
    return d >= monthStart && d < monthEnd;
  });
  const activeApril = aprilOrders.filter(o => !o.cancelled_at);
  const cancelledApril = aprilOrders.filter(o => !!o.cancelled_at);

  // Cross-month cancellations: created BEFORE April, cancelled IN April
  const crossMonth = allOrders.filter(o => {
    if (!o.cancelled_at) return false;
    const created = new Date(o.created_at);
    const cancelled = new Date(o.cancelled_at);
    return created < monthStart && cancelled >= monthStart && cancelled < monthEnd;
  });

  // Compute shipping amounts
  const shipPrice = (o) => (o.shipping_lines || []).reduce((s, sl) => s + (Number(sl.price) || 0), 0);
  const shipDiscounted = (o) => (o.shipping_lines || []).reduce((s, sl) => s + (Number(sl.discounted_price) || 0), 0);

  const activeShipGross = round2(activeApril.reduce((s, o) => s + shipPrice(o), 0));
  const activeShipDiscounted = round2(activeApril.reduce((s, o) => s + shipDiscounted(o), 0));
  const cancelledAprilShip = round2(cancelledApril.reduce((s, o) => s + shipPrice(o), 0));
  const crossMonthShip = round2(crossMonth.reduce((s, o) => s + shipPrice(o), 0));
  const shippingDiscount = round2(activeShipGross - activeShipDiscounted);

  // Revvo data
  const txSnap = await db.collection("transactions")
    .where("user_id", "==", uid)
    .where("category_id", "==", "shipping_revenue")
    .get();
  let revvoPos = 0, revvoNeg = 0;
  txSnap.docs.forEach(d => {
    const data = d.data();
    const dt = data.date_time?.toDate?.() || new Date(data.date_time?._seconds * 1000);
    if (dt >= monthStart && dt < monthEnd) {
      const amt = Number(data.amount) || 0;
      if (amt >= 0) revvoPos += amt;
      else revvoNeg += amt;
    }
  });
  revvoPos = round2(revvoPos);
  revvoNeg = round2(revvoNeg);
  const revvoNet = round2(revvoPos + revvoNeg);

  console.log("╔══════════════════════════════════════════════════════════════╗");
  console.log("║         SHIPPING RECONCILIATION — APRIL 2026                ║");
  console.log("╚══════════════════════════════════════════════════════════════╝\n");

  console.log("=== WHY REVVO SHOWS 18,901 ===");
  console.log(`  Active April orders shipping (gross price):  ${activeShipGross}`);
  console.log(`  + Cancelled April orders shipping (original): ${cancelledAprilShip}`);
  console.log(`  = Total positive shipping txns:               ${round2(activeShipGross + cancelledAprilShip)}`);
  console.log(`  Revvo positive shipping:                      ${revvoPos}`);
  console.log(`  Match: ${round2(activeShipGross + cancelledAprilShip) === revvoPos ? "✅ YES" : "❌ NO"}\n`);

  console.log("=== WHY SHOPIFY DASHBOARD SHOWS 16,656 ===");
  console.log(`  Active April orders (discounted_price):       ${activeShipDiscounted}`);
  console.log(`  − Cross-month cancellation shipping:          −${crossMonthShip}`);
  console.log(`  = Shopify dashboard shipping:                 ${round2(activeShipDiscounted - crossMonthShip)}`);
  console.log(`  User's Shopify figure:                        16656`);
  console.log(`  Match: ${round2(activeShipDiscounted - crossMonthShip) === 16656 ? "✅ YES" : "❌ NO"}\n`);

  console.log("=== THE 2,245 DIFFERENCE EXPLAINED ===");
  console.log(`  Revvo positive:                 ${revvoPos}`);
  console.log(`  Shopify dashboard:              16656`);
  console.log(`  Difference:                     ${round2(revvoPos - 16656)}\n`);
  console.log(`  Breakdown:`);
  console.log(`    1. Cancelled April orders     +${cancelledAprilShip}  (Revvo records these as +/- pairs;`);
  console.log(`       (created & cancelled                               Shopify just excludes them)`);
  console.log(`        in April)`);
  console.log(`    2. Cross-month cancellations  +${crossMonthShip}  (Created before April, cancelled in`);
  console.log(`       (reversal-only in April)                          April → Revvo has −${crossMonthShip} reversal;`);
  console.log(`                                                          Shopify deducts from total)`);
  console.log(`    3. Shipping discount          +${shippingDiscount}   (Order #19583 has ${shippingDiscount} EGP shipping`);
  console.log(`       (gross vs discounted)                             discount. Revvo uses gross price,`);
  console.log(`                                                          Shopify uses discounted_price)`);
  console.log(`    ─────────────────────────────────`);
  console.log(`    Total difference:             ${round2(cancelledAprilShip + crossMonthShip + shippingDiscount)}`);
  console.log(`    Expected:                     ${round2(revvoPos - 16656)}`);
  console.log(`    Match: ${round2(cancelledAprilShip + crossMonthShip + shippingDiscount) === round2(revvoPos - 16656) ? "✅ YES" : "❌ NO"}\n`);

  console.log("=== REVVO NET vs SHOPIFY DASHBOARD ===");
  console.log(`  Revvo net shipping (pos + neg): ${revvoNet}`);
  console.log(`  Shopify dashboard:              16656`);
  console.log(`  Remaining diff:                 ${round2(revvoNet - 16656)}`);
  console.log(`  This ${round2(revvoNet - 16656)} = shipping discount (${shippingDiscount}) on order #19583`);
  console.log(`  (Revvo records gross shipping price; Shopify nets the discount)\n`);

  // Show cross-month details
  console.log("=== Cross-Month Cancelled Orders (details) ===");
  for (const o of crossMonth) {
    console.log(`  #${o.order_number}: created=${o.created_at.slice(0,10)} cancelled=${o.cancelled_at.slice(0,10)} shipping=${shipPrice(o)}`);
  }

  // Show the shipping discount order
  console.log("\n=== Shipping Discount Order ===");
  for (const o of activeApril) {
    const gross = shipPrice(o);
    const disc = shipDiscounted(o);
    if (gross !== disc) {
      console.log(`  #${o.order_number}: gross=${gross} discounted=${disc} discount=${round2(gross - disc)}`);
    }
  }

  process.exit(0);
}

main().catch(console.error);
