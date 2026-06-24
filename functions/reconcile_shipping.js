/**
 * Per-order SHIPPING reconciliation for a month.
 * Shopify shipping for an order created in month = sum(discounted_price)
 *   minus shipping_refund adjustments processed in month.
 * Revvo shipping = sum of cat_shipping txns (sale_ship, sale_ship_reversal,
 *   sale_ship_refund) dated in month for that sale.
 *
 * Usage: node reconcile_shipping.js 2026-06
 */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(
      "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
    ))),
});
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const MONTH = process.argv[2] || "2026-06";
function decrypt(enc) {
  const [a, b, c] = enc.split(":");
  const d = crypto.createDecipheriv(
    "aes-256-gcm", Buffer.from(KEY, "hex"), Buffer.from(a, "base64"));
  d.setAuthTag(Buffer.from(b, "base64"));
  return d.update(Buffer.from(c, "base64")).toString("utf8") + d.final("utf8");
}
const r2 = (n) => Math.round(n * 100) / 100;
const cm = (s) => {
  const p = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo", year: "numeric", month: "2-digit",
  }).formatToParts(new Date(s));
  return `${p.find((x) => x.type === "year").value}-${
    p.find((x) => x.type === "month").value}`;
};
async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get())
    .data();
  const token = decrypt(conn.access_token);
  const shop = conn.shop_domain;
  let orders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2025-01-01T00:00:00Z`;
  while (url) {
    const res = await fetch(url, {
      headers: { "X-Shopify-Access-Token": token } });
    const j = await res.json();
    orders = orders.concat(j.orders || []);
    const m = (res.headers.get("link") || "").match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise((r) => setTimeout(r, 150));
  }
  // Shopify shipping per order id
  const shopShip = new Map();
  for (const o of orders) {
    let v = 0;
    if (cm(o.created_at) === MONTH) {
      for (const sl of o.shipping_lines || []) {
        v += Number(sl.discounted_price ?? sl.price) || 0;
      }
    }
    for (const rf of o.refunds || []) {
      if (cm(rf.created_at || o.created_at) !== MONTH) continue;
      for (const adj of rf.order_adjustments || []) {
        if (adj.kind === "shipping_refund") v -= Math.abs(Number(adj.amount) || 0);
      }
    }
    if (v !== 0) shopShip.set(String(o.id), r2(v));
  }
  // Revvo shipping per order id
  const tx = await db.collection("transactions")
    .where("user_id", "==", UID).get();
  const revShip = new Map();
  for (const d of tx.docs) {
    const t = d.data();
    if (t.category_id !== "cat_shipping" || !t.sale_id) continue;
    const dt = t.date_time && t.date_time.toDate();
    if (!dt || cm(dt.toISOString()) !== MONTH) continue;
    const oid = String(t.sale_id).split("_").pop();
    revShip.set(oid, r2((revShip.get(oid) || 0) + (Number(t.amount) || 0)));
  }
  const ids = new Set([...shopShip.keys(), ...revShip.keys()]);
  const rows = [];
  for (const id of ids) {
    const s = shopShip.get(id) || 0;
    const r = revShip.get(id) || 0;
    if (Math.abs(s - r) > 0.5) {
      const o = orders.find((x) => String(x.id) === id);
      rows.push({ no: o && o.order_number, cancelled: !!(o && o.cancelled_at),
        fs: o && o.financial_status, shop: s, revvo: r, diff: r2(r - s) });
    }
  }
  rows.sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));
  for (const x of rows) {
    console.log(`#${x.no} cancelled=${x.cancelled} fs=${x.fs} ` +
      `shopShip=${x.shop} revvoShip=${x.revvo} DIFF=${x.diff}`);
  }
  const total = rows.reduce((s, x) => s + x.diff, 0);
  console.log(`\nRows: ${rows.length}  Net shipping diff (Revvo-Shopify): ${r2(total)}`);
  process.exit(0);
}
main().catch((e) => { console.error(e); process.exit(1); });
