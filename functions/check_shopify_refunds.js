const admin = require("firebase-admin");
const path = require("path");
const https = require("https");

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(
      "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
    ))
  ),
});
const db = admin.firestore();
const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

function shopifyGet(shop, token, path) {
  return new Promise((resolve, reject) => {
    const req = https.get({
      hostname: shop,
      path: `/admin/api/2024-10${path}`,
      headers: {
        "X-Shopify-Access-Token": token,
        "Content-Type": "application/json",
      },
    }, (res) => {
      let body = "";
      res.on("data", (c) => body += c);
      res.on("end", () => {
        try { resolve(JSON.parse(body)); }
        catch { resolve(body); }
      });
    });
    req.on("error", reject);
  });
}

async function main() {
  // Get Shopify connection
  const connSnap = await db.collection("shopify_connections")
    .where("user_id", "==", uid)
    .limit(1)
    .get();
  
  if (connSnap.empty) {
    console.log("No Shopify connection found!");
    process.exit(1);
  }
  
  const conn = connSnap.docs[0].data();
  const shop = conn.shop_domain || conn.shop;
  const token = conn.access_token;
  console.log("Shop:", shop);

  // Get a sample sale to see all fields
  const sampleSale = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("status", "==", 3) // active fulfilled
    .limit(1)
    .get();
  
  if (!sampleSale.empty) {
    const data = sampleSale.docs[0].data();
    console.log("\n=== Sample Sale Fields ===");
    const keys = Object.keys(data).sort();
    keys.forEach(k => {
      const v = data[k];
      if (typeof v === "object" && v !== null && !Array.isArray(v) && v._seconds) {
        console.log(`  ${k}: Timestamp(${new Date(v._seconds * 1000).toISOString()})`);
      } else if (Array.isArray(v)) {
        console.log(`  ${k}: Array[${v.length}]`);
      } else {
        console.log(`  ${k}: ${JSON.stringify(v)}`);
      }
    });
  }

  // Query Shopify for orders with refunds
  console.log("\n=== Shopify Orders with Refunds ===");
  const data = await shopifyGet(shop, token, "/orders.json?status=any&financial_status=refunded,partially_refunded&limit=50");
  
  if (data.orders) {
    console.log(`Found ${data.orders.length} refunded orders`);
    for (const order of data.orders) {
      const refunds = order.refunds || [];
      console.log(JSON.stringify({
        orderNumber: order.order_number,
        shopifyId: order.id,
        financialStatus: order.financial_status,
        fulfillmentStatus: order.fulfillment_status,
        totalPrice: order.total_price,
        refundCount: refunds.length,
        refunds: refunds.map(r => ({
          id: r.id,
          createdAt: r.created_at,
          transactionsCount: r.transactions ? r.transactions.length : 0,
          transactionAmounts: (r.transactions || []).map(t => ({ amount: t.amount, kind: t.kind })),
          lineItemsCount: r.refund_line_items ? r.refund_line_items.length : 0,
          lineItemSubtotals: (r.refund_line_items || []).map(li => ({
            qty: li.quantity,
            subtotal: li.subtotal,
            totalTax: li.total_tax,
          })),
          orderAdjustments: r.order_adjustments || [],
        })),
      }));
    }
  } else {
    console.log("Error or no data:", JSON.stringify(data).substring(0, 500));
  }

  process.exit(0);
}

main().catch(console.error);
