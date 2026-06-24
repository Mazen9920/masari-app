/**
 * Debug: find the April non-cancelled refunded order and check
 * why refund txns weren't created.
 */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");

if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(
      require(path.resolve(
        "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
      ))
    ),
  });
}
const db = admin.firestore();

const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";

function decrypt(encryptedStr, key) {
  const [ivB64, tagB64, dataB64] = encryptedStr.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data).toString("utf8") + decipher.final("utf8");
}

async function main() {
  // Get Shopify connection
  const connSnap = await db.collection("shopify_connections").doc(UID).get();
  const conn = connSnap.data();
  const shopDomain = conn.shop_domain;
  
  const accessToken = decrypt(conn.access_token, ENCRYPTION_KEY);

  // Fetch April orders with refunds
  const baseUrl = `https://${shopDomain}/admin/api/2024-01`;
  const params = new URLSearchParams({
    status: "any",
    limit: "250",
    created_at_min: "2026-04-01T00:00:00+02:00",
    created_at_max: "2026-04-30T23:59:59+02:00",
  });

  let allOrders = [];
  let url = `${baseUrl}/orders.json?${params.toString()}`;
  
  while (url) {
    const res = await fetch(url, {
      headers: {
        "Content-Type": "application/json",
        "X-Shopify-Access-Token": accessToken,
      },
    });
    const json = await res.json();
    allOrders = allOrders.concat(json.orders || []);
    
    const link = res.headers.get("link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
  }

  console.log(`Total April orders from Shopify: ${allOrders.length}`);

  // Find non-cancelled orders with refunds
  const refundedOrders = allOrders.filter(o => {
    const fs = o.financial_status || "";
    return !o.cancelled_at && 
      (fs === "refunded" || fs === "partially_refunded");
  });

  console.log(`\nNon-cancelled orders with refund status: ${refundedOrders.length}`);
  
  for (const order of refundedOrders) {
    const shopifyId = String(order.id);
    console.log(`\n${"=".repeat(60)}`);
    console.log(`Order #${order.order_number} (Shopify ID: ${shopifyId})`);
    console.log(`  financial_status: ${order.financial_status}`);
    console.log(`  cancelled_at: ${order.cancelled_at}`);
    console.log(`  subtotal_price: ${order.subtotal_price}`);
    console.log(`  total_price: ${order.total_price}`);
    console.log(`  total_discounts: ${order.total_discounts}`);
    console.log(`  created_at: ${order.created_at}`);
    
    // Check refunds array
    const refunds = order.refunds || [];
    console.log(`  refunds count: ${refunds.length}`);
    
    for (const refund of refunds) {
      console.log(`\n  Refund ID: ${refund.id}`);
      console.log(`    created_at: ${refund.created_at}`);
      
      // Check refund_line_items
      const rlis = refund.refund_line_items || [];
      console.log(`    refund_line_items: ${rlis.length}`);
      let productRefund = 0;
      for (const ri of rlis) {
        const subtotal = Number(ri.subtotal) || 0;
        productRefund += subtotal;
        console.log(`      line_item_id=${ri.line_item_id}, qty=${ri.quantity}, subtotal=${subtotal}`);
      }
      
      // Check order_adjustments
      const adjs = refund.order_adjustments || [];
      console.log(`    order_adjustments: ${adjs.length}`);
      let shippingRefund = 0;
      for (const adj of adjs) {
        console.log(`      kind=${adj.kind}, amount=${adj.amount}, tax=${adj.tax_amount}`);
        if (adj.kind === "shipping_refund") {
          shippingRefund += Math.abs(Number(adj.amount) || 0);
        }
      }
      
      console.log(`    PRODUCT REFUND TOTAL: ${productRefund}`);
      console.log(`    SHIPPING REFUND TOTAL: ${shippingRefund}`);
      
      // Check if refund txn exists in Firestore
      // First find the Revvo sale
      const salesSnap = await db.collection("sales")
        .where("user_id", "==", UID)
        .where("external_order_id", "==", shopifyId)
        .limit(1)
        .get();
      
      if (salesSnap.empty) {
        console.log(`    ⚠️ NO SALE FOUND in Revvo for this order!`);
        continue;
      }
      
      const saleDoc = salesSnap.docs[0];
      const saleData = saleDoc.data();
      const saleId = saleDoc.id;
      console.log(`\n    Revvo sale ID: ${saleId}`);
      console.log(`    Revvo order_status: ${saleData.order_status}`);
      console.log(`    Revvo payment_status: ${saleData.payment_status}`);
      
      const refundTxnId = `sale_refund_${saleId}_${refund.id}`;
      const txnSnap = await db.collection("transactions").doc(refundTxnId).get();
      console.log(`    Refund txn (${refundTxnId}): ${txnSnap.exists ? "EXISTS ✅" : "MISSING ❌"}`);
      
      const shipRefundId = `sale_ship_refund_${saleId}_${refund.id}`;
      const shipTxnSnap = await db.collection("transactions").doc(shipRefundId).get();
      console.log(`    Ship refund txn (${shipRefundId}): ${shipTxnSnap.exists ? "EXISTS ✅" : "MISSING ❌"}`);
      
      // Check if there are reversal txns (from cancellation)
      const revRevId = `sale_rev_${saleId}_reversal`;
      const revRevSnap = await db.collection("transactions").doc(revRevId).get();
      console.log(`    Revenue reversal (${revRevId}): ${revRevSnap.exists ? "EXISTS" : "none"}`);
    }
  }

  // Also check ALL orders with non-empty refunds[] (even if financial_status is "paid")
  const ordersWithRefunds = allOrders.filter(o => {
    return !o.cancelled_at && o.refunds && o.refunds.length > 0;
  });
  
  console.log(`\n\n${"=".repeat(60)}`);
  console.log(`ALL non-cancelled orders with refunds[] array: ${ordersWithRefunds.length}`);
  
  for (const order of ordersWithRefunds) {
    const fs = order.financial_status;
    if (fs !== "refunded" && fs !== "partially_refunded") {
      console.log(`  Order #${order.order_number}: financial_status=${fs}, refunds=${order.refunds.length}`);
      for (const r of order.refunds) {
        let total = 0;
        for (const ri of (r.refund_line_items || [])) {
          total += Number(ri.subtotal) || 0;
        }
        console.log(`    Refund ${r.id}: product_amount=${total}`);
      }
    }
  }
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
