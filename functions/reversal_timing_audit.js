// Check if cancelled March orders have reversals dated outside March
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';
const marchStart = new Date('2026-03-01T00:00:00');
const marchEnd   = new Date('2026-04-01T00:00:00');
const ORDER_CANCELLED = 4;

(async () => {
  // Get all sales
  const salesSnap = await db.collection('sales')
    .where('user_id', '==', uid)
    .get();

  // Get ALL revenue txns (not filtered by date)
  const txnSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_sales_revenue')
    .get();

  // Build maps
  const posBySaleId = {};   // positive revenue by sale_id
  const negBySaleId = {};   // negative (reversal) by sale_id
  const reversalDates = {}; // reversal date by sale_id

  for (const doc of txnSnap.docs) {
    const t = doc.data();
    const saleId = t.sale_id;
    if (!saleId) continue;
    if (t.amount >= 0) {
      posBySaleId[saleId] = (posBySaleId[saleId] || 0) + t.amount;
    } else {
      negBySaleId[saleId] = (negBySaleId[saleId] || 0) + t.amount;
      const dt = t.date_time?.toDate ? t.date_time.toDate() : null;
      if (dt) reversalDates[saleId] = dt;
    }
  }

  // Find March cancelled sales whose positive revenue is in March
  // but reversal is in April+ (or missing)
  let outOfWindowReversals = [];
  let outOfWindowTotal = 0;
  let missingReversals = [];
  let missingTotal = 0;

  for (const doc of salesSnap.docs) {
    const d = doc.data();
    const date = d.date?.toDate ? d.date.toDate() : new Date(d.date);
    if (date < marchStart || date >= marchEnd) continue;
    if (d.order_status !== ORDER_CANCELLED) continue;

    const posRev = posBySaleId[doc.id] || 0;
    if (posRev <= 0) continue; // no revenue txn (imported as cancelled)

    const negRev = negBySaleId[doc.id] || 0;
    const revDate = reversalDates[doc.id];

    if (negRev === 0) {
      // No reversal at all
      missingReversals.push({ id: doc.id, orderNum: d.shopify_order_number, posRev, negRev: 0 });
      missingTotal += posRev;
    } else if (revDate && revDate >= marchEnd) {
      // Reversal exists but dated after March
      outOfWindowReversals.push({
        id: doc.id, orderNum: d.shopify_order_number,
        posRev, negRev, revDate: revDate.toISOString().slice(0, 10),
      });
      outOfWindowTotal += posRev; // net effect: +posRev in March (reversal outside)
    }
  }

  console.log('Cancelled March orders with revenue txns:');
  console.log(`  Missing reversals: ${missingReversals.length}, total: ${missingTotal.toFixed(2)}`);
  for (const o of missingReversals) {
    console.log(`    #${o.orderNum}: ${o.posRev.toFixed(2)}`);
  }

  console.log(`\n  Reversals outside March: ${outOfWindowReversals.length}, total: ${outOfWindowTotal.toFixed(2)}`);
  for (const o of outOfWindowReversals) {
    console.log(`    #${o.orderNum}: rev=${o.posRev.toFixed(2)}, reversal=${o.negRev.toFixed(2)}, reversal date: ${o.revDate}`);
  }

  // Now check: active (non-cancelled) March sales with NO revenue txn (should have one)
  let noRevTxnCount = 0;
  let noRevTxnTotal = 0;
  for (const doc of salesSnap.docs) {
    const d = doc.data();
    const date = d.date?.toDate ? d.date.toDate() : new Date(d.date);
    if (date < marchStart || date >= marchEnd) continue;
    if (d.order_status === ORDER_CANCELLED) continue;

    const posRev = posBySaleId[doc.id] || 0;
    if (posRev <= 0.01) {
      noRevTxnCount++;
      const items = d.items || [];
      const sub = items.reduce((s, i) => s + (i.quantity || 0) * (i.unit_price || 0), 0);
      noRevTxnTotal += sub - (d.discount_amount || 0);
    }
  }
  console.log(`\nActive March sales WITHOUT revenue txn: ${noRevTxnCount}, total netRev: ${noRevTxnTotal.toFixed(2)}`);

  // Summary of March revenue gap
  const marchPosTxns = Object.entries(posBySaleId).reduce((sum, [saleId, amt]) => {
    // Check if this sale is a March sale
    const saleDoc = salesSnap.docs.find(d => d.id === saleId);
    if (!saleDoc) return sum;
    const sd = saleDoc.data();
    const dt = sd.date?.toDate ? sd.date.toDate() : new Date(sd.date);
    if (dt >= marchStart && dt < marchEnd) return sum + amt;
    return sum;
  }, 0);

  const marchNegTxns = Object.entries(negBySaleId).reduce((sum, [saleId, amt]) => {
    const revDate = reversalDates[saleId];
    if (revDate && revDate >= marchStart && revDate < marchEnd) return sum + amt;
    return sum;
  }, 0);

  console.log(`\n--- Summary ---`);
  console.log(`Positive rev txns (March sales): ${marchPosTxns.toFixed(2)}`);
  console.log(`Negative rev txns (March-dated reversals): ${marchNegTxns.toFixed(2)}`);
  console.log(`Displayed March revenue: ${(marchPosTxns + marchNegTxns).toFixed(2)}`);

  process.exit(0);
})();
