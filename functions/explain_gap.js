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

  // Find orders CREATED in April but CANCELLED in April (April-only impact)
  // And orders CREATED in March but CANCELLED in April (cross-month impact)
  console.log("=== April Cancelled Orders Analysis ===\n");
  
  const aprilCancelledInApril = [];
  const marchCreatedAprilCancelled = [];
  
  allOrders.forEach(o => {
    if (!o.cancelled_at) return;
    const created = new Date(o.created_at);
    const cancelled = new Date(o.cancelled_at);
    
    if (cancelled >= monthStart && cancelled < monthEnd) {
      // Cancelled in April
      const createdInApril = created >= monthStart && created < monthEnd;
      const num = String(o.order_number);
      const gross = (o.line_items || []).reduce((s, li) => s + (Number(li.quantity) || 0) * (Number(li.price) || 0), 0);
      const disc = Number(o.total_discounts) || 0;
      const rev = round2(gross - disc);
      const ship = (o.shipping_lines || []).reduce((s, l) => s + (Number(l.price) || 0), 0);
      
      const entry = { num, rev, ship, created: o.created_at.substring(0,10), cancelled: o.cancelled_at.substring(0,10) };
      
      if (createdInApril) {
        aprilCancelledInApril.push(entry);
      } else {
        marchCreatedAprilCancelled.push(entry);
      }
    }
  });

  console.log("Orders CREATED in April AND CANCELLED in April:");
  let aprilAprilRev = 0, aprilAprilShip = 0;
  aprilCancelledInApril.forEach(e => {
    console.log(`  #${e.num}: rev=${e.rev} ship=${e.ship} created=${e.created} cancelled=${e.cancelled}`);
    aprilAprilRev += e.rev;
    aprilAprilShip += e.ship;
  });
  console.log(`  Total: ${aprilCancelledInApril.length} orders, rev=${round2(aprilAprilRev)}, ship=${round2(aprilAprilShip)}`);

  console.log("\nOrders CREATED before April BUT CANCELLED in April:");
  let crossRev = 0, crossShip = 0;
  marchCreatedAprilCancelled.forEach(e => {
    console.log(`  #${e.num}: rev=${e.rev} ship=${e.ship} created=${e.created} cancelled=${e.cancelled}`);
    crossRev += e.rev;
    crossShip += e.ship;
  });
  console.log(`  Total: ${marchCreatedAprilCancelled.length} orders, rev=${round2(crossRev)}, ship=${round2(crossShip)}`);

  console.log("\n=== Why the gap exists ===");
  console.log("Shopify: counts 179 active April orders. Does not include ANY cancelled orders.");
  console.log(`Revvo: Active April orders net revenue MATCHES Shopify (per-order = 0 diff).`);
  console.log(`BUT Revvo also has ${marchCreatedAprilCancelled.length} reversal txns in April for orders created BEFORE April.`);
  console.log(`These reversals reduce April revenue by ${round2(crossRev)} but Shopify never counted these in April.`);
  console.log(`Expected gap ≈ ${round2(-crossRev)} (negative = Revvo lower)`);

  process.exit(0);
}

main().catch(console.error);
