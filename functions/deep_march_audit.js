// Deep audit: find partially refunded orders + missing reversals
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';
const marchStart = new Date('2026-03-01T00:00:00');
const marchEnd   = new Date('2026-04-01T00:00:00');

// Enum indices
const PAY_UNPAID = 0, PAY_PARTIAL = 1, PAY_PAID = 2, PAY_REFUNDED = 3;
const ORD_CANCELLED = 4;

(async () => {
  const snap = await db.collection('sales')
    .where('user_id', '==', uid)
    .get();

  // Collect March sales by category
  const buckets = { paid: [], partial: [], refunded: [], unpaid: [], cancelled: [] };
  const marchSales = [];

  for (const doc of snap.docs) {
    const d = doc.data();
    const date = d.date?.toDate ? d.date.toDate() : new Date(d.date);
    if (date < marchStart || date >= marchEnd) continue;

    const items = d.items || [];
    const subtotal = items.reduce((s, i) => s + (i.quantity || 0) * (i.unit_price || 0), 0);
    const discount = d.discount_amount || 0;
    const netRev = subtotal - discount;

    const info = { id: doc.id, orderNum: d.shopify_order_number, netRev, payStatus: d.payment_status, orderStatus: d.order_status };
    marchSales.push(info);

    if (d.order_status === ORD_CANCELLED) buckets.cancelled.push(info);
    else if (d.payment_status === PAY_REFUNDED) buckets.refunded.push(info);
    else if (d.payment_status === PAY_PARTIAL) buckets.partial.push(info);
    else if (d.payment_status === PAY_PAID) buckets.paid.push(info);
    else buckets.unpaid.push(info);
  }

  const sum = arr => arr.reduce((s, o) => s + o.netRev, 0);
  console.log('March Sales Breakdown:');
  console.log(`  Paid (${buckets.paid.length}): ${sum(buckets.paid).toFixed(2)}`);
  console.log(`  Partial payment (${buckets.partial.length}): ${sum(buckets.partial).toFixed(2)}`);
  console.log(`  Refunded (${buckets.refunded.length}): ${sum(buckets.refunded).toFixed(2)}`);
  console.log(`  Unpaid (${buckets.unpaid.length}): ${sum(buckets.unpaid).toFixed(2)}`);
  console.log(`  Cancelled (${buckets.cancelled.length}): ${sum(buckets.cancelled).toFixed(2)}`);

  // For each sale, check if revenue + reversal txns exist
  let missingReversals = [];
  let extraRevenue = 0;

  // Check all revenue transactions in March
  const txnSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_sales_revenue')
    .get();

  const revBySaleId = {};
  for (const doc of txnSnap.docs) {
    const t = doc.data();
    const saleId = t.sale_id;
    if (!saleId) continue;
    if (!revBySaleId[saleId]) revBySaleId[saleId] = { pos: 0, neg: 0 };
    if (t.amount >= 0) revBySaleId[saleId].pos += t.amount;
    else revBySaleId[saleId].neg += t.amount;
  }

  // Find cancelled March sales with positive revenue but no/insufficient reversal
  for (const sale of buckets.cancelled) {
    const rev = revBySaleId[sale.id];
    if (rev && rev.pos > 0) {
      const net = rev.pos + rev.neg;
      if (net > 0.01) {
        missingReversals.push({ ...sale, revPos: rev.pos.toFixed(2), revNeg: rev.neg.toFixed(2), revNet: net.toFixed(2) });
        extraRevenue += net;
      }
    }
  }

  console.log(`\nCancelled orders with unreversed revenue: ${missingReversals.length}`);
  console.log(`Total unreversed revenue: ${extraRevenue.toFixed(2)}`);
  if (missingReversals.length > 0) {
    console.log('First 10:');
    for (const o of missingReversals.slice(0, 10)) {
      console.log(`  #${o.orderNum} (${o.id}): rev=${o.revPos}, reversal=${o.revNeg}, net=${o.revNet}`);
    }
  }

  // Also check if any "active" (paid) orders have refund amounts in their Shopify refunds field
  // by checking if there exist partial refund txns
  const refundTxnSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .get();

  let partialRefundRevenue = 0;
  let refundTxnCount = 0;
  for (const doc of refundTxnSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate ? t.date_time.toDate() : null;
    if (!dt || dt < marchStart || dt >= marchEnd) continue;
    if (doc.id.includes('_refund_') && t.category_id === 'cat_sales_revenue') {
      partialRefundRevenue += t.amount;
      refundTxnCount++;
    }
  }
  console.log(`\nRefund transactions in March: ${refundTxnCount}, total: ${partialRefundRevenue.toFixed(2)}`);

  // Summary: what Revvo net revenue SHOULD be
  const activeRev = sum(buckets.paid) + sum(buckets.partial) + sum(buckets.unpaid);
  console.log(`\nShould-be net revenue (active only): ${activeRev.toFixed(2)}`);
  console.log(`Extra from unreversed cancellations: ${extraRevenue.toFixed(2)}`);
  console.log(`Likely Revvo total: ${(activeRev + extraRevenue).toFixed(2)}`);

  process.exit(0);
})();
