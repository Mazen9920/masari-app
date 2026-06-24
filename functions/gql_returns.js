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
(async()=>{
  const conn=(await db.collection("shopify_connections").doc(UID).get()).data();
  const token=decrypt(conn.access_token); const shop=conn.shop_domain;
  const gql = async (query)=>{
    const res = await fetch(`https://${shop}/admin/api/2024-07/graphql.json`,{
      method:"POST", headers:{"X-Shopify-Access-Token":token,"Content-Type":"application/json"}, body:JSON.stringify({query})
    });
    return res.json();
  };
  // Pull returns created in June via GraphQL
  let after=null, all=[]; let pages=0;
  do{
    const q=`{ returns(first:50, query:"created_at:>=2026-06-01 created_at:<=2026-06-30"${after?`, after:\"${after}\"`:""}) {
      pageInfo{hasNextPage endCursor}
      edges{ node{ id name status createdAt totalQuantity
        order{ name }
        returnLineItems(first:20){ edges{ node{ ... on ReturnLineItem { quantity returnReason
          fulfillmentLineItem{ lineItem{ originalUnitPriceSet{shopMoney{amount}} discountedUnitPriceSet{shopMoney{amount}} } } } } } }
      } }
    } }`;
    const j=await gql(q);
    if(j.errors){ console.log("GraphQL errors:", JSON.stringify(j.errors).slice(0,400)); break; }
    const conn2=j.data?.returns; if(!conn2){ console.log("No returns connection. Resp:", JSON.stringify(j).slice(0,300)); break; }
    for(const e of conn2.edges) all.push(e.node);
    after=conn2.pageInfo.hasNextPage?conn2.pageInfo.endCursor:null; pages++;
    await new Promise(r=>setTimeout(r,250));
  } while(after && pages<20);

  console.log(`Returns (RMA) created in June: ${all.length}`);
  const byDay={};
  for(const r of all){
    const d=cairoDay(r.createdAt);
    let val=0;
    for(const li of r.returnLineItems.edges){ const n=li.node; const price=Number(n.fulfillmentLineItem?.lineItem?.discountedUnitPriceSet?.shopMoney?.amount||0); val+=price*(n.quantity||0); }
    byDay[d]=(byDay[d]||0)+val;
  }
  for(const d of Object.keys(byDay).sort()) console.log(`  ${d}: returns value ${fmt(byDay[d])}`);
  console.log(`  TOTAL return value: ${fmt(Object.values(byDay).reduce((a,b)=>a+b,0))}`);
  process.exit(0);
})();
