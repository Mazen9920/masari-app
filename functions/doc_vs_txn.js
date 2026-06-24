const admin = require("firebase-admin");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const TARGET = process.argv[2] || "2026-06";
const r2 = (n) => Math.round(n * 100) / 100;
function cairoMonth(d){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit"}).formatToParts(new Date(d));return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}`;}
(async()=>{
  const [salesSnap, txnSnap] = await Promise.all([
    db.collection("sales").where("user_id","==",UID).get(),
    db.collection("transactions").where("user_id","==",UID).get(),
  ]);
  // Map sale_id -> {rev, ship} positive txn amounts dated in TARGET
  const txnRev = new Map(), txnShip = new Map();
  for(const doc of txnSnap.docs){
    const t=doc.data(); const dt=t.date_time?.toDate?.(); if(!dt) continue;
    if(cairoMonth(dt.toISOString())!==TARGET) continue;
    const amt=Number(t.amount)||0; if(amt<=0) continue;
    const sid=t.sale_id||""; if(!sid) continue;
    if(t.category_id==="cat_sales_revenue") txnRev.set(sid,r2((txnRev.get(sid)||0)+amt));
    else if(t.category_id==="cat_shipping") txnShip.set(sid,r2((txnShip.get(sid)||0)+amt));
  }
  let totalDiff=0; const rows=[];
  const seen=new Set();
  for(const doc of salesSnap.docs){
    const s=doc.data(); const dt=s.date?.toDate?.(); if(!dt) continue;
    if(cairoMonth(dt.toISOString())!==TARGET) continue;
    seen.add(doc.id);
    let subtotal=0; for(const it of s.items||[]) subtotal+=r2((Number(it.quantity)||0)*(Number(it.unit_price)||0));
    subtotal=r2(subtotal);
    const netRevenue=r2(subtotal-(Number(s.discount_amount)||0));
    const docVal=r2(netRevenue+(Number(s.shipping_cost)||0));
    const txnVal=r2((txnRev.get(doc.id)||0)+(txnShip.get(doc.id)||0));
    const diff=r2(txnVal-docVal);
    if(Math.abs(diff)>0.01){ rows.push({id:doc.id,num:s.shopify_order_number||s.order_number,status:s.order_status,docVal,txnVal,diff}); totalDiff+=diff; }
  }
  // Positive txns whose sale doc is NOT dated in TARGET (orphan positives)
  let orphanPos=0;
  for(const [sid,amt] of txnRev.entries()) if(!seen.has(sid)) orphanPos+=amt;
  for(const [sid,amt] of txnShip.entries()) if(!seen.has(sid)) orphanPos+=amt;
  rows.sort((a,b)=>Math.abs(b.diff)-Math.abs(a.diff));
  for(const r of rows.slice(0,40)) console.log(`#${r.num} status=${r.status} doc=${r.docVal} txn=${r.txnVal} diff=${r.diff}`);
  console.log(`\nRows differing: ${rows.length}  sumDiff(matched)=${r2(totalDiff)}`);
  console.log(`Orphan positive txns (txn in ${TARGET} but sale doc not in ${TARGET}): ${r2(orphanPos)}`);
  process.exit(0);
})();
