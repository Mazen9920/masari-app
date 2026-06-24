/** Inspect the phantom refund txns: confirm they were created by the migration and have no sale_rev. */
const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const sample = [
  "shopify_EGYQnP7ughdUtTbn04UwUET534i1_7063865622848",
  "shopify_EGYQnP7ughdUtTbn04UwUET534i1_7044805689664",
  "shopify_EGYQnP7ughdUtTbn04UwUET534i1_7042278064448",
];
async function main() {
  for (const sid of sample) {
    console.log(`\n=== ${sid} ===`);
    const revDoc = await db.collection("transactions").doc(`sale_rev_${sid}`).get();
    console.log(`  sale_rev exists: ${revDoc.exists}` + (revDoc.exists ? ` amt=${revDoc.data().amount}` : ""));
    const snap = await db.collection("transactions").where("user_id","==",UID).where("sale_id","==",sid).get();
    snap.docs.forEach(d => {
      const t = d.data();
      console.log(`  [${d.id}] cat=${t.category_id} amt=${t.amount} excl=${t.exclude_from_pl} date=${t.date_time?.toDate?.()?.toISOString?.()} note=${(t.note||t.description||"").slice(0,60)}`);
    });
  }
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
