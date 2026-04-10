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

function round2(n) { return Math.round(n * 100) / 100; }

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const monthStart = new Date(2026, 3, 1); // April
  const monthEnd = new Date(2026, 4, 1);

  // Get ALL transactions for user (filter in code to avoid composite index)
  const txnSnap = await db.collection("transactions")
    .where("user_id", "==", uid)
    .get();

  const negTxns = [];
  const posTxns = [];
  let totalNeg = 0, totalPos = 0;

  txnSnap.forEach(doc => {
    const d = doc.data();
    if (d.category_id !== "cat_sales_revenue") return;
    
    let dt;
    if (d.date_time && d.date_time._seconds) {
      dt = new Date(d.date_time._seconds * 1000);
    } else if (d.date_time && typeof d.date_time === "string") {
      dt = new Date(d.date_time);
    } else {
      return;
    }
    if (dt < monthStart || dt >= monthEnd) return;
    
    const amt = Number(d.amount);
    const date = dt.toISOString().substring(0, 10);
    const entry = { id: doc.id, title: d.title, amount: amt, date, saleId: d.sale_id };
    if (amt < 0) {
      negTxns.push(entry);
      totalNeg += amt;
    } else {
      posTxns.push(entry);
      totalPos += amt;
    }
  });

  console.log(`=== April Revenue Transactions ===`);
  console.log(`Positive: ${posTxns.length} txns, total = ${round2(totalPos)}`);
  console.log(`Negative: ${negTxns.length} txns, total = ${round2(totalNeg)}`);
  console.log(`Net: ${round2(totalPos + totalNeg)}`);

  console.log(`\n--- Negative (reversal) transactions in April ---`);
  // For each negative txn, find the corresponding sale to get the order number
  for (const t of negTxns) {
    let orderNum = "???";
    if (t.saleId) {
      const saleDoc = await db.collection("sales").doc(t.saleId).get();
      if (saleDoc.exists) {
        const sd = saleDoc.data();
        orderNum = sd.shopify_order_number || sd.order_number || "???";
      }
    }
    console.log(`  #${orderNum}: amt=${t.amount} date=${t.date} title="${t.title}" id=${t.id}`);
  }

  // Now check: which positive txns are for cancelled orders?
  console.log(`\n--- Positive txns for cancelled orders in April ---`);
  let cancelledPosTot = 0;
  for (const t of posTxns) {
    if (t.title && t.title.includes("[Cancelled]")) {
      let orderNum = "???";
      if (t.saleId) {
        const saleDoc = await db.collection("sales").doc(t.saleId).get();
        if (saleDoc.exists) {
          const sd = saleDoc.data();
          orderNum = sd.shopify_order_number || sd.order_number || "???";
        }
      }
      console.log(`  #${orderNum}: amt=${t.amount} date=${t.date} title="${t.title}" id=${t.id}`);
      cancelledPosTot += t.amount;
    }
  }
  console.log(`  Total cancelled positive in April: ${round2(cancelledPosTot)}`);

  console.log("\n=== Summary ===");
  console.log(`Active positive revenue (exc cancelled): ${round2(totalPos - cancelledPosTot)}`);
  console.log(`Cancelled positive + reversals net: ${round2(cancelledPosTot + totalNeg)}`);
  console.log(`This cancelled net should be from cross-month cancellations: ${round2(cancelledPosTot + totalNeg)}`);

  process.exit(0);
}

main().catch(console.error);
