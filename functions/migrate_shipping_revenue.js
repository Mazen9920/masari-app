/**
 * Migration: Flip sale-linked shipping transactions from negative (expense)
 * to positive (income / revenue).
 *
 * Shipping charged to customers is revenue, not an expense.
 * This migration fixes all existing cat_shipping transactions that have
 * a sale_id and a negative amount → flips them to positive.
 *
 * Usage:
 *   node migrate_shipping_revenue.js          # dry-run
 *   node migrate_shipping_revenue.js --commit # apply changes
 */

const admin = require("firebase-admin");
const path = require("path");

const SA_PATH = path.resolve(
  "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
);

admin.initializeApp({
  credential: admin.credential.cert(require(SA_PATH)),
});

const db = admin.firestore();
const commit = process.argv.includes("--commit");

async function main() {
  console.log(`Mode: ${commit ? "COMMIT" : "DRY-RUN"}`);
  console.log("Querying cat_shipping transactions ...\n");

  const snap = await db
    .collection("transactions")
    .where("category_id", "==", "cat_shipping")
    .get();

  console.log(`Found ${snap.size} total cat_shipping transactions\n`);

  let toFlip = 0;
  let alreadyPositive = 0;
  let noSaleId = 0;
  let zeroAmount = 0;
  let totalAmountFlipped = 0;

  const batches = [];
  let currentBatch = db.batch();
  let batchCount = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const amount = Number(data.amount) || 0;
    const saleId = data.sale_id;

    // Only flip sale-linked shipping transactions
    if (!saleId) {
      noSaleId++;
      continue;
    }

    if (amount === 0) {
      zeroAmount++;
      continue;
    }

    if (amount > 0) {
      alreadyPositive++;
      continue;
    }

    // Negative sale-linked shipping → flip to positive
    const newAmount = Math.abs(amount);
    totalAmountFlipped += newAmount;

    if (commit) {
      currentBatch.update(doc.ref, { amount: newAmount });
      batchCount++;
      if (batchCount >= 499) {
        batches.push(currentBatch);
        currentBatch = db.batch();
        batchCount = 0;
      }
    }
    toFlip++;
  }

  if (batchCount > 0) batches.push(currentBatch);

  console.log("--- Summary ---");
  console.log(`Sale-linked, negative (to flip): ${toFlip}`);
  console.log(`Sale-linked, already positive:   ${alreadyPositive}`);
  console.log(`No sale_id (manual expenses):    ${noSaleId}`);
  console.log(`Zero amount:                     ${zeroAmount}`);
  console.log(`Total amount flipped:            ${totalAmountFlipped.toFixed(2)}`);

  if (commit && batches.length > 0) {
    console.log(`\nCommitting ${batches.length} batch(es) ...`);
    for (let i = 0; i < batches.length; i++) {
      await batches[i].commit();
      console.log(`  Batch ${i + 1}/${batches.length} committed`);
    }
    console.log(`\nDone! ${toFlip} shipping transactions flipped to positive.`);
  } else if (!commit) {
    console.log("\nDry-run complete. Run with --commit to apply changes.");
  } else {
    console.log("\nNothing to fix.");
  }
}

main().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
