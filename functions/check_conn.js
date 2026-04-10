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
  const connSnap = await db.collection("shopify_connections")
    .where("user_id", "==", uid)
    .limit(1)
    .get();
  
  if (connSnap.empty) {
    console.log("No Shopify connection");
    process.exit(1);
  }
  
  const data = connSnap.docs[0].data();
  const keys = Object.keys(data).sort();
  keys.forEach(k => {
    const v = data[k];
    if (k.includes("token") || k.includes("secret") || k.includes("key")) {
      console.log(`  ${k}: [${typeof v}] length=${String(v).length} starts=${String(v).substring(0, 10)}...`);
    } else if (typeof v === "object" && v !== null && v._seconds) {
      console.log(`  ${k}: Timestamp(${new Date(v._seconds * 1000).toISOString()})`);
    } else {
      console.log(`  ${k}: ${JSON.stringify(v)}`);
    }
  });

  // Also check: is there a field like shopify_financial_status on any kind of sale?
  console.log("\n=== Checking financial status fields ===");
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", uid)
    .limit(10)
    .get();
  
  const fstatuses = new Set();
  salesSnap.docs.forEach(d => {
    const sd = d.data();
    if (sd.shopify_financial_status) fstatuses.add("shopify_financial_status: " + sd.shopify_financial_status);
    if (sd.financial_status) fstatuses.add("financial_status: " + sd.financial_status);
    if (sd.payment_status !== undefined) fstatuses.add("payment_status: " + sd.payment_status);
  });
  console.log("Found statuses:", [...fstatuses]);

  // Check ALL sales for any with shopify_financial_status containing refund
  const allSales = await db.collection("sales")
    .where("user_id", "==", uid)
    .get();
  
  let refundedCount = 0;
  const statusMap = {};
  allSales.docs.forEach(d => {
    const sd = d.data();
    const sfs = sd.shopify_financial_status || "NOT_SET";
    statusMap[sfs] = (statusMap[sfs] || 0) + 1;
    if (sfs.includes("refund")) {
      refundedCount++;
      console.log(`  REFUND: ${d.id} sfs=${sfs} order=${sd.shopify_order_number || sd.order_number}`);
    }
  });
  console.log("\nshopify_financial_status distribution:", JSON.stringify(statusMap));
  console.log("Refund-flagged sales:", refundedCount);

  process.exit(0);
}

main().catch(console.error);
