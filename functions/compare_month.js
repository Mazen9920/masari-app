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
  const conn = (await db.collection("shopify_connections").where("user_id", "==", uid).limit(1).get()).docs[0].data();
  const shop = conn.shop_domain;
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);

  // Fetch ALL Shopify orders
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

  // Get Revvo data
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();

  // Build Revvo maps
  const revvoSalesByOrderNum = {};
  salesSnap.docs.forEach(d => {
    const data = d.data();
    const num = data.shopify_order_number;
    if (num) revvoSalesByOrderNum[String(num)] = { id: d.id, data };
  });

  // Get month to analyze (default: latest order's month)
  // Usage: node compare_month.js [YYYY-MM] e.g. node compare_month.js 2026-03
  let monthStart, monthEnd;
  const monthArg = process.argv[2];
  if (monthArg && /^\d{4}-\d{2}$/.test(monthArg)) {
    const [year, month] = monthArg.split("-").map(Number);
    monthStart = new Date(year, month - 1, 1);
    monthEnd = new Date(year, month, 1);
  } else {
    const latestDate = new Date(allOrders[allOrders.length - 1].created_at);
    console.log("Latest Shopify order date:", latestDate.toISOString());
    monthStart = new Date(latestDate.getFullYear(), latestDate.getMonth(), 1);
    monthEnd = new Date(latestDate.getFullYear(), latestDate.getMonth() + 1, 1);
  }
  console.log(`Analyzing: ${monthStart.toISOString().substring(0,10)} to ${monthEnd.toISOString().substring(0,10)}`);

  // This month from Shopify
  const tmOrders = allOrders.filter(o => {
    const d = new Date(o.created_at);
    return d >= monthStart && d < monthEnd;
  });
  console.log(`\nShopify this month: ${tmOrders.length} orders`);

  const tmActive = tmOrders.filter(o => !o.cancelled_at);
  const tmCancelled = tmOrders.filter(o => !!o.cancelled_at);
  console.log(`  Active: ${tmActive.length}, Cancelled: ${tmCancelled.length}`);

  // Shopify revenue breakdown (active only)
  let shopifyTotalPrice = 0;
  let shopifySubtotal = 0;
  let shopifyShipping = 0;
  let shopifyTax = 0;
  let shopifyDiscount = 0;
  let shopifyGrossLineItems = 0;

  tmActive.forEach(o => {
    shopifyTotalPrice += Number(o.total_price) || 0;
    shopifySubtotal += Number(o.subtotal_price) || 0;
    // Use discounted_price for shipping (net of shipping discounts)
    shopifyShipping += (o.shipping_lines || []).reduce((s, l) => s + (Number(l.discounted_price ?? l.price) || 0), 0);
    shopifyTax += Number(o.total_tax) || 0;
    shopifyDiscount += Number(o.total_discounts) || 0;
    shopifyGrossLineItems += (o.line_items || []).reduce((s, li) => s + (Number(li.quantity) || 0) * (Number(li.price) || 0), 0);
  });

  console.log(`\n=== Shopify Active Orders (This Month) ===`);
  console.log(`  Gross line items (qty*price):    ${round2(shopifyGrossLineItems)}`);
  console.log(`  subtotal_price (= gross-disc):   ${round2(shopifySubtotal)}`);
  console.log(`  Shipping: ${round2(shopifyShipping)}`);
  console.log(`  Tax: ${round2(shopifyTax)}`);
  console.log(`  Discounts: ${round2(shopifyDiscount)}`);
  console.log(`  Total price: ${round2(shopifyTotalPrice)}`);
  console.log(`  Revenue (gross - discounts): ${round2(shopifyGrossLineItems - shopifyDiscount)}`);
  console.log(`  Revenue (subtotal_price, already net of discounts): ${round2(shopifySubtotal)}`);

  // Revvo P&L for same month
  let revvoRevPlus = 0, revvoRevMinus = 0;
  let revvoShipPlus = 0, revvoShipMinus = 0;
  let revvoCOGS = 0;

  txnsSnap.docs.forEach(d => {
    const data = d.data();
    if (data.exclude_from_pl) return;

    // Get date
    let dt;
    if (data.date_time && data.date_time._seconds) {
      dt = new Date(data.date_time._seconds * 1000);
    } else if (data.date_time && typeof data.date_time === "string") {
      dt = new Date(data.date_time);
    } else {
      return;
    }
    if (dt < monthStart || dt >= monthEnd) return;

    const amount = Number(data.amount) || 0;
    const cat = data.category_id;

    if (cat === "cat_sales_revenue") {
      if (amount >= 0) revvoRevPlus += amount;
      else revvoRevMinus += amount;
    } else if (cat === "cat_shipping") {
      if (amount >= 0) revvoShipPlus += amount;
      else revvoShipMinus += amount;
    } else if (cat === "cat_cogs") {
      revvoCOGS += amount;
    }
  });

  console.log(`\n=== Revvo Transactions (This Month) ===`);
  console.log(`  Revenue (+): ${round2(revvoRevPlus)}`);
  console.log(`  Revenue (-): ${round2(revvoRevMinus)}`);
  console.log(`  Revenue net: ${round2(revvoRevPlus + revvoRevMinus)}`);
  console.log(`  Shipping (+): ${round2(revvoShipPlus)}`);
  console.log(`  Shipping (-): ${round2(revvoShipMinus)}`);
  console.log(`  Shipping net: ${round2(revvoShipPlus + revvoShipMinus)}`);
  console.log(`  COGS: ${round2(revvoCOGS)}`);

  // Compare
  // Revvo: netRevenue = sum(qty*unitPrice) - productDiscount (excludes shipping disc)
  // Shopify: equivalent = sum(qty*line_item_price) - productDiscount
  // shipping discount must be separated from total_discounts
  let shopifyShippingDiscount = 0;
  tmActive.forEach(o => {
    (o.shipping_lines || []).forEach(sl => {
      const gross = Number(sl.price) || 0;
      const net = Number(sl.discounted_price ?? sl.price) || 0;
      shopifyShippingDiscount += (gross - net);
    });
  });
  shopifyShippingDiscount = round2(shopifyShippingDiscount);
  const shopifyProductDiscount = round2(shopifyDiscount - shopifyShippingDiscount);
  // Note: subtotal_price = gross - discounts (same number but Shopify-rounded)
  const shopifyRevenue = round2(shopifyGrossLineItems - shopifyProductDiscount);
  console.log(`\n=== COMPARISON ===`);
  console.log(`  Shopify Revenue (gross-disc):      ${shopifyRevenue}`);
  console.log(`  Revvo Revenue net:                 ${round2(revvoRevPlus + revvoRevMinus)}`);
  console.log(`  Gap:                               ${round2((revvoRevPlus + revvoRevMinus) - shopifyRevenue)}`);
  console.log();
  console.log(`  Shopify Shipping:                  ${round2(shopifyShipping)}`);
  console.log(`  Revvo Shipping net:                ${round2(revvoShipPlus + revvoShipMinus)}`);
  console.log(`  Gap:                               ${round2((revvoShipPlus + revvoShipMinus) - shopifyShipping)}`);
  console.log();
  console.log(`  Shopify Total:                     ${round2(shopifyTotalPrice)}`);
  console.log(`  Revvo Total:                       ${round2((revvoRevPlus + revvoRevMinus) + (revvoShipPlus + revvoShipMinus))}`);
  console.log(`  Gap:                               ${round2(((revvoRevPlus + revvoRevMinus) + (revvoShipPlus + revvoShipMinus)) - shopifyTotalPrice)}`);

  // Cross-month cancellation adjustment
  // Orders created BEFORE this month but cancelled IN this month:
  // Their reversals are in this month's Revvo P&L but Shopify excludes them entirely.
  // Orders created IN this month but cancelled IN A LATER month:
  // Their positive revenue is in this month's Revvo P&L and their reversals are NOT.
  // Shopify also excludes them (no revenue and no reversal).
  let crossMonthCancelledInRev = 0;
  let crossMonthCancelledInShip = 0;
  let cancelledFromThisMonthRev = 0;
  let cancelledFromThisMonthShip = 0;

  allOrders.forEach(o => {
    if (!o.cancelled_at) return;
    const created = new Date(o.created_at);
    const cancelled = new Date(o.cancelled_at);
    const gross = (o.line_items || []).reduce((s, li) => s + (Number(li.quantity) || 0) * (Number(li.price) || 0), 0);
    const disc = Number(o.total_discounts) || 0;
    const shipDisc = (o.shipping_lines || []).reduce((s, sl) => {
      const g = Number(sl.price) || 0;
      const n = Number(sl.discounted_price ?? sl.price) || 0;
      return s + (g - n);
    }, 0);
    const rev = round2(gross - disc + shipDisc);
    const ship = (o.shipping_lines || []).reduce((s, l) => s + (Number(l.discounted_price ?? l.price) || 0), 0);

    // Created before this month, cancelled in this month → reversal in this month, no positive
    if (created < monthStart && cancelled >= monthStart && cancelled < monthEnd) {
      crossMonthCancelledInRev += rev;
      crossMonthCancelledInShip += ship;
    }
    // Created in this month, cancelled after this month → positive in this month, no reversal
    if (created >= monthStart && created < monthEnd && cancelled >= monthEnd) {
      cancelledFromThisMonthRev += rev;
      cancelledFromThisMonthShip += ship;
    }
  });

  console.log(`\n=== Cross-Month Cancellation Adjustment ===`);
  console.log(`  Orders created BEFORE month, cancelled IN month (reversals-only):`);
  console.log(`    Revenue: -${round2(crossMonthCancelledInRev)}, Shipping: -${round2(crossMonthCancelledInShip)}`);
  console.log(`  Orders created IN month, cancelled AFTER month (positives-only, no reversal yet):`);
  console.log(`    Revenue: +${round2(cancelledFromThisMonthRev)}, Shipping: +${round2(cancelledFromThisMonthShip)}`);

  const adjustedShopifyRevenue = round2(shopifyRevenue - crossMonthCancelledInRev + cancelledFromThisMonthRev);
  const adjustedShopifyShipping = round2(shopifyShipping - crossMonthCancelledInShip + cancelledFromThisMonthShip);
  const revvoNetRev = round2(revvoRevPlus + revvoRevMinus);
  const revvoNetShip = round2(revvoShipPlus + revvoShipMinus);

  console.log(`\n=== ADJUSTED COMPARISON (Accrual Accounting) ===`);
  console.log(`  Shopify Revenue (adjusted):        ${adjustedShopifyRevenue}`);
  console.log(`  Revvo Revenue net:                 ${revvoNetRev}`);
  console.log(`  Gap:                               ${round2(revvoNetRev - adjustedShopifyRevenue)}`);
  console.log();
  console.log(`  Shopify Shipping (adjusted):       ${adjustedShopifyShipping}`);
  console.log(`  Revvo Shipping net:                ${revvoNetShip}`);
  console.log(`  Gap:                               ${round2(revvoNetShip - adjustedShopifyShipping)}`);

  // Check: any Shopify active orders this month NOT in Revvo?
  console.log("\n=== Missing Active Orders This Month ===");
  let missingCount = 0;
  let missingTotal = 0;
  tmActive.forEach(o => {
    const num = String(o.order_number);
    if (!revvoSalesByOrderNum[num]) {
      missingCount++;
      missingTotal += Number(o.total_price) || 0;
      console.log(`  #${num} total=${o.total_price} date=${o.created_at.substring(0, 10)}`);
    }
  });
  console.log(`Missing: ${missingCount} orders, total=${round2(missingTotal)}`);

  // Order-by-order comparison for this month
  console.log("\n=== Per-Order Comparison (revenue only, first 20 with differences) ===");
  let diffCount = 0;
  for (const order of tmActive) {
    if (diffCount >= 20) break;
    const num = String(order.order_number);
    const sale = revvoSalesByOrderNum[num];
    if (!sale) continue;

    // subtotal_price is already net of discounts (= gross_items - total_discounts)
    // Revvo calculates revenue the same way: sum(qty*price) - discountAmount
    // BUT we need to use the same formula as Revvo: sum(qty * line.price) - total_discounts
    // since subtotal_price rounds differently than summing line items
    const grossItems = (order.line_items || []).reduce((s, li) => s + (Number(li.quantity) || 0) * (Number(li.price) || 0), 0);
    const disc = Number(order.total_discounts) || 0;
    // Separate shipping discount from product discount
    let orderShipDisc = 0;
    (order.shipping_lines || []).forEach(sl => {
      const g = Number(sl.price) || 0;
      const n = Number(sl.discounted_price ?? sl.price) || 0;
      orderShipDisc += (g - n);
    });
    const shopifyRev = round2(grossItems - (disc - orderShipDisc));
    const shopifyShip = round2((order.shipping_lines || []).reduce((s, l) => s + (Number(l.discounted_price ?? l.price) || 0), 0));

    // Find matching transactions
    const saleTxns = txnsSnap.docs.filter(d => d.data().sale_id === sale.id);
    let revRev = 0, revShip = 0;
    saleTxns.forEach(d => {
      const data = d.data();
      if (data.exclude_from_pl) return;
      const amt = Number(data.amount) || 0;
      if (data.category_id === "cat_sales_revenue") revRev += amt;
      else if (data.category_id === "cat_shipping") revShip += amt;
    });

    const revDiff = round2(revRev - shopifyRev);
    const shipDiff = round2(revShip - shopifyShip);
    if (Math.abs(revDiff) > 0.01 || Math.abs(shipDiff) > 0.01) {
      diffCount++;
      console.log(`  #${num}: shopRev=${shopifyRev} revvoRev=${round2(revRev)} diff=${revDiff} | shopShip=${shopifyShip} revvoShip=${round2(revShip)} diff=${shipDiff}`);
    }
  }
  if (diffCount === 0) {
    console.log("  All matching orders have identical revenue!");
  }

  process.exit(0);
}

main().catch(console.error);
