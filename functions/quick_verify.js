const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});
const db = admin.firestore();

function round2(n) { return Math.round(n * 100) / 100; }

(async () => {
  const uid = "EGYQnP7ughdUtTbn04UwUET534i1";
  const monthStart = new Date(2026, 3, 1);
  const monthEnd = new Date(2026, 4, 1);

  const txSnap = await db.collection("transactions")
    .where("user_id", "==", uid)
    .get();

  let shipPos = 0, shipNeg = 0, revPos = 0, revNeg = 0;
  txSnap.docs.forEach(d => {
    const data = d.data();
    const dt = data.date_time?.toDate?.() || new Date((data.date_time?._seconds || 0) * 1000);
    if (dt < monthStart || dt >= monthEnd) return;
    const amt = Number(data.amount) || 0;
    if (data.category_id === "cat_shipping") {
      if (amt >= 0) shipPos += amt; else shipNeg += amt;
    }
    if (data.category_id === "cat_sales_revenue") {
      if (amt >= 0) revPos += amt; else revNeg += amt;
    }
  });

  console.log("=== Post-Fix April Numbers ===");
  console.log(`Revenue (+): ${round2(revPos)}`);
  console.log(`Revenue (-): ${round2(revNeg)}`);
  console.log(`Revenue net: ${round2(revPos + revNeg)}`);
  console.log();
  console.log(`Shipping (+): ${round2(shipPos)}`);
  console.log(`Shipping (-): ${round2(shipNeg)}`);
  console.log(`Shipping net: ${round2(shipPos + shipNeg)}`);
  console.log();
  console.log("Cross-month cancel adj: -548");
  console.log(`Shipping adjusted: ${round2(shipPos + shipNeg + 548)}`);
  console.log(`Shopify dashboard:  16656`);
  console.log(`Gap:                ${round2(shipPos + shipNeg + 548 - 16656)}`);

  process.exit(0);
})();
