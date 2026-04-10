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
  const salesSnap = await db.collection("sales").where("user_id", "==", uid).get();
  
  let earliest = null;
  let earliestNum = null;
  let latest = null;
  let latestNum = null;
  let total = 0;
  
  salesSnap.docs.forEach(d => {
    const data = d.data();
    const num = Number(data.shopify_order_number || data.order_number || 0);
    if (!num) return;
    total++;
    
    let dt;
    if (data.date_time && data.date_time._seconds) {
      dt = new Date(data.date_time._seconds * 1000);
    } else if (data.created_at && data.created_at._seconds) {
      dt = new Date(data.created_at._seconds * 1000);
    }
    
    if (!earliest || num < earliestNum) {
      earliest = dt;
      earliestNum = num;
    }
    if (!latest || num > latestNum) {
      latest = dt;
      latestNum = num;
    }
  });
  
  console.log(`Total Revvo sales: ${total}`);
  console.log(`Earliest order: #${earliestNum} date=${earliest ? earliest.toISOString().substring(0,10) : "?"}`);
  console.log(`Latest order: #${latestNum} date=${latest ? latest.toISOString().substring(0,10) : "?"}`);

  // Count by month
  const byMonth = {};
  salesSnap.docs.forEach(d => {
    const data = d.data();
    let dt;
    if (data.date_time && data.date_time._seconds) {
      dt = new Date(data.date_time._seconds * 1000);
    } else if (data.created_at && data.created_at._seconds) {
      dt = new Date(data.created_at._seconds * 1000);
    }
    if (!dt) return;
    const key = dt.toISOString().substring(0, 7);
    byMonth[key] = (byMonth[key] || 0) + 1;
  });
  console.log("\nOrders by month:");
  Object.keys(byMonth).sort().forEach(k => console.log(`  ${k}: ${byMonth[k]}`));

  process.exit(0);
}

main().catch(console.error);
