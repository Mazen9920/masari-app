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

function round2(n) { return Math.round(n * 100) / 100; }

function shopifyGet(shop, token, apiPath) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: shop, path: `/admin/api/2024-10${apiPath}`,
      headers: { "X-Shopify-Access-Token": token },
    };
    const req = https.get(options, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => { try { resolve(JSON.parse(body)); } catch { resolve({ error: body }); } });
    });
    req.on("error", reject);
  });
}

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

  // Check specific orders with discrepancies
  const orderNums = [19476, 19487, 19491, 19494, 19506];

  for (const num of orderNums) {
    // Find in Revvo
    const salesSnap = await db.collection("sales")
      .where("user_id", "==", uid)
      .where("shopify_order_number", "==", String(num))
      .limit(1)
      .get();

    if (salesSnap.empty) {
      console.log(`#${num}: NOT IN REVVO`);
      continue;
    }

    const saleData = salesSnap.docs[0].data();
    const saleId = salesSnap.docs[0].id;

    // Get revenue transaction
    const txnSnap = await db.collection("transactions")
      .where("sale_id", "==", saleId)
      .where("category_id", "==", "cat_sales_revenue")
      .get();

    let revvoRevAmount = 0;
    txnSnap.docs.forEach(d => {
      const data = d.data();
      if (!data.exclude_from_pl) revvoRevAmount += data.amount;
    });

    console.log(`\n#${num} (sale: ${saleId}):`);
    console.log(`  Revvo sale discount_amount: ${saleData.discount_amount}`);
    console.log(`  Revvo sale tax_amount: ${saleData.tax_amount}`);
    console.log(`  Revvo sale shipping_cost: ${saleData.shipping_cost}`);
    console.log(`  Revvo items:`, saleData.items.map(i => `${i.quantity}x${i.unit_price} (${i.product_name})`));
    console.log(`  Revvo revenue txn: ${round2(revvoRevAmount)}`);
    console.log(`  Revvo txn IDs:`, txnSnap.docs.map(d => d.id));
  }

  // Now check one via Shopify API
  console.log("\n=== Shopify API data ===");
  for (const num of [19476, 19487]) {
    // Find the Shopify order ID first by searching all orders
    const data = await shopifyGet(shop, token, `/orders.json?status=any&limit=1&name=%23${num}`);
    if (data.orders && data.orders.length > 0) {
      const o = data.orders[0];
      console.log(`\n#${num} Shopify:`);
      console.log(`  subtotal_price: ${o.subtotal_price}`);
      console.log(`  total_discounts: ${o.total_discounts}`);
      console.log(`  total_tax: ${o.total_tax}`);
      console.log(`  total_price: ${o.total_price}`);
      console.log(`  line_items:`, o.line_items.map(li => ({
        qty: li.quantity,
        price: li.price,
        title: li.title,
        discounts: li.discount_allocations,
      })));
    }
  }

  process.exit(0);
}

main().catch(console.error);
