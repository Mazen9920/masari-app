/**
 * Per-order reconciliation of orders CREATED in a month.
 * Compares Shopify gross/discount/shipping against Revvo's stored sale +
 * its positive (non-refund, non-reversal) transactions, to locate the
 * residual Net-sales and Shipping gaps.
 *
 * Usage: node reconcile_created.js 2026-06
 */
const admin = require("firebase-admin");
const crypto = require("crypto");
const path = require("path");

admin.initializeApp({
  credential: admin.credential.cert(
    require(path.resolve(
      "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json"
    ))
  ),
});
const db = admin.firestore();

const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const ENCRYPTION_KEY =
  "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const MONTH = process.argv[2] || "2026-06";

function decrypt(enc, key) {
  const [ivB64, tagB64, dataB64] = enc.split(":");
  const kb = Buffer.from(key, "hex");
  const d = crypto.createDecipheriv(
    "aes-256-gcm", kb, Buffer.from(ivB64, "base64"));
  d.setAuthTag(Buffer.from(tagB64, "base64"));
  return d.update(Buffer.from(dataB64, "base64")).toString("utf8") +
    d.final("utf8");
}
const r2 = (n) => Math.round(n * 100) / 100;
function cairoMonth(s) {
  const p = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Africa/Cairo", year: "numeric", month: "2-digit",
  }).formatToParts(new Date(s));
  return `${p.find((x) => x.type === "year").value}-${
    p.find((x) => x.type === "month").value}`;
}

async function main() {
  const conn = (await db.collection("shopify_connections").doc(UID).get())
    .data();
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  const shop = conn.shop_domain;

  let orders = [];
  let url = `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250`;
  while (url) {
    const res = await fetch(url, {
      headers: { "X-Shopify-Access-Token": token },
    });
    const json = await res.json();
    orders = orders.concat(json.orders || []);
    const m = (res.headers.get("link") || "").match(
      /<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise((r) => setTimeout(r, 150));
  }

  // Revvo: all positive sales-revenue txns + shipping txns for the user
  const txSnap = await db.collection("transactions")
    .where("user_id", "==", UID).get();
  const revTx = new Map(); // saleId -> {rev, ship}
  for (const d of txSnap.docs) {
    const t = d.data();
    const sid = t.sale_id;
    if (!sid) continue;
    const dt = t.date_time && t.date_time.toDate();
    if (!dt || cairoMonth(dt.toISOString()) !== MONTH) continue;
    const e = revTx.get(sid) || { rev: 0, ship: 0 };
    if (t.category_id === "cat_sales_revenue") e.rev += Number(t.amount) || 0;
    if (t.category_id === "cat_shipping") e.ship += Number(t.amount) || 0;
    revTx.set(sid, e);
  }

  let gGross = 0, gDisc = 0, gShip = 0;
  let rRevPos = 0, rShip = 0;
  const rows = [];
  for (const o of orders) {
    if (cairoMonth(o.created_at) !== MONTH) continue;
    let gross = 0;
    for (const li of o.line_items || []) {
      gross += (Number(li.price) || 0) * (Number(li.quantity) || 0);
    }
    let shipDisc = 0, shipGross = 0;
    for (const sl of o.shipping_lines || []) {
      shipGross += Number(sl.discounted_price ?? sl.price) || 0;
      shipDisc += (Number(sl.price) || 0) -
        (Number(sl.discounted_price ?? sl.price) || 0);
    }
    const prodDisc = (Number(o.total_discounts) || 0) - shipDisc;
    const shopNet = r2(gross - prodDisc); // gross product net of discount
    gGross += gross; gDisc += prodDisc; gShip += shipGross;

    const saleId = `shopify_${UID}_${o.id}`;
    const rv = revTx.get(saleId) || { rev: 0, ship: 0 };
    // Revvo positive revenue for this order = rev minus negative refunds;
    // we want the ORIGINAL net revenue posted this month (exclude refunds
    // & reversals which are also in rev). Easiest: positive part only.
    rRevPos += rv.rev; rShip += rv.ship;

    const cancelled = !!o.cancelled_at;
    // Compare Shopify net (gross-disc) against Revvo rev signed total
    const diff = r2(rv.rev - shopNet);
    if (Math.abs(diff) > 0.5) {
      rows.push({
        no: o.order_number, cancelled,
        fs: o.financial_status,
        shopNet, revvoRev: r2(rv.rev), diff,
        shipShop: r2(shipGross), shipRevvo: r2(rv.ship),
      });
    }
  }

  console.log(`\n${MONTH} orders created — Shopify vs Revvo (per order)\n`);
  rows.sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));
  for (const r of rows.slice(0, 40)) {
    console.log(
      `#${r.no} cancelled=${r.cancelled} fs=${r.fs} ` +
      `shopNet=${r.shopNet} revvoRev=${r.revvoRev} DIFF=${r.diff} ` +
      `| ship shop=${r.shipShop} revvo=${r.shipRevvo}`);
  }
  console.log(`\nRows with diff: ${rows.length}`);
  console.log(`Totals: Shopify gross=${r2(gGross)} disc=${r2(gDisc)} ` +
    `net=${r2(gGross - gDisc)} ship=${r2(gShip)}`);
  console.log(`        Revvo revPos=${r2(rRevPos)} ship=${r2(rShip)}`);
  console.log(`Net diff (Revvo - Shopify net incl refunds handled ` +
    `elsewhere): see reconcile_month`);
  process.exit(0);
}
main().catch((e) => { console.error(e); process.exit(1); });
