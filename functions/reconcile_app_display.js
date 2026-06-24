/**
 * Replicates the APP's exact on-screen revenue computations and compares
 * them to Shopify's "Total sales" for a month. This is what the USER sees,
 * which is computed differently from raw transaction sums.
 *
 *  A) P&L "Revenue"      = Σ signed (cat_sales_revenue + cat_shipping) txns
 *                          (skip excludeFromPL / plExcludedCats)
 *  B) "Sales" metric     = Σ (sale.netRevenue + sale.shippingCost) over sales
 *                          by sale.date  −  Σ negative non-reversal
 *                          (cat_sales_revenue + cat_shipping) refund txns
 *
 *  sale.netRevenue = round2(Σ round2(qty*unit_price)) − discount_amount
 *
 * Usage: node reconcile_app_display.js 2026-06
 */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(
      "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
    ))
  ),
});
const db = admin.firestore();

const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const TARGET = process.argv[2] || "2026-06";

const PL_EXCLUDED = new Set([
  "cat_investments", "cat_loan_received", "cat_loan_repayment",
  "cat_equity_injection", "cat_owner_withdrawal", "cat_salary_payment",
  "cat_asset_sale",
]);

function decrypt(enc, key) {
  const [ivB64, tagB64, dataB64] = enc.split(":");
  const kb = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const d = crypto.createDecipheriv("aes-256-gcm", kb, iv);
  d.setAuthTag(tag);
  return d.update(data).toString("utf8") + d.final("utf8");
}
const r2 = (n) => Math.round(n * 100) / 100;
const fmt = (n) => r2(n).toLocaleString("en", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
function cairoMonth(d) {
  const p = new Intl.DateTimeFormat("en-CA", { timeZone: "Africa/Cairo", year: "numeric", month: "2-digit" }).formatToParts(new Date(d));
  return `${p.find((x) => x.type === "year").value}-${p.find((x) => x.type === "month").value}`;
}

async function main() {
  // ── Shopify Total sales (same logic as reconcile_month.js) ──
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  const shop = conn.shop_domain;
  let orders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2025-01-01T00:00:00Z`;
  while (url) {
    const res = await fetch(url, { headers: { "X-Shopify-Access-Token": token, "Content-Type": "application/json" } });
    const json = await res.json();
    orders = orders.concat(json.orders || []);
    const link = res.headers.get("link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise((r) => setTimeout(r, 200));
  }
  let gross = 0, disc = 0, returns = 0, ship = 0, shipRef = 0;
  for (const o of orders) {
    if (cairoMonth(o.created_at) === TARGET) {
      for (const li of o.line_items || []) gross += (Number(li.price) || 0) * (Number(li.quantity) || 0);
      let sd = 0;
      for (const sl of o.shipping_lines || []) {
        const g = Number(sl.price) || 0, n = Number(sl.discounted_price ?? sl.price) || 0;
        ship += n; sd += g - n;
      }
      disc += (Number(o.total_discounts) || 0) - sd;
    }
    for (const rf of o.refunds || []) {
      if (cairoMonth(rf.created_at || o.created_at) !== TARGET) continue;
      for (const ri of rf.refund_line_items || []) returns += Number(ri.subtotal) || 0;
      for (const adj of rf.order_adjustments || []) if (adj.kind === "shipping_refund") shipRef += Math.abs(Number(adj.amount) || 0);
    }
  }
  const shopNet = r2(gross - disc - returns);
  const shopShip = r2(ship - shipRef);
  const shopTotal = r2(shopNet + shopShip);

  // ── App data ──
  const [salesSnap, txnSnap] = await Promise.all([
    db.collection("sales").where("user_id", "==", UID).get(),
    db.collection("transactions").where("user_id", "==", UID).get(),
  ]);

  // B) Sales metric
  let bSales = 0;
  let bGrossPart = 0;
  // Breakdown (product-only): Gross=Σsubtotal, Disc=Σdiscount
  let bdGross = 0, bdDisc = 0;
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    const dt = s.date?.toDate?.();
    if (!dt || cairoMonth(dt.toISOString()) !== TARGET) continue;
    let subtotal = 0;
    for (const it of s.items || []) subtotal += r2((Number(it.quantity) || 0) * (Number(it.unit_price) || 0));
    subtotal = r2(subtotal);
    const netRevenue = r2(subtotal - (Number(s.discount_amount) || 0));
    bGrossPart += netRevenue + (Number(s.shipping_cost) || 0);
    bdGross += subtotal;
    bdDisc += Number(s.discount_amount) || 0;
  }
  // A) P&L revenue
  let aRevenue = 0;
  let bRefundPart = 0;
  let bRefundPlusReversal = 0;
  // Breakdown Returns (product-only, cat_sales_revenue negatives)
  let bdReturnsNoRev = 0, bdReturnsWithRev = 0;
  for (const doc of txnSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate?.();
    if (!dt || cairoMonth(dt.toISOString()) !== TARGET) continue;
    if (t.exclude_from_pl || PL_EXCLUDED.has(t.category_id)) continue;
    const amt = Number(t.amount) || 0;
    if (t.category_id === "cat_sales_revenue" || t.category_id === "cat_shipping") {
      aRevenue += amt;
      if (amt < 0 && !String(doc.id).endsWith("_reversal")) bRefundPart += amt;
      if (amt < 0) bRefundPlusReversal += amt;
    }
    if (t.category_id === "cat_sales_revenue" && amt < 0) {
      bdReturnsWithRev += Math.abs(amt);
      if (!String(doc.id).endsWith("_reversal")) bdReturnsNoRev += Math.abs(amt);
    }
  }
  bSales = r2(bGrossPart + bRefundPart);
  const bFixed = r2(bGrossPart + bRefundPlusReversal);
  aRevenue = r2(aRevenue);
  const bdNetNoRev = r2(bdGross - bdDisc - bdReturnsNoRev);
  const bdNetWithRev = r2(bdGross - bdDisc - bdReturnsWithRev);

  console.log(`\n════ ${TARGET} — what the APP shows vs Shopify ════\n`);
  console.log(`Shopify Total sales (Net + Shipping): ${fmt(shopTotal)}`);
  console.log(`  (Net ${fmt(shopNet)} + Shipping ${fmt(shopShip)})\n`);
  console.log(`APP "Sales" metric NOW (B):  ${fmt(bSales)}   GAP ${fmt(bSales - shopTotal)}`);
  console.log(`   gross part (sales): ${fmt(bGrossPart)}  refund part (txns): ${fmt(bRefundPart)}`);
  console.log(`APP "Sales" FIXED (incl reversals): ${fmt(bFixed)}   GAP ${fmt(bFixed - shopTotal)}`);
  console.log(`APP "Sales" TXN-BASED (= P&L A): ${fmt(aRevenue)}   GAP ${fmt(aRevenue - shopTotal)}`);
  console.log(`APP P&L "Revenue" (A):   ${fmt(aRevenue)}   GAP ${fmt(aRevenue - shopTotal)}\n`);
  console.log(`── Breakdown view (product-only Net, vs Shopify Net ${fmt(shopNet)}) ──`);
  console.log(`  Gross(Σsubtotal) ${fmt(bdGross)}  Disc ${fmt(bdDisc)}`);
  console.log(`  Returns NOW (excl reversals): ${fmt(bdReturnsNoRev)} → Net ${fmt(bdNetNoRev)}  GAP ${fmt(bdNetNoRev - shopNet)}`);
  console.log(`  Returns FIXED (incl reversals): ${fmt(bdReturnsWithRev)} → Net ${fmt(bdNetWithRev)}  GAP ${fmt(bdNetWithRev - shopNet)}`);
}

main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
