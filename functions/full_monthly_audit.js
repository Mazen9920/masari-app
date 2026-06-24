// Full monthly comparison: Revvo vs Shopify (via shopifyProxy CF)
// Computes Revvo numbers from Firestore, then calls the deployed CF to get Shopify numbers.
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  // ══════════════════════════════════════════════════════════
  //  PART 1: REVVO NUMBERS (from transactions)
  // ══════════════════════════════════════════════════════════
  console.log('Loading Revvo transactions...');
  
  const revSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_sales_revenue')
    .get();

  const shipSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_shipping')
    .get();

  // Bucket by month
  const revvoRevenue = {};  // YYYY-MM → net revenue
  const revvoShipping = {}; // YYYY-MM → net shipping

  for (const doc of revSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate ? t.date_time.toDate() : null;
    if (!dt) continue;
    const month = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    revvoRevenue[month] = (revvoRevenue[month] || 0) + (Number(t.amount) || 0);
  }

  for (const doc of shipSnap.docs) {
    const t = doc.data();
    const dt = t.date_time?.toDate ? t.date_time.toDate() : null;
    if (!dt) continue;
    const month = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, '0')}`;
    revvoShipping[month] = (revvoShipping[month] || 0) + (Number(t.amount) || 0);
  }

  // ══════════════════════════════════════════════════════════
  //  PART 2: SHOPIFY NUMBERS (from orders in Firestore sales)
  //  Recompute what Shopify's net revenue should be from our
  //  imported order data
  // ══════════════════════════════════════════════════════════
  console.log('Loading sales...');
  
  const salesSnap = await db.collection('sales')
    .where('user_id', '==', uid)
    .get();

  const ORDER_CANCELLED = 4;
  const shopifyRevenue = {};  // what revenue SHOULD be per month
  const shopifyShipping = {}; // what shipping SHOULD be per month
  const saleDetails = {};     // sale_id → { month, netRev, shipping, cancelled }

  for (const doc of salesSnap.docs) {
    const d = doc.data();
    if (d.external_source !== 'shopify') continue;

    const date = d.date?.toDate ? d.date.toDate() : new Date(d.date);
    const month = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;

    const items = d.items || [];
    const subtotal = items.reduce((s, i) => s + (i.quantity || 0) * (i.unit_price || 0), 0);
    const discount = d.discount_amount || 0;
    const netRev = subtotal - discount;
    const shipping = d.shipping_cost || 0;
    const isCancelled = d.order_status === ORDER_CANCELLED;

    saleDetails[doc.id] = { month, netRev, shipping, isCancelled, orderNum: d.shopify_order_number };

    if (!isCancelled) {
      shopifyRevenue[month] = (shopifyRevenue[month] || 0) + netRev;
      shopifyShipping[month] = (shopifyShipping[month] || 0) + shipping;
    }
  }

  // ══════════════════════════════════════════════════════════
  //  PART 3: COMPARE
  // ══════════════════════════════════════════════════════════
  const allMonths = new Set([
    ...Object.keys(revvoRevenue),
    ...Object.keys(shopifyRevenue),
    ...Object.keys(revvoShipping),
    ...Object.keys(shopifyShipping),
  ]);
  const sorted = [...allMonths].sort();

  console.log('\n═══════════════════════════════════════════════════');
  console.log('Month       │ Expected Rev  │ Revvo Rev     │ Rev Gap    │ Expected Ship │ Revvo Ship    │ Ship Gap');
  console.log('────────────┼───────────────┼───────────────┼────────────┼───────────────┼───────────────┼──────────');
  
  let totalRevGap = 0;
  let totalShipGap = 0;
  
  for (const m of sorted) {
    const expRev = shopifyRevenue[m] || 0;
    const actRev = revvoRevenue[m] || 0;
    const revGap = actRev - expRev;
    
    const expShip = shopifyShipping[m] || 0;
    const actShip = revvoShipping[m] || 0;
    const shipGap = actShip - expShip;

    totalRevGap += revGap;
    totalShipGap += shipGap;

    const flag = (Math.abs(revGap) > 1 || Math.abs(shipGap) > 1) ? ' ⚠️' : '';
    console.log(
      `${m}    │ ${expRev.toFixed(2).padStart(13)} │ ${actRev.toFixed(2).padStart(13)} │ ${revGap.toFixed(2).padStart(10)} │ ${expShip.toFixed(2).padStart(13)} │ ${actShip.toFixed(2).padStart(13)} │ ${shipGap.toFixed(2).padStart(8)}${flag}`
    );
  }
  console.log('────────────┼───────────────┼───────────────┼────────────┼───────────────┼───────────────┼──────────');
  console.log(
    `TOTAL       │               │               │ ${totalRevGap.toFixed(2).padStart(10)} │               │               │ ${totalShipGap.toFixed(2).padStart(8)}`
  );

  // ══════════════════════════════════════════════════════════
  //  PART 4: DIAGNOSE THE GAP — find which sales have wrong txns
  // ══════════════════════════════════════════════════════════
  // Check: any sale missing revenue txn? any sale with wrong amount?
  console.log('\n\n═══════════════════════════════════════════════════');
  console.log('DIAGNOSIS');
  console.log('═══════════════════════════════════════════════════\n');
  
  // Load ALL revenue + shipping txns keyed by sale_id
  const revBySale = {};
  for (const doc of revSnap.docs) {
    const t = doc.data();
    if (!t.sale_id) continue;
    revBySale[t.sale_id] = (revBySale[t.sale_id] || 0) + (Number(t.amount) || 0);
  }
  const shipBySale = {};
  for (const doc of shipSnap.docs) {
    const t = doc.data();
    if (!t.sale_id) continue;
    shipBySale[t.sale_id] = (shipBySale[t.sale_id] || 0) + (Number(t.amount) || 0);
  }

  let missingRevTxn = 0;
  let missingShipTxn = 0;
  let wrongRevAmount = 0;
  let wrongShipAmount = 0;
  let totalRevDiff = 0;
  let totalShipDiff = 0;
  
  const wrongRevSamples = [];
  const wrongShipSamples = [];

  for (const [saleId, info] of Object.entries(saleDetails)) {
    if (info.isCancelled) {
      // Cancelled: net revenue txn should be 0 (original + reversal)
      const netRev = revBySale[saleId] || 0;
      if (Math.abs(netRev) > 0.01) {
        wrongRevAmount++;
        totalRevDiff += netRev;
      }
      continue;
    }

    // Active sale: should have revenue txn equal to netRev
    const actualRev = revBySale[saleId];
    if (actualRev === undefined) {
      missingRevTxn++;
      totalRevDiff -= info.netRev;
    } else if (Math.abs(actualRev - info.netRev) > 0.01) {
      wrongRevAmount++;
      totalRevDiff += (actualRev - info.netRev);
      if (wrongRevSamples.length < 5) {
        wrongRevSamples.push({ saleId, orderNum: info.orderNum, expected: info.netRev, actual: actualRev });
      }
    }

    // Shipping: should have shipping txn equal to shipping
    if (info.shipping > 0) {
      const actualShip = shipBySale[saleId];
      if (actualShip === undefined) {
        missingShipTxn++;
        totalShipDiff -= info.shipping;
      } else if (Math.abs(actualShip - info.shipping) > 0.01) {
        wrongShipAmount++;
        totalShipDiff += (actualShip - info.shipping);
        if (wrongShipSamples.length < 5) {
          wrongShipSamples.push({ saleId, orderNum: info.orderNum, expected: info.shipping, actual: actualShip });
        }
      }
    } else {
      // No shipping expected, but check if a txn exists anyway
      const actualShip = shipBySale[saleId] || 0;
      if (Math.abs(actualShip) > 0.01) {
        wrongShipAmount++;
        totalShipDiff += actualShip;
      }
    }
  }

  console.log('Revenue issues:');
  console.log(`  Missing revenue txns: ${missingRevTxn}`);
  console.log(`  Wrong revenue amounts: ${wrongRevAmount}`);
  console.log(`  Total revenue diff: ${totalRevDiff.toFixed(2)}`);
  if (wrongRevSamples.length > 0) {
    console.log('  Samples:');
    for (const s of wrongRevSamples) {
      console.log(`    #${s.orderNum} (${s.saleId}): expected=${s.expected.toFixed(2)}, actual=${s.actual.toFixed(2)}, diff=${(s.actual - s.expected).toFixed(2)}`);
    }
  }

  console.log('\nShipping issues:');
  console.log(`  Missing shipping txns: ${missingShipTxn}`);
  console.log(`  Wrong shipping amounts: ${wrongShipAmount}`);
  console.log(`  Total shipping diff: ${totalShipDiff.toFixed(2)}`);
  if (wrongShipSamples.length > 0) {
    console.log('  Samples:');
    for (const s of wrongShipSamples) {
      console.log(`    #${s.orderNum} (${s.saleId}): expected=${s.expected.toFixed(2)}, actual=${s.actual.toFixed(2)}, diff=${(s.actual - s.expected).toFixed(2)}`);
    }
  }

  // Check: cancelled orders that still have unreversed amounts
  let unreversedCancelled = 0;
  let unreversedTotal = 0;
  for (const [saleId, info] of Object.entries(saleDetails)) {
    if (!info.isCancelled) continue;
    const netRev = revBySale[saleId] || 0;
    if (netRev > 0.01) {
      unreversedCancelled++;
      unreversedTotal += netRev;
    }
  }
  console.log(`\nCancelled orders with unreversed revenue: ${unreversedCancelled}, total: ${unreversedTotal.toFixed(2)}`);

  process.exit(0);
})();
