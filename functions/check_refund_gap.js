// Check: Does Revvo have refund transactions? Are historical refunds missing?
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  // Get ALL revenue transactions (cat_sales_revenue)
  const revSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_sales_revenue')
    .get();

  let positiveRev = 0;
  let refundRev = 0;
  let reversalRev = 0;
  let refundCount = 0;
  let reversalCount = 0;
  let positiveCount = 0;

  const byMonth = {};  // month → { positive, refunds, reversals }

  for (const doc of revSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate ? t.date_time.toDate() : null;
    if (!dt) continue;
    const month = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    if (!byMonth[month]) byMonth[month] = { positive: 0, refunds: 0, reversals: 0, net: 0 };

    const amt = Number(t.amount) || 0;
    const id = doc.id;

    if (id.includes('_reversal')) {
      reversalRev += amt;
      reversalCount++;
      byMonth[month].reversals += amt;
    } else if (id.includes('_refund') || amt < 0) {
      refundRev += amt;
      refundCount++;
      byMonth[month].refunds += amt;
    } else {
      positiveRev += amt;
      positiveCount++;
      byMonth[month].positive += amt;
    }
    byMonth[month].net += amt;
  }

  console.log('Revenue Transaction Breakdown:');
  console.log(`  Positive (original sales): ${positiveCount} txns, total: ${positiveRev.toFixed(2)}`);
  console.log(`  Refunds: ${refundCount} txns, total: ${refundRev.toFixed(2)}`);
  console.log(`  Reversals (cancellations): ${reversalCount} txns, total: ${reversalRev.toFixed(2)}`);
  console.log(`  NET TOTAL: ${(positiveRev + refundRev + reversalRev).toFixed(2)}`);

  console.log('\nBy Month:');
  console.log('Month      │ Gross Rev    │ Refunds     │ Reversals   │ Revvo Net');
  console.log('───────────┼──────────────┼─────────────┼─────────────┼──────────');
  for (const m of Object.keys(byMonth).sort()) {
    const d = byMonth[m];
    console.log(`${m}    │ ${d.positive.toFixed(2).padStart(12)} │ ${d.refunds.toFixed(2).padStart(11)} │ ${d.reversals.toFixed(2).padStart(11)} │ ${d.net.toFixed(2).padStart(10)}`);
  }

  // Now check: which sales have refund-related fields in Shopify?
  console.log('\n\nChecking sales with Shopify refund data...');
  const salesSnap = await db.collection('sales')
    .where('user_id', '==', uid)
    .where('external_source', '==', 'shopify')
    .get();

  let salesWithRefundStatus = 0;
  let salesRefundedNotCancelled = 0;
  const refundedSaleIds = [];

  for (const doc of salesSnap.docs) {
    const s = doc.data();
    // payment_status 3 = refunded
    if (s.payment_status === 3) {
      salesWithRefundStatus++;
      if (s.order_status !== 4) {
        salesRefundedNotCancelled++;
        refundedSaleIds.push(doc.id);
      }
    }
  }

  console.log(`Sales with payment_status=refunded: ${salesWithRefundStatus}`);
  console.log(`Refunded but NOT cancelled: ${salesRefundedNotCancelled}`);

  // For each refunded-not-cancelled sale, check if refund txn exists
  console.log('\nRefunded (not cancelled) sales — checking for refund txns:');
  let missingRefundTxns = 0;
  let hasRefundTxns = 0;

  for (const saleId of refundedSaleIds) {
    // Check for any refund transaction for this sale
    const refundTxns = await db.collection('transactions')
      .where('sale_id', '==', saleId)
      .where('category_id', '==', 'cat_sales_revenue')
      .get();

    let hasRefund = false;
    for (const doc of refundTxns.docs) {
      if (doc.id.includes('refund')) {
        hasRefund = true;
        break;
      }
    }

    const saleDoc = await db.doc(`sales/${saleId}`).get();
    const s = saleDoc.data();
    if (!hasRefund) {
      missingRefundTxns++;
      if (missingRefundTxns <= 10) {
        console.log(`  MISSING REFUND TXN: ${saleId} (#${s.shopify_order_number}), rev=${s.items?.reduce((a, i) => a + (i.quantity || 0) * (i.unit_price || 0), 0) - (s.discount_amount || 0)}, status: payment=${s.payment_status}, order=${s.order_status}`);
      }
    } else {
      hasRefundTxns++;
    }
  }
  console.log(`\nWith refund txns: ${hasRefundTxns}`);
  console.log(`Missing refund txns: ${missingRefundTxns}`);

  // Also, check Shopify's raw refund data — do we store it?
  // Check if orders have refunds array in their shopify data
  console.log('\n\nChecking shipping txns breakdown...');
  const shipSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_shipping')
    .get();

  const shipByMonth = {};
  let shipPositive = 0;
  let shipNegative = 0;

  for (const doc of shipSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate ? t.date_time.toDate() : null;
    if (!dt) continue;
    const month = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    if (!shipByMonth[month]) shipByMonth[month] = { positive: 0, negative: 0, net: 0 };

    const amt = Number(t.amount) || 0;
    if (amt >= 0) {
      shipPositive += amt;
      shipByMonth[month].positive += amt;
    } else {
      shipNegative += amt;
      shipByMonth[month].negative += amt;
    }
    shipByMonth[month].net += amt;
  }

  console.log('\nShipping by Month:');
  console.log('Month      │ Collected   │ Reversed    │ Net Ship');
  console.log('───────────┼─────────────┼─────────────┼──────────');
  for (const m of Object.keys(shipByMonth).sort()) {
    const d = shipByMonth[m];
    console.log(`${m}    │ ${d.positive.toFixed(2).padStart(11)} │ ${d.negative.toFixed(2).padStart(11)} │ ${d.net.toFixed(2).padStart(10)}`);
  }

  process.exit(0);
})();
