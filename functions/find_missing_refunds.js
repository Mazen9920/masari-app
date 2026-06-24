// Find non-cancelled orders that have Shopify refunds but no refund txn in Revvo
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  // Load all sales
  const salesSnap = await db.collection('sales')
    .where('user_id', '==', uid)
    .where('external_source', '==', 'shopify')
    .get();

  // Load all revenue txns
  const revSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_sales_revenue')
    .get();
  
  // Load all shipping txns
  const shipSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_shipping')
    .get();

  // Index txns
  const revBySale = {};
  for (const doc of revSnap.docs) {
    const t = doc.data();
    if (!t.sale_id) continue;
    if (!revBySale[t.sale_id]) revBySale[t.sale_id] = [];
    revBySale[t.sale_id].push({ id: doc.id, amount: Number(t.amount) || 0 });
  }
  const shipBySale = {};
  for (const doc of shipSnap.docs) {
    const t = doc.data();
    if (!t.sale_id) continue;
    if (!shipBySale[t.sale_id]) shipBySale[t.sale_id] = [];
    shipBySale[t.sale_id].push({ id: doc.id, amount: Number(t.amount) || 0 });
  }

  // Check non-cancelled orders with payment_status that might indicate refund
  console.log('Non-cancelled orders with potential refund indicators:\n');
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    if (s.order_status === 4) continue; // skip cancelled
    
    // Check for refund indicators
    const ps = s.payment_status;
    // 3 = refunded (but could also be partially_refunded mapped to something)
    if (ps === 3) {
      const revTxns = revBySale[doc.id] || [];
      const hasRefundTxn = revTxns.some(t => t.id.includes('refund'));
      const netRev = revTxns.reduce((s, t) => s + t.amount, 0);
      console.log(`  #${s.shopify_order_number} (${doc.id}): payment_status=${ps}, netRev=${netRev.toFixed(2)}, hasRefundTxn=${hasRefundTxn}`);
    }
  }

  // Also check: are there cancelled orders whose reversal doesn't fully negate?
  console.log('\n\nCancelled orders - checking complete negation:\n');
  let incompleteCancelCount = 0;
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    if (s.order_status !== 4) continue;
    
    const revTxns = revBySale[doc.id] || [];
    const netRev = revTxns.reduce((sum, t) => sum + t.amount, 0);
    const shipTxns = shipBySale[doc.id] || [];
    const netShip = shipTxns.reduce((sum, t) => sum + t.amount, 0);
    
    if (Math.abs(netRev) > 0.01 || Math.abs(netShip) > 0.01) {
      incompleteCancelCount++;
      if (incompleteCancelCount <= 10) {
        console.log(`  #${s.shopify_order_number} (${doc.id}): netRev=${netRev.toFixed(2)}, netShip=${netShip.toFixed(2)}`);
        for (const t of revTxns) console.log(`    REV: ${t.id}: ${t.amount}`);
        for (const t of shipTxns) console.log(`    SHIP: ${t.id}: ${t.amount}`);
      }
    }
  }
  console.log(`Total cancelled orders with incomplete negation: ${incompleteCancelCount}`);

  // Summary
  console.log('\n\nMonthly totals (all revenue txns including refund/reversal):');
  const byMonth = {};
  for (const doc of revSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate?.();
    if (!dt) continue;
    const mo = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    byMonth[mo] = (byMonth[mo] || { rev: 0, ship: 0 });
    byMonth[mo].rev += Number(t.amount) || 0;
  }
  for (const doc of shipSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate?.();
    if (!dt) continue;
    const mo = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    if (!byMonth[mo]) byMonth[mo] = { rev: 0, ship: 0 };
    byMonth[mo].ship += Number(t.amount) || 0;
  }
  for (const mo of Object.keys(byMonth).sort()) {
    console.log(`  ${mo}: rev=${byMonth[mo].rev.toFixed(2)}, ship=${byMonth[mo].ship.toFixed(2)}`);
  }

  process.exit(0);
})();
