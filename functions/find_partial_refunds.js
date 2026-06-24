// Find non-cancelled orders with payment_status=1 (partially_refunded maps to partial=1)
// and check if they have refund transactions
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  const salesSnap = await db.collection('sales')
    .where('user_id', '==', uid)
    .where('external_source', '==', 'shopify')
    .get();

  const revSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_sales_revenue')
    .get();

  // Index refund txns
  const refundBySale = {};
  for (const doc of revSnap.docs) {
    if (doc.id.includes('refund')) {
      const sid = doc.data().sale_id;
      if (!refundBySale[sid]) refundBySale[sid] = [];
      refundBySale[sid].push({ id: doc.id, amount: Number(doc.data().amount) || 0 });
    }
  }

  console.log('Non-cancelled orders with payment_status=1 (could be partially_refunded):\n');
  let count = 0;
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    if (s.order_status === 4) continue;
    if (s.payment_status !== 1) continue;
    
    count++;
    const refunds = refundBySale[doc.id] || [];
    const hasRefund = refunds.length > 0;
    const date = s.date?.toDate?.()?.toISOString()?.slice(0, 10) || '?';
    const items = s.items || [];
    const subtotal = items.reduce((sum, i) => sum + (i.quantity || 0) * (i.unit_price || 0), 0);
    const netRev = subtotal - (s.discount_amount || 0);
    
    console.log(`  #${s.shopify_order_number} (${doc.id}): date=${date}, netRev=${netRev.toFixed(2)}, hasRefundTxn=${hasRefund}, payment_status=${s.payment_status}`);
  }
  console.log(`\nTotal: ${count}`);

  // Also check: ALL non-cancelled orders with ANY payment_status that are NOT cancelled
  // but might have refunds visible on Shopify side  
  console.log('\n\nAll non-cancelled orders grouped by payment_status:');
  const byPS = {};
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    if (s.order_status === 4) continue;
    const ps = s.payment_status;
    byPS[ps] = (byPS[ps] || 0) + 1;
  }
  for (const [ps, count] of Object.entries(byPS)) {
    const label = { 0: 'unpaid', 1: 'partial', 2: 'paid', 3: 'refunded' }[ps] || ps;
    console.log(`  ${label} (${ps}): ${count}`);
  }

  process.exit(0);
})();
