/** Delete phantom refund txns: cancelled orders with NO sale_rev that carry only refund deductions.
 *  Dry-run by default; pass --apply to delete. */
const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const APPLY = process.argv.includes("--apply");
const r2 = n => Math.round(n*100)/100;
async function main() {
  const salesSnap = await db.collection("sales").where("user_id","==",UID).get();
  const cancelled = new Set(); salesSnap.docs.forEach(d=>{ if(d.data().order_status===4) cancelled.add(d.id); });

  // Gather ALL txns for each sale (rev + shipping) to identify phantom orders
  const revSnap = await db.collection("transactions").where("user_id","==",UID).where("category_id","==","cat_sales_revenue").get();
  const shipSnap = await db.collection("transactions").where("user_id","==",UID).where("category_id","==","cat_shipping").get();
  const bySaleRev = {}, bySaleShip = {};
  revSnap.docs.forEach(d=>{const t=d.data();const s=t.sale_id||"none";(bySaleRev[s]=bySaleRev[s]||[]).push(d);});
  shipSnap.docs.forEach(d=>{const t=d.data();const s=t.sale_id||"none";(bySaleShip[s]=bySaleShip[s]||[]).push(d);});

  const toDelete = [];
  let revVal = 0, shipVal = 0;
  for (const sid of cancelled){
    const revTxns = bySaleRev[sid]||[];
    const hasRev = revTxns.some(d=>d.id===`sale_rev_${sid}`);
    if (hasRev) continue; // legit order, skip
    // confirm: every rev txn here is a refund (negative, no sale_rev) — phantom
    const refunds = revTxns.filter(d=>!d.data().exclude_from_pl && (Number(d.data().amount)||0) < 0);
    if (refunds.length === 0) continue; // nothing to clean
    // SAFETY: only delete if there is genuinely no revenue (no positive rev txn at all)
    const anyPos = revTxns.some(d=>(Number(d.data().amount)||0) > 0);
    if (anyPos) { console.log(`  SKIP ${sid} has positive rev — NOT phantom`); continue; }
    // mark all rev refund txns + all ship refund txns (no sale_ship) for deletion
    for (const d of revTxns){ toDelete.push(d.ref); revVal += Number(d.data().amount)||0; }
    const shipTxns = bySaleShip[sid]||[];
    const hasShip = shipTxns.some(d=>d.id===`sale_ship_${sid}`);
    if (!hasShip){ for (const d of shipTxns){ toDelete.push(d.ref); shipVal += Number(d.data().amount)||0; } }
  }
  console.log(`\nPhantom orders cleaned. Txns to delete: ${toDelete.length}`);
  console.log(`  revenue refund value removed: ${r2(revVal)} (returns will DROP by ${r2(-revVal)})`);
  console.log(`  shipping refund value removed: ${r2(shipVal)}`);
  if (!APPLY){ console.log("\n(dry run — pass --apply to delete)"); process.exit(0); }
  // batch delete
  let n=0;
  for (let i=0;i<toDelete.length;i+=400){
    const batch = db.batch();
    toDelete.slice(i,i+400).forEach(ref=>batch.delete(ref));
    await batch.commit(); n += Math.min(400, toDelete.length-i);
    console.log(`  deleted ${n}/${toDelete.length}`);
  }
  console.log("DONE — phantoms deleted.");
  process.exit(0);
}
main().catch(e=>{console.error(e);process.exit(1);});
