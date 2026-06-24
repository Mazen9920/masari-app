const admin = require("firebase-admin");
const sa = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(sa) });
const db = admin.firestore();

const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

(async () => {
  // Get any 3 sales for this user to see field names
  const sample = await db.collection("sales")
    .where("user_id", "==", uid)
    .limit(3)
    .get();

  console.log("Sample sales count:", sample.size);
  sample.docs.forEach(d => {
    const s = d.data();
    console.log("\nSale ID:", d.id);
    console.log("  Keys:", Object.keys(s).sort().join(", "));
    console.log("  shopify_order_number:", s.shopify_order_number, typeof s.shopify_order_number);
    console.log("  external_order_id:", s.external_order_id);
    console.log("  external_source:", s.external_source);
    console.log("  order_number:", s.order_number);
    console.log("  discount_amount:", s.discount_amount);
    console.log("  shipping_cost:", s.shipping_cost);
    console.log("  net_revenue:", s.net_revenue);
    console.log("  subtotal:", s.subtotal);
    console.log("  total:", s.total);
  });

  // Try finding #19583 by external_order_id
  const byExtId = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("external_order_id", "==", "19583")
    .get();
  console.log("\n\nBy external_order_id='19583':", byExtId.size);

  // Try as number
  const byExtIdNum = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("shopify_order_number", "==", "19583")
    .get();
  console.log("By shopify_order_number='19583' (string):", byExtIdNum.size);

  // Check total count
  const allSales = await db.collection("sales")
    .where("user_id", "==", uid)
    .get();
  console.log("\nTotal sales for user:", allSales.size);

  // Check if any were updated recently (simple - just check last few by created_at desc)
  // Look for any sale with shopify in it
  let shopifyCount = 0;
  let recentCount = 0;
  const now = new Date();
  const today = new Date("2026-04-13T00:00:00Z");
  
  allSales.docs.forEach(d => {
    const s = d.data();
    if (s.external_source === "shopify") shopifyCount++;
    const updatedAt = s.updated_at;
    if (updatedAt && updatedAt.toDate && updatedAt.toDate() > today) {
      recentCount++;
    }
  });
  console.log("Shopify sales:", shopifyCount);
  console.log("Updated today:", recentCount);

  process.exit(0);
})();
