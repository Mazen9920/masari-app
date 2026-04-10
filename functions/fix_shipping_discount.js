const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});
const db = admin.firestore();

// Order #19583 has a 100% shipping discount (99 EGP free shipping).
// Currently: shipping_cost=99, shipping txn=99, revenue=3550 (= subtotal - 99 discount)
// Correct:  shipping_cost=0,  shipping txn deleted, revenue=3649 (= subtotal - 0 product discount)
// The 99 in total_discounts is entirely a shipping discount, not product.

const DRY_RUN = !process.argv.includes("--apply");

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const saleId = "bd2679d2-4e57-4bb2-b8c7-ff950f2f303c";

  // Verify current state
  const saleDoc = await db.collection("sales").doc(saleId).get();
  if (!saleDoc.exists) { console.log("Sale not found!"); process.exit(1); }
  const sale = saleDoc.data();
  console.log("Current sale state:");
  console.log(`  shopify_order_number: ${sale.shopify_order_number}`);
  console.log(`  shipping_cost: ${sale.shipping_cost}`);
  console.log(`  discount_amount: ${sale.discount_amount}`);

  // Get transactions
  const txns = await db.collection("transactions").where("sale_id", "==", saleId).get();
  console.log(`\nCurrent transactions (${txns.size}):`);
  for (const t of txns.docs) {
    const d = t.data();
    console.log(`  ${t.id}: cat=${d.category_id} amount=${d.amount}`);
  }

  // Compute what's correct
  // The discount_amount of 99 is entirely shipping discount (target_type=shipping_line)
  // Product discount = 0
  // Shipping cost (net) = 0  (gross 99 - discount 99)
  const shippingDiscount = 99;  // from Shopify: price=99, discounted_price=0
  const productDiscount = sale.discount_amount - shippingDiscount; // = 0

  // Current revenue = subtotal - total_discounts = subtotal - 99
  // Correct revenue = subtotal - product_discount = subtotal - 0 = subtotal
  const currentRevenue = txns.docs.find(t => t.data().category_id === "cat_sales_revenue")?.data().amount || 0;
  const subtotal = currentRevenue + sale.discount_amount; // reverse the formula
  const correctRevenue = subtotal - productDiscount;

  console.log(`\nFix calculations:`);
  console.log(`  subtotal (from items): ${subtotal}`);
  console.log(`  shipping discount: ${shippingDiscount}`);
  console.log(`  product discount: ${productDiscount}`);
  console.log(`  current revenue: ${currentRevenue} → correct: ${correctRevenue} (diff: +${correctRevenue - currentRevenue})`);
  console.log(`  current shipping: 99 → correct: 0 (delete shipping txn)`);
  console.log(`  Net P&L change: +${correctRevenue - currentRevenue} (revenue) - 99 (shipping) = ${(correctRevenue - currentRevenue) - 99}`);

  if (DRY_RUN) {
    console.log("\n🔸 DRY RUN — pass --apply to execute");
    process.exit(0);
  }

  console.log("\n🔧 Applying fixes...");
  const batch = db.batch();

  // 1. Update sale: shipping_cost=0, discount_amount=0 (product discount only)
  batch.update(saleDoc.ref, {
    shipping_cost: 0,
    discount_amount: productDiscount,
    updated_at: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 2. Update revenue transaction
  const revTxn = txns.docs.find(t => t.data().category_id === "cat_sales_revenue");
  if (revTxn) {
    batch.update(revTxn.ref, {
      amount: correctRevenue,
      updated_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`  Updated ${revTxn.id}: amount ${currentRevenue} → ${correctRevenue}`);
  }

  // 3. Delete shipping transaction (shipping is now 0)
  const shipTxn = txns.docs.find(t => t.data().category_id === "cat_shipping");
  if (shipTxn) {
    batch.delete(shipTxn.ref);
    console.log(`  Deleted ${shipTxn.id}`);
  }

  await batch.commit();
  console.log("✅ Done!");

  process.exit(0);
}
main().catch(console.error);
