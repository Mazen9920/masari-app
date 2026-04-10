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

async function main() {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const orderNums = ["19466", "19475", "19493", "19552", "19515", "19478"];

  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();

  for (const num of orderNums) {
    const sale = salesSnap.docs.find(d => String(d.data().shopify_order_number) === num);
    if (!sale) {
      console.log(`#${num}: NOT FOUND`);
      continue;
    }
    const data = sale.data();
    console.log(`#${num}:`);
    console.log(`  doc ID: ${sale.id}`);
    console.log(`  external_order_id: ${data.external_order_id || "NOT SET"}`);
    console.log(`  external_source: ${data.external_source || "NOT SET"}`);
    console.log(`  shopify_order_id: ${data.shopify_order_id || "NOT SET"}`);
    console.log(`  shopify_order_number: ${data.shopify_order_number || "NOT SET"}`);
    console.log(`  order_status: ${data.order_status}`);
    console.log(`  payment_status: ${data.payment_status}`);
    console.log();
  }

  process.exit(0);
}

main().catch(console.error);
