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
const TARGETS = ["21079", "21554"]; // order numbers

async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token);
  const shop = conn.shop_domain;

  let allOrders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250`;
  while (url) {
    const res = await fetch(url, { headers: { "X-Shopify-Access-Token": token } });
    const json = await res.json();
    allOrders = allOrders.concat(json.orders || []);
    const link = res.headers.get("link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise(r => setTimeout(r, 150));
  }

  for (const num of TARGETS) {
    const order = allOrders.find(o => String(o.order_number) === num);
    if (!order) { console.log(`#${num} not found`); continue; }
    console.log(`\n${"=".repeat(60)}`);
    console.log(`Order #${order.order_number} (id=${order.id})`);
    console.log(`  created_at:   ${order.created_at}`);
    console.log(`  cancelled_at: ${order.cancelled_at}`);
    console.log(`  financial_status: ${order.financial_status}`);
    console.log(`  subtotal_price: ${order.subtotal_price}`);
    console.log(`  total_price: ${order.total_price}`);
    console.log(`  Line items:`);
    for (const li of order.line_items) {
      console.log(`    ${li.title} qty=${li.quantity} price=${li.price}`);
    }
    console.log(`  Refunds (${order.refunds.length}):`);
    for (const ref of order.refunds) {
      console.log(`    refund id=${ref.id} created_at=${ref.created_at} processed_at=${ref.processed_at}`);
      for (const ri of ref.refund_line_items) {
        console.log(`      line_item refund: subtotal=${ri.subtotal} qty=${ri.quantity}`);
      }
      for (const adj of (ref.order_adjustments || [])) {
        console.log(`      adjustment: kind=${adj.kind} amount=${adj.amount}`);
      }
    }

    // Revvo side
    const saleSnap = await db.collection("sales")
      .where("user_id", "==", UID)
      .where("external_order_id", "==", String(order.id))
      .get();
    if (saleSnap.empty) { console.log("  REVVO: sale not found"); continue; }
    const saleDoc = saleSnap.docs[0];
    const sale = saleDoc.data();
    console.log(`  REVVO sale id=${saleDoc.id} order_status=${sale.order_status} discount=${sale.discount_amount} ship=${sale.shipping_cost}`);
    const txnSnap = await db.collection("transactions")
      .where("user_id", "==", UID)
      .where("sale_id", "==", saleDoc.id)
      .get();
    console.log(`  REVVO transactions (${txnSnap.size}):`);
    for (const d of txnSnap.docs) {
      const t = d.data();
      const dt = t.date_time?.toDate?.()?.toISOString();
      console.log(`    [${d.id}] cat=${t.category_id} amount=${t.amount} date=${dt} title=${t.title}`);
    }
  }
}
main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
