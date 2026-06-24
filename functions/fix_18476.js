// Fix order #18476 revenue: discount wasn't deducted in old webhook version
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const txnId = 'sale_rev_shopify_EGYQnP7ughdUtTbn04UwUET534i1_7028869955904';

(async () => {
  const doc = await db.doc(`transactions/${txnId}`).get();
  if (!doc.exists) { console.log('NOT FOUND'); process.exit(1); }
  console.log('Current amount:', doc.data().amount);
  // subtotal 2773 - discount 125 = 2648
  await db.doc(`transactions/${txnId}`).update({
    amount: 2648,
    updated_at: admin.firestore.Timestamp.now(),
  });
  console.log('Updated to 2648 (applied 125 discount)');
  process.exit(0);
})();
