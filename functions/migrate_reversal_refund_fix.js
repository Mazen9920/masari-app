/**
 * Migration: fix two revenue-reconciliation bugs so Revvo monthly totals
 * match Shopify's "Total sales breakdown" report exactly.
 *
 *  Bug A — Reversal date attribution
 *    Cancellation reversal txns (sale_rev/cogs/ship_<saleId>_reversal) were
 *    dated to the ORDER date instead of the CANCELLATION date. This made the
 *    +sale and -reversal net to zero in the order's month, so the return
 *    never showed up in the cancellation month. Fix: re-date reversals to
 *    order.cancelled_at.
 *
 *  Bug B — Phantom refund double-count
 *    A money-only refund (the settlement leg of a split refund, or a goodwill
 *    cash refund) has no refund_line_items and no shipping_refund adjustment.
 *    A previous fallback summed refund.transactions[] and created a phantom
 *    negative txn. Shopify's "Returns" never counts these. Fix: DELETE phantom
 *    refund txns (refund with 0 line items + 0 shipping adjustment).
 *
 *  Also re-dates legitimate refund txns to refund.created_at so they land in
 *  the month Shopify reports them.
 *
 * Authoritative source of truth = the live Shopify order objects.
 *
 * Usage:
 *   node migrate_reversal_refund_fix.js            # DRY RUN (default)
 *   node migrate_reversal_refund_fix.js --apply    # write changes
 *   node migrate_reversal_refund_fix.js --apply --uid <UID>
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

const ENCRYPTION_KEY =
  "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";

const APPLY = process.argv.includes("--apply");
const uidArg = process.argv.indexOf("--uid");
const ONLY_UID = uidArg !== -1 ? process.argv[uidArg + 1] : null;

function decrypt(enc, key) {
  const [ivB64, tagB64, dataB64] = enc.split(":");
  const kb = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const d = crypto.createDecipheriv("aes-256-gcm", kb, iv);
  d.setAuthTag(tag);
  return d.update(data).toString("utf8") + d.final("utf8");
}

const r2 = (n) => Math.round(n * 100) / 100;
const tsFrom = (iso) => admin.firestore.Timestamp.fromDate(new Date(iso));
const sameTs = (a, b) =>
  a && b && a.seconds === b.seconds && a.nanoseconds === b.nanoseconds;

async function fetchAllOrders(shop, token) {
  let all = [];
  // created_at_min is REQUIRED: without it Shopify's orders.json only returns
  // the last ~60 days, which would silently skip older orders for users with
  // longer histories. Use a wide lower bound to cover all imported data.
  let url =
    `https://${shop}/admin/api/2024-01/orders.json?status=any&limit=250` +
    "&created_at_min=2024-01-01T00:00:00Z";
  while (url) {
    const res = await fetch(url, {
      headers: {
        "X-Shopify-Access-Token": token,
        "Content-Type": "application/json",
      },
    });
    const json = await res.json();
    all = all.concat(json.orders || []);
    const link = res.headers.get("link") || "";
    const m = link.match(/<([^>]+)>;\s*rel="next"/);
    url = m ? m[1] : null;
    await new Promise((r) => setTimeout(r, 200));
  }
  return all;
}

async function migrateUser(uid) {
  const connSnap = await db.collection("shopify_connections").doc(uid).get();
  if (!connSnap.exists) {
    console.log(`  [${uid}] no shopify_connection, skipping`);
    return;
  }
  const conn = connSnap.data();
  if (!conn.access_token || !conn.shop_domain) {
    console.log(`  [${uid}] missing token/shop, skipping`);
    return;
  }
  const token = decrypt(conn.access_token, ENCRYPTION_KEY);
  const shop = conn.shop_domain;

  console.log(`\n=== User ${uid} (${shop}) ===`);
  const orders = await fetchAllOrders(shop, token);
  console.log(`  Fetched ${orders.length} Shopify orders`);

  const txnCol = db.collection("transactions");
  let batch = db.batch();
  let pending = 0;
  const stats = {
    reversalRedated: 0,
    phantomDeleted: 0,
    refundRedated: 0,
    refundAmountFixed: 0,
    shipRefundRedated: 0,
    shipRefundDeleted: 0,
    shipRefundAmountFixed: 0,
    shipReversalFixed: 0,
  };

  const commit = async () => {
    if (pending === 0) return;
    if (APPLY) await batch.commit();
    batch = db.batch();
    pending = 0;
  };
  const queue = async (fn) => {
    fn(batch);
    if (++pending >= 400) await commit();
  };

  for (const order of orders) {
    const saleId = `shopify_${uid}_${order.id}`;

    // ── Bug A: re-date cancellation reversals ──
    if (order.cancelled_at) {
      const want = tsFrom(order.cancelled_at);
      for (const suffix of ["rev", "cogs", "ship"]) {
        const id = `sale_${suffix}_${saleId}_reversal`;
        const doc = await txnCol.doc(id).get();
        if (!doc.exists) continue;
        const cur = doc.data().date_time;
        if (sameTs(cur, want)) continue;
        console.log(
          `  [A] re-date ${id}: ` +
          `${cur && cur.toDate().toISOString()} -> ${order.cancelled_at}`
        );
        stats.reversalRedated++;
        await queue((b) =>
          b.update(doc.ref, {
            date_time: want,
            updated_at: admin.firestore.Timestamp.now(),
          })
        );
      }

      // ── Bug C: shipping reversal must not double-count a shipping
      // refund. The double-count only occurs when BOTH a sale_ship_refund
      // txn AND a sale_ship_reversal exist for the same shipping. The
      // correct reversal = -(origShip - alreadyRefundedShipping) where
      // alreadyRefundedShipping is summed from EXISTING sale_ship_refund
      // txns in Firestore (mirrors handleOrderCancelled). When no refund
      // txn exists, the reversal is the sole deduction and stays -origShip.
      const shipOrigDoc = await txnCol.doc(`sale_ship_${saleId}`).get();
      const shipRevDoc = await txnCol.doc(`sale_ship_${saleId}_reversal`)
        .get();
      if (shipOrigDoc.exists && shipRevDoc.exists) {
        const origShip = Number(shipOrigDoc.data().amount) || 0;
        let alreadyRefundedShipping = 0;
        const shipRefSnap = await txnCol
          .where("sale_id", "==", saleId)
          .where("category_id", "==", "cat_shipping")
          .get();
        for (const d of shipRefSnap.docs) {
          if (d.id.startsWith(`sale_ship_refund_${saleId}_`)) {
            alreadyRefundedShipping += Math.abs(Number(d.data().amount) || 0);
          }
        }
        const correct = r2(-(origShip - alreadyRefundedShipping));
        const cur = r2(Number(shipRevDoc.data().amount) || 0);
        if (Math.abs(cur - correct) > 0.005) {
          console.log(
            `  [C] fix ship reversal ${saleId}: ${cur} -> ${correct} ` +
            `(origShip=${origShip} refundedTxn=${alreadyRefundedShipping})`
          );
          stats.shipReversalFixed++;
          await queue((b) =>
            b.update(shipRevDoc.ref, {
              amount: correct,
              updated_at: admin.firestore.Timestamp.now(),
            })
          );
        }
      }
    }

    // ── Bug B + refund amount/date correction ──
    for (const refund of order.refunds || []) {
      const refundId = String(refund.id);
      let productRefund = 0;
      for (const ri of refund.refund_line_items || []) {
        productRefund += Number(ri.subtotal) || 0;
      }
      let shippingRefund = 0;
      for (const adj of refund.order_adjustments || []) {
        if (adj.kind === "shipping_refund") {
          shippingRefund += Math.abs(Number(adj.amount) || 0);
        }
        // refund_discrepancy and other adjustments are NOT returns —
        // Shopify "Returns" counts only refund_line_items. Ignore them.
      }
      productRefund = r2(productRefund);
      shippingRefund = r2(shippingRefund);
      const want = tsFrom(refund.created_at);

      const refundTxnId = `sale_refund_${saleId}_${refundId}`;
      const refDoc = await txnCol.doc(refundTxnId).get();
      if (refDoc.exists) {
        if (productRefund <= 0) {
          // Phantom: Shopify reports 0 product return for this refund
          console.log(
            `  [B] DELETE phantom ${refundTxnId} ` +
            `(amount ${refDoc.data().amount})`
          );
          stats.phantomDeleted++;
          await queue((b) => b.delete(refDoc.ref));
        } else {
          const curAmt = r2(Number(refDoc.data().amount) || 0);
          const wantAmt = r2(-productRefund);
          const dateOk = sameTs(refDoc.data().date_time, want);
          const amtOk = Math.abs(curAmt - wantAmt) < 0.005;
          if (!amtOk) {
            console.log(
              `  [D] fix refund amount ${refundTxnId}: ` +
              `${curAmt} -> ${wantAmt}`
            );
            stats.refundAmountFixed++;
          } else if (!dateOk) {
            console.log(
              `  [R] re-date ${refundTxnId} -> ${refund.created_at}`
            );
            stats.refundRedated++;
          }
          if (!amtOk || !dateOk) {
            await queue((b) =>
              b.update(refDoc.ref, {
                amount: wantAmt,
                date_time: want,
                updated_at: admin.firestore.Timestamp.now(),
              })
            );
          }
        }
      }

      const shipTxnId = `sale_ship_refund_${saleId}_${refundId}`;
      const shipDoc = await txnCol.doc(shipTxnId).get();
      if (shipDoc.exists) {
        if (shippingRefund <= 0) {
          console.log(`  [B] DELETE phantom ship refund ${shipTxnId}`);
          stats.shipRefundDeleted++;
          await queue((b) => b.delete(shipDoc.ref));
        } else {
          const curAmt = r2(Number(shipDoc.data().amount) || 0);
          const wantAmt = r2(-shippingRefund);
          const dateOk = sameTs(shipDoc.data().date_time, want);
          const amtOk = Math.abs(curAmt - wantAmt) < 0.005;
          if (!amtOk) {
            console.log(
              `  [D] fix ship refund amount ${shipTxnId}: ` +
              `${curAmt} -> ${wantAmt}`
            );
            stats.shipRefundAmountFixed++;
          } else if (!dateOk) {
            console.log(`  [R] re-date ${shipTxnId} -> ${refund.created_at}`);
            stats.shipRefundRedated++;
          }
          if (!amtOk || !dateOk) {
            await queue((b) =>
              b.update(shipDoc.ref, {
                amount: wantAmt,
                date_time: want,
                updated_at: admin.firestore.Timestamp.now(),
              })
            );
          }
        }
      }
    }
  }

  await commit();
  console.log(`  Summary for ${uid}:`, JSON.stringify(stats));
}

async function main() {
  console.log(
    APPLY
      ? ">>> APPLY MODE — writing changes <<<"
      : ">>> DRY RUN — no changes (pass --apply to write) <<<"
  );

  let uids;
  if (ONLY_UID) {
    uids = [ONLY_UID];
  } else {
    const snap = await db.collection("shopify_connections").get();
    uids = snap.docs.map((d) => d.id);
  }
  console.log(`Users to process: ${uids.length}`);

  for (const uid of uids) {
    try {
      await migrateUser(uid);
    } catch (e) {
      console.error(`  [${uid}] ERROR:`, e.message);
    }
  }
  console.log("\nDone.");
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
