/**
 * Quick debug script to inspect the full wallet/cashCycle response
 * from Bosta's delivery detail API for a specific tracking number.
 *
 * Usage: BOSTA_ENCRYPTION_KEY=<key> node debug_cashcycle.js 87147383
 */
const admin = require("firebase-admin");
const crypto = require("crypto");

if (!admin.apps.length) {
  admin.initializeApp({ projectId: "massari-574ff" });
}
const db = admin.firestore();

const USER_ID = "EGYQnP7ughdUtTbn04UwUET534i1";
const TRACKING = process.argv[2] || "87147383";
const BOSTA_API_BASE = "https://app.bosta.co/api/v2";
const ENCRYPTION_KEY = process.env.BOSTA_ENCRYPTION_KEY || "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";

function decrypt(encrypted, key) {
  const [ivB64, tagB64, dataB64] = encrypted.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data, null, "utf8") + decipher.final("utf8");
}

async function main() {
  // Get encrypted API key from Firestore
  const connDoc = await db.doc(`bosta_connections/${USER_ID}`).get();
  if (!connDoc.exists) { console.error("No connection doc found"); return; }
  const encryptedApiKey = connDoc.data().api_key_encrypted;
  const apiKey = decrypt(encryptedApiKey, ENCRYPTION_KEY);

  // Fetch delivery detail
  const url = `${BOSTA_API_BASE}/deliveries/business/${encodeURIComponent(TRACKING)}`;
  console.log(`Fetching: ${url}\n`);

  const resp = await fetch(url, {
    method: "GET",
    headers: { "Content-Type": "application/json", "Authorization": apiKey },
  });
  const raw = await resp.json();
  const data = raw.data || raw;  // API wraps in { success, data }

  // Print raw top-level keys
  console.log("=== Status:", resp.status, "===");
  console.log("=== Top-level keys ===", Object.keys(data));

  // Print full wallet object
  console.log("\n=== FULL wallet ===");
  console.log(JSON.stringify(data.wallet, null, 2));

  // Check for any payment-related fields at top level
  const paymentFields = ['paymentMethod', 'paymentStatus', 'payment_status', 
    'cashoutStatus', 'cashout_status', 'isPaid', 'is_paid', 'paidAt', 'paid_at',
    'POSDelivery', 'POSReceiptNo', 'shipmentFees'];
  console.log("\n=== Payment-related fields ===");
  for (const f of paymentFields) {
    if (data[f] !== undefined) console.log(`  ${f}:`, JSON.stringify(data[f]));
  }

  // Print any other interesting top-level fields
  console.log("\n=== cod ===", data.cod);
  console.log("=== state ===", data.state?.value, data.state?.code);
  console.log("=== businessReference ===", data.businessReference);
  console.log("=== trackingNumber ===", data.trackingNumber);
}

main().catch(console.error);
