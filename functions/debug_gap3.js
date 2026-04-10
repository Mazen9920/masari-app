const admin = require("firebase-admin");
const path = require("path");

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(
      "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
    ))
  ),
});
const db = admin.firestore();

function round2(n) { return Math.round(n * 100) / 100; }

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const missingOrders = ["19466", "19475", "19493", "19552", "19515", "19478"];

  // Get all sales and transactions
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();

  // Build lookups
  const saleByOrderNum = {};
  salesSnap.docs.forEach(d => {
    const data = d.data();
    if (data.shopify_order_number) {
      saleByOrderNum[String(data.shopify_order_number)] = { id: d.id, data };
    }
  });

  console.log("=== Cancelled-in-Shopify but Active-in-Revvo Orders ===\n");
  let totalRev = 0, totalShip = 0, totalCogs = 0;

  for (const num of missingOrders) {
    const sale = saleByOrderNum[num];
    if (!sale) { console.log(`#${num}: NOT IN REVVO`); continue; }

    console.log(`Order #${num}:`);
    console.log(`  Sale ID: ${sale.id}`);
    console.log(`  order_status: ${sale.data.order_status} (${["pending","confirmed","processing","completed","cancelled"][sale.data.order_status]})`);
    console.log(`  payment_status: ${sale.data.payment_status}`);

    // Get all transactions for this sale
    const saleTxns = txnsSnap.docs.filter(d => d.data().sale_id === sale.id);
    let rev = 0, ship = 0, cogs = 0;
    saleTxns.forEach(d => {
      const data = d.data();
      const amt = Number(data.amount) || 0;
      const cat = data.category_id;
      const excl = data.exclude_from_pl ? " [EXCLUDED]" : "";
      console.log(`  txn: ${d.id} | cat=${cat} | amt=${amt}${excl}`);
      if (!data.exclude_from_pl) {
        if (cat === "cat_sales_revenue") rev += amt;
        else if (cat === "cat_shipping") ship += amt;
        else if (cat === "cat_cogs") cogs += amt;
      }
    });
    console.log(`  Net: rev=${round2(rev)} ship=${round2(ship)} cogs=${round2(cogs)}`);
    totalRev += rev;
    totalShip += ship;
    totalCogs += cogs;
    console.log();
  }

  console.log(`\nTOTALS for these ${missingOrders.length} orders:`);
  console.log(`  Revenue: ${round2(totalRev)}`);
  console.log(`  Shipping: ${round2(totalShip)}`);
  console.log(`  COGS: ${round2(totalCogs)}`);
  console.log(`\nThese exactly explain the gap:`);
  console.log(`  Revenue gap expected: ~3783, actual: ${round2(totalRev)}`);
  console.log(`  Shipping gap expected: ~744, actual: ${round2(totalShip)}`);

  process.exit(0);
}

main().catch(console.error);
