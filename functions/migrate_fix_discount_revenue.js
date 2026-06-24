// Migration: Fix ALL revenue transactions where discount wasn't deducted.
// Scans all Shopify sales, checks if sale_rev_{saleId} amount matches
// netRevenue (subtotal - discount_amount), and corrects if not.
// Idempotent and safe to re-run.
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const DRY_RUN = process.argv.includes('--dry-run');

(async () => {
  console.log(DRY_RUN ? '=== DRY RUN ===' : '=== LIVE RUN ===');

  const salesSnap = await db.collection('sales')
    .where('external_source', '==', 'shopify')
    .get();

  console.log(`Found ${salesSnap.size} Shopify sales.`);

  let checked = 0;
  let fixed = 0;
  let skippedCancelled = 0;
  let noTxn = 0;
  let alreadyOk = 0;

  for (const saleDoc of salesSnap.docs) {
    const s = saleDoc.data();
    const saleId = saleDoc.id;

    // Skip cancelled
    if (s.order_status === 4) { skippedCancelled++; continue; }

    checked++;

    // Compute expected netRevenue
    const items = s.items || [];
    const subtotal = items.reduce((sum, i) =>
      sum + (i.quantity || 0) * (i.unit_price || 0), 0);
    const discount = s.discount_amount || 0;
    const expected = Math.round((subtotal - discount) * 100) / 100;

    // Get revenue txn
    const txnId = `sale_rev_${saleId}`;
    const txnDoc = await db.doc(`transactions/${txnId}`).get();
    if (!txnDoc.exists) { noTxn++; continue; }

    const actual = Number(txnDoc.data().amount) || 0;
    if (Math.abs(actual - expected) < 0.01) {
      alreadyOk++;
      continue;
    }

    console.log(`  FIX: ${saleId} (#${s.shopify_order_number}): ${actual} → ${expected} (diff=${(actual - expected).toFixed(2)})`);
    if (!DRY_RUN) {
      await db.doc(`transactions/${txnId}`).update({
        amount: expected,
        updated_at: admin.firestore.Timestamp.now(),
      });
    }
    fixed++;
  }

  console.log(`\n═══ Summary ═══`);
  console.log(`Total Shopify sales: ${salesSnap.size}`);
  console.log(`Cancelled (skipped): ${skippedCancelled}`);
  console.log(`Checked: ${checked}`);
  console.log(`No revenue txn: ${noTxn}`);
  console.log(`Already correct: ${alreadyOk}`);
  console.log(`Fixed: ${fixed}`);

  process.exit(0);
})();
