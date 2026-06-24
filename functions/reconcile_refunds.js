/**
 * Per-order June reconciliation focused on refund handling.
 * Shopify attributes a refund to the month it was PROCESSED (refund.created_at).
 * Revvo stores refund transactions - we check their date_time + amount.
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
function cairoMonth(dateStr) {
  const dt = new Date(dateStr);
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo", year: "numeric", month: "2-digit",
  }).formatToParts(dt);
  return `${parts.find(p => p.type === "year").value}-${parts.find(p => p.type === "month").value}`;
}

async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  const shop = conn.shop_domain;

  let allOrders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250`;
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
  console.log(`Fetched ${allOrders.length} Shopify orders\n`);

  // Map external_order_id -> sale doc
  const salesSnap = await db.collection("sales").where("user_id", "==", UID).get();
  const orderToSale = {};
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    if (s.external_order_id) orderToSale[String(s.external_order_id)] = { id: doc.id, data: s };
  }

  // Build per-sale revenue txns with dates
  const allTxnSnap = await db.collection("transactions").where("user_id", "==", UID).get();
  const revBySale = {};   // saleId -> [{amount, month, date}]
  for (const doc of allTxnSnap.docs) {
    const t = doc.data();
    if (t.category_id !== "cat_sales_revenue") continue;
    const sid = t.sale_id || "unknown";
    const dt = t.date_time?.toDate?.();
    if (!revBySale[sid]) revBySale[sid] = [];
    revBySale[sid].push({
      amount: Number(t.amount) || 0,
      month: dt ? cairoMonth(dt.toISOString()) : "?",
      id: doc.id,
    });
  }

  // For each order that has a refund PROCESSED in TARGET_MONTH, compare
  // Shopify refund amount vs Revvo negative txn in TARGET_MONTH.
  let totalShopifyRefund = 0;
  let totalRevvoRefund = 0;
  const problems = [];

  for (const order of allOrders) {
    let shopifyRefundThisMonth = 0;
    let hasRefundThisMonth = false;
    for (const refund of (order.refunds || [])) {
      const rm = cairoMonth(refund.created_at || refund.processed_at || order.created_at);
      if (rm !== TARGET_MONTH) continue;
      hasRefundThisMonth = true;
      for (const ri of (refund.refund_line_items || [])) {
        shopifyRefundThisMonth += Number(ri.subtotal) || 0;
      }
    }
    if (!hasRefundThisMonth) continue;

    totalShopifyRefund += shopifyRefundThisMonth;

    const sale = orderToSale[String(order.id)];
    let revvoRefundThisMonth = 0;
    let revvoRevTxns = [];
    if (sale) {
      revvoRevTxns = revBySale[sale.id] || [];
      for (const tx of revvoRevTxns) {
        if (tx.month === TARGET_MONTH && tx.amount < 0) {
          revvoRefundThisMonth += Math.abs(tx.amount);
        }
      }
    }
    totalRevvoRefund += revvoRefundThisMonth;

    const gap = r2(shopifyRefundThisMonth - revvoRefundThisMonth);
    if (Math.abs(gap) > 0.01) {
      problems.push({
        orderNum: order.order_number,
        orderId: order.id,
        orderMonth: cairoMonth(order.created_at),
        financialStatus: order.financial_status,
        cancelled: !!order.cancelled_at,
        shopifyRefund: r2(shopifyRefundThisMonth),
        revvoRefund: r2(revvoRefundThisMonth),
        gap,
        saleFound: !!sale,
        orderStatus: sale?.data?.order_status,
        revTxns: revvoRevTxns.map(t => `${t.amount}@${t.month}`).join(", "),
      });
    }
  }

  console.log(`═══ Refund reconciliation for ${TARGET_MONTH} ═══`);
  console.log(`Shopify returns (processed this month): ${r2(totalShopifyRefund)}`);
  console.log(`Revvo returns (negative txns this month): ${r2(totalRevvoRefund)}`);
  console.log(`GAP: ${r2(totalShopifyRefund - totalRevvoRefund)}\n`);

  console.log(`${problems.length} orders with refund mismatch:\n`);
  problems.sort((a, b) => Math.abs(b.gap) - Math.abs(a.gap));
  for (const p of problems.slice(0, 40)) {
    console.log(`#${p.orderNum} (created ${p.orderMonth}) fs=${p.financialStatus} cancelled=${p.cancelled} status=${p.orderStatus} saleFound=${p.saleFound}`);
    console.log(`   Shopify refund=${p.shopifyRefund} Revvo refund=${p.revvoRefund} GAP=${p.gap}`);
    console.log(`   Revvo rev txns: ${p.revTxns || "(none)"}`);
  }
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
