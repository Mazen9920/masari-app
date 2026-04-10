const admin = require("firebase-admin");
const path = require("path");

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(
      "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
    ))
  ),
});
const db = admin.firestore();
const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

async function main() {
  // Find refunded sales
  const snap = await db.collection("sales").where("user_id", "==", uid).get();
  const refunded = [];
  
  snap.docs.forEach((d) => {
    const data = d.data();
    const fs = data.shopify_financial_status || data.financial_status;
    if (fs === "refunded" || fs === "partially_refunded") {
      refunded.push({
        id: d.id,
        orderNum: data.shopify_order_number || data.order_number,
        shopifyOrderId: data.shopify_order_id,
        financialStatus: fs,
        status: data.status,
        totalAmount: data.total_amount,
        amountPaid: data.amount_paid,
        shippingCost: data.shipping_cost,
        refundsField: data.refunds ? JSON.stringify(data.refunds).substring(0, 200) : "none",
        shopifyRefundIds: data.shopify_refund_ids || "none",
      });
    }
  });
  
  console.log("Refunded sales:", refunded.length);
  refunded.forEach((r) => console.log(JSON.stringify(r)));
  
  // Check if ANY refund transactions exist
  const refundTxns = await db.collection("transactions")
    .where("user_id", "==", uid)
    .where("category_id", "==", "cat_sales_revenue")
    .get();
  
  const negRevenue = refundTxns.docs.filter(d => d.data().amount < 0);
  console.log("\nNegative revenue transactions:", negRevenue.length);
  negRevenue.forEach(d => {
    const data = d.data();
    console.log(JSON.stringify({
      id: d.id,
      title: data.title,
      amount: data.amount,
      saleId: data.sale_id,
      shopifyRefundId: data.shopify_refund_id || "none",
      note: data.note,
    }));
  });
  
  process.exit(0);
}

main().catch(console.error);
