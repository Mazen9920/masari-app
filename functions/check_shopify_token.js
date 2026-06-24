// Check how shopify token is stored and try to access API
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

const uid = 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  // Check both possible doc locations
  const byId = await db.collection('shopify_connections').doc(uid).get();
  const byQuery = await db.collection('shopify_connections')
    .where('user_id', '==', uid).limit(1).get();

  const doc = byId.exists ? byId : (!byQuery.empty ? byQuery.docs[0] : null);
  if (!doc || !doc.exists) { console.log('No connection'); process.exit(1); }

  const d = doc.data();
  console.log('Doc ID:', doc.id);
  console.log('shop_domain:', d.shop_domain);
  console.log('access_token length:', (d.access_token || '').length);
  console.log('access_token first 10:', (d.access_token || '').substring(0, 10));
  console.log('Has encrypted_token:', !!d.encrypted_token);
  console.log('shop_timezone:', d.shop_timezone);

  // Try direct API call
  const shop = d.shop_domain;
  const token = d.access_token;
  try {
    const resp = await fetch(
      `https://${shop}/admin/api/2024-01/orders/count.json?status=any`,
      { headers: { 'X-Shopify-Access-Token': token } }
    );
    console.log('\nAPI test status:', resp.status);
    const body = await resp.json();
    console.log('Response:', JSON.stringify(body));
  } catch (e) {
    console.log('API error:', e.message);
  }

  process.exit(0);
})();
