/** Classify the 46 inconsistent cancelled orders: prior [backfill] phantom vs today's new phantom. Plus reversal/refund coverage. */
const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const r2 = n => Math.round(n*100)/100;
const todayStart = new Date("2026-06-23T00:00:00Z").getTime();
async function main() {
  const salesSnap = await db.collection("sales").where("user_id","==",UID).get();
  const cancelled = new Set(); salesSnap.docs.forEach(d=>{ if(d.data().order_status===4) cancelled.add(d.id); });
  const txnSnap = await db.collection("transactions").where("user_id","==",UID).where("category_id","==","cat_sales_revenue").get();
  const bySale = {};
  txnSnap.docs.forEach(d=>{ const t=d.data(); const sid=t.sale_id||"none"; (bySale[sid]=bySale[sid]||[]).push({id:d.id,amt:Number(t.amount)||0,excl:!!t.exclude_from_pl,note:t.note||"",ca:t.created_at?.toDate?.()?.getTime?.()}); });
  let priorPhantom=0, priorPhantomVal=0, todayPhantom=0, todayPhantomVal=0, otherBad=0, otherBadVal=0;
  for (const sid of cancelled){
    const txns=bySale[sid]||[]; let net=0; for(const t of txns) if(!t.excl) net+=t.amt;
    if (Math.abs(r2(net))<=0.01) continue;
    const hasRev = txns.some(t=>t.id===`sale_rev_${sid}`);
    if (!hasRev){
      // phantom: refund(s) with no revenue
      const anyToday = txns.some(t=>t.ca && t.ca>=todayStart);
      const anyBackfill = txns.some(t=>t.note.includes("[backfill]"));
      if (anyToday && !anyBackfill){ todayPhantom++; todayPhantomVal+=net; }
      else { priorPhantom++; priorPhantomVal+=net; }
    } else { otherBad++; otherBadVal+=net; console.log(`  OTHER-BAD ${sid} net=${r2(net)} txns=${txns.length}`); }
  }
  console.log(`\nPrior [backfill] phantom (no rev): ${priorPhantom}  val=${r2(priorPhantomVal)}`);
  console.log(`Today NEW phantom (no rev):       ${todayPhantom}  val=${r2(todayPhantomVal)}`);
  console.log(`Other inconsistent (has rev):     ${otherBad}  val=${r2(otherBadVal)}`);
  process.exit(0);
}
main().catch(e=>{console.error(e);process.exit(1);});
