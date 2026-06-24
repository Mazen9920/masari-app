// Check actual sale doc structure for user
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  // Get first 3 sales for the user — inspect fields
  const snap = await db.collection('sales')
    .where('user_id', '==', uid)
    .limit(3)
    .get();

  console.log(`Found ${snap.size} sales`);
  for (const doc of snap.docs) {
    const d = doc.data();
    console.log(`\n--- ${doc.id} ---`);
    console.log('date:', d.date, typeof d.date);
    console.log('date_time:', d.date_time, typeof d.date_time);
    console.log('payment_status:', d.payment_status);
    console.log('order_status:', d.order_status);
    console.log('external_source:', d.external_source);
    console.log('external_order_id:', d.external_order_id);
    console.log('shopify_order_number:', d.shopify_order_number);
    console.log('discount_amount:', d.discount_amount);
    console.log('items count:', (d.items || []).length);
    if (d.items && d.items[0]) {
      console.log('item[0] keys:', Object.keys(d.items[0]).join(', '));
    }
  }
  process.exit(0);
})();
