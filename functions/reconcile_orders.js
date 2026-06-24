/**
 * Per-order reconciliation: computes each order's Shopify net vs Revvo net
 * to pinpoint exactly which orders cause the remaining gap.
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

async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get()).data();
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  const shop = conn.shop_domain;

  // Fetch ALL Shopify orders
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
  console.log(`Fetched ${allOrders.length} Shopify orders`);

  // Load ALL Revvo transactions
  const [revSnap, shipSnap] = await Promise.all([
    db.collection("transactions")
      .where("user_id", "==", UID)
      .where("category_id", "==", "cat_sales_revenue")
      .get(),
    db.collection("transactions")
      .where("user_id", "==", UID)
      .where("category_id", "==", "cat_shipping")
      .get(),
  ]);

  // Build sale_id → txn amounts map
  const revBySale = {};  // saleId → total revenue (positive + negatives)
  const shipBySale = {};
  for (const doc of revSnap.docs) {
    const t = doc.data();
    const sid = t.sale_id || "unknown";
    revBySale[sid] = (revBySale[sid] || 0) + (Number(t.amount) || 0);
  }
  for (const doc of shipSnap.docs) {
    const t = doc.data();
    const sid = t.sale_id || "unknown";
    shipBySale[sid] = (shipBySale[sid] || 0) + (Number(t.amount) || 0);
  }

  // Load all sales to map external_order_id → sale_id
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", UID)
    .get();
  const orderToSale = {};
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    if (s.external_order_id) {
      orderToSale[s.external_order_id] = {
        saleId: doc.id,
        orderStatus: s.order_status,
        paymentStatus: s.payment_status,
      };
    }
  }

  // Per-order comparison
  const getMonth = d => {
    const dt = new Date(d);
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}`;
  };

  const mismatches = { "2026-03": [], "2026-04": [] };

  for (const order of allOrders) {
    const month = getMonth(order.created_at);
    if (month !== "2026-03" && month !== "2026-04") continue;

    const shopifyId = String(order.id);

    // Shopify net for this order
    let grossSales = 0;
    for (const li of (order.line_items || [])) {
      grossSales += (Number(li.price) || 0) * (Number(li.quantity) || 0);
    }
    const discounts = Number(order.total_discounts) || 0;
    let returns = 0;
    let shipRefunds = 0;
    for (const refund of (order.refunds || [])) {
      for (const ri of (refund.refund_line_items || [])) {
        returns += Number(ri.subtotal) || 0;
      }
      for (const adj of (refund.order_adjustments || [])) {
        if (adj.kind === "shipping_refund") {
          shipRefunds += Math.abs(Number(adj.amount) || 0);
        }
      }
    }
    let shipping = 0;
    for (const sl of (order.shipping_lines || [])) {
      shipping += Number(sl.discounted_price ?? sl.price) || 0;
    }

    const shopifyNetRev = r2(Number(order.subtotal_price || 0) - returns);
    const shopifyNetShip = r2(shipping - shipRefunds);

    // Revvo net for this order
    const sale = orderToSale[shopifyId];
    let revvoNetRev = 0;
    let revvoNetShip = 0;
    if (sale) {
      revvoNetRev = r2(revBySale[sale.saleId] || 0);
      revvoNetShip = r2(shipBySale[sale.saleId] || 0);
    }

    const revGap = r2(revvoNetRev - shopifyNetRev);
    const shipGap = r2(revvoNetShip - shopifyNetShip);

    if ((Math.abs(revGap) > 0.01 || Math.abs(shipGap) > 0.01) && sale) {
      if (mismatches[month]) {
        mismatches[month].push({
          orderNum: order.order_number,
          shopifyId,
          cancelled: !!order.cancelled_at,
          financialStatus: order.financial_status,
          refundsCount: (order.refunds || []).length,
          shopifyNetRev,
          revvoNetRev,
          revGap,
          shopifyNetShip,
          revvoNetShip,
          shipGap,
          saleId: sale?.saleId || "NOT_FOUND",
          orderStatus: sale?.orderStatus,
        });
      }
    }
  }

  for (const [month, items] of Object.entries(mismatches)) {
    console.log(`\n${"=".repeat(60)}`);
    console.log(`${month}: ${items.length} mismatched orders`);
    let totalRevGap = 0, totalShipGap = 0;
    for (const item of items) {
      totalRevGap += item.revGap;
      totalShipGap += item.shipGap;
      console.log(`  #${item.orderNum} (${item.shopifyId}) ` +
        `cancelled=${item.cancelled} fs=${item.financialStatus} ` +
        `refunds=${item.refundsCount} ` +
        `status=${item.orderStatus}`);
      console.log(`    Rev: Shopify=${item.shopifyNetRev} Revvo=${item.revvoNetRev} gap=${item.revGap}`);
      if (Math.abs(item.shipGap) > 0.01) {
        console.log(`    Ship: Shopify=${item.shopifyNetShip} Revvo=${item.revvoNetShip} gap=${item.shipGap}`);
      }
    }
    console.log(`  TOTAL: revGap=${r2(totalRevGap)}, shipGap=${r2(totalShipGap)}`);
  }
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
