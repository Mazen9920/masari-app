const admin = require("firebase-admin");
const sa = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

(async () => {
  // Find sale for order #19583
  const saleSnap = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("shopify_order_number", "==", "19583")
    .get();

  if (saleSnap.empty) {
    console.log("Order #19583 not found");
    process.exit(1);
  }

  const saleDoc = saleSnap.docs[0];
  const sale = saleDoc.data();
  console.log("=== Order #19583 ===");
  console.log("Sale ID:", saleDoc.id);
  console.log("discount_amount:", sale.discount_amount);
  console.log("shipping_cost:", sale.shipping_cost);
  console.log("items:", JSON.stringify(sale.items?.map(i => ({name: i.name, qty: i.quantity, price: i.price, lineTotal: i.line_total || i.lineTotal})), null, 2));
  const ua = sale.updated_at;
  if (ua && ua.toDate) console.log("updated_at:", ua.toDate().toISOString());

  // Get ALL transactions for this sale
  const txnSnap = await db.collection("transactions")
    .where("user_id", "==", uid)
    .where("sale_id", "==", saleDoc.id)
    .get();

  console.log("\nTransactions for this sale:", txnSnap.size);
  txnSnap.docs.forEach(d => {
    const t = d.data();
    const tDate = t.date?.toDate ? t.date.toDate().toISOString().slice(0,10) : t.date;
    const tUpdated = t.updated_at?.toDate ? t.updated_at.toDate().toISOString() : "no updated_at";
    console.log(`  [${d.id}] cat=${t.category} type=${t.type} amount=${t.amount} date=${tDate} updated=${tUpdated} desc=${t.description}`);
  });

  // Now check a March order that had wrong shipping - #19201
  const marchSnap = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("shopify_order_number", "==", "19201")
    .get();

  if (!marchSnap.empty) {
    const marchDoc = marchSnap.docs[0];
    const marchSale = marchDoc.data();
    console.log("\n=== Order #19201 ===");
    console.log("Sale ID:", marchDoc.id);
    console.log("discount_amount:", marchSale.discount_amount);
    console.log("shipping_cost:", marchSale.shipping_cost);

    const mTxnSnap = await db.collection("transactions")
      .where("user_id", "==", uid)
      .where("sale_id", "==", marchDoc.id)
      .get();

    console.log("Transactions:", mTxnSnap.size);
    mTxnSnap.docs.forEach(d => {
      const t = d.data();
      console.log(`  cat=${t.category} type=${t.type} amount=${t.amount} desc=${t.description}`);
    });
  }

  // Check overall: how many transactions have been updated today?
  const allTxns = await db.collection("transactions")
    .where("user_id", "==", uid)
    .get();

  const today = new Date("2026-04-13T00:00:00Z");
  let txnUpdatedToday = 0;
  let totalTxns = allTxns.size;
  
  allTxns.docs.forEach(d => {
    const t = d.data();
    if (t.updated_at?.toDate && t.updated_at.toDate() > today) {
      txnUpdatedToday++;
    }
  });

  console.log("\n=== Transaction Summary ===");
  console.log("Total transactions:", totalTxns);
  console.log("Updated today:", txnUpdatedToday);

  process.exit(0);
})();
