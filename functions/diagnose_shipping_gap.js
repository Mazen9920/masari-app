// Diagnose shipping gap: find cancelled orders with unreversed shipping
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  // Load all shipping txns
  const shipSnap = await db.collection('transactions')
    .where('user_id', '==', uid)
    .where('category_id', '==', 'cat_shipping')
    .get();

  // Load all sales
  const salesSnap = await db.collection('sales')
    .where('user_id', '==', uid)
    .get();

  const ORDER_CANCELLED = 4;
  const cancelledSales = new Map();
  const activeSales = new Map();
  
  for (const doc of salesSnap.docs) {
    const d = doc.data();
    if (d.external_source !== 'shopify') continue;
    const info = {
      id: doc.id,
      orderNum: d.shopify_order_number,
      shipping: d.shipping_cost || 0,
      isCancelled: d.order_status === ORDER_CANCELLED,
      date: d.date?.toDate ? d.date.toDate() : new Date(d.date),
    };
    if (info.isCancelled) {
      cancelledSales.set(doc.id, info);
    } else {
      activeSales.set(doc.id, info);
    }
  }

  // Group shipping txns by sale_id
  const shipBySale = {};
  const shipTxns = {};
  for (const doc of shipSnap.docs) {
    const t = doc.data();
    const sid = t.sale_id;
    if (!sid) continue;
    if (!shipBySale[sid]) shipBySale[sid] = 0;
    shipBySale[sid] += Number(t.amount) || 0;
    if (!shipTxns[sid]) shipTxns[sid] = [];
    shipTxns[sid].push({ docId: doc.id, amount: Number(t.amount) || 0, type: t.type, description: t.description?.substring(0, 60) });
  }

  // Check cancelled orders
  console.log('CANCELLED ORDERS WITH NON-ZERO SHIPPING NET:\n');
  let totalUnreversedShip = 0;
  let count = 0;
  
  for (const [saleId, info] of cancelledSales) {
    const net = shipBySale[saleId] || 0;
    if (Math.abs(net) > 0.01) {
      count++;
      totalUnreversedShip += net;
      console.log(`  #${info.orderNum} (${saleId}): shipping=${info.shipping}, txn net=${net.toFixed(2)}, date=${info.date.toISOString().slice(0,10)}`);
      const txns = shipTxns[saleId] || [];
      for (const txn of txns) {
        console.log(`    - ${txn.amount.toFixed(2)} | ${txn.type || ''} | ${txn.description || ''}`);
      }
    }
  }
  console.log(`\nTotal cancelled orders with shipping gap: ${count}`);
  console.log(`Total unreversed shipping from cancelled orders: ${totalUnreversedShip.toFixed(2)}`);

  // Check active orders with wrong shipping amount
  console.log('\n\nACTIVE ORDERS WITH WRONG SHIPPING AMOUNT:\n');
  let wrongShipCount = 0;
  let wrongShipTotal = 0;
  
  for (const [saleId, info] of activeSales) {
    const actual = shipBySale[saleId] || 0;
    if (info.shipping > 0 && Math.abs(actual - info.shipping) > 0.01) {
      wrongShipCount++;
      wrongShipTotal += (actual - info.shipping);
      console.log(`  #${info.orderNum} (${saleId}): expected=${info.shipping}, actual=${actual.toFixed(2)}, diff=${(actual - info.shipping).toFixed(2)}`);
      const txns = shipTxns[saleId] || [];
      for (const txn of txns) {
        console.log(`    - ${txn.amount.toFixed(2)} | ${txn.type || ''} | ${txn.description || ''}`);
      }
    }
  }
  console.log(`\nWrong shipping count: ${wrongShipCount}, total diff: ${wrongShipTotal.toFixed(2)}`);

  // Check: shipping txns not linked to any sale
  console.log('\n\nORPHAN SHIPPING TXNS (no matching sale or non-shopify):');
  let orphanTotal = 0;
  let orphanCount = 0;
  for (const doc of shipSnap.docs) {
    const t = doc.data();
    const sid = t.sale_id;
    if (!sid || (!cancelledSales.has(sid) && !activeSales.has(sid))) {
      orphanCount++;
      orphanTotal += Number(t.amount) || 0;
      if (orphanCount <= 10) {
        console.log(`  ${doc.id}: sale_id=${sid || 'NULL'}, amount=${t.amount}, desc=${(t.description || '').substring(0, 60)}`);
      }
    }
  }
  console.log(`Orphan shipping txns: ${orphanCount}, total: ${orphanTotal.toFixed(2)}`);

  // Also: check refunded orders — do refunds affect shipping?
  console.log('\n\nREFUNDED SALES CHECK:');
  const PAYMENT_REFUNDED = 3;
  for (const [saleId, info] of activeSales) {
    // Check if there's a refund-related shipping txn
    const txns = shipTxns[saleId] || [];
    if (txns.length > 1) {
      console.log(`  #${info.orderNum} (${saleId}): ${txns.length} shipping txns, net=${(shipBySale[saleId] || 0).toFixed(2)}`);
      for (const txn of txns) {
        console.log(`    - ${txn.amount.toFixed(2)} | ${txn.docId}`);
      }
    }
  }

  process.exit(0);
})();
