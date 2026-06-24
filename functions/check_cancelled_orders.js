// Check exactly what transactions exist for the 3 problematic cancelled orders
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const saleIds = [
  '15f9c4cf-a84c-47b9-9c46-748a826fcfad', // #19168
  '5cb622ed-1b4f-4e9c-9dfd-c35e73c55b02', // #19270
  '88996569-f521-4195-bb9c-582c2bce3432', // #19606
];

(async () => {
  for (const saleId of saleIds) {
    console.log(`\n══ Sale: ${saleId} ══`);
    
    // Get sale doc
    const saleDoc = await db.doc(`sales/${saleId}`).get();
    if (saleDoc.exists) {
      const s = saleDoc.data();
      console.log(`  Order: #${s.shopify_order_number}, status: ${s.order_status}, shipping: ${s.shipping_cost}`);
      console.log(`  Date: ${s.date?.toDate?.()?.toISOString()}`);
      console.log(`  external_order_id: ${s.external_order_id}`);
    }

    // Get ALL transactions for this sale
    const txns = await db.collection('transactions')
      .where('sale_id', '==', saleId)
      .get();
    
    console.log(`  Transactions (${txns.size}):`);
    for (const doc of txns.docs) {
      const t = doc.data();
      console.log(`    ${doc.id}: cat=${t.category_id}, amount=${t.amount}, title="${(t.title || '').substring(0, 60)}", exclude=${t.exclude_from_pl}`);
    }

    // Also check for expected reversal IDs directly
    const expectedIds = [
      `sale_rev_${saleId}`,
      `sale_rev_${saleId}_reversal`,
      `sale_cogs_${saleId}`,
      `sale_cogs_${saleId}_reversal`,
      `sale_ship_${saleId}`,
      `sale_ship_${saleId}_reversal`,
    ];
    console.log(`  Direct ID lookup:`);
    for (const id of expectedIds) {
      const doc = await db.doc(`transactions/${id}`).get();
      console.log(`    ${id}: ${doc.exists ? `EXISTS (amount=${doc.data().amount})` : 'MISSING'}`);
    }
  }
  process.exit(0);
})();
