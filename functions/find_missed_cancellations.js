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
      hostname: shop,
      path: `/admin/api/2024-10${apiPath}`,
      headers: { "X-Shopify-Access-Token": token },
    };
    const req = https.get(options, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => {
        try { resolve(JSON.parse(body)); }
        catch { resolve({ error: body }); }
      });
    });
    req.on("error", reject);
  });
}
async function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";

  // Load ALL Shopify orders
  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

  const allOrders = [];
  let since_id = 0;
  while (true) {
    const data = await shopifyGet(shop, token, `/orders.json?status=any&limit=250&since_id=${since_id}`);
    if (!data.orders || data.orders.length === 0) break;
    allOrders.push(...data.orders);
    since_id = data.orders[data.orders.length - 1].id;
    if (data.orders.length < 250) break;
    await sleep(500);
  }

  // Shopify cancelled orders with their cancel_reason
  const shopifyCancelled = {};
  allOrders.forEach(o => {
    if (o.cancelled_at) {
      shopifyCancelled[String(o.order_number)] = {
        cancel_reason: o.cancel_reason,
        cancelled_at: o.cancelled_at,
        financial_status: o.financial_status,
        id: o.id,
      };
    }
  });
  console.log(`Total Shopify cancelled: ${Object.keys(shopifyCancelled).length}`);

  // Load ALL Revvo sales
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();

  // Find Revvo sales that are NOT cancelled but Shopify says cancelled
  let totalRevenue = 0;
  let totalShipping = 0;
  let totalCogs = 0;
  const affected = [];

  salesSnap.docs.forEach(d => {
    const data = d.data();
    const orderNum = String(data.shopify_order_number || "");
    if (!orderNum || !shopifyCancelled[orderNum]) return;

    // Check if Revvo thinks it's NOT cancelled
    if (data.order_status !== 4) {
      const shopData = shopifyCancelled[orderNum];
      
      // Find transactions for this sale
      const saleTxns = txnsSnap.docs.filter(td => td.data().sale_id === d.id);
      let rev = 0, ship = 0, cogs = 0;
      saleTxns.forEach(td => {
        const tdata = td.data();
        if (tdata.exclude_from_pl) return;
        const amt = Number(tdata.amount) || 0;
        if (tdata.category_id === "cat_sales_revenue") rev += amt;
        else if (tdata.category_id === "cat_shipping") ship += amt;
        else if (tdata.category_id === "cat_cogs") cogs += amt;
      });

      // Check if there's already a reversal
      const hasReversal = saleTxns.some(td => td.id.includes("_reversal"));

      affected.push({
        orderNum,
        saleId: d.id,
        revvoStatus: data.order_status,
        shopifyReason: shopData.cancel_reason,
        cancelledAt: shopData.cancelled_at,
        rev: round2(rev),
        ship: round2(ship),
        cogs: round2(cogs),
        hasReversal,
      });

      totalRevenue += rev;
      totalShipping += ship;
      totalCogs += cogs;
    }
  });

  console.log(`\n=== Cancelled in Shopify but NOT in Revvo ===`);
  console.log(`Count: ${affected.length}`);
  affected.sort((a, b) => a.orderNum.localeCompare(b.orderNum));
  affected.forEach(a => {
    console.log(`  #${a.orderNum} | saleId=${a.saleId} | revvoStatus=${a.revvoStatus} | reason=${a.shopifyReason} | cancelledAt=${a.cancelledAt.substring(0,10)} | rev=${a.rev} ship=${a.ship} cogs=${a.cogs} | reversal=${a.hasReversal}`);
  });
  console.log(`\nTotals:`);
  console.log(`  Revenue: ${round2(totalRevenue)}`);
  console.log(`  Shipping: ${round2(totalShipping)}`);
  console.log(`  COGS: ${round2(totalCogs)}`);

  // Also check cancel_reason distribution
  const reasonCounts = {};
  Object.values(shopifyCancelled).forEach(o => {
    const reason = o.cancel_reason || "null";
    reasonCounts[reason] = (reasonCounts[reason] || 0) + 1;
  });
  console.log(`\nShopify cancel_reason distribution:`);
  Object.entries(reasonCounts).sort((a, b) => b[1] - a[1]).forEach(([r, c]) => {
    console.log(`  ${r}: ${c}`);
  });

  process.exit(0);
}

main().catch(console.error);
