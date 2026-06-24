const admin = require("firebase-admin");
const sa = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

(async () => {
  // Fetch ALL transactions for user (no date filter to avoid index)
  console.log("Fetching all transactions...");
  const allTxns = await db.collection("transactions")
    .where("user_id", "==", uid)
    .get();

  console.log("Total transactions:", allTxns.size);

  // Group by month and category
  const months = {};
  let updatedToday = 0;
  const today = new Date("2026-04-13T00:00:00Z");

  allTxns.docs.forEach(d => {
    const t = d.data();
    const cat = t.category_id || "unknown";
    const dt = t.date_time?.toDate?.();
    if (!dt) return;
    
    const key = `${dt.getFullYear()}-${String(dt.getMonth()+1).padStart(2,"0")}`;
    if (!months[key]) months[key] = {};
    if (!months[key][cat]) months[key][cat] = 0;
    months[key][cat] += t.amount;

    if (t.updated_at?.toDate?.() > today) updatedToday++;
  });

  console.log("Transactions updated today:", updatedToday);

  // Show March and April
  for (const month of ["2026-03", "2026-04"]) {
    const data = months[month] || {};
    console.log(`\n=== ${month} ===`);
    const salesRev = data["cat_sales_revenue"] || 0;
    const shipRev = data["cat_shipping_revenue"] || 0;
    const cogs = data["cat_cogs"] || 0;
    const shipCogs = data["cat_shipping_cogs"] || 0;
    const bostaFees = data["cat_bosta_fees"] || 0;
    console.log("Sales Revenue:", salesRev.toFixed(2));
    console.log("Shipping Revenue:", shipRev.toFixed(2));
    console.log("COGS:", cogs.toFixed(2));
    console.log("Shipping COGS:", shipCogs.toFixed(2));
    console.log("Bosta Fees:", bostaFees.toFixed(2));
    
    // Show all categories
    console.log("All categories:");
    Object.entries(data).sort().forEach(([cat, amt]) => {
      console.log(`  ${cat}: ${amt.toFixed(2)}`);
    });
  }

  // Also show what the reconcile script said Shopify should be
  // For comparison, fetch from Shopify
  const connSnap = await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get();
  if (!connSnap.empty) {
    const conn = connSnap.docs[0].data();
    console.log("\nShopify connection exists:", conn.shop_domain);
  }

  process.exit(0);
})();
