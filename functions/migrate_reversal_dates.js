/**
 * Migration: Fix reversal transaction dates to use original order date
 * instead of cancellation date. Also create missing reversals.
 *
 * Safe for ALL users — no hardcoded user IDs.
 */
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

(async () => {
  const DRY_RUN = process.argv.includes('--dry-run');
  if (DRY_RUN) console.log('=== DRY RUN ===\n');

  // 1. Get all cancelled sales with external_order_id (Shopify orders)
  const salesSnap = await db.collection('sales').get();
  const ORDER_CANCELLED = 4;

  let fixedDates = 0;
  let createdReversals = 0;
  let batchOps = [];
  const BATCH_SIZE = 250;

  for (const saleDoc of salesSnap.docs) {
    const sale = saleDoc.data();
    if (sale.order_status !== ORDER_CANCELLED) continue;
    if (!sale.external_order_id) continue; // only Shopify orders

    const saleId = saleDoc.id;
    const originalDate = sale.date; // Firestore Timestamp of original order

    if (!originalDate) continue;

    // Check for revenue reversal
    const reversalId = `sale_rev_${saleId}_reversal`;
    const reversalDoc = await db.collection('transactions').doc(reversalId).get();

    if (reversalDoc.exists) {
      const revData = reversalDoc.data();
      const currentDate = revData.date_time;

      // Compare: if reversal date != original order date, fix it
      if (currentDate && originalDate &&
          currentDate.toMillis() !== originalDate.toMillis()) {
        if (!DRY_RUN) {
          batchOps.push({ ref: reversalDoc.ref, data: { date_time: originalDate, updated_at: admin.firestore.Timestamp.now() } });
        }
        fixedDates++;
      }

      // Also fix COGS reversal date
      const cogsReversalId = `sale_cogs_${saleId}_reversal`;
      const cogsDoc = await db.collection('transactions').doc(cogsReversalId).get();
      if (cogsDoc.exists) {
        const cogsData = cogsDoc.data();
        if (cogsData.date_time && cogsData.date_time.toMillis() !== originalDate.toMillis()) {
          if (!DRY_RUN) {
            batchOps.push({ ref: cogsDoc.ref, data: { date_time: originalDate, updated_at: admin.firestore.Timestamp.now() } });
          }
        }
      }

      // Also fix shipping reversal date
      const shipReversalId = `sale_ship_${saleId}_reversal`;
      const shipDoc = await db.collection('transactions').doc(shipReversalId).get();
      if (shipDoc.exists) {
        const shipData = shipDoc.data();
        if (shipData.date_time && shipData.date_time.toMillis() !== originalDate.toMillis()) {
          if (!DRY_RUN) {
            batchOps.push({ ref: shipDoc.ref, data: { date_time: originalDate, updated_at: admin.firestore.Timestamp.now() } });
          }
        }
      }
    } else {
      // No reversal exists — check if there IS a positive revenue txn
      const revTxnId = `sale_rev_${saleId}`;
      const revTxnDoc = await db.collection('transactions').doc(revTxnId).get();
      if (revTxnDoc.exists) {
        const revData = revTxnDoc.data();
        const origAmount = Number(revData.amount) || 0;
        if (origAmount > 0) {
          // Check for existing refund txns to avoid double-deduction
          const refundSnap = await db.collection('transactions')
            .where('sale_id', '==', saleId)
            .where('category_id', '==', 'cat_sales_revenue')
            .get();
          let alreadyRefunded = 0;
          for (const d of refundSnap.docs) {
            if (d.id.startsWith(`sale_refund_${saleId}_`)) {
              alreadyRefunded += Math.abs(Number(d.data().amount) || 0);
            }
          }

          const netToReverse = origAmount - alreadyRefunded;
          if (netToReverse > 0.01) {
            console.log(`  Creating missing reversal for ${saleId} (#${sale.shopify_order_number}): -${netToReverse.toFixed(2)}`);
            if (!DRY_RUN) {
              const now = admin.firestore.Timestamp.now();
              batchOps.push({
                ref: db.collection('transactions').doc(reversalId),
                data: {
                  id: reversalId,
                  user_id: sale.user_id,
                  title: `[Reversal] Sale Revenue (Shopify)`,
                  amount: -netToReverse,
                  date_time: originalDate,
                  category_id: 'cat_sales_revenue',
                  note: 'Auto-reversal — migration fix for cancelled order',
                  sale_id: saleId,
                  exclude_from_pl: false,
                  created_at: now,
                  updated_at: now,
                },
                isSet: true,
              });
            }
            createdReversals++;
          }

          // Also create COGS reversal if missing
          const cogsTxnId = `sale_cogs_${saleId}`;
          const cogsTxnDoc = await db.collection('transactions').doc(cogsTxnId).get();
          const cogsReversalId = `sale_cogs_${saleId}_reversal`;
          const cogsReversalDoc = await db.collection('transactions').doc(cogsReversalId).get();
          if (cogsTxnDoc.exists && !cogsReversalDoc.exists) {
            const cogsAmount = Number(cogsTxnDoc.data().amount) || 0;
            if (cogsAmount !== 0 && !DRY_RUN) {
              const now = admin.firestore.Timestamp.now();
              batchOps.push({
                ref: db.collection('transactions').doc(cogsReversalId),
                data: {
                  id: cogsReversalId,
                  user_id: sale.user_id,
                  title: `[Reversal] Cost of Goods Sold (Shopify)`,
                  amount: -cogsAmount,
                  date_time: originalDate,
                  category_id: 'cat_cogs',
                  note: 'Auto-reversal — migration fix for cancelled order',
                  sale_id: saleId,
                  exclude_from_pl: false,
                  created_at: now,
                  updated_at: now,
                },
                isSet: true,
              });
            }
          }
        }
      }
    }

    // Also fix refund txn dates for this sale
    const allRefundSnap = await db.collection('transactions')
      .where('sale_id', '==', saleId)
      .where('category_id', '==', 'cat_sales_revenue')
      .get();
    for (const doc of allRefundSnap.docs) {
      if (!doc.id.startsWith(`sale_refund_${saleId}_`)) continue;
      const d = doc.data();
      if (d.date_time && d.date_time.toMillis() !== originalDate.toMillis()) {
        if (!DRY_RUN) {
          batchOps.push({ ref: doc.ref, data: { date_time: originalDate, updated_at: admin.firestore.Timestamp.now() } });
        }
      }
    }

    // Commit in batches
    if (batchOps.length >= BATCH_SIZE) {
      const batch = db.batch();
      for (const op of batchOps) {
        if (op.isSet) batch.set(op.ref, op.data);
        else batch.update(op.ref, op.data);
      }
      await batch.commit();
      batchOps = [];
    }
  }

  // Flush remaining
  if (batchOps.length > 0 && !DRY_RUN) {
    const batch = db.batch();
    for (const op of batchOps) {
      if (op.isSet) batch.set(op.ref, op.data);
      else batch.update(op.ref, op.data);
    }
    await batch.commit();
  }

  console.log(`\nDone (${DRY_RUN ? 'DRY RUN' : 'APPLIED'}):`);
  console.log(`  Reversal dates fixed: ${fixedDates}`);
  console.log(`  Missing reversals created: ${createdReversals}`);

  process.exit(0);
})();
