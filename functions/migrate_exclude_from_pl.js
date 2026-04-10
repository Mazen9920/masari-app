/**
 * Migration: Fix exclude_from_pl on paid Shopify order transactions.
 *
 * COD orders were created with exclude_from_pl: true on their
 * revenue/COGS/shipping transactions. When the order was later marked as paid,
 * the flag was never flipped to false — hiding the revenue from the dashboard.
 *
 * This script finds all paid Shopify sales and ensures their linked
 * transactions have exclude_from_pl: false.
 *
 * Usage:
 *   node migrate_exclude_from_pl.js          # dry run
 *   node migrate_exclude_from_pl.js --commit # apply changes
 */

const admin = require("firebase-admin");
const serviceAccount = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function migrate() {
  const commit = process.argv.includes("--commit");
  console.log(commit ? "=== COMMIT MODE ===" : "=== DRY RUN (add --commit to apply) ===\n");

  // Find all paid Shopify sales (payment_status 2 = paid)
  const salesSnap = await db.collection("sales")
    .where("external_source", "==", "shopify")
    .where("payment_status", "==", 2)
    .get();

  console.log(`Found ${salesSnap.size} paid Shopify sales\n`);

  let fixed = 0;
  let alreadyOk = 0;
  let missing = 0;
  let recoveredRevenue = 0;

  // Build all transaction refs up front
  const txnLookups = [];
  for (const saleDoc of salesSnap.docs) {
    const sale = saleDoc.data();
    const saleId = sale.id || saleDoc.id;
    const orderNum = sale.shopify_order_number || "?";
    for (const prefix of ["sale_rev_", "sale_cogs_", "sale_ship_"]) {
      txnLookups.push({ txnId: `${prefix}${saleId}`, orderNum });
    }
  }

  // Batch getAll (Firestore supports up to ~10k refs per call)
  const refs = txnLookups.map(t => db.collection("transactions").doc(t.txnId));
  const txnSnaps = await db.getAll(...refs);

  const toUpdate = [];
  for (let i = 0; i < txnSnaps.length; i++) {
    const snap = txnSnaps[i];
    const { txnId, orderNum } = txnLookups[i];

    if (!snap.exists) { missing++; continue; }

    const txnData = snap.data();
    if (txnData.exclude_from_pl === true) {
      const amt = Number(txnData.amount) || 0;
      const cat = txnData.category_id || "";
      console.log(`  FIX: ${txnId} | ${cat} | amt=${amt} | order=#${orderNum}`);
      if (cat === "cat_sales_revenue") recoveredRevenue += amt;
      toUpdate.push(txnId);
      fixed++;
    } else {
      alreadyOk++;
    }
  }

  // Commit in batches of 500
  if (commit && toUpdate.length > 0) {
    for (let i = 0; i < toUpdate.length; i += 500) {
      const batch = db.batch();
      for (const txnId of toUpdate.slice(i, i + 500)) {
        batch.update(db.collection("transactions").doc(txnId), {
          exclude_from_pl: false,
          updated_at: admin.firestore.Timestamp.now(),
        });
      }
      await batch.commit();
      console.log(`  Committed batch ${Math.floor(i/500)+1}`);
    }
  }

  console.log(`\n=== Results ===`);
  console.log(`  Transactions fixed:    ${fixed}`);
  console.log(`  Already correct:       ${alreadyOk}`);
  console.log(`  Missing transactions:  ${missing}`);
  console.log(`  Revenue recovered:     ${recoveredRevenue.toFixed(2)}`);

  if (!commit && fixed > 0) {
    console.log(`\nRun with --commit to apply these ${fixed} fixes.`);
  }
}

migrate().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
