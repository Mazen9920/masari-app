/**
 * Per-order, month-aware NET reconciliation.
 *
 * For each Shopify order, compute its contribution to the target month's
 * "Net sales" on BOTH sides and report the per-order difference:
 *
 *   Shopify month-net contribution =
 *       (gross - product discounts)        if created_at month == TARGET
 *     - sum(refund_line_items.subtotal)    for each refund whose created_at month == TARGET
 *
 *   Revvo month-net contribution =
 *       sum(cat_sales_revenue txns for that sale_id whose date_time month == TARGET)
 *
 * Usage: node reconcile_net_perorder.js 2026-05
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
const TARGET_MONTH = process.argv[2] || "2026-05";

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

const r2 = n => Math.round(n * 100) / 100;

function cairoMonth(dateStr) {
  const dt = new Date(dateStr);
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo",
    year: "numeric",
    month: "2-digit",
  }).formatToParts(dt);
  const y = parts.find(p => p.type === "year").value;
  const m = parts.find(p => p.type === "month").value;
  return `${y}-${m}`;
}

async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  const shop = conn.shop_domain;

  let allOrders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2025-01-01T00:00:00Z`;
  while (url) {
    const res = await fetch(url, {
      headers: { "X-Shopify-Access-Token": token, "Content-Type": "application/json" },
    });
    const json = await res.json();
    allOrders = allOrders.concat(json.orders || []);
    const link = res.headers.get("link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise(r => setTimeout(r, 200));
  }
  console.error(`Fetched ${allOrders.length} Shopify orders\n`);

  // Build Revvo per-sale month-net map.
  const txnSnap = await db.collection("transactions").where("user_id", "==", UID).get();
  const revvoBySale = new Map(); // sale_id -> net cat_sales_revenue in month
  for (const doc of txnSnap.docs) {
    const t = doc.data();
    if (t.category_id !== "cat_sales_revenue") continue;
    const dt = t.date_time?.toDate?.();
    if (!dt) continue;
    if (cairoMonth(dt.toISOString()) !== TARGET_MONTH) continue;
    const sid = t.sale_id;
    if (!sid) continue;
    revvoBySale.set(sid, r2((revvoBySale.get(sid) || 0) + (Number(t.amount) || 0)));
  }

  const rows = [];
  let shopTotal = 0, revvoTotal = 0;
  const seenSales = new Set();

  for (const order of allOrders) {
    const saleId = `shopify_${UID}_${order.id}`;
    seenSales.add(saleId);
    let shopNet = 0;

    if (cairoMonth(order.created_at) === TARGET_MONTH) {
      let gross = 0;
      for (const li of (order.line_items || [])) {
        gross += (Number(li.price) || 0) * (Number(li.quantity) || 0);
      }
      let shipDisc = 0;
      for (const sl of (order.shipping_lines || [])) {
        const g = Number(sl.price) || 0;
        const net = Number(sl.discounted_price ?? sl.price) || 0;
        shipDisc += g - net;
      }
      const prodDisc = (Number(order.total_discounts) || 0) - shipDisc;
      shopNet += gross - prodDisc;
    }

    for (const refund of (order.refunds || [])) {
      if (cairoMonth(refund.created_at || refund.processed_at || order.created_at) !== TARGET_MONTH) continue;
      for (const ri of (refund.refund_line_items || [])) {
        shopNet -= Number(ri.subtotal) || 0;
      }
    }

    shopNet = r2(shopNet);
    const revvoNet = revvoBySale.get(saleId) || 0;
    shopTotal += shopNet;
    revvoTotal += revvoNet;

    const diff = r2(revvoNet - shopNet);
    if (Math.abs(diff) > 0.01) {
      rows.push({
        num: order.name,
        cancelled: !!order.cancelled_at,
        fs: order.financial_status,
        created: cairoMonth(order.created_at),
        cancMonth: order.cancelled_at ? cairoMonth(order.cancelled_at) : "-",
        shopNet,
        revvoNet,
        diff,
      });
    }
  }

  // Revvo sales that have no matching Shopify order in the fetched set.
  let orphanTotal = 0;
  for (const [sid, amt] of revvoBySale.entries()) {
    if (!seenSales.has(sid)) {
      orphanTotal += amt;
      rows.push({
        num: sid.replace(`shopify_${UID}_`, "ORPHAN#"),
        cancelled: false, fs: "-", created: "?", cancMonth: "-",
        shopNet: 0, revvoNet: amt, diff: amt,
      });
    }
  }

  rows.sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));

  console.log(`Per-order NET diffs for ${TARGET_MONTH} (revvo - shopify):\n`);
  for (const r of rows.slice(0, 60)) {
    console.log(
      `${String(r.num).padEnd(12)} canc=${String(r.cancelled).padEnd(5)} fs=${String(r.fs).padEnd(8)} ` +
      `cr=${r.created} cancM=${r.cancMonth} shop=${String(r.shopNet).padStart(10)} ` +
      `revvo=${String(r.revvoNet).padStart(10)} diff=${String(r.diff).padStart(10)}`
    );
  }
  console.log(`\nTotal rows with diff: ${rows.length}`);
  console.log(`Sum of diffs: ${r2(rows.reduce((s, r) => s + r.diff, 0))}`);
  console.log(`Orphan (Revvo sale, no Shopify order) total: ${r2(orphanTotal)}`);
  console.log(`Shopify month-net total: ${r2(shopTotal)}`);
  console.log(`Revvo month-net total:   ${r2(revvoTotal)}`);
  console.log(`Overall GAP:             ${r2(revvoTotal - shopTotal)}`);
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
