const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp({ credential: admin.credential.cert(require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const COMMIT = process.argv.includes("--commit");
const ACTUAL_BOSTA_MARCH = -71678.71; // user-provided actual Bosta fees for March

async function main() {
  const snap = await db.collection("transactions").where("user_id", "==", UID).get();
  const docs = [];
  snap.docs.forEach(d => {
    const x = d.data();
    if (x.category_id !== "cat_shipping_expense") return;
    let dt; try { dt = x.date_time.toDate(); } catch (e) { return; }
    if (dt.toISOString().slice(0, 7) !== "2026-03") return;
    docs.push({ id: d.id, date: dt.toISOString().slice(0, 10), amount: x.amount, createdMs: (x.created_at && x.created_at.toMillis) ? x.created_at.toMillis() : 0 });
  });

  // Group by (date, amount); keep the earliest-created, delete the rest.
  const groups = {};
  docs.forEach(r => { const k = r.date + "|" + r.amount; (groups[k] = groups[k] || []).push(r); });
  const toDelete = [];
  let keptSum = 0;
  Object.values(groups).forEach(g => {
    g.sort((a, b) => a.createdMs - b.createdMs || a.id.localeCompare(b.id));
    keptSum += g[0].amount; // keep first
    for (let i = 1; i < g.length; i++) toDelete.push(g[i].id);
  });

  const trueUp = +(ACTUAL_BOSTA_MARCH - keptSum).toFixed(2);
  console.log(`March cat_shipping_expense: total docs=${docs.length}, unique groups=${Object.keys(groups).length}`);
  console.log(`Duplicate docs to delete: ${toDelete.length}`);
  console.log(`Kept (deduped) sum: ${keptSum.toFixed(2)}`);
  console.log(`Target actual: ${ACTUAL_BOSTA_MARCH.toFixed(2)}`);
  console.log(`True-up adjustment to add: ${trueUp.toFixed(2)}`);

  if (!COMMIT) { console.log("\nDRY RUN — re-run with --commit to apply."); process.exit(0); }

  // 1) Delete duplicates
  let batch = db.batch(), n = 0;
  for (const id of toDelete) {
    batch.delete(db.collection("transactions").doc(id));
    if (++n % 450 === 0) { await batch.commit(); batch = db.batch(); }
  }
  await batch.commit();
  console.log(`Deleted ${toDelete.length} duplicate docs.`);

  // 2) Add one reconciliation entry so March Bosta = exactly the actual
  if (Math.abs(trueUp) >= 0.01) {
    const { v4: uuidv4 } = require("uuid");
    const id = uuidv4();
    await db.collection("transactions").doc(id).set({
      user_id: UID,
      title: "Bosta Shipping — Actual Reconciliation",
      amount: trueUp, // negative = additional expense
      category_id: "cat_shipping_expense",
      date_time: admin.firestore.Timestamp.fromDate(new Date("2026-03-31T12:00:00Z")),
      note: "True-up of estimated Bosta fees to actual invoice (71,678.71)",
      payment_method: "Bank",
      supplier_id: null,
      sale_id: null,
      exclude_from_pl: false,
      is_estimate: false,
      is_reconciliation: true,
      created_at: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(`Added reconciliation entry ${id} for ${trueUp.toFixed(2)}.`);
  }
  console.log("Done.");
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
