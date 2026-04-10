/**
 * fix_reversal_dates.js
 * 
 * Updates the date_time on reversal transactions created by
 * migrate_missed_cancellations.js to use the Shopify cancelled_at date
 * instead of the migration run time.
 */
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

  // Get Shopify cancelled orders
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

  const cancelledByNum = {};
  allOrders.forEach(o => {
    if (o.cancelled_at) {
      cancelledByNum[String(o.order_number)] = o.cancelled_at;
    }
  });

  // Get all sales and their order numbers
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const saleOrderNum = {};
  salesSnap.docs.forEach(d => {
    const data = d.data();
    if (data.shopify_order_number) {
      saleOrderNum[d.id] = String(data.shopify_order_number);
    }
  });

  // Find all reversal transactions from our migration
  const txnsSnap = await db.collection("transactions")
    .where("user_id", "==", uid)
    .get();

  let updated = 0;
  const batch = db.batch();

  for (const doc of txnsSnap.docs) {
    const data = doc.data();
    // Only migration reversals
    if (!data.note || !data.note.includes("migration fix")) continue;
    if (!doc.id.includes("_reversal")) continue;

    const saleId = data.sale_id;
    const orderNum = saleOrderNum[saleId];
    if (!orderNum) continue;

    const cancelledAt = cancelledByNum[orderNum];
    if (!cancelledAt) continue;

    const cancelDate = new Date(cancelledAt);
    const cancelTs = admin.firestore.Timestamp.fromDate(cancelDate);

    batch.update(doc.ref, { date_time: cancelTs });
    updated++;
    console.log(`  ${doc.id} → ${cancelledAt.substring(0, 10)}`);
  }

  console.log(`\nUpdating ${updated} reversal dates...`);
  if (updated > 0) {
    await batch.commit();
    console.log("Done!");
  }

  process.exit(0);
}

main().catch(console.error);
