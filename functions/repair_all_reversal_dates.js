#!/usr/bin/env node
/**
 * repair_all_reversal_dates.js
 *
 * One-time script: re-date ALL reversal/refund transactions to their
 * parent sale's original order date.  This eliminates "orphan" reversals
 * that appear in date ranges where the original order doesn't exist.
 *
 * Usage:
 *   node functions/repair_all_reversal_dates.js          # dry-run
 *   node functions/repair_all_reversal_dates.js apply     # apply changes
 */

const admin = require("firebase-admin");

const SERVICE_ACCOUNT = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
const USER_ID = "EGYQnP7ughdUtTbn04UwUET534i1";

admin.initializeApp({
  credential: admin.credential.cert(SERVICE_ACCOUNT),
});
const db = admin.firestore();

const DRY_RUN = process.argv[2] !== "apply";

async function main() {
  console.log(`Mode: ${DRY_RUN ? "DRY-RUN" : "APPLY"}\n`);

  // ── 1. Load all sales for this user (we need their dates) ──
  const salesSnap = await db
    .collection("sales")
    .where("user_id", "==", USER_ID)
    .get();

  const saleDateMap = new Map(); // saleId -> Firestore Timestamp
  for (const doc of salesSnap.docs) {
    const d = doc.data();
    const saleId = d.id || doc.id;
    if (d.date) {
      saleDateMap.set(saleId, d.date);
    }
  }
  console.log(`Loaded ${saleDateMap.size} sales with dates.\n`);

  // ── 2. Load all Shopify-related transactions ──
  // We look for transactions that have a sale_id and are in Shopify categories
  const txnSnap = await db
    .collection("transactions")
    .where("user_id", "==", USER_ID)
    .get();

  // Filter to reversal/refund transactions (those with sale_id that are
  // reversals, refunds, or Shopify-linked financial transactions)
  const candidates = [];
  for (const doc of txnSnap.docs) {
    const t = doc.data();
    if (!t.sale_id) continue;
    const cat = t.category_id || "";
    if (
      cat !== "cat_sales_revenue" &&
      cat !== "cat_shipping" &&
      cat !== "cat_cogs"
    )
      continue;

    // We want to re-date ALL sale-linked transactions (original + reversals)
    // to their parent sale's date so every order's lifecycle stays in one period
    candidates.push({
      docId: doc.id,
      ref: doc.ref,
      saleId: t.sale_id,
      categoryId: cat,
      amount: t.amount,
      currentDateTime: t.date_time,
      title: t.title || "",
    });
  }
  console.log(
    `Found ${candidates.length} sale-linked transactions (cat_sales_revenue, cat_shipping, cat_cogs).\n`
  );

  // ── 3. Compare and collect fixes ──
  let alreadyCorrect = 0;
  let needFix = 0;
  let noSaleFound = 0;
  const fixes = [];

  for (const c of candidates) {
    const saleDate = saleDateMap.get(c.saleId);
    if (!saleDate) {
      noSaleFound++;
      continue;
    }

    const currentSec = c.currentDateTime?._seconds ?? c.currentDateTime?.seconds;
    const saleSec = saleDate._seconds ?? saleDate.seconds;

    if (currentSec === saleSec) {
      alreadyCorrect++;
    } else {
      needFix++;
      fixes.push({
        docId: c.docId,
        ref: c.ref,
        saleId: c.saleId,
        title: c.title,
        amount: c.amount,
        category: c.categoryId,
        currentDate: c.currentDateTime?.toDate
          ? c.currentDateTime.toDate().toISOString()
          : "unknown",
        correctDate: saleDate.toDate
          ? saleDate.toDate().toISOString()
          : "unknown",
        correctTs: saleDate,
      });
    }
  }

  console.log(`Already correct: ${alreadyCorrect}`);
  console.log(`Need fixing:     ${needFix}`);
  console.log(`No parent sale:  ${noSaleFound}\n`);

  if (fixes.length === 0) {
    console.log("Nothing to fix!");
    process.exit(0);
  }

  // Show details
  console.log("Transactions to fix:");
  console.log("─".repeat(100));
  for (const f of fixes) {
    console.log(
      `  ${f.docId}  [${f.category}]  amount=${f.amount}  "${f.title}"`
    );
    console.log(
      `    current: ${f.currentDate}  →  correct: ${f.correctDate}`
    );
  }
  console.log("");

  if (DRY_RUN) {
    console.log("DRY-RUN complete. Run with 'apply' to make changes.");
    process.exit(0);
  }

  // ── 4. Apply fixes in batches of 500 ──
  const BATCH_SIZE = 500;
  let applied = 0;

  for (let i = 0; i < fixes.length; i += BATCH_SIZE) {
    const batch = db.batch();
    const chunk = fixes.slice(i, i + BATCH_SIZE);
    for (const f of chunk) {
      batch.update(f.ref, { date_time: f.correctTs });
    }
    await batch.commit();
    applied += chunk.length;
    console.log(`Applied batch: ${applied}/${fixes.length}`);
  }

  console.log(`\nDone! Updated ${applied} transactions.`);
  process.exit(0);
}

main().catch((err) => {
  console.error("Fatal:", err);
  process.exit(1);
});
