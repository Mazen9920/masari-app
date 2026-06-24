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
  const res = await fetch(`https://${shop}/admin/api/2024-01/orders/7333841862976.json`, {
    headers: { "X-Shopify-Access-Token": token },
  });
  const { order } = await res.json();
  for (const ref of order.refunds) {
    const liTotal = (ref.refund_line_items || []).reduce((s, ri) => s + Number(ri.subtotal || 0), 0);
    const txnTotal = (ref.transactions || []).reduce((s, t) => s + Number(t.amount || 0), 0);
    console.log(`\nRefund ${ref.id} created=${ref.created_at}`);
    console.log(`  refund_line_items: ${(ref.refund_line_items||[]).length} (subtotal sum=${liTotal})`);
    console.log(`  order_adjustments: ${JSON.stringify(ref.order_adjustments)}`);
    console.log(`  transactions: ${(ref.transactions||[]).length} (amount sum=${txnTotal})`);
    for (const t of (ref.transactions||[])) {
      console.log(`     tx kind=${t.kind} status=${t.status} amount=${t.amount} gateway=${t.gateway}`);
    }
  }
}
main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
