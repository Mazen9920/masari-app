/**
 * Fast June reconciliation: compares Revvo vs Shopify for Gross / Discounts /
 * Returns, per order, to locate the exact source of the breakdown gap.
 * Uses Cairo timezone (matches Shopify Admin) and bounds the order fetch.
 */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))
  ),
});
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const MONTH = process.argv[2] || "2026-06";
const CREATED_MIN = "2026-03-01T00:00:00Z";

function decrypt(enc, key) {
  const [ivB64, tagB64, dataB64] = enc.split(":");
  const kb = Buffer.from(key, "hex");
  const d = crypto.createDecipheriv("aes-256-gcm", kb, Buffer.from(ivB64, "base64"));
  d.setAuthTag(Buffer.from(tagB64, "base64"));
  return d.update(Buffer.from(dataB64, "base64")).toString("utf8") + d.final("utf8");
}
const r2 = n => Math.round(n * 100) / 100;
function cairoMonth(dateStr) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo", year: "numeric", month: "2-digit",
  }).formatToParts(new Date(dateStr));
  return `${parts.find(p => p.type === "year").value}-${parts.find(p => p.type === "month").value}`;
}

async function fetchWithTimeout(url, opts, ms = 20000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try { return await fetch(url, { ...opts, signal: ctrl.signal }); }
  finally { clearTimeout(t); }
}

async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  const shop = conn.shop_domain;

  let orders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=${encodeURIComponent(CREATED_MIN)}`;
  let page = 0;
  while (url) {
    const res = await fetchWithTimeout(url, {
      headers: { "X-Shopify-Access-Token": token, "Content-Type": "application/json" },
    });
    const json = await res.json();
    orders = orders.concat(json.orders || []);
    page++;
    process.stderr.write(`page ${page} (${orders.length})\n`);
    const link = res.headers.get("link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise(r => setTimeout(r, 150));
  }
  process.stderr.write(`Fetched ${orders.length} orders\n`);

  // Revvo data
  const salesSnap = await db.collection("sales").where("user_id", "==", UID).get();
  const orderToSale = {};
  const saleById = {};
  salesSnap.docs.forEach(doc => {
    const s = doc.data();
    saleById[doc.id] = s;
    if (s.external_order_id) orderToSale[String(s.external_order_id)] = { id: doc.id, data: s };
  });
  const txnSnap = await db.collection("transactions").where("user_id", "==", UID).get();
  const negRevBySale = {}; // saleId -> sum |neg cat_sales_revenue| in MONTH (cairo)
  txnSnap.docs.forEach(doc => {
    const t = doc.data();
    if (t.category_id !== "cat_sales_revenue") return;
    const a = Number(t.amount) || 0;
    if (a >= 0) return;
    const dt = t.date_time?.toDate?.();
    if (!dt || cairoMonth(dt.toISOString()) !== MONTH) return;
    const sid = t.sale_id || "unknown";
    negRevBySale[sid] = (negRevBySale[sid] || 0) + Math.abs(a);
  });

  // ── Shopify totals (Cairo) ──
  let sGross = 0, sDisc = 0, sReturns = 0;
  const discProblems = [], retProblems = [];
  const shopRetBySale = {}; // saleId -> shopify returns in MONTH
  const orderBySale = {};   // saleId -> order

  for (const o of orders) {
    const om = cairoMonth(o.created_at);
    const sale = orderToSale[String(o.id)];
    if (sale) orderBySale[sale.id] = o;
    // Gross + discounts attributed to order's created month
    if (om === MONTH) {
      let g = 0;
      for (const li of (o.line_items || [])) {
        g += (Number(li.price) || 0) * (Number(li.quantity) || 0);
      }
      // Shopify total_discounts INCLUDES free-shipping (shipping_line) discounts.
      // Revvo stores PRODUCT-only discounts, matching Shopify's displayed
      // "Discounts" line — so subtract shipping_line discount allocations.
      let shipDisc = 0;
      for (const sl of (o.shipping_lines || [])) {
        for (const a of (sl.discount_allocations || [])) shipDisc += Number(a.amount) || 0;
      }
      const d = r2((Number(o.total_discounts) || 0) - shipDisc);
      sGross += g; sDisc += d;

      const revvoDisc = sale ? (Number(sale.data.discount_amount) || 0) : 0;
      if (Math.abs(r2(d - revvoDisc)) > 0.01) {
        discProblems.push({ num: o.order_number, shopify: r2(d), revvo: r2(revvoDisc), gap: r2(revvoDisc - d), saleFound: !!sale });
      }
    }
    // Returns attributed to refund created month
    let shopRet = 0, hasRet = false;
    for (const rf of (o.refunds || [])) {
      if (cairoMonth(rf.created_at || o.created_at) !== MONTH) continue;
      for (const ri of (rf.refund_line_items || [])) shopRet += Number(ri.subtotal) || 0;
      hasRet = true;
    }
    if ((hasRet || shopRet > 0) && sale) shopRetBySale[sale.id] = (shopRetBySale[sale.id] || 0) + shopRet;
    if (hasRet || shopRet > 0) sReturns += shopRet;
  }

  // Union of sale ids that have either a Shopify June return or a Revvo June return
  const allSaleIds = new Set([...Object.keys(shopRetBySale), ...Object.keys(negRevBySale)]);
  let revvoReturnsTotal = 0;
  for (const sid of Object.keys(negRevBySale)) revvoReturnsTotal += negRevBySale[sid];
  for (const sid of allSaleIds) {
    const shopR = r2(shopRetBySale[sid] || 0);
    const revR = r2(negRevBySale[sid] || 0);
    if (Math.abs(r2(revR - shopR)) > 0.01) {
      const o = orderBySale[sid];
      retProblems.push({ num: o ? o.order_number : (saleById[sid]?.external_order_id || sid), shopify: shopR, revvo: revR, gap: r2(revR - shopR), saleFound: !!saleById[sid], cancelled: o ? !!o.cancelled_at : null, noOrder: !o });
    }
  }

  // Revvo refunds that have NO matching Shopify order refund this month (e.g. manual / RMA backfill)
  console.log(`\n═══ ${MONTH} (Cairo) — SHOPIFY ═══`);
  console.log(`Gross=${r2(sGross)}  Discounts=${r2(sDisc)}  Returns=${r2(sReturns)}  Net=${r2(sGross - sDisc - sReturns)}`);
  console.log(`Revvo Returns total (neg cat_sales_revenue, Cairo): ${r2(revvoReturnsTotal)}`);

  console.log(`\n── DISCOUNT mismatches (Revvo − Shopify), ${discProblems.length} orders ──`);
  discProblems.sort((a, b) => Math.abs(b.gap) - Math.abs(a.gap));
  let discGap = 0; discProblems.forEach(p => discGap += p.gap);
  discProblems.slice(0, 25).forEach(p => console.log(`  #${p.num} shopify=${p.shopify} revvo=${p.revvo} gap=${p.gap} saleFound=${p.saleFound}`));
  console.log(`  TOTAL discount gap (Revvo−Shopify): ${r2(discGap)}`);

  console.log(`\n── RETURNS mismatches (Revvo − Shopify), ${retProblems.length} orders ──`);
  retProblems.sort((a, b) => Math.abs(b.gap) - Math.abs(a.gap));
  let retGap = 0; retProblems.forEach(p => retGap += p.gap);
  retProblems.slice(0, 40).forEach(p => console.log(`  #${p.num} shopify=${p.shopify} revvo=${p.revvo} gap=${p.gap} saleFound=${p.saleFound} cancelled=${p.cancelled} noOrder=${p.noOrder}`));
  console.log(`  TOTAL returns gap (Revvo−Shopify): ${r2(retGap)}`);

  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
