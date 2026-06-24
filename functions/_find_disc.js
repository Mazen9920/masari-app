/** Find June orders with non-zero Shopify discounts and show where stored. */
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
async function fetchAll(shop, token) {
  let orders = [], url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2026-05-25T00:00:00Z`;
  while (url) {
    const res = await fetch(url, { headers: { "X-Shopify-Access-Token": token } });
    const j = await res.json();
    orders = orders.concat(j.orders || []);
    const link = res.headers.get("link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise(r => setTimeout(r, 150));
  }
  return orders;
}
async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, KEY);
  const shop = conn.shop_domain;
  const orders = await fetchAll(shop, token);
  console.log(`fetched ${orders.length}`);
  let withDisc = orders.filter(o => Number(o.total_discounts) > 0);
  console.log(`orders with total_discounts>0: ${withDisc.length}`);
  let sum = 0;
  withDisc.slice(0, 10).forEach(o => {
    console.log(`#${o.order_number} total_discounts=${o.total_discounts} apps=${JSON.stringify(o.discount_applications)} liDisc=${o.line_items.reduce((s,li)=>s+Number(li.total_discount),0)}`);
  });
  withDisc.forEach(o => sum += Number(o.total_discounts));
  console.log(`TOTAL total_discounts (created>=May25): ${Math.round(sum*100)/100}`);
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
