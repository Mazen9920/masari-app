/**
 * Find orphan Revvo transactions that don't match any Shopify order.
 * These cause the remaining gap in the CF comparison.
 */
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

const UID = "EGYQnP7ughdUtTbn04UwUET534i1";

async function main() {
  // Load all Shopify sale IDs
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", UID)
    .get();
  const shopifySaleIds = new Set();
  for (const doc of salesSnap.docs) {
    if (doc.data().external_order_id) {
      shopifySaleIds.add(doc.id);
    }
  }
  console.log(`Total Shopify sales in Revvo: ${shopifySaleIds.size}`);

  // Load ALL revenue and shipping txns
  const [revSnap, shipSnap] = await Promise.all([
    db.collection("transactions")
      .where("user_id", "==", UID)
      .where("category_id", "==", "cat_sales_revenue")
      .get(),
    db.collection("transactions")
      .where("user_id", "==", UID)
      .where("category_id", "==", "cat_shipping")
      .get(),
  ]);

  const getMonth = ts => {
    const dt = ts?.toDate?.();
    if (!dt) return "unknown";
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}`;
  };

  // Check each transaction
  const orphansByMonth = {};
  const shopifyByMonth = {};
  const nonShopifyByMonth = {};

  for (const doc of [...revSnap.docs, ...shipSnap.docs]) {
    const t = doc.data();
    const month = getMonth(t.date_time);
    if (month !== "2026-03" && month !== "2026-04") continue;

    const saleId = t.sale_id || "";
    const cat = t.category_id;
    const amount = Number(t.amount) || 0;

    if (!saleId) {
      // No sale_id — definitely not from Shopify order
      if (!nonShopifyByMonth[month]) nonShopifyByMonth[month] = { rev: 0, ship: 0, items: [] };
      if (cat === "cat_sales_revenue") nonShopifyByMonth[month].rev += amount;
      else nonShopifyByMonth[month].ship += amount;
      nonShopifyByMonth[month].items.push({
        id: doc.id, title: t.title, amount, category: cat,
        paymentMethod: t.payment_method,
      });
    } else if (!shopifySaleIds.has(saleId)) {
      // Has sale_id but it's not a Shopify sale
      if (!orphansByMonth[month]) orphansByMonth[month] = { rev: 0, ship: 0, items: [] };
      if (cat === "cat_sales_revenue") orphansByMonth[month].rev += amount;
      else orphansByMonth[month].ship += amount;
      orphansByMonth[month].items.push({
        id: doc.id, title: t.title, amount, saleId, category: cat,
        paymentMethod: t.payment_method,
      });
    } else {
      // Matched Shopify sale
      if (!shopifyByMonth[month]) shopifyByMonth[month] = { rev: 0, ship: 0 };
      if (cat === "cat_sales_revenue") shopifyByMonth[month].rev += amount;
      else shopifyByMonth[month].ship += amount;
    }
  }

  for (const month of ["2026-03", "2026-04"]) {
    console.log(`\n${"=".repeat(60)}`);
    console.log(`${month}:`);
    const s = shopifyByMonth[month] || { rev: 0, ship: 0 };
    console.log(`  Shopify-matched: rev=${s.rev.toFixed(2)}, ship=${s.ship.toFixed(2)}`);

    const o = orphansByMonth[month];
    if (o) {
      console.log(`  Orphan sale_id txns: rev=${o.rev.toFixed(2)}, ship=${o.ship.toFixed(2)}`);
      for (const item of o.items) {
        console.log(`    ${item.id}: ${item.title} = ${item.amount} (${item.category}, pm=${item.paymentMethod}, sale=${item.saleId})`);
      }
    }

    const n = nonShopifyByMonth[month];
    if (n) {
      console.log(`  No-sale-id txns: rev=${n.rev.toFixed(2)}, ship=${n.ship.toFixed(2)}`);
      for (const item of n.items) {
        console.log(`    ${item.id}: ${item.title} = ${item.amount} (${item.category}, pm=${item.paymentMethod})`);
      }
    }
  }

  // Also check: are there manual sales for this user?
  const manualSales = await db.collection("sales")
    .where("user_id", "==", UID)
    .where("order_source", "==", "manual")
    .get();
  console.log(`\nManual sales: ${manualSales.size}`);

  // Check sales without order_source
  const allSales = await db.collection("sales")
    .where("user_id", "==", UID)
    .get();
  let noSource = 0;
  for (const doc of allSales.docs) {
    if (!doc.data().order_source) noSource++;
  }
  console.log(`Sales without order_source: ${noSource} (of ${allSales.size} total)`);
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
