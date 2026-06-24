const admin = require("firebase-admin");
const sa = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

(async () => {
  // Get order #19583 with correct field name (string)
  const saleSnap = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("shopify_order_number", "==", "19583")
    .get();

  const saleDoc = saleSnap.docs[0];
  const sale = saleDoc.data();
  console.log("=== Order #19583 ===");
  console.log("discount_amount:", sale.discount_amount, "shipping_cost:", sale.shipping_cost);

  // Get transactions with CORRECT field names
  const txnSnap = await db.collection("transactions")
    .where("user_id", "==", uid)
    .where("sale_id", "==", saleDoc.id)
    .get();

  console.log("Transactions:");
  txnSnap.docs.forEach(d => {
    const t = d.data();
    console.log(`  [${d.id}] category_id=${t.category_id} amount=${t.amount} title=${t.title} date=${t.date_time?.toDate?.().toISOString().slice(0,10)}`);
  });

  // Now do a quick P&L check for April: sum all revenue and shipping txns
  const aprStart = new Date("2026-04-01T00:00:00+02:00");
  const aprEnd = new Date("2026-04-30T23:59:59+02:00");

  const allTxns = await db.collection("transactions")
    .where("user_id", "==", uid)
    .where("date_time", ">=", admin.firestore.Timestamp.fromDate(aprStart))
    .where("date_time", "<=", admin.firestore.Timestamp.fromDate(aprEnd))
    .get();

  let salesRevenue = 0;
  let shippingRevenue = 0;
  let cogsTotal = 0;
  let shippingCogs = 0;
  let otherIncome = 0;
  let otherExpense = 0;
  const categoryCounts = {};

  allTxns.docs.forEach(d => {
    const t = d.data();
    const cat = t.category_id || "unknown";
    categoryCounts[cat] = (categoryCounts[cat] || 0) + 1;

    if (cat === "cat_sales_revenue") salesRevenue += t.amount;
    else if (cat === "cat_shipping_revenue") shippingRevenue += t.amount;
    else if (cat === "cat_cogs") cogsTotal += t.amount;
    else if (cat === "cat_shipping_cogs" || cat === "cat_bosta_fees") shippingCogs += t.amount;
    else if (t.amount > 0) otherIncome += t.amount;
    else otherExpense += t.amount;
  });

  console.log("\n=== April 2026 P&L from Firestore ===");
  console.log("Total transactions:", allTxns.size);
  console.log("Category breakdown:", JSON.stringify(categoryCounts, null, 2));
  console.log("\nSales Revenue:", salesRevenue.toFixed(2));
  console.log("Shipping Revenue:", shippingRevenue.toFixed(2));
  console.log("COGS:", cogsTotal.toFixed(2));
  console.log("Shipping COGS:", shippingCogs.toFixed(2));
  console.log("Other Income:", otherIncome.toFixed(2));
  console.log("Other Expense:", otherExpense.toFixed(2));

  // Same for March
  const marStart = new Date("2026-03-01T00:00:00+02:00");
  const marEnd = new Date("2026-03-31T23:59:59+02:00");

  const marTxns = await db.collection("transactions")
    .where("user_id", "==", uid)
    .where("date_time", ">=", admin.firestore.Timestamp.fromDate(marStart))
    .where("date_time", "<=", admin.firestore.Timestamp.fromDate(marEnd))
    .get();

  let marSalesRevenue = 0;
  let marShippingRevenue = 0;
  const marCategoryCounts = {};

  marTxns.docs.forEach(d => {
    const t = d.data();
    const cat = t.category_id || "unknown";
    marCategoryCounts[cat] = (marCategoryCounts[cat] || 0) + 1;
    if (cat === "cat_sales_revenue") marSalesRevenue += t.amount;
    else if (cat === "cat_shipping_revenue") marShippingRevenue += t.amount;
  });

  console.log("\n=== March 2026 P&L from Firestore ===");
  console.log("Total transactions:", marTxns.size);
  console.log("Category breakdown:", JSON.stringify(marCategoryCounts, null, 2));
  console.log("Sales Revenue:", marSalesRevenue.toFixed(2));
  console.log("Shipping Revenue:", marShippingRevenue.toFixed(2));

  process.exit(0);
})();
