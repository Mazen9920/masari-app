// Cross-reference Shopify refunds to Revvo refund txns to find sync gaps.
const admin = require("firebase-admin");
const path = require("path");
const https = require("https");
const crypto = require("crypto");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
function decrypt(s, k) {
  const [iv, tag, data] = s.split(":");
  const d = crypto.createDecipheriv("aes-256-gcm", Buffer.from(k, "hex"), Buffer.from(iv, "base64"));
  d.setAuthTag(Buffer.from(tag, "base64"));
  return d.update(Buffer.from(data, "base64")).toString("utf8") + d.final("utf8");
}
function r2(n) { return Math.round(n * 100) / 100; }
function get(shop, token, p) {
  return new Promise((res, rej) => {
    https.get({ hostname: shop, path: `/admin/api/2024-10${p}`, headers: { "X-Shopify-Access-Token": token } }, r => {
      let b = ""; r.on("data", c => b += c); r.on("end", () => { try { res(JSON.parse(b)); } catch { res({ err: b }); } });
    }).on("error", rej);
  });
}
async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

(async () => {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const ms = new Date(2026, 3, 1), me = new Date(2026, 4, 1);

  const conn = (await db.collection("shopify_connections").where("user_id","==",uid).limit(1).get()).docs[0].data();
  const token = decrypt(conn.access_token, KEY);

  const all = [];
  let since_id = 0;
  while (true) {
    const d = await get(conn.shop_domain, token, `/orders.json?status=any&limit=250&since_id=${since_id}`);
    if (!d.orders || d.orders.length === 0) break;
    all.push(...d.orders);
    since_id = d.orders[d.orders.length - 1].id;
    if (d.orders.length < 250) break;
    await sleep(400);
  }

  // Collect Shopify refunds dated in April
  const shopifyRefunds = []; // {orderNum, cancelled, refundId, refundDate, refundLineSubtotal, shippingRefund}
  all.forEach(o => {
    (o.refunds || []).forEach(ref => {
      const rd = new Date(ref.created_at);
      if (rd < ms || rd >= me) return;
      const subtotal = (ref.refund_line_items || []).reduce((s, rli) => s + (+rli.subtotal||0), 0);
      const shipRefund = (ref.order_adjustments || []).filter(a => a.kind === 'shipping_refund').reduce((s, a) => s + Math.abs(+a.amount||0), 0);
      const orderAdjOther = (ref.order_adjustments || []).filter(a => a.kind !== 'shipping_refund').reduce((s, a) => s + Math.abs(+a.amount||0), 0);
      shopifyRefunds.push({
        orderNum: o.order_number,
        cancelled: !!o.cancelled_at,
        cancelledAt: o.cancelled_at,
        createdAt: o.created_at,
        shopifyOrderId: o.id,
        refundId: ref.id,
        refundDate: ref.created_at,
        subtotal: r2(subtotal),
        shipRefund: r2(shipRefund),
        orderAdjOther: r2(orderAdjOther),
      });
    });
  });
  console.log(`Shopify refunds in April: ${shopifyRefunds.length} events`);
  const sTotal = shopifyRefunds.reduce((s, r) => s + r.subtotal, 0);
  console.log(`Total refund_line_items subtotal: ${r2(sTotal)}`);

  // Collect Revvo negative cat_sales_revenue txns in April
  const txnsSnap = await db.collection("transactions").where("user_id","==",uid).get();
  const revvoNegRev = [];
  txnsSnap.docs.forEach(d => {
    const t = d.data();
    if (t.exclude_from_pl) return;
    if (t.category_id !== "cat_sales_revenue") return;
    const amt = +t.amount || 0;
    if (amt >= 0) return;
    const dt = t.date_time?.toDate ? t.date_time.toDate() : new Date((t.date_time?._seconds||0)*1000);
    if (dt < ms || dt >= me) return;
    revvoNegRev.push({ id: d.id, saleId: t.sale_id, amount: amt, date: dt.toISOString() });
  });
  console.log(`\nRevvo negative cat_sales_revenue txns in April: ${revvoNegRev.length}`);
  console.log(`Total amount: ${r2(revvoNegRev.reduce((s, t) => s + t.amount, 0))}`);

  // Map sales by shopify_order_number
  const salesSnap = await db.collection("sales").where("user_id","==",uid).get();
  const salesByOrderNum = {};
  const salesById = {};
  salesSnap.docs.forEach(d => {
    salesById[d.id] = d.data();
    const n = d.data().shopify_order_number;
    if (n !== undefined) salesByOrderNum[String(n)] = { id: d.id, data: d.data() };
  });

  // For each Shopify refund, find matching Revvo txn
  console.log(`\n=== Shopify Refund → Revvo Txn Mapping ===`);
  const unmatched = [];
  shopifyRefunds.forEach(sr => {
    const sale = salesByOrderNum[String(sr.orderNum)];
    if (!sale) {
      unmatched.push({ ...sr, reason: "no sale" });
      return;
    }
    // Find Revvo refund txn: sale_refund_{saleId}_{refundId}
    const expectedId = `sale_refund_${sale.id}_${sr.refundId}`;
    const match = revvoNegRev.find(t => t.id === expectedId);
    if (!match) {
      // Also try finding by saleId alone (cancellation reversal)
      const cancelMatch = revvoNegRev.find(t => t.saleId === sale.id);
      if (!cancelMatch) {
        unmatched.push({ ...sr, reason: "no matching revvo txn", saleId: sale.id });
      }
    }
  });
  console.log(`Unmatched Shopify refunds: ${unmatched.length}`);
  unmatched.slice(0, 15).forEach(u => {
    console.log(`  #${u.orderNum} (cancelled=${u.cancelled}) refund=${u.refundId} date=${u.refundDate.substring(0,10)} amount=${u.subtotal} reason=${u.reason}`);
  });
  const unmatchedTotal = unmatched.reduce((s, u) => s + u.subtotal, 0);
  console.log(`Unmatched refund subtotal: ${r2(unmatchedTotal)}`);

  // Now try matching Revvo negative txns back to Shopify refunds
  console.log(`\n=== Revvo Negative Txn → Shopify Refund Match ===`);
  const revvoUnmatched = [];
  revvoNegRev.forEach(t => {
    const sale = salesById[t.saleId];
    if (!sale) { revvoUnmatched.push({...t, reason: "no sale"}); return; }
    const num = String(sale.shopify_order_number);
    const matchingRefunds = shopifyRefunds.filter(r => String(r.orderNum) === num);
    if (matchingRefunds.length === 0) {
      revvoUnmatched.push({ ...t, orderNum: num, reason: "no matching shopify refund in month", orderStatus: sale.order_status, cancelledAt: "?" });
    }
  });
  console.log(`Revvo negative txns with NO Shopify refund in April: ${revvoUnmatched.length}`);
  revvoUnmatched.slice(0, 15).forEach(u => {
    console.log(`  sale=${u.saleId} order=#${u.orderNum} status=${u.orderStatus} amount=${u.amount} date=${u.date.substring(0,10)}`);
  });
  const revvoUnmatchedTotal = revvoUnmatched.reduce((s, u) => s + u.amount, 0);
  console.log(`Total amount: ${r2(revvoUnmatchedTotal)}`);

  // Also check: cancelled orders in April - do their refund events exist?
  console.log(`\n=== Cancelled Orders (cancelled_at in April): Refund Events ===`);
  let cancInApril = 0;
  let cancWithRefundInApril = 0;
  let cancRevenue = 0;
  all.forEach(o => {
    if (!o.cancelled_at) return;
    const cd = new Date(o.cancelled_at);
    if (cd < ms || cd >= me) return;
    cancInApril++;
    const hasRefundInApril = (o.refunds || []).some(r => {
      const rd = new Date(r.created_at);
      return rd >= ms && rd < me;
    });
    if (hasRefundInApril) cancWithRefundInApril++;
    const gross = (o.line_items || []).reduce((s, li) => s + (+li.quantity||0)*(+li.price||0), 0);
    const disc = +o.total_discounts || 0;
    cancRevenue += (gross - disc);
  });
  console.log(`  Cancelled in April: ${cancInApril}, with refund in April: ${cancWithRefundInApril}`);
  console.log(`  Total revenue (gross - disc): ${r2(cancRevenue)}`);

  process.exit(0);
})();
