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
  const txnsSnap = await db.collection("transactions").where("user_id", "==", uid).get();
  
  // Group revenue txns by month (using date_time)
  const revByMonth = {};
  txnsSnap.docs.forEach(d => {
    const data = d.data();
    if (data.category_id !== "cat_sales_revenue") return;
    let dt;
    if (data.date_time && data.date_time._seconds) {
      dt = new Date(data.date_time._seconds * 1000);
    } else if (data.date_time && typeof data.date_time === "string") {
      dt = new Date(data.date_time);
    } else { return; }
    
    const key = dt.toISOString().substring(0, 7);
    if (!revByMonth[key]) revByMonth[key] = { pos: 0, neg: 0, count: 0 };
    const amt = Number(data.amount) || 0;
    if (amt >= 0) revByMonth[key].pos += amt;
    else revByMonth[key].neg += amt;
    revByMonth[key].count++;
  });
  
  console.log("=== Revvo Revenue by Month (from transactions) ===");
  Object.keys(revByMonth).sort().forEach(k => {
    const m = revByMonth[k];
    console.log(`  ${k}: pos=${round2(m.pos)} neg=${round2(m.neg)} net=${round2(m.pos + m.neg)} txns=${m.count}`);
  });

  // Check: what's the earliest and latest transaction date?
  let minDt = null, maxDt = null;
  txnsSnap.docs.forEach(d => {
    const data = d.data();
    let dt;
    if (data.date_time && data.date_time._seconds) {
      dt = new Date(data.date_time._seconds * 1000);
    } else if (data.date_time && typeof data.date_time === "string") {
      dt = new Date(data.date_time);
    } else { return; }
    if (!minDt || dt < minDt) minDt = dt;
    if (!maxDt || dt > maxDt) maxDt = dt;
  });
  console.log(`\nTransaction date range: ${minDt?.toISOString().substring(0,10)} to ${maxDt?.toISOString().substring(0,10)}`);

  process.exit(0);
}

main().catch(console.error);
