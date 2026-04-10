const https = require("https");
const crypto = require("crypto");
const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});
const db = admin.firestore();
const EK = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";

function decrypt(e, k) {
  const [i, t, d] = e.split(":");
  const kb = Buffer.from(k, "hex");
  const iv = Buffer.from(i, "base64");
  const tg = Buffer.from(t, "base64");
  const dt = Buffer.from(d, "base64");
  const dc = crypto.createDecipheriv("aes-256-gcm", kb, iv);
  dc.setAuthTag(tg);
  return dc.update(dt).toString("utf8") + dc.final("utf8");
}

function shopifyGet(shop, token, apiPath) {
  return new Promise((resolve, reject) => {
    https.get(
      { hostname: shop, path: `/admin/api/2024-10${apiPath}`, headers: { "X-Shopify-Access-Token": token } },
      (res) => { let b = ""; res.on("data", (c) => (b += c)); res.on("end", () => { try { resolve(JSON.parse(b)); } catch { resolve({ error: b }); } }); }
    ).on("error", reject);
  });
}

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, EK);

  // Fetch all orders and find by order_number
  const allOrders = [];
  let since_id = 0;
  while (true) {
    const data = await shopifyGet(shop, token, `/orders.json?status=any&limit=250&since_id=${since_id}`);
    if (!data.orders || data.orders.length === 0) break;
    allOrders.push(...data.orders);
    since_id = data.orders[data.orders.length - 1].id;
    if (data.orders.length < 250) break;
    await new Promise(r => setTimeout(r, 500));
  }
  console.log("Total orders fetched:", allOrders.length);

  const nums = [19476, 19487, 19491, 19494];
  for (const num of nums) {
    const o = allOrders.find(o => o.order_number === num);
    if (o) {
      console.log(`\n#${num} Shopify:`);
      console.log(`  subtotal_price: ${o.subtotal_price}`);
      console.log(`  total_discounts: ${o.total_discounts}`);
      console.log(`  total_tax: ${o.total_tax}`);
      console.log(`  total_price: ${o.total_price}`);
      console.log(`  line_items:`);
      for (const li of o.line_items) {
        console.log(`    ${li.quantity}x ${li.title} price=${li.price} disc_allocs=${JSON.stringify(li.discount_allocations)}`);
      }
      console.log(`  discount_codes:`, JSON.stringify(o.discount_codes));
    } else {
      console.log(`#${num}: not found in ${allOrders.length} orders`);
    }
  }

  process.exit(0);
}

main().catch(console.error);
