const admin = require("firebase-admin");
const path = require("path");
const https = require("https");
const crypto = require("crypto");

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(
      "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
    ))
  ),
});
const db = admin.firestore();

const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";

function decrypt(encryptedStr, key) {
  const [ivB64, tagB64, dataB64] = encryptedStr.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data).toString("utf8") + decipher.final("utf8");
}

function shopifyGet(shop, token, apiPath) {
  return new Promise((resolve, reject) => {
    const url = `https://${shop}/admin/api/2024-10${apiPath}`;
    console.log("  GET:", url);
    const options = {
      hostname: shop,
      path: `/admin/api/2024-10${apiPath}`,
      headers: {
        "X-Shopify-Access-Token": token,
        "Content-Type": "application/json",
      },
    };
    const req = https.get(options, (res) => {
      console.log("  Status:", res.statusCode);
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => {
        try {
          resolve(JSON.parse(body));
        } catch {
          resolve({ error: body });
        }
      });
    });
    req.on("error", reject);
  });
}

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const connSnap = await db.collection("shopify_connections")
    .where("user_id", "==", uid)
    .limit(1)
    .get();

  const conn = connSnap.docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  console.log("Shop:", shop);
  console.log("Token length:", token.length, "starts:", token.substring(0, 8));

  // Test 1: Basic orders list
  console.log("\n=== Test 1: Basic orders (limit=3) ===");
  const test1 = await shopifyGet(shop, token, "/orders.json?status=any&limit=3");
  if (test1.orders) {
    console.log("  Got", test1.orders.length, "orders");
    test1.orders.forEach(o => console.log(`  #${o.order_number} fs=${o.financial_status} cancel=${o.cancelled_at ? 'yes' : 'no'}`));
  } else {
    console.log("  Error:", JSON.stringify(test1).substring(0, 300));
  }

  // Test 2: Refunded orders
  console.log("\n=== Test 2: Refunded orders ===");
  const test2 = await shopifyGet(shop, token, "/orders.json?status=any&financial_status=refunded&limit=10");
  if (test2.orders) {
    console.log("  Got", test2.orders.length, "refunded orders");
    test2.orders.forEach(o => {
      console.log(`  #${o.order_number} fs=${o.financial_status} refunds=${(o.refunds||[]).length}`);
    });
  } else {
    console.log("  Error:", JSON.stringify(test2).substring(0, 300));
  }

  // Test 3: Partially refunded
  console.log("\n=== Test 3: Partially refunded orders ===");
  const test3 = await shopifyGet(shop, token, "/orders.json?status=any&financial_status=partially_refunded&limit=10");
  if (test3.orders) {
    console.log("  Got", test3.orders.length, "partially refunded orders");
    test3.orders.forEach(o => {
      console.log(`  #${o.order_number} fs=${o.financial_status} refunds=${(o.refunds||[]).length}`);
      (o.refunds || []).forEach(r => {
        const items = r.refund_line_items || [];
        const adjs = r.order_adjustments || [];
        const txns = r.transactions || [];
        let itemTotal = 0;
        items.forEach(i => { itemTotal += (Number(i.subtotal)||0) + (Number(i.total_tax)||0); });
        console.log(`    Refund ${r.id}: items=${items.length} totalFromItems=${itemTotal} txns=${txns.length} adjs=${adjs.length}`);
        txns.forEach(t => console.log(`      txn: kind=${t.kind} amount=${t.amount}`));
        adjs.forEach(a => console.log(`      adj: kind=${a.kind} amount=${a.amount}`));
      });
    });
  } else {
    console.log("  Error:", JSON.stringify(test3).substring(0, 300));
  }

  // Test 4: Check all financial statuses
  console.log("\n=== Test 4: Financial status=any ===");
  const test4 = await shopifyGet(shop, token, "/orders.json?status=any&limit=250&fields=id,order_number,financial_status");
  if (test4.orders) {
    const statusCounts = {};
    test4.orders.forEach(o => {
      statusCounts[o.financial_status] = (statusCounts[o.financial_status] || 0) + 1;
    });
    console.log("  Total orders:", test4.orders.length);
    console.log("  Financial status distribution:", JSON.stringify(statusCounts));
  }

  process.exit(0);
}

main().catch(console.error);
