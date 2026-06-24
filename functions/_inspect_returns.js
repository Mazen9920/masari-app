/** Inspect specific June return-mismatch orders: Revvo txns + sale + Shopify order/refund state. */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const TARGETS = ["21206", "21179", "21156", "21694", "21587", "19450"];
function decrypt(enc, key) {
  const [iv, tag, data] = enc.split(":");
  const d = crypto.createDecipheriv("aes-256-gcm", Buffer.from(key, "hex"), Buffer.from(iv, "base64"));
  d.setAuthTag(Buffer.from(tag, "base64"));
  return d.update(Buffer.from(data, "base64")).toString("utf8") + d.final("utf8");
}
const cairo = s => new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Cairo", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(s));
async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, KEY);
  const shop = conn.shop_domain;

  // Fetch bounded order set
  let orders = [], url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2026-03-01T00:00:00Z`;
  while (url) {
    const res = await fetch(url, { headers: { "X-Shopify-Access-Token": token } });
    const j = await res.json();
    orders = orders.concat(j.orders || []);
    const link = res.headers.get("link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise(r => setTimeout(r, 150));
  }
  const byNum = {};
  orders.forEach(o => { byNum[String(o.order_number)] = o; });

  // Map external_order_id (shopify order id) -> sale
  const salesSnap = await db.collection("sales").where("user_id", "==", UID).get();
  const byExt = {};
  salesSnap.docs.forEach(d => {
    const s = d.data();
    if (s.external_order_id) byExt[String(s.external_order_id)] = { id: d.id, data: s };
  });

  for (const num of TARGETS) {
    console.log(`\n════════ #${num} ════════`);
    const o = byNum[num];
    let sale = o ? byExt[String(o.id)] : null;
    if (sale) {
      const s = sale.data;
      console.log(`SALE ${sale.id}: status=${s.status} fulfillment=${s.fulfillment_status} financial=${s.financial_status} ext=${s.external_order_id} subtotal=${s.subtotal} total=${s.total} discount=${s.discount_amount}`);
      const txq = await db.collection("transactions").where("user_id", "==", UID).where("sale_id", "==", sale.id).get();
      txq.docs.forEach(td => {
        const t = td.data();
        console.log(`  TXN ${td.id}: cat=${t.category_id} amount=${t.amount} date=${cairo(t.date_time?.toDate?.()?.toISOString())} note="${(t.note||'').slice(0,60)}" excl=${t.exclude_from_pl} src=${t.source||''}`);
      });
    } else {
      console.log("  NO Revvo sale found" + (o ? ` (order id ${o.id})` : " (no Shopify order in set)"));
    }
    if (o) {
      console.log(`SHOPIFY #${o.order_number}: created=${cairo(o.created_at)} cancelled=${o.cancelled_at ? cairo(o.cancelled_at) : 'no'} financial=${o.financial_status} fulfillment=${o.fulfillment_status} total=${o.total_price}`);
      (o.refunds || []).forEach(rf => {
        const sub = (rf.refund_line_items || []).reduce((s, ri) => s + Number(ri.subtotal), 0);
        console.log(`  REFUND ${rf.id}: created=${cairo(rf.created_at)} lineSubtotal=${sub} note="${(rf.note||'').slice(0,40)}"`);
      });
      if (!o.refunds?.length) console.log("  (no Shopify refunds)");
    } else console.log("  NO Shopify order in fetched set");
  }
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
