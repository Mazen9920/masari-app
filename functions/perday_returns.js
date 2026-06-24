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
function cairoDay(s){const p=new Intl.DateTimeFormat("en-CA",{timeZone:"Africa/Cairo",year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(new Date(s));return `${p.find(x=>x.type==="year").value}-${p.find(x=>x.type==="month").value}-${p.find(x=>x.type==="day").value}`;}

// CSV "Returns" (abs) and "Shipping charges" per day from the user's export
const CSV = {
 "2026-06-01":[11203.7,2817],"2026-06-02":[7904.8,1847],"2026-06-03":[4120,1661],
 "2026-06-04":[1234.1,2030],"2026-06-05":[3499,1752],"2026-06-06":[0,2057],
 "2026-06-07":[3062.1,2340],"2026-06-08":[12505,2380],"2026-06-09":[6972.6,1471],
 "2026-06-10":[5727.5,1203],"2026-06-11":[1884,1073],"2026-06-12":[0,2463],
 "2026-06-13":[2054.5,1560],"2026-06-14":[335,2825],"2026-06-15":[9076,2178],
 "2026-06-16":[785,2898],"2026-06-17":[5878,3433],"2026-06-18":[8472.1,2678],
 "2026-06-19":[973.1,2877],"2026-06-20":[8867.1,2130],"2026-06-21":[2755.6,653],
};
(async()=>{
  const conn=(await db.collection("shopify_connections").doc(UID).get()).data();
  const token=decrypt(conn.access_token); const shop=conn.shop_domain;
  let orders=[]; let url=`https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250&created_at_min=2025-01-01T00:00:00Z`;
  while(url){const res=await fetch(url,{headers:{"X-Shopify-Access-Token":token}});const j=await res.json();orders=orders.concat(j.orders||[]);const l=res.headers.get("link")||"";const m=l.match(/<([^>]+)>;\s*rel="next"/);url=m?m[1]:null;await new Promise(r=>setTimeout(r,200));}
  const ret={}, shipGross={}, shipRef={};
  for(const o of orders){
    const cm=cairoDay(o.created_at).slice(0,7);
    if(cm==="2026-06"){ const d=cairoDay(o.created_at);
      let s=0; for(const sl of o.shipping_lines||[]) s+=Number(sl.discounted_price??sl.price)||0;
      shipGross[d]=(shipGross[d]||0)+s;
    }
    for(const rf of o.refunds||[]){ const d=cairoDay(rf.created_at||o.created_at);
      if(d.slice(0,7)!=="2026-06") continue;
      for(const ri of rf.refund_line_items||[]) ret[d]=(ret[d]||0)+(Number(ri.subtotal)||0);
      for(const adj of rf.order_adjustments||[]) if(adj.kind==="shipping_refund") shipRef[d]=(shipRef[d]||0)+Math.abs(Number(adj.amount)||0);
    }
  }
  console.log(`Day          CSVret    APIret    Δret     | CSVship   APIship   Δship`);
  let tR=0,tS=0;
  for(const d of Object.keys(CSV).sort()){
    const [cr,cs]=CSV[d];
    const ar=r2(ret[d]||0); const as=r2((shipGross[d]||0)-(shipRef[d]||0));
    const dr=r2(cr-ar); const ds=r2(cs-as); tR+=dr; tS+=ds;
    const mark=(Math.abs(dr)>0.5||Math.abs(ds)>0.5)?"  <<":"";
    console.log(`${d}  ${fmt(cr).padStart(9)} ${fmt(ar).padStart(9)} ${fmt(dr).padStart(8)} | ${fmt(cs).padStart(8)} ${fmt(as).padStart(8)} ${fmt(ds).padStart(7)}${mark}`);
  }
  console.log(`\nΣ Δreturns = ${fmt(tR)}   Σ Δshipping = ${fmt(tS)}`);
  process.exit(0);
})();
