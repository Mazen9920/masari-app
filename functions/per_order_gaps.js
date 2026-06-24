// Deep-dive: identify EXACTLY which orders cause the remaining revenue & shipping gaps
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

  // Load ALL transactions for this user by category
  const [revSnap, shipSnap] = await Promise.all([
    db.collection('transactions')
      .where('user_id', '==', uid)
      .where('category_id', '==', 'cat_sales_revenue')
      .get(),
    db.collection('transactions')
      .where('user_id', '==', uid)
      .where('category_id', '==', 'cat_shipping')
      .get(),
  ]);

  // Group txns by sale_id
  const revBySale = {};
  const revTxnsBySale = {};
  for (const doc of revSnap.docs) {
    const t = doc.data();
    const sid = t.sale_id;
    if (!sid) continue;
    revBySale[sid] = (revBySale[sid] || 0) + (Number(t.amount) || 0);
    if (!revTxnsBySale[sid]) revTxnsBySale[sid] = [];
    revTxnsBySale[sid].push({ id: doc.id, amount: Number(t.amount) || 0 });
  }
  const shipBySale = {};
  for (const doc of shipSnap.docs) {
    const t = doc.data();
    const sid = t.sale_id;
    if (!sid) continue;
    shipBySale[sid] = (shipBySale[sid] || 0) + (Number(t.amount) || 0);
  }

  // For each sale, compare:
  // - Expected net revenue = items subtotal - discount (if not cancelled, full amount; if cancelled, 0)
  // - Actual net revenue from transactions
  // - Expected shipping (if not cancelled; if cancelled, 0)
  // - Actual shipping from transactions
  
  const ORDER_CANCELLED = 4;
  
  const revGaps = [];  // { saleId, orderNum, month, expected, actual, diff }
  const shipGaps = [];
  
  for (const doc of salesSnap.docs) {
    const s = doc.data();
    const saleId = doc.id;
    const date = s.date?.toDate ? s.date.toDate() : new Date(s.date);
    const month = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
    const isCancelled = s.order_status === ORDER_CANCELLED;
    
    const items = s.items || [];
    const subtotal = items.reduce((a, i) => a + (i.quantity || 0) * (i.unit_price || 0), 0);
    const discount = s.discount_amount || 0;
    const expectedRev = isCancelled ? 0 : (subtotal - discount);
    const expectedShip = isCancelled ? 0 : (s.shipping_cost || 0);
    
    const actualRev = revBySale[saleId] || 0;
    const actualShip = shipBySale[saleId] || 0;
    
    const revDiff = actualRev - expectedRev;
    const shipDiff = actualShip - expectedShip;
    
    if (Math.abs(revDiff) > 0.01) {
      revGaps.push({
        saleId, orderNum: s.shopify_order_number, month,
        expected: expectedRev, actual: actualRev, diff: revDiff,
        items: items.length, payStatus: s.payment_status, orderStatus: s.order_status,
        txns: revTxnsBySale[saleId]?.map(t => `${t.id}(${t.amount})`),
      });
    }
    if (Math.abs(shipDiff) > 0.01) {
      shipGaps.push({
        saleId, orderNum: s.shopify_order_number, month,
        expected: expectedShip, actual: actualShip, diff: shipDiff,
        orderStatus: s.order_status,
      });
    }
  }

  console.log(`\n═══ REVENUE GAPS (${revGaps.length} orders) ═══`);
  for (const g of revGaps.sort((a, b) => a.month.localeCompare(b.month))) {
    console.log(`  #${g.orderNum} (${g.saleId}) [${g.month}]: expected=${g.expected.toFixed(2)}, actual=${g.actual.toFixed(2)}, diff=${g.diff.toFixed(2)}, payStatus=${g.payStatus}, orderStatus=${g.orderStatus}`);
    if (g.txns) {
      console.log(`    txns: ${g.txns.join(', ')}`);
    }
  }
  
  const totalRevGap = revGaps.reduce((s, g) => s + g.diff, 0);
  console.log(`  TOTAL revenue gap: ${totalRevGap.toFixed(2)}`);

  console.log(`\n═══ SHIPPING GAPS (${shipGaps.length} orders) ═══`);
  for (const g of shipGaps.sort((a, b) => a.month.localeCompare(b.month))) {
    console.log(`  #${g.orderNum} (${g.saleId}) [${g.month}]: expected=${g.expected.toFixed(2)}, actual=${g.actual.toFixed(2)}, diff=${g.diff.toFixed(2)}, orderStatus=${g.orderStatus}`);
  }
  
  const totalShipGap = shipGaps.reduce((s, g) => s + g.diff, 0);
  console.log(`  TOTAL shipping gap: ${totalShipGap.toFixed(2)}`);

  // Also: check for orders that are NOT in the sales collection but have txns
  console.log('\n═══ ORPHAN TRANSACTIONS (txns without matching sales) ═══');
  const allSaleIds = new Set(salesSnap.docs.map(d => d.id));
  let orphanRev = 0;
  let orphanShip = 0;
  for (const sid of Object.keys(revBySale)) {
    if (!allSaleIds.has(sid)) {
      orphanRev += revBySale[sid];
      console.log(`  REV: sale_id=${sid}, amount=${revBySale[sid].toFixed(2)}`);
    }
  }
  for (const sid of Object.keys(shipBySale)) {
    if (!allSaleIds.has(sid)) {
      orphanShip += shipBySale[sid];
      console.log(`  SHIP: sale_id=${sid}, amount=${shipBySale[sid].toFixed(2)}`);
    }
  }
  console.log(`  Total orphan: rev=${orphanRev.toFixed(2)}, ship=${orphanShip.toFixed(2)}`);

  process.exit(0);
})();
