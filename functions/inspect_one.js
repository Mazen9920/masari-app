const admin = require("firebase-admin");
const path = require("path");
const crypto = require("crypto");
admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(
      "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
    ))),
});
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const NO = Number(process.argv[2] || 21402);
const dec = (e) => {
  const [a, b, c] = e.split(":");
  const d = crypto.createDecipheriv(
    "aes-256-gcm", Buffer.from(KEY, "hex"), Buffer.from(a, "base64"));
  d.setAuthTag(Buffer.from(b, "base64"));
  return d.update(Buffer.from(c, "base64")).toString("utf8") + d.final("utf8");
};
(async () => {
  const conn = (await db.collection("shopify_connections").doc(UID).get())
    .data();
  const token = dec(conn.access_token);
  const shop = conn.shop_domain;
  let orders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250`;
  while (url) {
    const res = await fetch(url, {
      headers: { "X-Shopify-Access-Token": token } });
    const j = await res.json();
    orders = orders.concat(j.orders || []);
    const m = (res.headers.get("link") || "").match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise((r) => setTimeout(r, 150));
  }
  const o = orders.find((x) => x.order_number === NO);
  if (!o) { console.log("order not found"); process.exit(0); }
  console.log("created", o.created_at, "cancelled", o.cancelled_at,
    "fs", o.financial_status);
  console.log("shipping_lines", JSON.stringify((o.shipping_lines || [])
    .map((s) => ({ price: s.price, disc: s.discounted_price }))));
  for (const rf of o.refunds || []) {
    console.log("refund", rf.id, "created", rf.created_at,
      "adjustments", JSON.stringify(rf.order_adjustments),
      "lineItems", (rf.refund_line_items || []).length);
  }
  const sid = `shopify_${UID}_${o.id}`;
  const tx = await db.collection("transactions")
    .where("user_id", "==", UID).where("sale_id", "==", sid).get();
  console.log("\nRevvo txns:");
  tx.docs.forEach((d) => {
    const t = d.data();
    console.log(d.id, "|", t.category_id, "|", t.amount, "|",
      t.date_time.toDate().toISOString(), "|", t.title);
  });
  process.exit(0);
})();
