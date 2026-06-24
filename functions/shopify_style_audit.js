// Audit matching Shopify Sales Report semantics:
//   Gross sales     = Σ line_item.qty × line_item.price for ALL orders (incl. cancelled)
//   Discounts       = Σ total_discounts (product-only)
//   Returns         = Σ refund_line_items.subtotal + cancelled order subtotals
//                     (reported on refund/cancel date, NOT order date)
//   Net sales       = Gross - Discounts - Returns
//   Orders count    = all orders created in month (incl. cancelled)
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
  const monthArg = process.argv[2] || "2026-04";
  const [yy, mm] = monthArg.split("-").map(Number);
  const monthStart = new Date(yy, mm - 1, 1);
  const monthEnd = new Date(yy, mm, 1);
  console.log(`Period: ${monthStart.toISOString().slice(0,10)} → ${monthEnd.toISOString().slice(0,10)}`);

  const conn = (await db.collection("shopify_connections").where("user_id","==",uid).limit(1).get()).docs[0].data();
  const token = decrypt(conn.access_token, KEY);

  // Fetch all Shopify orders
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
  console.log(`\nShopify orders (all time): ${all.length}`);

  // SHOPIFY: Sales report logic =========================================
  // Orders created in month (incl cancelled)
  const created = all.filter(o => {
    const d = new Date(o.created_at);
    return d >= monthStart && d < monthEnd;
  });
  const createdCancelled = created.filter(o => !!o.cancelled_at);
  console.log(`\n=== Shopify Orders Created in Month: ${created.length} (${createdCancelled.length} cancelled) ===`);

  let sGross = 0, sDisc = 0, sShipDisc = 0, sSubtotal = 0, sShipping = 0, sTax = 0, sTotal = 0;
  created.forEach(o => {
    const gross = (o.line_items || []).reduce((s, li) => s + (+li.quantity || 0) * (+li.price || 0), 0);
    const disc = +o.total_discounts || 0;
    const shipDisc = (o.shipping_lines || []).reduce((s, sl) => s + ((+sl.price||0) - (+sl.discounted_price||+sl.price||0)), 0);
    sGross += gross;
    sDisc += disc;
    sShipDisc += shipDisc;
    sSubtotal += +o.subtotal_price || 0;
    sShipping += (o.shipping_lines || []).reduce((s,l)=>s + (+l.discounted_price||+l.price||0), 0);
    sTax += +o.total_tax || 0;
    sTotal += +o.total_price || 0;
  });
  const sProductDisc = sDisc - sShipDisc;
  console.log(`  Gross line items:  ${r2(sGross)}`);
  console.log(`  subtotal_price:    ${r2(sSubtotal)}`);
  console.log(`  total_discounts:   ${r2(sDisc)}  (product: ${r2(sProductDisc)}, shipping: ${r2(sShipDisc)})`);
  console.log(`  Shipping:          ${r2(sShipping)}`);
  console.log(`  Tax:               ${r2(sTax)}`);
  console.log(`  Total price:       ${r2(sTotal)}`);

  // Returns reported on refund/cancel date within the month
  let sReturnsRefundLines = 0;  // partial refunds
  let sReturnsCancellation = 0; // full cancellations
  let sReturnsOrderAdjust = 0;  // order_adjustments on refunds (e.g. restocking, other)
  all.forEach(o => {
    // Cancellation reversal: if cancelled_at in month, treat the remaining (non-refunded) subtotal as a return
    if (o.cancelled_at) {
      const cDate = new Date(o.cancelled_at);
      if (cDate >= monthStart && cDate < monthEnd) {
        const gross = (o.line_items || []).reduce((s, li) => s + (+li.quantity || 0) * (+li.price || 0), 0);
        const prodDisc = (+o.total_discounts || 0) - (o.shipping_lines || []).reduce((s,sl)=>s + ((+sl.price||0) - (+sl.discounted_price||+sl.price||0)), 0);
        sReturnsCancellation += (gross - prodDisc);
      }
    }
    // Refunds (can occur on active or cancelled orders)
    (o.refunds || []).forEach(ref => {
      const rDate = new Date(ref.created_at);
      if (rDate < monthStart || rDate >= monthEnd) return;
      (ref.refund_line_items || []).forEach(rli => sReturnsRefundLines += +rli.subtotal || 0);
      (ref.order_adjustments || []).forEach(adj => {
        // positive adjustment = restocking fee or similar (offsets refund), negative = additional refund
        if (adj.kind === 'refund_discrepancy' || adj.kind === 'shipping_refund') return; // skip, shipping not in sales returns
      });
    });
  });
  // Shopify's Sales report counts Returns on creation date (for refunds of line items),
  // but for cancellations it reports on cancellation date. Shopify dashboard you showed
  // uses "reporting date" which for refunds is the refund date. Use refund date.
  const sReturns = sReturnsRefundLines + sReturnsCancellation;
  console.log(`  Returns (refund_line_items subtotal): ${r2(sReturnsRefundLines)}`);
  console.log(`  Returns (full cancellations net):     ${r2(sReturnsCancellation)}`);
  console.log(`  Returns TOTAL:                        ${r2(sReturns)}`);

  const shopifyNetSales = r2(sGross - sProductDisc - sReturns);
  console.log(`\n  Shopify NET SALES = ${r2(sGross)} - ${r2(sProductDisc)} - ${r2(sReturns)} = ${shopifyNetSales}`);

  // REVVO ==========================================================
  const salesSnap = await db.collection("sales").where("user_id","==",uid).get();
  const txnsSnap = await db.collection("transactions").where("user_id","==",uid).get();

  // Count ALL Revvo sales created in month (incl cancelled)
  const rSalesCreated = salesSnap.docs.filter(d => {
    const s = d.data();
    const dt = s.date?.toDate ? s.date.toDate() : (s.date?._seconds ? new Date(s.date._seconds*1000) : null);
    return dt && dt >= monthStart && dt < monthEnd;
  });
  const rSalesActive = rSalesCreated.filter(d => (d.data().order_status ?? 0) !== 4);
  const rSalesCancelled = rSalesCreated.filter(d => d.data().order_status === 4);
  console.log(`\n=== Revvo Sales Created in Month: ${rSalesCreated.length} (active: ${rSalesActive.length}, cancelled: ${rSalesCancelled.length}) ===`);

  // Revvo Gross (all) vs Shopify-style (include cancelled)
  let rGrossAll = 0, rDiscAll = 0;
  let rGrossActive = 0, rDiscActive = 0;
  rSalesCreated.forEach(d => {
    const s = d.data();
    const items = s.items || [];
    const sub = items.reduce((a, it) => a + (+it.quantity||0) * (+it.unit_price||0), 0);
    const disc = +s.discount_amount || 0;
    rGrossAll += sub;
    rDiscAll += disc;
    if (s.order_status !== 4) {
      rGrossActive += sub;
      rDiscActive += disc;
    }
  });
  console.log(`  Revvo Gross (all):        ${r2(rGrossAll)}`);
  console.log(`  Revvo Gross (active):     ${r2(rGrossActive)}   ← current analytics shows this`);
  console.log(`  Revvo Discounts (all):    ${r2(rDiscAll)}`);
  console.log(`  Revvo Discounts (active): ${r2(rDiscActive)}`);

  // Revvo Returns: negative cat_sales_revenue txns dated in month
  let rReturnsActiveOrders = 0;   // refund txns on active sales
  let rReturnsCancelReversal = 0; // cancellation reversal txns
  const salesById = {};
  salesSnap.docs.forEach(d => salesById[d.id] = d.data());
  txnsSnap.docs.forEach(d => {
    const t = d.data();
    if (t.exclude_from_pl) return;
    if (t.category_id !== "cat_sales_revenue") return;
    const amt = +t.amount || 0;
    if (amt >= 0) return;
    const dt = t.date_time?.toDate ? t.date_time.toDate() : new Date((t.date_time?._seconds||0)*1000);
    if (dt < monthStart || dt >= monthEnd) return;
    const sale = salesById[t.sale_id];
    if (sale && sale.order_status === 4) rReturnsCancelReversal += -amt;
    else rReturnsActiveOrders += -amt;
  });
  const rReturnsTotal = rReturnsActiveOrders + rReturnsCancelReversal;
  console.log(`\n  Revvo Returns (partial refunds on active):     ${r2(rReturnsActiveOrders)}`);
  console.log(`  Revvo Returns (cancellation reversals):        ${r2(rReturnsCancelReversal)}`);
  console.log(`  Revvo Returns TOTAL:                           ${r2(rReturnsTotal)}`);

  const revvoNetShopifyStyle = r2(rGrossAll - rDiscAll - rReturnsTotal);
  console.log(`\n  Revvo NET (Shopify-style: all orders, incl cancel reversals as returns)`);
  console.log(`    = ${r2(rGrossAll)} - ${r2(rDiscAll)} - ${r2(rReturnsTotal)} = ${revvoNetShopifyStyle}`);

  // Diff
  console.log(`\n=== SHOPIFY vs REVVO DIFFS (Shopify-style computation on both sides) ===`);
  console.log(`  Gross sales:  Shopify ${r2(sGross)} | Revvo ${r2(rGrossAll)} | Δ ${r2(rGrossAll - sGross)}`);
  console.log(`  Discounts:    Shopify ${r2(sProductDisc)} | Revvo ${r2(rDiscAll)} | Δ ${r2(rDiscAll - sProductDisc)}`);
  console.log(`  Returns:      Shopify ${r2(sReturns)} | Revvo ${r2(rReturnsTotal)} | Δ ${r2(rReturnsTotal - sReturns)}`);
  console.log(`  Net sales:    Shopify ${shopifyNetSales} | Revvo ${revvoNetShopifyStyle} | Δ ${r2(revvoNetShopifyStyle - shopifyNetSales)}`);
  console.log(`  Order count:  Shopify ${created.length} | Revvo ${rSalesCreated.length} | Δ ${rSalesCreated.length - created.length}`);

  // Explain current analytics chart gap
  console.log(`\n=== Why current Revvo analytics shows different numbers ===`);
  console.log(`  Current analytics: Gross/Disc use ACTIVE-only, Returns counts only refunds (not cancel reversals)`);
  console.log(`    Gross:    ${r2(rGrossActive)}`);
  console.log(`    Disc:     ${r2(rDiscActive)}`);
  console.log(`    Returns:  ${r2(rReturnsActiveOrders)}  (after Option B fix — cancellation reversals excluded)`);
  console.log(`    Net:      ${r2(rGrossActive - rDiscActive - rReturnsActiveOrders)}`);
  console.log(`  Orders count in analytics: ${rSalesActive.length} (active only) — Shopify shows ${created.length} (all)`);

  process.exit(0);
})();
