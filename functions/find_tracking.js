const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp({projectId: "massari-574ff"});
const db = admin.firestore();

// Get any settled shipment using existing index (estimate_recorded + deposited_at)
db.collection("bosta_shipments")
  .where("user_id","==","EGYQnP7ughdUtTbn04UwUET534i1")
  .where("estimate_recorded","==",true)
  .orderBy("deposited_at","desc")
  .limit(3).get()
  .then(s => s.docs.forEach(d => {
    const dd = d.data();
    console.log(d.id, "| tracking:", dd.tracking_number, "| biz_ref:", dd.business_reference, "| fees:", dd.total_fees, "| state:", dd.state);
  }));
