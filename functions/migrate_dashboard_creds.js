/**
 * Migration: Store encrypted Bosta dashboard credentials.
 *
 * One-time script to encrypt and store the Bosta Dashboard
 * email/password in the user's bosta_connections document.
 * These credentials are needed for the /wallet/cashouts API
 * (requires dashboard login token, not the business API key).
 *
 * Usage:
 *   node migrate_dashboard_creds.js          # dry run
 *   node migrate_dashboard_creds.js --commit # apply changes
 */

const admin = require("firebase-admin");
const crypto = require("crypto");
const serviceAccount = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// ── Configuration ──────────────────────────────────────────

const TARGET_USER_ID = "EGYQnP7ughdUtTbn04UwUET534i1";
const DASHBOARD_EMAIL = "mazenappl99@gmail.com";
const DASHBOARD_PASSWORD = "ZA.za.05";

// Same key used for Bosta API key encryption (SHOPIFY_TOKEN_ENCRYPTION_KEY)
const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";

// ── Encryption (mirrors functions/src/shopify-auth.ts) ────

function encrypt(text, key) {
  const keyBuf = Buffer.from(key, "hex");
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", keyBuf, iv);
  const encrypted = Buffer.concat([
    cipher.update(text, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();
  return [
    iv.toString("base64"),
    tag.toString("base64"),
    encrypted.toString("base64"),
  ].join(":");
}

// ── Migration ──────────────────────────────────────────────

async function migrate() {
  const commit = process.argv.includes("--commit");
  console.log(commit ? "=== COMMIT MODE ===" : "=== DRY RUN (add --commit to apply) ===\n");

  // Check that connection doc exists
  const connRef = db.collection("bosta_connections").doc(TARGET_USER_ID);
  const connDoc = await connRef.get();

  if (!connDoc.exists) {
    console.error(`ERROR: No bosta_connections doc for user ${TARGET_USER_ID}`);
    process.exit(1);
  }

  const connData = connDoc.data();
  console.log(`Found bosta_connections for user ${TARGET_USER_ID}`);
  console.log(`  status: ${connData.status}`);
  console.log(`  has api_key_encrypted: ${!!connData.api_key_encrypted}`);
  console.log(`  has dashboard_email_encrypted: ${!!connData.dashboard_email_encrypted}`);
  console.log();

  if (connData.dashboard_email_encrypted) {
    console.log("WARNING: Dashboard credentials already exist. They will be overwritten.");
    console.log();
  }

  // Encrypt credentials
  const encryptedEmail = encrypt(DASHBOARD_EMAIL, ENCRYPTION_KEY);
  const encryptedPassword = encrypt(DASHBOARD_PASSWORD, ENCRYPTION_KEY);

  console.log(`Email to encrypt: ${DASHBOARD_EMAIL}`);
  console.log(`Encrypted email: ${encryptedEmail.substring(0, 30)}...`);
  console.log(`Encrypted password: ${encryptedPassword.substring(0, 30)}...`);
  console.log();

  // Verify encryption round-trip
  const decryptFn = (encStr, key) => {
    const [ivB64, tagB64, dataB64] = encStr.split(":");
    const keyBuf = Buffer.from(key, "hex");
    const iv = Buffer.from(ivB64, "base64");
    const tag = Buffer.from(tagB64, "base64");
    const data = Buffer.from(dataB64, "base64");
    const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
    decipher.setAuthTag(tag);
    return decipher.update(data).toString("utf8") + decipher.final("utf8");
  };

  const decryptedEmail = decryptFn(encryptedEmail, ENCRYPTION_KEY);
  const decryptedPassword = decryptFn(encryptedPassword, ENCRYPTION_KEY);

  if (decryptedEmail !== DASHBOARD_EMAIL || decryptedPassword !== DASHBOARD_PASSWORD) {
    console.error("ERROR: Encryption round-trip failed!");
    process.exit(1);
  }
  console.log("Encryption round-trip verified OK\n");

  // Test login with these credentials
  console.log("Testing Bosta dashboard login...");
  const loginRes = await fetch("https://app.bosta.co/api/v0/users/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: DASHBOARD_EMAIL, password: DASHBOARD_PASSWORD }),
  });

  if (!loginRes.ok) {
    const body = await loginRes.text().catch(() => "");
    console.error(`ERROR: Bosta login failed (${loginRes.status}): ${body.substring(0, 200)}`);
    process.exit(1);
  }

  const loginJson = await loginRes.json();
  const token = loginJson.data?.token || loginJson.token;
  if (token) {
    console.log(`Login OK — token starts with: ${token.substring(0, 30)}...`);
  } else {
    console.error("ERROR: Login succeeded but no token in response");
    process.exit(1);
  }
  console.log();

  // Apply update
  const updateData = {
    dashboard_email_encrypted: encryptedEmail,
    dashboard_password_encrypted: encryptedPassword,
    dashboard_status: "active",
    dashboard_status_updated_at: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (commit) {
    await connRef.update(updateData);
    console.log("Dashboard credentials written to Firestore.");
  } else {
    console.log("Would write to Firestore:");
    console.log(JSON.stringify({
      dashboard_email_encrypted: `${encryptedEmail.substring(0, 30)}...`,
      dashboard_password_encrypted: `${encryptedPassword.substring(0, 30)}...`,
      dashboard_status: "active",
      dashboard_status_updated_at: "SERVER_TIMESTAMP",
    }, null, 2));
  }

  console.log("\nDone.");
}

migrate().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
