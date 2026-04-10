const https = require("https");
const crypto = require("crypto");
const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});
const db = admin.firestore();
const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";

function decrypt(e, k) {
  const [i, t, d] = e.split(":");
  const kb = Buffer.from(k, "hex");
  const iv = Buffer.from(i, "base64");
  const tag = Buffer.from(t, "base64");
  const data = Buffer.from(d, "base64");
  const dec = crypto.createDecipheriv("aes-256-gcm", kb, iv);
  dec.setAuthTag(tag);
  return dec.update(data).toString("utf8") + dec.final("utf8");
}

function shopifyGet(shop, token, path) {
  return new Promise((resolve, reject) => {
    https.get({ hostname: shop, path: `/admin/api/2024-10${path}`, headers: { "X-Shopify-Access-Token": token } }, (res) => {
      let b = ""; res.on("data", c => b += c); res.on("end", () => resolve(JSON.parse(b)));
    }).on("error", reject);
  });
}

(async () => {
  const conn = (await db.collection("shopify_connections").where("user_id", "==", "EGYQnP7ughdUtTbn04UwUET534i1").limit(1).get()).docs[0].data();
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  // Get order 19583 by its Shopify ID
  const data = await shopifyGet(conn.shop_domain, token, "/orders/7112654225728.json?fields=id,order_number,shipping_lines,total_shipping_price_set,discount_applications,discount_codes");
  const o = data.order;
  console.log("Order #" + o.order_number);
  console.log("\nshipping_lines:");
  for (const sl of o.shipping_lines) {
    console.log("  price:", sl.price);
    console.log("  discounted_price:", sl.discounted_price);
    console.log("  discount_allocations:", JSON.stringify(sl.discount_allocations));
  }
  console.log("\ntotal_shipping_price_set:", JSON.stringify(o.total_shipping_price_set, null, 2));
  console.log("\ndiscount_applications:", JSON.stringify(o.discount_applications, null, 2));
  console.log("discount_codes:", JSON.stringify(o.discount_codes, null, 2));
  process.exit(0);
})();
