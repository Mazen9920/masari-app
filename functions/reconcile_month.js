/**
 * Month-level reconciliation that mirrors Shopify's "Total sales breakdown"
 * report (Gross, Discounts, Returns, Net sales, Shipping, Total sales)
 * and compares it against Revvo's transaction totals for the same period.
 *
 * Usage: node reconcile_month.js 2026-06
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
const TARGET_MONTH = process.argv[2] || "2026-06";

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
const fmt = n => r2(n).toLocaleString("en", { minimumFractionDigits: 2, maximumFractionDigits: 2 });

// Shopify reports are based on the shop's local timezone (Africa/Cairo, +02/+03).
// We classify an order/refund by the month of its created/processed date in Cairo time.
function cairoMonth(dateStr) {
  const dt = new Date(dateStr);
  // Cairo is UTC+2 (no DST currently observed in data range; +3 in summer 2026).
  // Use Intl to be safe.
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

  console.log(`Reconciling ${TARGET_MONTH} for shop ${shop}\n`);

  // Fetch ALL Shopify orders
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
  console.log(`Fetched ${allOrders.length} Shopify orders total\n`);

  // ── Shopify "Total sales breakdown" aggregation ──
  // Gross sales = sum(line_item.price * qty) for orders CREATED in month
  // Discounts = sum(total_discounts) for orders created in month
  // Returns = sum(refund_line_item.subtotal) for refunds PROCESSED in month
  // Net sales = Gross - Discounts - Returns
  // Shipping = sum(shipping_lines.discounted_price) created in month - shipping refunds processed in month
  // Total sales = Net sales + Shipping + Return fees + Taxes
  let grossSales = 0;
  let discounts = 0;
  let returns = 0;
  let shipping = 0;
  let shipRefunds = 0;
  let taxes = 0;
  let orderCount = 0;

  for (const order of allOrders) {
    const om = cairoMonth(order.created_at);
    if (om === TARGET_MONTH) {
      orderCount++;
      for (const li of (order.line_items || [])) {
        grossSales += (Number(li.price) || 0) * (Number(li.quantity) || 0);
      }
      // Shopify's "Discounts" line is PRODUCT discounts only. Shipping
      // discounts are netted out of the Shipping section (shipping_lines
      // already report discounted_price), so subtract them here to avoid
      // double-counting the shipping discount.
      let shipDisc = 0;
      for (const sl of (order.shipping_lines || [])) {
        const gross = Number(sl.price) || 0;
        const net = Number(sl.discounted_price ?? sl.price) || 0;
        shipping += net;
        shipDisc += gross - net;
      }
      discounts += (Number(order.total_discounts) || 0) - shipDisc;
      taxes += Number(order.total_tax) || 0;
    }

    // Refunds are attributed to the month they were processed/created.
    for (const refund of (order.refunds || [])) {
      const rm = cairoMonth(refund.created_at || refund.processed_at || order.created_at);
      if (rm !== TARGET_MONTH) continue;
      for (const ri of (refund.refund_line_items || [])) {
        returns += Number(ri.subtotal) || 0;
      }
      for (const adj of (refund.order_adjustments || [])) {
        if (adj.kind === "shipping_refund") {
          shipRefunds += Math.abs(Number(adj.amount) || 0);
        }
      }
    }
  }

  const netSales = grossSales - discounts - returns;
  const netShipping = shipping - shipRefunds;
  const totalSales = netSales + netShipping + taxes;

  console.log("═══ SHOPIFY (Total sales breakdown) ═══");
  console.log(`  Orders created:    ${orderCount}`);
  console.log(`  Gross sales:       ${fmt(grossSales)}`);
  console.log(`  Discounts:        -${fmt(discounts)}`);
  console.log(`  Returns:          -${fmt(returns)}`);
  console.log(`  Net sales:         ${fmt(netSales)}`);
  console.log(`  Shipping charges:  ${fmt(netShipping)}  (gross ${fmt(shipping)} - refunds ${fmt(shipRefunds)})`);
  console.log(`  Taxes:             ${fmt(taxes)}`);
  console.log(`  Total sales:       ${fmt(totalSales)}`);

  // ── Revvo aggregation from transactions ──
  // The app computes revenue from cat_sales_revenue + cat_shipping transactions
  // filtered by date_time within the month.
  const monthStart = new Date(`${TARGET_MONTH}-01T00:00:00+02:00`);
  const [y, mo] = TARGET_MONTH.split("-").map(Number);
  const monthEnd = new Date(y, mo, 0, 23, 59, 59); // last day of month local
  const monthEndUtc = new Date(`${TARGET_MONTH}-${String(monthEnd.getDate()).padStart(2,"0")}T23:59:59+02:00`);

  const allTxnSnap = await db.collection("transactions")
    .where("user_id", "==", UID)
    .get();

  let revvoSalesRev = 0;
  let revvoShipping = 0;
  let revvoCogs = 0;
  let salesRevTxns = 0, salesRevNegative = 0;
  let shipTxns = 0;

  for (const doc of allTxnSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate?.();
    if (!dt) continue;
    const tm = cairoMonth(dt.toISOString());
    if (tm !== TARGET_MONTH) continue;

    const amt = Number(t.amount) || 0;
    if (t.category_id === "cat_sales_revenue") {
      revvoSalesRev += amt;
      salesRevTxns++;
      if (amt < 0) salesRevNegative += amt;
    } else if (t.category_id === "cat_shipping") {
      revvoShipping += amt;
      shipTxns++;
    } else if (t.category_id === "cat_cogs") {
      revvoCogs += amt;
    }
  }

  console.log("\n═══ REVVO (transactions in month) ═══");
  console.log(`  Sales revenue txns: ${salesRevTxns} (incl ${fmt(salesRevNegative)} negative/refunds)`);
  console.log(`  Sales revenue:      ${fmt(revvoSalesRev)}`);
  console.log(`  Shipping revenue:   ${fmt(revvoShipping)}  (${shipTxns} txns)`);
  console.log(`  Sales + Shipping:   ${fmt(revvoSalesRev + revvoShipping)}`);
  console.log(`  COGS:               ${fmt(revvoCogs)}`);

  console.log("\n═══ COMPARISON ═══");
  console.log(`  Shopify Net sales:    ${fmt(netSales)}`);
  console.log(`  Revvo Sales revenue:  ${fmt(revvoSalesRev)}`);
  console.log(`  Sales GAP:            ${fmt(revvoSalesRev - netSales)}`);
  console.log("");
  console.log(`  Shopify Shipping:     ${fmt(netShipping)}`);
  console.log(`  Revvo Shipping:       ${fmt(revvoShipping)}`);
  console.log(`  Shipping GAP:         ${fmt(revvoShipping - netShipping)}`);
  console.log("");
  console.log(`  Shopify Total sales:  ${fmt(totalSales)}`);
  console.log(`  Revvo Total:          ${fmt(revvoSalesRev + revvoShipping)}`);
  console.log(`  TOTAL GAP:            ${fmt((revvoSalesRev + revvoShipping) - totalSales)}`);
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
