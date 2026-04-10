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

  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  
  const salesMap = {};
  salesSnap.docs.forEach(d => { salesMap[d.id] = d.data(); });

  // Group active positive revenue txns by order number
  const byOrder = {};
  txnsSnap.docs.forEach(doc => {
    const d = doc.data();
    if (d.category_id !== "cat_sales_revenue") return;
    const amt = Number(d.amount);
    if (amt <= 0) return;
    if (d.title && d.title.includes("[Cancelled]")) return;
    
    let dt;
    if (d.date_time && d.date_time._seconds) {
      dt = new Date(d.date_time._seconds * 1000);
    } else if (d.date_time && typeof d.date_time === "string") {
      dt = new Date(d.date_time);
    } else { return; }
    if (dt < monthStart || dt >= monthEnd) return;

    const sale = d.sale_id ? salesMap[d.sale_id] : null;
    const orderNum = sale ? String(sale.shopify_order_number || sale.order_number || "???") : "???";
    if (!byOrder[orderNum]) byOrder[orderNum] = [];
    byOrder[orderNum].push({ id: doc.id, amt, date: dt.toISOString().substring(0,10), title: d.title, saleId: d.sale_id });
  });

  console.log("=== Orders with multiple active positive revenue txns ===");
  let dupTotal = 0;
  for (const [num, txns] of Object.entries(byOrder)) {
    if (txns.length > 1) {
      console.log(`\n#${num}: ${txns.length} txns`);
      txns.forEach(t => {
        console.log(`  amt=${t.amt} date=${t.date} title="${t.title}" id=${t.id}`);
      });
      const extra = txns.slice(1).reduce((s, t) => s + t.amt, 0);
      dupTotal += extra;
    }
  }
  console.log(`\nTotal duplicate revenue: ${round2(dupTotal)}`);
  console.log(`Expected: should equal 102,846.30 - 102,106.30 = 740`);

  process.exit(0);
}

main().catch(console.error);
