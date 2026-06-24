// Investigate order #18476 — the last remaining gap
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const saleId = 'shopify_EGYQnP7ughdUtTbn04UwUET534i1_7028869955904';

(async () => {
  // Look at the sale doc
  const saleDoc = await db.doc(`sales/${saleId}`).get();
  if (!saleDoc.exists) { console.log('Sale not found!'); process.exit(1); }
  const s = saleDoc.data();
  
  console.log('=== SALE DOC ===');
  console.log(`  Order #${s.shopify_order_number}`);
  console.log(`  Date: ${s.date?.toDate?.()?.toISOString()}`);
  console.log(`  order_status: ${s.order_status}`);
  console.log(`  payment_status: ${s.payment_status}`);
  console.log(`  external_order_id: ${s.external_order_id}`);
  console.log(`  discount_amount: ${s.discount_amount}`);
  console.log(`  shipping_cost: ${s.shipping_cost}`);
  console.log(`  tax_amount: ${s.tax_amount}`);
  
  // Compute subtotal from items
  const items = s.items || [];
  let subtotal = 0;
  for (const item of items) {
    const qty = item.quantity || 0;
    const price = item.unit_price || 0;
    subtotal += qty * price;
    console.log(`  Item: ${item.product_name || item.variant_name || '?'} × ${qty} @ ${price} = ${qty * price}`);
  }
  console.log(`  Computed subtotal: ${subtotal}`);
  console.log(`  Expected netRev (subtotal - discount): ${subtotal - (s.discount_amount || 0)}`);

  // Look at ALL transactions for this sale
  console.log('\n=== TRANSACTIONS ===');
  const txns = await db.collection('transactions')
    .where('sale_id', '==', saleId)
    .get();
  
  let totalRev = 0;
  let totalShip = 0;
  for (const doc of txns.docs) {
    const t = doc.data();
    console.log(`  ${doc.id}: cat=${t.category_id}, amount=${t.amount}, title="${(t.title || '').substring(0, 80)}"`);
    if (t.category_id === 'cat_sales_revenue') totalRev += Number(t.amount) || 0;
    if (t.category_id === 'cat_shipping') totalShip += Number(t.amount) || 0;
  }
  console.log(`\n  Total revenue txns: ${totalRev}`);
  console.log(`  Total shipping txns: ${totalShip}`);
  console.log(`  Gap: revenue txn (${totalRev}) - expected (${subtotal - (s.discount_amount || 0)}) = ${totalRev - (subtotal - (s.discount_amount || 0))}`);

  process.exit(0);
})();
