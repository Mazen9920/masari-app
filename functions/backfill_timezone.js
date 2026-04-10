#!/usr/bin/env node
process.env.GOOGLE_APPLICATION_CREDENTIALS =
  "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json";

const admin = require("firebase-admin");
const crypto = require("crypto");
if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();

function decrypt(enc, key) {
  const [iv64, tag64, data64] = enc.split(":");
  const d = crypto.createDecipheriv(
    "aes-256-gcm",
    Buffer.from(key, "hex"),
    Buffer.from(iv64, "base64")
  );
  d.setAuthTag(Buffer.from(tag64, "base64"));
  return d.update(Buffer.from(data64, "base64")).toString("utf8") + d.final("utf8");
}

(async () => {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const doc = await db.collection("shopify_connections").doc(uid).get();
  const data = doc.data();
  console.log("Current shop_timezone:", data.shop_timezone || "(not set)");

  const token = decrypt(data.access_token, process.env.ENCRYPTION_KEY.trim());
  const res = await fetch(
    `https://${data.shop_domain}/admin/api/2024-01/shop.json`,
    {
      headers: {
        "X-Shopify-Access-Token": token,
        "Content-Type": "application/json",
      },
    }
  );
  const shop = await res.json();
  const tz = shop.shop.iana_timezone;
  console.log("Shopify iana_timezone:", tz);

  await db.collection("shopify_connections").doc(uid).update({ shop_timezone: tz });
  console.log("Updated shop_timezone to:", tz);
  process.exit(0);
})();
