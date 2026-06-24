// Quick audit: compare Revvo sale revenue vs Shopify for March 2025
// for user EGYQnP7ughdUtTbn04UwUET534i1
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';
const marchStart = new Date('2026-03-01T00:00:00');
const marchEnd   = new Date('2026-04-01T00:00:00');

// Enum indices from sale_model.dart
const PAY_REFUNDED = 3;
const ORDER_CANCELLED = 4;

(async () => {
  // 1. Get all sales for user (filter date client-side)
  const snap = await db.collection('sales')
    .where('user_id', '==', uid)
    .get();

  let totalRevenue = 0;
  let refundedRevenue = 0;
  let cancelledRevenue = 0;
  let refundedCount = 0;
  let cancelledCount = 0;
  let activeCount = 0;
  let totalCount = 0;

  const refundedOrders = [];

  for (const doc of snap.docs) {
    const d = doc.data();
    // Filter to March
    const date = d.date?.toDate ? d.date.toDate() : new Date(d.date);
    if (date < marchStart || date >= marchEnd) continue;
    totalCount++;

    const items = d.items || [];
    const subtotal = items.reduce((s, i) => s + (i.quantity || 0) * (i.unit_price || 0), 0);
    const discount = d.discount_amount || 0;
    const netRev = subtotal - discount;

    const payStatus = d.payment_status;
    const orderStatus = d.order_status;

    totalRevenue += netRev;

    if (orderStatus === ORDER_CANCELLED) {
      cancelledRevenue += netRev;
      cancelledCount++;
    } else if (payStatus === PAY_REFUNDED) {
      refundedRevenue += netRev;
      refundedCount++;
      refundedOrders.push({
        id: doc.id,
        orderNum: d.shopify_order_number || d.external_order_id,
        netRev: netRev.toFixed(2),
        financialStatus: payStatus,
      });
    } else {
      activeCount++;
    }
  }

  console.log(`\nMarch Sales for ${uid}:`);
  console.log(`Total sales: ${totalCount}`);
  console.log(`Active: ${activeCount}, Refunded: ${refundedCount}, Cancelled: ${cancelledCount}`);
  console.log(`\nTotal netRevenue (all): ${totalRevenue.toFixed(2)}`);
  console.log(`Refunded order revenue: ${refundedRevenue.toFixed(2)}`);
  console.log(`Cancelled order revenue: ${cancelledRevenue.toFixed(2)}`);
  console.log(`Active revenue only: ${(totalRevenue - refundedRevenue - cancelledRevenue).toFixed(2)}`);

  // 2. Check for reversal transactions
  const revSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_sales_revenue')
    .get();

  let posRevenue = 0;
  let negRevenue = 0;
  let reversalCount = 0;
  for (const doc of revSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate ? t.date_time.toDate() : new Date(t.date_time);
    if (dt < marchStart || dt >= marchEnd) continue;
    if (t.amount >= 0) {
      posRevenue += t.amount;
    } else {
      negRevenue += t.amount;
      reversalCount++;
    }
  }

  console.log(`\nRevenue transactions:`);
  console.log(`Positive (sales): ${posRevenue.toFixed(2)}`);
  console.log(`Negative (reversals): ${negRevenue.toFixed(2)}`);
  console.log(`Reversal count: ${reversalCount}`);
  console.log(`Net revenue txns: ${(posRevenue + negRevenue).toFixed(2)}`);
  console.log(`\nGap (pos revenue - active revenue): ${(posRevenue - (totalRevenue - refundedRevenue - cancelledRevenue)).toFixed(2)}`);

  if (refundedOrders.length > 0) {
    console.log(`\nRefunded orders (revenue counted but should have reversals):`);
    for (const o of refundedOrders) {
      // Check if reversal transaction exists
      const revId = `sale_rev_${o.id}_reversal`;
      const revDoc = await db.collection('transactions').doc(revId).get();
      console.log(`  ${o.orderNum}: EGP ${o.netRev} | reversal exists: ${revDoc.exists}`);
    }
  }

  process.exit(0);
})();
