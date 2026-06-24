// Check for duplicate Shopify orders + revenue txn mismatches
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';
const marchStart = new Date('2026-03-01T00:00:00');
const marchEnd   = new Date('2026-04-01T00:00:00');

(async () => {
  const snap = await db.collection('sales')
    .where('user_id', '==', uid)
    .get();

  // Group March sales by external_order_id
  const byOrderId = {};
  let marchCount = 0;

  for (const doc of snap.docs) {
    const d = doc.data();
    const date = d.date?.toDate ? d.date.toDate() : new Date(d.date);
    if (date < marchStart || date >= marchEnd) continue;
    marchCount++;

    const extId = d.external_order_id;
    if (!extId) continue;
    if (!byOrderId[extId]) byOrderId[extId] = [];
    byOrderId[extId].push({
      saleId: doc.id,
      orderNum: d.shopify_order_number,
      idFormat: doc.id.startsWith('shopify_') ? 'deterministic' : 'uuid',
    });
  }

  // Find duplicates
  const dupes = Object.entries(byOrderId).filter(([, arr]) => arr.length > 1);
  console.log(`March sales: ${marchCount}`);
  console.log(`Unique Shopify orders: ${Object.keys(byOrderId).length}`);
  console.log(`Duplicate orders: ${dupes.length}`);
  if (dupes.length > 0) {
    console.log('\nFirst 10 duplicates:');
    for (const [extId, arr] of dupes.slice(0, 10)) {
      console.log(`  Order ${arr[0].orderNum} (${extId}): ${arr.length} copies`);
      for (const s of arr) {
        console.log(`    ${s.saleId} (${s.idFormat})`);
      }
    }
  }

  // Also check: how many sales use deterministic vs UUID IDs
  let deterministicCount = 0;
  let uuidCount = 0;
  for (const [, arr] of Object.entries(byOrderId)) {
    for (const s of arr) {
      if (s.idFormat === 'deterministic') deterministicCount++;
      else uuidCount++;
    }
  }
  console.log(`\nSale ID format: deterministic=${deterministicCount}, UUID=${uuidCount}`);

  // Check netRevenue mismatch: compute from items vs revenue txn amount
  console.log('\n--- Revenue Txn vs Computed Net Revenue (sample) ---');
  const txnSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_sales_revenue')
    .get();

  const revenueByTxnId = {};
  for (const doc of txnSnap.docs) {
    const t = doc.data();
    if (t.amount > 0 && t.sale_id) {
      revenueByTxnId[t.sale_id] = (revenueByTxnId[t.sale_id] || 0) + t.amount;
    }
  }

  // Compare for 5 March paid sales
  let mismatchCount = 0;
  let totalMismatch = 0;
  let checkedCount = 0;
  for (const doc of snap.docs) {
    const d = doc.data();
    const date = d.date?.toDate ? d.date.toDate() : new Date(d.date);
    if (date < marchStart || date >= marchEnd) continue;
    if (d.order_status === 4) continue; // skip cancelled

    const items = d.items || [];
    const subtotal = items.reduce((s, i) => s + (i.quantity || 0) * (i.unit_price || 0), 0);
    const discount = d.discount_amount || 0;
    const computedNetRev = subtotal - discount;
    const txnRevenue = revenueByTxnId[doc.id] || 0;

    if (Math.abs(computedNetRev - txnRevenue) > 0.01) {
      mismatchCount++;
      totalMismatch += (txnRevenue - computedNetRev);
      if (mismatchCount <= 5) {
        console.log(`  #${d.shopify_order_number} (${doc.id}): computed=${computedNetRev.toFixed(2)}, txn=${txnRevenue.toFixed(2)}, diff=${(txnRevenue - computedNetRev).toFixed(2)}`);
      }
    }
    checkedCount++;
  }
  console.log(`\nChecked ${checkedCount} active sales:`);
  console.log(`  Mismatches: ${mismatchCount}`);
  console.log(`  Total mismatch amount: ${totalMismatch.toFixed(2)}`);

  process.exit(0);
})();
