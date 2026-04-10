/**
 * Migration: Flip exclude_from_pl on cancelled/reversal transactions.
 *
 * Phase 1 changed the TS cancellation handler to set exclude_from_pl: false
 * (audit-trail approach). This migration fixes EXISTING historical entries
 * that still have exclude_from_pl: true from the old logic.
 *
 * What it does:
 *   - Finds all transactions with exclude_from_pl == true
 *   - SKIPS cat_supplier_payment (correctly excluded from P&L)
 *   - Flips everything else to exclude_from_pl: false
 *     (cancelled originals, reversals, refunds, and any other remnants)
 *
 * Usage:
 *   node migrate_cancelled_reversals.js          # dry-run
 *   node migrate_cancelled_reversals.js --commit # apply changes
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
  console.log("Querying transactions with exclude_from_pl == true ...\n");

  const snap = await db
    .collection("transactions")
    .where("exclude_from_pl", "==", true)
    .get();

  console.log(`Found ${snap.size} transactions with exclude_from_pl: true\n`);

  let toFix = 0;
  let skippedSupplier = 0;
  const byCategory = {};
  const byTitlePrefix = {};

  const batches = [];
  let currentBatch = db.batch();
  let batchCount = 0;

  for (const doc of snap.docs) {
    const data = doc.data();
    const catId = data.category_id || "unknown";
    const title = data.title || "";

    // Skip supplier payments — correctly excluded from P&L
    if (catId === "cat_supplier_payment") {
      skippedSupplier++;
      continue;
    }

    // Track stats
    byCategory[catId] = (byCategory[catId] || 0) + 1;
    const prefix = title.match(/^\[([^\]]+)\]/)?.[1] || "(no prefix)";
    byTitlePrefix[prefix] = (byTitlePrefix[prefix] || 0) + 1;

    if (commit) {
      currentBatch.update(doc.ref, { exclude_from_pl: false });
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

  console.log("--- Summary ---");
  console.log(`Skipped (cat_supplier_payment): ${skippedSupplier}`);
  console.log(`To fix (exclude_from_pl → false): ${toFix}`);
  console.log("\nBy category:");
  for (const [cat, count] of Object.entries(byCategory).sort((a, b) => b[1] - a[1])) {
    console.log(`  ${cat}: ${count}`);
  }
  console.log("\nBy title prefix:");
  for (const [prefix, count] of Object.entries(byTitlePrefix).sort((a, b) => b[1] - a[1])) {
    console.log(`  [${prefix}]: ${count}`);
  }

  if (commit && batches.length > 0) {
    console.log(`\nCommitting ${batches.length} batch(es) ...`);
    for (let i = 0; i < batches.length; i++) {
      await batches[i].commit();
      console.log(`  Batch ${i + 1}/${batches.length} committed`);
    }
    console.log(`\nDone! ${toFix} transactions updated.`);
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
