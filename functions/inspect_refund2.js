const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({
  credential: admin.credential.cert(require(path.resolve(
    "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))),
});
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
function decrypt(enc) {
  const [a, b, c] = enc.split(":");
  const d = crypto.createDecipheriv("aes-256-gcm", Buffer.from(KEY, "hex"), Buffer.from(a, "base64"));
  d.setAuthTag(Buffer.from(b, "base64"));
  return d.update(Buffer.from(c, "base64")).toString("utf8") + d.final("utf8");
}

async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token);
  const shop = conn.shop_domain;
  // Fetch single order directly by id
  const res = await fetch(`https://${shop}/admin/api/2024-01/orders/7333841862976.json`, {
    headers: { "X-Shopify-Access-Token": token },
  });
  const { order } = await res.json();
  console.log("Order #" + order.order_number);
  console.log(JSON.stringify(order.refunds, null, 2).slice(0, 4000));
}
main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
