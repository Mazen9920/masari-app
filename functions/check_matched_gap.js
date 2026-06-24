/**
 * Check if matched orders have shipping discounts.
 */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");

admin.initializeApp({
  credential: admin.credential.cert(require(path.resolve(
    "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
  ))),
});
const db = admin.firestore();

const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const EK = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
function decrypt(e, k) {
  const [i, t, d] = e.split(":");
  const kb = Buffer.from(k, "hex");
  const iv = Buffer.from(i, "base64");
  const tg = Buffer.from(t, "base64");
  const da = Buffer.from(d, "base64");
  const c = crypto.createDecipheriv("aes-256-gcm", kb, iv);
  c.setAuthTag(tg);
  return c.update(da).toString("utf8") + c.final("utf8");
}
const r2 = n => Math.round(n * 100) / 100;

async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, EK);

  // Fetch Shopify
  let all = [];
  let url = `https://${conn.shop_domain}/admin/api/2024-01/orders.json?status=any&limit=250`;
  while (url) {
    const r = await fetch(url, { headers: { "X-Shopify-Access-Token": token } });
    const j = await r.json();
    all = all.concat(j.orders || []);
    const lk = r.headers.get("link") || "";
    const m = lk.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise(r => setTimeout(r, 200));
  }

  // Load sales
  const salesSnap = await db.collection("sales").where("user_id", "==", UID).get();
  const orderToSale = {};
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    if (s.external_order_id) orderToSale[s.external_order_id] = doc.id;
  }

  // Load txns
  const [revSnap, shipSnap] = await Promise.all([
    db.collection("transactions").where("user_id", "==", UID).where("category_id", "==", "cat_sales_revenue").get(),
    db.collection("transactions").where("user_id", "==", UID).where("category_id", "==", "cat_shipping").get(),
  ]);
  const revBySale = {}, shipBySale = {};
  for (const d of revSnap.docs) { const t = d.data(); revBySale[t.sale_id] = (revBySale[t.sale_id]||0) + (Number(t.amount)||0); }
  for (const d of shipSnap.docs) { const t = d.data(); shipBySale[t.sale_id] = (shipBySale[t.sale_id]||0) + (Number(t.amount)||0); }

  const getMonth = d => { const dt = new Date(d); return `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,"0")}`; };

  const stats = {};
  for (const o of all) {
    const mo = getMonth(o.created_at);
    if (mo !== "2026-03" && mo !== "2026-04") continue;
    if (!stats[mo]) stats[mo] = {
      matchedShopifyRev: 0, matchedRevvoRev: 0,
      matchedShipDisc: 0, matchedOrders: 0,
      unmatchedShopifyRev: 0, unmatchedOrders: 0,
      unmatchedShipDisc: 0,
      matchedShopifyShip: 0, matchedRevvoShip: 0,
      unmatchedShopifyShip: 0,
    };
    const s = stats[mo];

    let gross = 0;
    for (const li of (o.line_items || [])) gross += (Number(li.price)||0) * (Number(li.quantity)||0);
    const disc = Number(o.total_discounts) || 0;
    let ret = 0;
    for (const rf of (o.refunds || [])) for (const ri of (rf.refund_line_items || [])) ret += Number(ri.subtotal) || 0;
    let shipDisc = 0;
    let ship = 0;
    for (const sl of (o.shipping_lines || [])) {
      const g = Number(sl.price) || 0;
      const n = Number(sl.discounted_price ?? sl.price) || 0;
      shipDisc += g - n;
      ship += n;
    }
    let shipRef = 0;
    for (const rf of (o.refunds || [])) for (const adj of (rf.order_adjustments || [])) {
      if (adj.kind === "shipping_refund") shipRef += Math.abs(Number(adj.amount) || 0);
    }

    const shopifyNet = r2(gross - disc - ret);
    const shopifyShipNet = r2(ship - shipRef);
    const saleId = orderToSale[String(o.id)];

    if (saleId) {
      s.matchedOrders++;
      s.matchedShopifyRev += shopifyNet;
      s.matchedRevvoRev += r2(revBySale[saleId] || 0);
      s.matchedShipDisc += shipDisc;
      s.matchedShopifyShip += shopifyShipNet;
      s.matchedRevvoShip += r2(shipBySale[saleId] || 0);
    } else {
      s.unmatchedOrders++;
      s.unmatchedShopifyRev += shopifyNet;
      s.unmatchedShipDisc += shipDisc;
      s.unmatchedShopifyShip += shopifyShipNet;
    }
  }

  for (const [mo, s] of Object.entries(stats)) {
    console.log(`\n${mo} (matched: ${s.matchedOrders}, unmatched: ${s.unmatchedOrders}):`);
    console.log(`  REVENUE:`);
    console.log(`    Matched Shopify: ${r2(s.matchedShopifyRev)}`);
    console.log(`    Matched Revvo: ${r2(s.matchedRevvoRev)}`);
    console.log(`    Matched gap: ${r2(s.matchedRevvoRev - s.matchedShopifyRev)}`);
    console.log(`    Matched shipping discounts: ${r2(s.matchedShipDisc)}`);
    console.log(`    Unmatched Shopify: ${r2(s.unmatchedShopifyRev)}`);
    console.log(`    Unmatched ship disc: ${r2(s.unmatchedShipDisc)}`);
    console.log(`  SHIPPING:`);
    console.log(`    Matched Shopify: ${r2(s.matchedShopifyShip)}`);
    console.log(`    Matched Revvo: ${r2(s.matchedRevvoShip)}`);
    console.log(`    Matched gap: ${r2(s.matchedRevvoShip - s.matchedShopifyShip)}`);
    console.log(`    Unmatched Shopify: ${r2(s.unmatchedShopifyShip)}`);
  }
}
main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
