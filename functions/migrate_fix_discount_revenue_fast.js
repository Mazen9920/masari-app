// Fast migration: Fix ALL revenue transactions where discount wasn't deducted.
// Uses batch queries instead of per-doc reads.
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const DRY_RUN = process.argv.includes('--dry-run');

(async () => {
  console.log(DRY_RUN ? '=== DRY RUN ===' : '=== LIVE RUN ===');

  // Load ALL Shopify sales at once
  const salesSnap = await db.collection('sales')
    .where('external_source', '==', 'shopify')
    .get();
  console.log(`Loaded ${salesSnap.size} Shopify sales.`);

  // Load ALL cat_sales_revenue transactions at once
  const revSnap = await db.collection('transactions')
    .where('category_id', '==', 'cat_sales_revenue')
    .get();
  console.log(`Loaded ${revSnap.size} revenue txns.`);

  // Index revenue txns by doc ID
  const revById = new Map();
  for (const doc of revSnap.docs) {
    revById.set(doc.id, { ref: doc.ref, amount: Number(doc.data().amount) || 0 });
  }

  let fixed = 0;
  let skippedCancelled = 0;
  let noTxn = 0;
  let alreadyOk = 0;

  for (const saleDoc of salesSnap.docs) {
    const s = saleDoc.data();
    const saleId = saleDoc.id;

    if (s.order_status === 4) { skippedCancelled++; continue; }

    const items = s.items || [];
    const subtotal = items.reduce((sum, i) =>
      sum + (i.quantity || 0) * (i.unit_price || 0), 0);
    const discount = s.discount_amount || 0;
    const expected = Math.round((subtotal - discount) * 100) / 100;

    const txnId = `sale_rev_${saleId}`;
    const revEntry = revById.get(txnId);
    if (!revEntry) { noTxn++; continue; }

    if (Math.abs(revEntry.amount - expected) < 0.01) {
      alreadyOk++;
      continue;
    }

    console.log(`  FIX: ${saleId} (#${s.shopify_order_number}, user=${s.user_id}): ${revEntry.amount} → ${expected} (diff=${(revEntry.amount - expected).toFixed(2)})`);
    if (!DRY_RUN) {
      await revEntry.ref.update({
        amount: expected,
        updated_at: admin.firestore.Timestamp.now(),
      });
    }
    fixed++;
  }

  console.log(`\n═══ Summary ═══`);
  console.log(`Total Shopify sales: ${salesSnap.size}`);
  console.log(`Cancelled (skipped): ${skippedCancelled}`);
  console.log(`No revenue txn: ${noTxn}`);
  console.log(`Already correct: ${alreadyOk}`);
  console.log(`Fixed: ${fixed}`);

  process.exit(0);
})();
