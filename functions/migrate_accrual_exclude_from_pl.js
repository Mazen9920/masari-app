/**
 * Migration: Switch from cash-basis to accrual accounting.
 *
 * Under accrual accounting, revenue and expenses are recognised at point of
 * sale regardless of payment status. This script flips ALL transactions that
 * have exclude_from_pl: true → false, EXCEPT cancelled/refunded reversal
 * entries (those already have exclude_from_pl: false by design).
 *
 * Usage:
 *   node migrate_accrual_exclude_from_pl.js          # dry run
 *   node migrate_accrual_exclude_from_pl.js --commit # apply changes
 */

const admin = require("firebase-admin");
const serviceAccount = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function migrate() {
  const commit = process.argv.includes("--commit");
  console.log(commit ? "=== COMMIT MODE ===" : "=== DRY RUN (add --commit to apply) ===\n");

  // Query all transactions where exclude_from_pl == true
  const snap = await db.collection("transactions")
    .where("exclude_from_pl", "==", true)
    .get();

  console.log(`Found ${snap.size} transactions with exclude_from_pl: true\n`);

  const toUpdate = [];
  let recoveredRevenue = 0;
  let recoveredCogs = 0;
  let recoveredShipping = 0;
  let skipped = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const cat = data.category_id || "";
    const amt = Number(data.amount) || 0;
    const title = data.title || "";

    // Skip cancelled/refunded reversal entries (shouldn't have true, but be safe)
    if (title.startsWith("[Cancelled]") || title.startsWith("[Reversal]") ||
        title.startsWith("[Refunded]") || title.startsWith("[Refund]")) {
      skipped++;
      continue;
    }

    console.log(`  FIX: ${doc.id} | ${cat} | amt=${amt} | title=${title.substring(0, 50)}`);

    if (cat === "cat_sales_revenue") recoveredRevenue += amt;
    else if (cat === "cat_cogs") recoveredCogs += Math.abs(amt);
    else if (cat === "cat_shipping") recoveredShipping += Math.abs(amt);

    toUpdate.push(doc.id);
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
      console.log(`  Committed batch ${Math.floor(i / 500) + 1}`);
    }
  }

  console.log(`\n=== Results ===`);
  console.log(`  Transactions to fix:     ${toUpdate.length}`);
  console.log(`  Skipped (reversals):     ${skipped}`);
  console.log(`  Revenue recovered:       ${recoveredRevenue.toFixed(2)}`);
  console.log(`  COGS recovered:          ${recoveredCogs.toFixed(2)}`);
  console.log(`  Shipping recovered:      ${recoveredShipping.toFixed(2)}`);

  if (!commit && toUpdate.length > 0) {
    console.log(`\nRun with --commit to apply these ${toUpdate.length} fixes.`);
  }
}

migrate().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
