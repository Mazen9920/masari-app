/** Investigate the 46 phantom-refund orders: are they genuinely cancelled-with-no-revenue? */
const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const r2 = n => Math.round(n*100)/100;
async function main() {
  const salesSnap = await db.collection("sales").where("user_id","==",UID).get();
  const saleDocs = {}; salesSnap.docs.forEach(d=>saleDocs[d.id]=d.data());
  const cancelled = new Set(); salesSnap.docs.forEach(d=>{ if(d.data().order_status===4) cancelled.add(d.id); });

  const txnSnap = await db.collection("transactions").where("user_id","==",UID).where("category_id","==","cat_sales_revenue").get();
  const bySale = {};
  txnSnap.docs.forEach(d=>{ const t=d.data(); const sid=t.sale_id||"none"; (bySale[sid]=bySale[sid]||[]).push({id:d.id,amt:Number(t.amount)||0,excl:!!t.exclude_from_pl,note:t.note||""}); });

  const phantoms = [];
  for (const sid of cancelled){
    const txns=bySale[sid]||[]; let net=0; for(const t of txns) if(!t.excl) net+=t.amt;
    if (Math.abs(r2(net))<=0.01) continue;
    const hasRev = txns.some(t=>t.id===`sale_rev_${sid}`);
    if (!hasRev) phantoms.push(sid);
  }
  console.log(`Phantom orders: ${phantoms.length}`);
  // characterize: sale doc created date, order_status, net_revenue field, any positive rev txn anywhere
  let stats = { hasSaleDoc:0, statusCancelled:0, anyPositiveRev:0, createdMonths:{} };
  for (const sid of phantoms){
    const s = saleDocs[sid];
    if (s) stats.hasSaleDoc++;
    if (s && s.order_status===4) stats.statusCancelled++;
    const txns=bySale[sid]||[];
    const pos = txns.filter(t=>t.amt>0);
    if (pos.length) stats.anyPositiveRev++;
    const cd = s && (s.created_at?.toDate?.() || s.date_time?.toDate?.() || (s.order_date?.toDate?.()));
    const m = cd ? `${cd.getUTCFullYear()}-${String(cd.getUTCMonth()+1).padStart(2,"0")}` : "none";
    stats.createdMonths[m]=(stats.createdMonths[m]||0)+1;
  }
  console.log(JSON.stringify(stats,null,2));
  // sample 6 in detail
  console.log("\n=== Sample 6 ===");
  for (const sid of phantoms.slice(0,6)){
    const s = saleDocs[sid] || {};
    console.log(`\n${sid}`);
    console.log(`  sale: status=${s.order_status} net_revenue=${s.net_revenue} total=${s.total_price||s.total} ext=${s.external_order_id} num=${s.order_number||s.name}`);
    (bySale[sid]||[]).forEach(t=>console.log(`   txn [${t.id}] amt=${t.amt} excl=${t.excl} note=${t.note.slice(0,40)}`));
  }
  process.exit(0);
}
main().catch(e=>{console.error(e);process.exit(1);});
