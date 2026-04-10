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

const DRY_RUN = !process.argv.includes("--apply");

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();

  // Group sales by shopify_order_number
  const salesByOrderNum = {};
  salesSnap.docs.forEach(d => {
    const data = d.data();
    const num = String(data.shopify_order_number || data.order_number || "");
    if (!num) return;
    if (!salesByOrderNum[num]) salesByOrderNum[num] = [];
    salesByOrderNum[num].push({ id: d.id, data });
  });

  // Find orders with multiple sale docs
  const duplicates = {};
  for (const [num, sales] of Object.entries(salesByOrderNum)) {
    if (sales.length > 1) {
      // Check if they have different IDs (UUID vs shopify format)
      const uuidSales = sales.filter(s => !s.id.startsWith("shopify_"));
      const shopifySales = sales.filter(s => s.id.startsWith("shopify_"));
      if (uuidSales.length > 0 && shopifySales.length > 0) {
        duplicates[num] = { uuidSales, shopifySales };
      }
    }
  }

  console.log(`Found ${Object.keys(duplicates).length} orders with duplicate sale docs (UUID + webhook)\n`);
  
  if (Object.keys(duplicates).length === 0) {
    console.log("No duplicates found!");
    process.exit(0);
  }

  // Build txn map by sale_id
  const txnsBySaleId = {};
  txnsSnap.docs.forEach(d => {
    const data = d.data();
    const sid = data.sale_id;
    if (!sid) return;
    if (!txnsBySaleId[sid]) txnsBySaleId[sid] = [];
    txnsBySaleId[sid].push({ id: d.id, data });
  });

  let totalDupRevenue = 0;
  let totalDupShipping = 0;
  let totalDupCOGS = 0;
  const toDelete = { sales: [], transactions: [] };

  for (const [num, { uuidSales, shopifySales }] of Object.entries(duplicates)) {
    console.log(`\n#${num}:`);
    
    // Keep the webhook sale (shopify_ prefix), delete the UUID one (import duplicate)
    for (const s of uuidSales) {
      console.log(`  UUID sale: ${s.id} status=${s.data.status}`);
      const txns = txnsBySaleId[s.id] || [];
      let rev = 0, ship = 0, cogs = 0;
      txns.forEach(t => {
        const cat = t.data.category_id;
        const amt = Number(t.data.amount);
        if (cat === "cat_sales_revenue") rev += amt;
        else if (cat === "cat_shipping") ship += amt;
        else if (cat === "cat_cogs") cogs += amt;
      });
      console.log(`    Txns: ${txns.length} (rev=${round2(rev)}, ship=${round2(ship)}, cogs=${round2(cogs)})`);
      totalDupRevenue += rev;
      totalDupShipping += ship;
      totalDupCOGS += cogs;
      
      toDelete.sales.push(s.id);
      txns.forEach(t => toDelete.transactions.push(t.id));
    }
    
    for (const s of shopifySales) {
      console.log(`  Webhook sale: ${s.id} status=${s.data.status} (KEEPING)`);
      const txns = txnsBySaleId[s.id] || [];
      let rev = 0, ship = 0, cogs = 0;
      txns.forEach(t => {
        const cat = t.data.category_id;
        const amt = Number(t.data.amount);
        if (cat === "cat_sales_revenue") rev += amt;
        else if (cat === "cat_shipping") ship += amt;
        else if (cat === "cat_cogs") cogs += amt;
      });
      console.log(`    Txns: ${txns.length} (rev=${round2(rev)}, ship=${round2(ship)}, cogs=${round2(cogs)})`);
    }
  }

  console.log(`\n=== Summary ===`);
  console.log(`Duplicate sales to delete: ${toDelete.sales.length}`);
  console.log(`Duplicate transactions to delete: ${toDelete.transactions.length}`);
  console.log(`Duplicate revenue: ${round2(totalDupRevenue)}`);
  console.log(`Duplicate shipping: ${round2(totalDupShipping)}`);
  console.log(`Duplicate COGS: ${round2(totalDupCOGS)}`);

  if (DRY_RUN) {
    console.log("\n** DRY RUN ** — pass --apply to delete");
  } else {
    console.log("\nApplying deletes...");
    const BATCH_SIZE = 500;
    const allDeletes = [
      ...toDelete.transactions.map(id => ({ collection: "transactions", id })),
      ...toDelete.sales.map(id => ({ collection: "sales", id })),
    ];
    
    for (let i = 0; i < allDeletes.length; i += BATCH_SIZE) {
      const batch = db.batch();
      const chunk = allDeletes.slice(i, i + BATCH_SIZE);
      chunk.forEach(item => {
        batch.delete(db.collection(item.collection).doc(item.id));
      });
      await batch.commit();
      console.log(`  Deleted ${chunk.length} docs (batch ${Math.floor(i/BATCH_SIZE) + 1})`);
    }
    console.log("Done!");
  }

  process.exit(0);
}

main().catch(console.error);
