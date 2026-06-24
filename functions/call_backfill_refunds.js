// Call the backfillShopifyRefunds CF using Firebase Admin + custom token
const admin = require('firebase-admin');
if (!admin.apps.length) admin.initializeApp();

const uid = process.argv[2] || 'EGYQnP7ughdUtTbn04UwUET534i1';

(async () => {
  // Create custom token for the user
  const customToken = await admin.auth().createCustomToken(uid);
  
  // Exchange for ID token via Firebase Auth REST API
  const apiKey = 'AIzaSyAFVWnGbHrYL9SGYisMNGZD7UjjyaRknrE'; // Firebase web API key
  const resp = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${apiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        token: customToken,
        returnSecureToken: true,
      }),
    }
  );
  
  if (!resp.ok) {
    const err = await resp.text();
    console.error('Failed to get ID token:', err);
    process.exit(1);
  }
  
  const { idToken } = await resp.json();
  console.log('Got ID token, calling backfillShopifyRefunds...');
  
  // Call the CF
  const cfResp = await fetch(
    'https://us-central1-massari-574ff.cloudfunctions.net/backfillShopifyRefunds',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${idToken}`,
      },
      body: JSON.stringify({
        data: { uid },
      }),
    }
  );
  
  const result = await cfResp.json();
  console.log('Result:', JSON.stringify(result, null, 2));
  
  process.exit(0);
})();
