const admin = require("firebase-admin");
const sa = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

(async () => {
  // Check order #19583 (had shipping discount 99)
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("shopify_order_number", "==", 19583)
    .get();

  if (salesSnap.empty) {
    console.log("Order #19583 NOT FOUND");
  } else {
    const sale = salesSnap.docs[0].data();
    console.log("Order #19583 sale:");
    console.log("  discount_amount:", sale.discount_amount);
    console.log("  shipping_cost:", sale.shipping_cost);
    console.log("  total:", sale.total);
    console.log("  net_revenue:", sale.net_revenue);
    console.log("  subtotal:", sale.subtotal);
    const updatedAt = sale.updated_at;
    if (updatedAt && updatedAt.toDate) {
      console.log("  updated_at:", updatedAt.toDate().toISOString());
    }
  }

  // Check a shipping-discount order from March
  const marchSnap = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("shopify_order_number", "==", 19201)
    .get();

  if (marchSnap.empty) {
    console.log("\nOrder #19201 NOT FOUND");
  } else {
    const sale = marchSnap.docs[0].data();
    console.log("\nOrder #19201 sale:");
    console.log("  discount_amount:", sale.discount_amount);
    console.log("  shipping_cost:", sale.shipping_cost);
    console.log("  total:", sale.total);
    console.log("  net_revenue:", sale.net_revenue);
    console.log("  subtotal:", sale.subtotal);
    const updatedAt = sale.updated_at;
    if (updatedAt && updatedAt.toDate) {
      console.log("  updated_at:", updatedAt.toDate().toISOString());
    }
  }

  // Check if transactions were updated - get txns for #19583
  if (!salesSnap.empty) {
    const saleId = salesSnap.docs[0].id;
    const txnSnap = await db.collection("transactions")
      .where("user_id", "==", uid)
      .where("sale_id", "==", saleId)
      .get();

    console.log("\nTransactions for #19583 (sale_id=" + saleId + "):");
    txnSnap.docs.forEach(d => {
      const t = d.data();
      console.log("  ", t.category, t.type, t.amount, t.description);
    });
  }

  // Check if backfill function was actually called recently - look at function logs
  // Instead, check how many sales have been updated recently
  const recentlyUpdated = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("updated_at", ">", new Date("2026-04-13T00:00:00Z"))
    .limit(5)
    .get();

  console.log("\nSales updated today:", recentlyUpdated.size);
  recentlyUpdated.docs.forEach(d => {
    const s = d.data();
    console.log("  #" + s.shopify_order_number, "updated:", s.updated_at.toDate().toISOString());
  });

  process.exit(0);
})();
