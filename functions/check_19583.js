const admin = require("firebase-admin");
const https = require("https");
const crypto = require("crypto");

admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
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
    https.get({
      hostname: shop,
      path: `/admin/api/2024-10${apiPath}`,
      headers: { "X-Shopify-Access-Token": token },
    }, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => resolve(JSON.parse(body)));
    }).on("error", reject);
  });
}

async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

  // Fetch all orders to find #19583
  const allOrders = [];
  let since_id = 0;
  while (true) {
    const data = await shopifyGet(conn.shop_domain, token,
      `/orders.json?status=any&limit=250&since_id=${since_id}&fields=id,order_number,shipping_lines,total_shipping_price_set,total_discounts,discount_codes,discount_applications`);
    if (!data.orders || data.orders.length === 0) break;
    allOrders.push(...data.orders);
    since_id = data.orders[data.orders.length - 1].id;
    if (data.orders.length < 250) break;
    await sleep(500);
  }

  const o = allOrders.find(x => x.order_number === 19583);
  if (o) {
    console.log("=== Order #19583 ===");
    console.log("shipping_lines:", JSON.stringify(o.shipping_lines, null, 2));
    console.log("total_shipping_price_set:", JSON.stringify(o.total_shipping_price_set, null, 2));
    console.log("total_discounts:", o.total_discounts);
    console.log("discount_codes:", JSON.stringify(o.discount_codes, null, 2));
    console.log("discount_applications:", JSON.stringify(o.discount_applications, null, 2));
  }

  // Also check: what does Revvo have for this order?
  const sales = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("shopify_order_number", "==", "19583")
    .get();
  for (const s of sales.docs) {
    const d = s.data();
    console.log("\n=== Revvo Sale ===");
    console.log("  id:", s.id);
    console.log("  shipping_cost:", d.shipping_cost);
    console.log("  discount_amount:", d.discount_amount);

    // Get shipping transaction
    const txns = await db.collection("transactions")
      .where("sale_id", "==", s.id)
      .get();
    for (const t of txns.docs) {
      const td = t.data();
      console.log(`  txn: ${t.id} cat=${td.category_id} amount=${td.amount}`);
    }
  }

  process.exit(0);
}
main().catch(console.error);
