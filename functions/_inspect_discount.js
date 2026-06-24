/** Dump discount-related fields for a few June orders to find the right field. */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
function decrypt(enc, key) {
  const [iv, tag, data] = enc.split(":");
  const d = crypto.createDecipheriv("aes-256-gcm", Buffer.from(key, "hex"), Buffer.from(iv, "base64"));
  d.setAuthTag(Buffer.from(tag, "base64"));
  return d.update(Buffer.from(data, "base64")).toString("utf8") + d.final("utf8");
}
async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, KEY);
  const shop = conn.shop_domain;
  // a known discounted order from results: #21364
  const res = await fetch(`https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2026-06-01T00:00:00Z`, {
    headers: { "X-Shopify-Access-Token": token },
  });
  const orders = (await res.json()).orders;
  const o = orders.find(x => x.order_number == 21364) || orders[0];
  console.log("order_number:", o.order_number);
  console.log("total_discounts:", o.total_discounts);
  console.log("current_total_discounts:", o.current_total_discounts);
  console.log("total_discounts_set:", JSON.stringify(o.total_discounts_set));
  console.log("discount_applications:", JSON.stringify(o.discount_applications, null, 1));
  console.log("discount_codes:", JSON.stringify(o.discount_codes));
  console.log("line_items discount fields:");
  for (const li of o.line_items) {
    console.log(`  ${li.name}: price=${li.price} qty=${li.quantity} total_discount=${li.total_discount} alloc=${JSON.stringify(li.discount_allocations)}`);
  }
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
