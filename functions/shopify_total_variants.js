const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"))) });
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const TARGET = process.argv[2] || "2026-06";
function decrypt(enc){const[a,b,c]=enc.split(":");const d=crypto.createDecipheriv("aes-256-gcm",Buffer.from(KEY,"hex"),Buffer.from(a,"base64"));d.setAuthTag(Buffer.from(b,"base64"));return d.update(Buffer.from(c,"base64")).toString("utf8")+d.final("utf8");}
const r2=n=>Math.round(n*100)/100;
const fmt=n=>r2(n).toLocaleString("en",{minimumFractionDigits:2,maximumFractionDigits:2});
function cairoMonth(s){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit"}).formatToParts(new Date(s));return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}`;}

function calc(orders,{excludeCancelled=false, cancelledAsNegative=false}={}){
  let gross=0,disc=0,returns=0,ship=0,shipRef=0;
  let cancelNeg=0;
  for(const o of orders){
    const cancelled = !!o.cancelled_at;
    const cm=cairoMonth(o.created_at);
    if(cm===TARGET){
      if(!(excludeCancelled && cancelled)){
        let oGross=0; for(const li of o.line_items||[]) oGross+=(Number(li.price)||0)*(Number(li.quantity)||0);
        let sd=0,oShip=0; for(const sl of o.shipping_lines||[]){const g=Number(sl.price)||0,n=Number(sl.discounted_price??sl.price)||0;oShip+=n;sd+=g-n;}
        gross+=oGross; ship+=oShip; disc+=((Number(o.total_discounts)||0)-sd);
      }
    }
    // cancellation booked as negative in the month it was cancelled
    if(cancelled && cancelledAsNegative){
      const xm=cairoMonth(o.cancelled_at);
      if(xm===TARGET){
        let oGross=0; for(const li of o.line_items||[]) oGross+=(Number(li.price)||0)*(Number(li.quantity)||0);
        let sd=0,oShip=0; for(const sl of o.shipping_lines||[]){const g=Number(sl.price)||0,n=Number(sl.discounted_price??sl.price)||0;oShip+=n;sd+=g-n;}
        cancelNeg+=(oGross-((Number(o.total_discounts)||0)-sd))+oShip;
      }
    }
    if(!(excludeCancelled && cancelled)){
      for(const rf of o.refunds||[]){ if(cairoMonth(rf.created_at||o.created_at)!==TARGET) continue;
        for(const ri of rf.refund_line_items||[]) returns+=Number(ri.subtotal)||0;
        for(const adj of rf.order_adjustments||[]) if(adj.kind==="shipping_refund") shipRef+=Math.abs(Number(adj.amount)||0);
      }
    }
  }
  const net=gross-disc-returns; const nShip=ship-shipRef;
  return r2(net+nShip-cancelNeg);
}

(async()=>{
  const conn=(await db.collection("shopify_connections").doc(UID).get()).data();
  const token=decrypt(conn.access_token); const shop=conn.shop_domain;
  let orders=[]; let url=`https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2025-01-01T00:00:00Z`;
  while(url){const res=await fetch(url,{headers:{"X-Shopify-Access-Token":token}});const j=await res.json();orders=orders.concat(j.orders||[]);const l=res.headers.get("link")||"";const m=l.match(/<([^>]+)>;\s*rel="next"/);url=m?m[1]:null;await new Promise(r=>setTimeout(r,200));}

  console.log(`\n${TARGET} Total sales variants (looking for ~336k):`);
  console.log(`  (1) ALL orders incl cancelled (current/Revvo): ${fmt(calc(orders,{}))}`);
  console.log(`  (2) EXCLUDE cancelled orders entirely:         ${fmt(calc(orders,{excludeCancelled:true}))}`);
  console.log(`  (3) Cancellation booked as negative (cancel month): ${fmt(calc(orders,{cancelledAsNegative:true}))}`);

  // Count cancelled orders in June & their gross
  let cCount=0,cGrossThis=0,cCancelThis=0;
  for(const o of orders){ if(!o.cancelled_at) continue;
    if(cairoMonth(o.created_at)===TARGET){cCount++; for(const li of o.line_items||[]) cGrossThis+=(Number(li.price)||0)*(Number(li.quantity)||0);}
    if(cairoMonth(o.cancelled_at)===TARGET){let g=0;for(const li of o.line_items||[])g+=(Number(li.price)||0)*(Number(li.quantity)||0);cCancelThis+=g;}
  }
  console.log(`\nCancelled orders CREATED in ${TARGET}: ${cCount}  gross ${fmt(cGrossThis)}`);
  console.log(`Cancelled orders CANCELLED in ${TARGET}: gross ${fmt(cCancelThis)}`);
  process.exit(0);
})();
