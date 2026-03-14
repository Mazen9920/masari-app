// Migration: Create shipping expense transactions (cat_shipping) for existing sales with shipping_cost > 0
// Uses Firestore REST API and Firebase CLI token

const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch');

const PROJECT_ID = 'massari-574ff';

// Get Firebase CLI token from config
function getFirebaseToken() {
  const cfgPath = path.join(process.env.HOME, '.config/configstore/firebase-tools.json');
  const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  const token = cfg.tokens?.access_token;
  if (!token) throw new Error('No access_token found in firebase-tools.json');
  return token;
}

const BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

async function getAllUsers(token) {
  const url = `${BASE}/users?pageSize=1000`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const data = await res.json();
  return (data.documents || []).map(doc => doc.name.split('/').pop());
}

async function getSalesForUser(token, userId) {
  const url = `${BASE}/users/${userId}/sales?pageSize=1000`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  const data = await res.json();
  return data.documents || [];
}

async function getTxn(token, userId, txnId) {
  const url = `${BASE}/users/${userId}/transactions/${txnId}`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (res.status === 200) return await res.json();
  return null;
}

async function createTxn(token, userId, txnId, txn) {
  const url = `${BASE}/users/${userId}/transactions?documentId=${txnId}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ fields: txn })
  });
  if (!res.ok) throw new Error(`Failed to create txn: ${res.status} ${await res.text()}`);
}

function toFirestoreFields(obj) {
  // Converts JS object to Firestore REST API fields
  const wrap = v =>
    typeof v === 'string' ? { stringValue: v } :
    typeof v === 'number' ? { doubleValue: v } :
    v instanceof Date ? { timestampValue: v.toISOString() } :
    typeof v === 'boolean' ? { booleanValue: v } :
    v && v._seconds ? { timestampValue: new Date(v._seconds * 1000).toISOString() } :
    { stringValue: String(v) };
  const out = {};
  for (const k in obj) out[k] = wrap(obj[k]);
  return out;
}

(async () => {
  const token = getFirebaseToken();
  let totalCreated = 0;
  const users = await getAllUsers(token);
  for (const userId of users) {
    const sales = await getSalesForUser(token, userId);
    for (const saleDoc of sales) {
      const sale = saleDoc.fields;
      const saleId = saleDoc.name.split('/').pop();
      const shippingCost = sale.shipping_cost?.doubleValue || sale.shipping_cost?.integerValue || 0;
      if (shippingCost <= 0) continue;
      const txnId = `sale_ship_${saleId}`;
      const existing = await getTxn(token, userId, txnId);
      if (existing) continue;
      // Compose title
      let title = 'Shipping — Sale';
      if (sale.shopify_order_number?.stringValue) {
        title = `Shipping — #${sale.shopify_order_number.stringValue} — Shopify`;
      } else if (sale.customer_name?.stringValue) {
        title = `Shipping — ${sale.customer_name.stringValue}`;
      }
      const now = new Date();
      const dateTime = sale.date_time?.timestampValue || sale.date?.timestampValue || now.toISOString();
      const txn = toFirestoreFields({
        id: txnId,
        user_id: userId,
        title,
        amount: -Math.abs(Number(shippingCost)),
        date_time: dateTime,
        category_id: 'cat_shipping',
        note: 'Auto-generated shipping expense (migration)',
        sale_id: saleId,
        created_at: now,
        updated_at: now,
      });
      await createTxn(token, userId, txnId, txn);
      totalCreated++;
      console.log(`Created ${txnId} for user ${userId}`);
    }
  }
  console.log(`\nDone. Created ${totalCreated} shipping expense transactions.`);
})();
