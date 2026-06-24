/**
 * Migration: Create missing shipping reversals for cancelled Shopify orders.
 *
 * Some cancelled orders had revenue + COGS reversals created by the webhook
 * but were missing the shipping reversal. This script:
 * 1. Finds ALL cancelled Shopify sales across ALL users
 * 2. Checks if `sale_ship_{saleId}` exists (original shipping txn)
 * 3. Checks if `sale_ship_{saleId}_reversal` exists
 * 4. If original exists but reversal is missing, creates the reversal
 *
 * Safe to re-run (idempotent).
 */
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const DRY_RUN = process.argv.includes('--dry-run');

(async () => {
  console.log(DRY_RUN ? '=== DRY RUN ===' : '=== LIVE RUN ===');

  // Find all cancelled Shopify sales
  const salesSnap = await db.collection('sales')
    .where('order_status', '==', 4)         // cancelled
    .where('external_source', '==', 'shopify')
    .get();

  console.log(`Found ${salesSnap.size} cancelled Shopify sales across all users.\n`);

  let created = 0;
  let alreadyOk = 0;
  let noShipTxn = 0;
  let errors = 0;

  for (const saleDoc of salesSnap.docs) {
    const saleId = saleDoc.id;
    const saleData = saleDoc.data();
    const userId = saleData.user_id;

    const shipTxnId = `sale_ship_${saleId}`;
    const reversalId = `sale_ship_${saleId}_reversal`;

    // Check if original shipping txn exists
    const shipDoc = await db.doc(`transactions/${shipTxnId}`).get();
    if (!shipDoc.exists) {
      noShipTxn++;
      continue;
    }

    // Check if reversal already exists
    const reversalDoc = await db.doc(`transactions/${reversalId}`).get();
    if (reversalDoc.exists) {
      alreadyOk++;
      continue;
    }

    // Reversal is missing — create it
    const shipData = shipDoc.data();
    const origAmount = Number(shipData.amount) || 0;
    if (origAmount === 0) {
      alreadyOk++;
      continue;
    }

    // Use the original order date for reversal (same accounting period)
    const reversalDate = saleData.date || shipData.date_time;

    const reversalTxn = {
      id: reversalId,
      user_id: userId,
      title: `[Reversal] ${shipData.title || 'Shipping'}`,
      amount: -origAmount,
      date_time: reversalDate,
      category_id: 'cat_shipping',
      note: 'Auto-reversal — Shopify order cancelled (backfill migration)',
      sale_id: saleId,
      exclude_from_pl: false,
      created_at: admin.firestore.Timestamp.now(),
      updated_at: admin.firestore.Timestamp.now(),
    };

    console.log(`  CREATE ${reversalId}: amount=${-origAmount} (order #${saleData.shopify_order_number}, user=${userId})`);

    if (!DRY_RUN) {
      try {
        await db.doc(`transactions/${reversalId}`).set(reversalTxn);
        created++;
      } catch (err) {
        console.error(`  ERROR creating ${reversalId}:`, err.message);
        errors++;
      }
    } else {
      created++;
    }
  }

  console.log(`\n══ Summary ══`);
  console.log(`Cancelled Shopify sales: ${salesSnap.size}`);
  console.log(`No shipping txn (nothing to reverse): ${noShipTxn}`);
  console.log(`Already have reversal: ${alreadyOk}`);
  console.log(`Reversals created: ${created}`);
  console.log(`Errors: ${errors}`);

  process.exit(0);
})();
