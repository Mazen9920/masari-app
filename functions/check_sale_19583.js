const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});
const db = admin.firestore();

(async () => {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

  // Try both string and number
  let sales = await db.collection("sales")
    .where("user_id", "==", uid)
    .where("shopify_order_number", "==", "19583")
    .get();
  if (sales.empty) {
    sales = await db.collection("sales")
      .where("user_id", "==", uid)
      .where("shopify_order_number", "==", 19583)
      .get();
  }
  // Also try external_order_id
  if (sales.empty) {
    console.log("Not found by shopify_order_number, trying external_order_id...");
    const all = await db.collection("sales").where("user_id", "==", uid).get();
    const found = all.docs.filter(d => {
      const data = d.data();
      return String(data.shopify_order_number) === "19583" ||
        String(data.external_order_id).includes("19583");
    });
    console.log(`Found ${found.length} by scanning`);
    for (const s of found) {
      const d = s.data();
      console.log(`  ${s.id}: order_num=${d.shopify_order_number} ext_id=${d.external_order_id} ship=${d.shipping_cost}`);
    }
  }

  console.log(`Found ${sales.size} sales`);
  for (const s of sales.docs) {
    const d = s.data();
    console.log(`Sale: ${s.id}`);
    console.log(`  shipping_cost: ${d.shipping_cost}`);
    console.log(`  discount_amount: ${d.discount_amount}`);
    console.log(`  shopify_order_number: ${d.shopify_order_number}`);
    console.log(`  external_order_id: ${d.external_order_id}`);

    const txns = await db.collection("transactions").where("sale_id", "==", s.id).get();
    for (const t of txns.docs) {
      const td = t.data();
      console.log(`  txn: ${t.id} cat=${td.category_id} amount=${td.amount}`);
    }
  }

  process.exit(0);
})();
