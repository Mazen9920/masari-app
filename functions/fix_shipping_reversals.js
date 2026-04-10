/**
 * Hotfix: Flip shipping REVERSAL entries to negative.
 *
 * After flipping sale-linked shipping from negative (expense) to positive (income),
 * the reversal entries for cancelled orders are wrong — they were already positive
 * (since they reversed a negative original). Now both original and reversal are
 * positive, double-counting instead of netting to zero.
 *
 * This migration finds all shipping reversal entries (id contains "_reversal")
 * with positive amounts and flips them to negative.
 *
 * Usage:
 *   node fix_shipping_reversals.js          # dry-run
 *   node fix_shipping_reversals.js --commit # apply changes
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

  let toFix = 0;
  let skipped = 0;
  let totalAmount = 0;

  const batches = [];
  let currentBatch = db.batch();
  let batchCount = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const id = data.id || doc.id;
    const amount = Number(data.amount) || 0;
    const title = data.title || "";

    // Only fix reversal entries (positive amount that should be negative)
    const isReversal = id.includes("_reversal") || title.startsWith("[Reversal]");
    if (!isReversal) {
      skipped++;
      continue;
    }

    if (amount <= 0) {
      // Already negative or zero — fine
      skipped++;
      continue;
    }

    // Positive reversal → flip to negative
    const newAmount = -Math.abs(amount);
    totalAmount += Math.abs(amount);
    console.log(`  FIX: ${id}  ${amount} → ${newAmount}  "${title}"`);

    if (commit) {
      currentBatch.update(doc.ref, { amount: newAmount });
      batchCount++;
      if (batchCount >= 499) {
        batches.push(currentBatch);
        currentBatch = db.batch();
        batchCount = 0;
      }
    }
    toFix++;
  }

  if (batchCount > 0) batches.push(currentBatch);

  console.log("\n--- Summary ---");
  console.log(`Shipping reversals to fix (positive → negative): ${toFix}`);
  console.log(`Skipped (non-reversal or already negative):      ${skipped}`);
  console.log(`Total amount corrected: ${totalAmount.toFixed(2)}`);

  if (commit && batches.length > 0) {
    console.log(`\nCommitting ${batches.length} batch(es) ...`);
    for (let i = 0; i < batches.length; i++) {
      await batches[i].commit();
      console.log(`  Batch ${i + 1}/${batches.length} committed`);
    }
    console.log(`\nDone! ${toFix} shipping reversal entries fixed.`);
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
