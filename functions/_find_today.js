/** Find txns created/updated today (the partial apply) vs prior backfill phantoms. */
const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
async function main() {
  const snap = await db.collection("transactions").where("user_id","==",UID).get();
  const todayStart = new Date("2026-06-23T00:00:00Z").getTime();
  let createdToday = [], updatedToday = [], backfillTag = 0;
  snap.docs.forEach(d => {
    const t = d.data();
    const ca = t.created_at?.toDate?.()?.getTime?.();
    const ua = t.updated_at?.toDate?.()?.getTime?.();
    const note = t.note || t.description || "";
    if (note.includes("[backfill]")) backfillTag++;
    if (ca && ca >= todayStart) createdToday.push({ id: d.id, amt: t.amount, cat: t.category_id, note: note.slice(0,50), excl: t.exclude_from_pl });
    if (ua && ua >= todayStart) updatedToday.push({ id: d.id, amt: t.amount, note: note.slice(0,50) });
  });
  console.log(`Total txns with [backfill] tag (prior migration): ${backfillTag}`);
  console.log(`\n=== Created TODAY (partial apply): ${createdToday.length} ===`);
  createdToday.slice(0,60).forEach(t => console.log(`  + [${t.id}] ${t.cat} amt=${t.amt} excl=${t.excl} note=${t.note}`));
  console.log(`\n=== Updated TODAY (partial apply): ${updatedToday.length} ===`);
  updatedToday.slice(0,60).forEach(t => console.log(`  ~ [${t.id}] amt=${t.amt} note=${t.note}`));
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
