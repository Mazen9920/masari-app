/**
 * Targeted fix for 3 remaining edge-case cancelled sales.
 *
 * 1. da8fd102 — create missing revenue reversal (-480)
 * 2. order #1018 — adjust revenue reversal from -800 to -900
 * 3. order #1031 — create reversals for the 2 [Cancelled] refund txns
 *
 * Usage:
 *   node fix_edge_cases.js          # dry-run
 *   node fix_edge_cases.js --commit # apply
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
const now = admin.firestore.Timestamp.now();
const txnCol = db.collection("transactions");

async function main() {
  console.log(`Mode: ${commit ? "COMMIT" : "DRY-RUN"}\n`);
  const batch = db.batch();

  // ── Fix 1: da8fd102 — missing reversal for +480 revenue ──
  const saleId1 = "da8fd102-6719-426d-8663-083fed2f31a6";
  const revDoc1 = await txnCol.doc(`sale_rev_${saleId1}`).get();
  if (revDoc1.exists) {
    const d = revDoc1.data();
    const reversalId = `sale_rev_${saleId1}_reversal`;
    const existing = await txnCol.doc(reversalId).get();
    if (!existing.exists) {
      console.log(`FIX 1: Create reversal for ${saleId1} → -${d.amount}`);
      if (commit) {
        batch.set(txnCol.doc(reversalId), {
          id: reversalId,
          user_id: d.user_id,
          title: `[Reversal] ${d.title.replace("[Cancelled] ", "")}`,
          amount: -Number(d.amount),
          date_time: now,
          category_id: "cat_sales_revenue",
          note: "Auto-reversal — repair for cancelled sale",
          sale_id: saleId1,
          exclude_from_pl: false,
          created_at: now,
          updated_at: now,
        });
      }
    } else {
      console.log("FIX 1: Reversal already exists, skipping");
    }
  } else {
    console.log("FIX 1: Revenue txn not found, skipping");
  }

  // ── Fix 2: order #1018 — reversal is -800, should be -900 ──
  const saleId2 = "shopify_C2B7b4OWQsZQ8Dw0JtrgOVe9k2O2_16543346884979";
  const reversalDoc2 = await txnCol.doc(`sale_rev_${saleId2}_reversal`).get();
  if (reversalDoc2.exists) {
    const current = Number(reversalDoc2.data().amount);
    const original = await txnCol.doc(`sale_rev_${saleId2}`).get();
    const origAmount = original.exists ? Number(original.data().amount) : 0;
    const correctReversal = -origAmount;
    if (Math.abs(current - correctReversal) > 0.01) {
      console.log(`FIX 2: Adjust reversal for ${saleId2}: ${current} → ${correctReversal}`);
      if (commit) {
        batch.update(reversalDoc2.ref, {
          amount: correctReversal,
          note: "Adjusted reversal — full cancellation (no partial refund offset)",
          updated_at: now,
        });
      }
    } else {
      console.log("FIX 2: Reversal already correct");
    }
  } else {
    console.log("FIX 2: Reversal not found, skipping");
  }

  // ── Fix 3: order #1031 — create reversals for [Cancelled] refund txns ──
  const saleId3 = "shopify_HCyIgSCPxIS842GWDl1Q9T0WoJm2_16555529765235";
  const refundIds = [
    `sale_refund_${saleId3}_1061787894131`,
    `sale_refund_${saleId3}_1061787959667`,
  ];

  for (const refundId of refundIds) {
    const refDoc = await txnCol.doc(refundId).get();
    if (!refDoc.exists) {
      console.log(`FIX 3: Refund ${refundId} not found, skipping`);
      continue;
    }
    const rd = refDoc.data();
    const reversalId = `${refundId}_reversal`;
    const existingRev = await txnCol.doc(reversalId).get();
    if (!existingRev.exists) {
      const amt = Number(rd.amount) || 0;
      console.log(`FIX 3: Create reversal for refund ${refundId}: ${amt} → ${-amt}`);
      if (commit) {
        batch.set(txnCol.doc(reversalId), {
          id: reversalId,
          user_id: rd.user_id,
          title: `[Reversal] ${rd.title.replace("[Cancelled] ", "")}`,
          amount: -amt,
          date_time: now,
          category_id: "cat_sales_revenue",
          note: "Auto-reversal — repair for cancelled refund on cancelled order #1031",
          sale_id: saleId3,
          exclude_from_pl: false,
          created_at: now,
          updated_at: now,
        });
      }
    } else {
      console.log(`FIX 3: Reversal for ${refundId} already exists, skipping`);
    }
  }

  if (commit) {
    await batch.commit();
    console.log("\nDone! All edge cases fixed.");
  } else {
    console.log("\nDry-run complete. Run with --commit to apply.");
  }
}

main().catch((err) => {
  console.error("Fix failed:", err);
  process.exit(1);
});
