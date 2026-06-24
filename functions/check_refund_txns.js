// Check all refund transactions
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  const snap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_sales_revenue')
    .get();
  
  let refundCount = 0, refundTotal = 0;
  for (const doc of snap.docs) {
    if (doc.id.includes('refund')) {
      refundCount++;
      refundTotal += Number(doc.data().amount) || 0;
      const t = doc.data();
      const dt = t.date_time?.toDate?.()?.toISOString()?.slice(0,10) || '?';
      console.log(`  ${doc.id}: ${t.amount} (${dt})`);
    }
  }
  console.log(`\nRevenue refund txns: ${refundCount}, total: ${refundTotal.toFixed(2)}`);

  // Shipping refunds
  const shipSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_shipping')
    .get();
  
  let shipRefundCount = 0, shipRefundTotal = 0;
  for (const doc of shipSnap.docs) {
    if (doc.id.includes('refund')) {
      shipRefundCount++;
      shipRefundTotal += Number(doc.data().amount) || 0;
      const t = doc.data();
      const dt = t.date_time?.toDate?.()?.toISOString()?.slice(0,10) || '?';
      console.log(`  SHIP: ${doc.id}: ${t.amount} (${dt})`);
    }
  }
  console.log(`Shipping refund txns: ${shipRefundCount}, total: ${shipRefundTotal.toFixed(2)}`);

  // Now compute the Revvo total including refunds
  let revByMonth = {};
  let shipByMonth = {};
  for (const doc of snap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate?.();
    if (!dt) continue;
    const mo = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    revByMonth[mo] = (revByMonth[mo] || 0) + (Number(t.amount) || 0);
  }
  for (const doc of shipSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate?.();
    if (!dt) continue;
    const mo = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    shipByMonth[mo] = (shipByMonth[mo] || 0) + (Number(t.amount) || 0);
  }

  console.log('\nRevvo totals (including refund txns):');
  for (const mo of Object.keys(revByMonth).sort()) {
    console.log(`  ${mo}: rev=${revByMonth[mo].toFixed(2)}, ship=${(shipByMonth[mo] || 0).toFixed(2)}`);
  }

  process.exit(0);
})();
