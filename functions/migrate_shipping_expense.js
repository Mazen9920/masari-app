#!/usr/bin/env node
/**
 * Migration: Create shipping expense transactions (cat_shipping)
 * for existing sales that have shipping_cost > 0 but no sale_ship_ txn.
 */
const admin = require("firebase-admin");
const {Firestore} = require("@google-cloud/firestore");
const {execSync} = require("child_process");

const PROJECT_ID = "massari-574ff";

// Get a fresh access token using the Firebase CLI refresh token
function getFreshToken() {
  const fs = require("fs");
  const path = require("path");
  const https = require("https");
  const cfgPath = path.join(process.env.HOME, ".config/configstore/firebase-tools.json");
  const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
  const refreshToken = cfg.tokens?.refresh_token;
  if (!refreshToken) throw new Error("No refresh token in firebase-tools.json");
  return refreshToken;
}

async function refreshAccessToken(refreshToken) {
  // Firebase CLI OAuth client ID/secret (from firebase-tools source)
  const clientId = "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
  const clientSecret = "j9iVZfS8kkCEFUPaAeJV0sAi";

  const postData = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    refresh_token: refreshToken,
    grant_type: "refresh_token",
  }).toString();

  return new Promise((resolve, reject) => {
    const req = require("https").request({
      hostname: "oauth2.googleapis.com",
      path: "/token",
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "Content-Length": Buffer.byteLength(postData),
      },
    }, (res) => {
      let data = "";
      res.on("data", (chunk) => data += chunk);
      res.on("end", () => {
        const parsed = JSON.parse(data);
        if (parsed.access_token) resolve(parsed.access_token);
        else reject(new Error(`Token refresh failed: ${data}`));
      });
    });
    req.on("error", reject);
    req.write(postData);
    req.end();
  });
}

async function main() {
  const refreshToken = getFreshToken();
  const accessToken = await refreshAccessToken(refreshToken);
  const db = new Firestore({projectId: PROJECT_ID, host: "firestore.googleapis.com", ssl: true, customHeaders: {Authorization: `Bearer ${accessToken}`}});

  // Get all users
  const usersSnap = await db.collection("users").get();
  let totalCreated = 0;

  for (const userDoc of usersSnap.docs) {
    const userId = userDoc.id;
    const salesSnap = await db
      .collection("users")
      .doc(userId)
      .collection("sales")
      .get();

    for (const saleDoc of salesSnap.docs) {
      const sale = saleDoc.data();
      const shippingCost = Number(sale.shipping_cost) || 0;
      if (shippingCost <= 0) continue;

      const saleId = saleDoc.id;
      const shipTxnId = `sale_ship_${saleId}`;
      const txnRef = db
        .collection("users")
        .doc(userId)
        .collection("transactions")
        .doc(shipTxnId);

      const existing = await txnRef.get();
      if (existing.exists) {
        console.log(`  SKIP ${shipTxnId} (already exists)`);
        continue;
      }

      // Determine title
      const orderNum = sale.shopify_order_number;
      const customerName = sale.customer_name;
      let title;
      if (orderNum) {
        title = `Shipping — #${orderNum} — Shopify`;
      } else if (customerName) {
        title = `Shipping — ${customerName}`;
      } else {
        title = "Shipping — Sale";
      }

      const now = Firestore.Timestamp.now();
      const dateTime = sale.date || sale.date_time || now;

      await txnRef.set({
        id: shipTxnId,
        user_id: userId,
        title,
        amount: -shippingCost,
        date_time: dateTime,
        category_id: "cat_shipping",
        note: "Auto-generated shipping expense (migration)",
        sale_id: saleId,
        created_at: now,
        updated_at: now,
      });

      totalCreated++;
      console.log(
        `  CREATED ${shipTxnId} => -${shippingCost} for user ${userId}`
      );
    }
  }

  console.log(`\nDone. Created ${totalCreated} shipping expense transactions.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
