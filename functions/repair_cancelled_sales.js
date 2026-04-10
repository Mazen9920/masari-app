/**
 * Repair: Create missing reversal entries for cancelled sales.
 *
 * Finds cancelled sales (order_status === 4) whose transactions don't
 * net to zero — meaning the cancellation webhook failed or never fired.
 * Creates the missing [Cancelled] prefix + [Reversal] entries.
 *
 * Usage:
 *   node repair_cancelled_sales.js          # dry-run
 *   node repair_cancelled_sales.js --commit # apply changes
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

async function main() {
  console.log(`Mode: ${commit ? "COMMIT" : "DRY-RUN"}\n`);

  // Load all cancelled sales
  const salesSnap = await db
    .collection("sales")
    .where("order_status", "==", 4)
    .get();

  console.log(`Cancelled sales: ${salesSnap.size}\n`);

  let repaired = 0;
  let alreadyOk = 0;
  let totalLeakFixed = 0;
  let reversalsCreated = 0;
  let originalsMarked = 0;

  for (const saleDoc of salesSnap.docs) {
    const sale = saleDoc.data();
    const saleId = sale.id || saleDoc.id;
    const userId = sale.user_id;
    const orderNum = sale.shopify_order_number || sale.external_order_id || "?";

    // Get all txns for this sale
    const txnSnap = await db
      .collection("transactions")
      .where("sale_id", "==", saleId)
      .get();

    const txns = txnSnap.docs.map((d) => ({ ref: d.ref, ...d.data() }));

    // Check if transactions net to zero (P&L perspective)
    const netAmount = txns.reduce((s, t) => s + (Number(t.amount) || 0), 0);

    if (Math.abs(netAmount) <= 0.01) {
      alreadyOk++;
      continue;
    }

    // This sale needs repair
    console.log(`REPAIR: ${saleId} (order #${orderNum}) user=${userId} net=${netAmount.toFixed(2)}`);

    const batch = db.batch();
    const txnCol = db.collection("transactions");

    for (const t of txns) {
      const txnId = t.id || t.ref.id;
      const amount = Number(t.amount) || 0;
      const catId = t.category_id || "";
      const title = t.title || "";

      // Skip if already has [Cancelled] or [Reversal] prefix
      if (title.startsWith("[Cancelled]") || title.startsWith("[Reversal]")) {
        console.log(`  SKIP (already tagged): ${txnId} ${amount >= 0 ? "+" : ""}${amount.toFixed(2)} "${title}"`);
        continue;
      }

      // Skip if there's already a reversal for this txn
      const reversalId = `${txnId}_reversal`;
      const existingReversal = txns.find((r) => (r.id || r.ref.id) === reversalId);
      if (existingReversal) {
        console.log(`  SKIP (has reversal): ${txnId}`);
        continue;
      }

      // Mark original as [Cancelled]
      if (commit) {
        batch.update(t.ref, {
          title: `[Cancelled] ${title}`,
          updated_at: now,
        });
      }
      originalsMarked++;
      console.log(`  MARK: ${txnId} "${title}" → "[Cancelled] ${title}"`);

      // Create reversal entry (only if amount != 0)
      if (amount !== 0) {
        const reversalData = {
          id: reversalId,
          user_id: userId,
          title: `[Reversal] ${title}`,
          amount: -amount,
          date_time: now,
          category_id: catId,
          note: `Auto-reversal — repair for cancelled order #${orderNum}`,
          sale_id: saleId,
          exclude_from_pl: false,
          created_at: now,
          updated_at: now,
        };

        if (commit) {
          batch.set(txnCol.doc(reversalId), reversalData);
        }
        reversalsCreated++;
        totalLeakFixed += amount;
        console.log(`  CREATE: ${reversalId} ${-amount >= 0 ? "+" : ""}${(-amount).toFixed(2)} ${catId}`);
      }
    }

    if (commit) {
      await batch.commit();
    }
    repaired++;
    console.log("");
  }

  console.log("=== SUMMARY ===");
  console.log(`Already correct (net zero): ${alreadyOk}`);
  console.log(`Repaired:                   ${repaired}`);
  console.log(`Originals marked [Cancelled]: ${originalsMarked}`);
  console.log(`Reversals created:          ${reversalsCreated}`);
  console.log(`Total revenue leak fixed:   ${totalLeakFixed.toFixed(2)}`);

  if (!commit) {
    console.log("\nDry-run complete. Run with --commit to apply changes.");
  } else {
    console.log("\nDone!");
  }
}

main().catch((err) => {
  console.error("Repair failed:", err);
  process.exit(1);
});
