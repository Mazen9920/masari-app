const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
function decrypt(enc){const[a,b,c]=enc.split(":");const d=crypto.createDecipheriv("aes-256-gcm",Buffer.from(KEY,"hex"),Buffer.from(a,"base64"));d.setAuthTag(Buffer.from(b,"base64"));return d.update(Buffer.from(c,"base64")).toString("utf8")+d.final("utf8");}
const r2=n=>Math.round(n*100)/100;
const fmt=n=>r2(n).toLocaleString("en",{minimumFractionDigits:2,maximumFractionDigits:2});
// Cairo-local YYYY-MM-DD
function cairoDay(s){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date(s));return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}-${p.find(x=>x.type==="day").value}`;}
function inRange(s,from,to){const d=cairoDay(s);return d>=from && d<=to;}

function windowTotals(orders,from,to){
  let gross=0,disc=0,returns=0,ship=0,shipRef=0;
  for(const o of orders){
    if(inRange(o.created_at,from,to)){
      for(const li of o.line_items||[]) gross+=(Number(li.price)||0)*(Number(li.quantity)||0);
      let sd=0; for(const sl of o.shipping_lines||[]){const g=Number(sl.price)||0,n=Number(sl.discounted_price??sl.price)||0;ship+=n;sd+=g-n;}
      disc+=((Number(o.total_discounts)||0)-sd);
    }
    for(const rf of o.refunds||[]){ if(!inRange(rf.created_at||o.created_at,from,to)) continue;
      for(const ri of rf.refund_line_items||[]) returns+=Number(ri.subtotal)||0;
      for(const adj of rf.order_adjustments||[]) if(adj.kind==="shipping_refund") shipRef+=Math.abs(Number(adj.amount)||0);
    }
  }
  const net=r2(gross-disc-returns); const nShip=r2(ship-shipRef);
  return {gross:r2(gross),disc:r2(disc),returns:r2(returns),net,ship:nShip,total:r2(net+nShip)};
}

(async()=>{
  const conn=(await db.collection("shopify_connections").doc(UID).get()).data();
  const token=decrypt(conn.access_token); const shop=conn.shop_domain;
  let orders=[]; let url=`https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2025-01-01T00:00:00Z`;
  while(url){const res=await fetch(url,{headers:{"X-Shopify-Access-Token":token}});const j=await res.json();orders=orders.concat(j.orders||[]);const l=res.headers.get("link")||"";const m=l.match(/<([^>]+)>;\s*rel="next"/);url=m?m[1]:null;await new Promise(r=>setTimeout(r,200));}

  const windows = [
    ["June (calendar)","2026-06-01","2026-06-30"],
    ["June MTD (1-21)","2026-06-01","2026-06-21"],
    ["Last 30 days (5/22-6/21)","2026-05-22","2026-06-21"],
    ["Last 30 days (5/23-6/21)","2026-05-23","2026-06-21"],
    ["Last 7 days","2026-06-15","2026-06-21"],
  ];
  for(const [label,f,t] of windows){
    const w=windowTotals(orders,f,t);
    console.log(`${label.padEnd(28)} Net ${fmt(w.net).padStart(12)}  Total ${fmt(w.total).padStart(12)}  (gross ${fmt(w.gross)} disc ${fmt(w.disc)} ret ${fmt(w.returns)} ship ${fmt(w.ship)})`);
  }
  process.exit(0);
})();
