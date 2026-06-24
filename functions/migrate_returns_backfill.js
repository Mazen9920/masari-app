/**
 * migrate_returns_backfill.js
 *
 * Backfills Shopify RMA Returns (the separate "Returns" object, NOT the
 * Orders REST `refunds[]`) as negative-revenue transactions so Revvo's
 * "Total sales" matches Shopify exactly.
 *
 * Shopify subtracts the value of returned items from "Total sales" the
 * moment a Return is created, even when no cash refund is recorded in
 * Shopify (typical for COD). Those returns are invisible to the Orders
 * REST API, so we read them via GraphQL (requires the `read_returns`
 * scope) and book only the UN-refunded portion of each return line —
 * `(quantity − refundedQuantity) × discountedUnitPrice` — to avoid
 * double-counting with the existing refund handler.
 *
 * Mirrors the live handler in src/shopify-processor.ts: txn id
 * `sale_return_${saleId}_${returnId}`, category `cat_sales_revenue`.
 *
 * Usage:
 *   node migrate_returns_backfill.js [--uid <id>] [--since YYYY-MM-DD] [--dry-run]
 *
 * NOTE: requires the merchant to have re-approved the `read_returns`
 * scope; otherwise GraphQL returns ACCESS_DENIED.
 */
const admin = require("firebase-admin");
const path = require("path");
const https = require("https");
const crypto = require("crypto");

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
const API_VERSION = "2024-01";
const DRY_RUN = process.argv.includes("--dry-run");

function argVal(flag) {
  const i = process.argv.indexOf(flag);
  return i >= 0 ? process.argv[i + 1] : null;
}
const ONLY_UID = argVal("--uid");
const SINCE = argVal("--since"); // YYYY-MM-DD

function decrypt(encryptedStr, key) {
  const [ivB64, tagB64, dataB64] = encryptedStr.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data).toString("utf8") + decipher.final("utf8");
}

function round2(n) {
  return Math.round(n * 100) / 100;
}
function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function shopifyGraphQL(shop, token, query, variables) {
  const payload = JSON.stringify({query, variables: variables || {}});
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: shop,
        path: `/admin/api/${API_VERSION}/graphql.json`,
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Shopify-Access-Token": token,
          "Content-Length": Buffer.byteLength(payload),
        },
      },
      (res) => {
        let body = "";
        res.on("data", (c) => (body += c));
        res.on("end", () => {
          try {
            resolve(JSON.parse(body));
          } catch {
            resolve({error: body});
          }
        });
      }
    );
    req.on("error", reject);
    req.write(payload);
    req.end();
  });
}

const ORDERS_QUERY = `
query($cursor: String, $q: String) {
  orders(first: 25, after: $cursor, query: $q, sortKey: CREATED_AT) {
    pageInfo { hasNextPage endCursor }
    edges {
      node {
        legacyResourceId
        name
        createdAt
        returns(first: 20) {
          edges {
            node {
              id
              status
              returnLineItems(first: 100) {
                edges {
                  node {
                    ... on ReturnLineItem {
                      quantity
                      refundedQuantity
                      withCodeDiscountedTotalPriceSet { shopMoney { amount } }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}`;

function numericId(gid) {
  const m = String(gid).match(/(\d+)$/);
  return m ? m[1] : String(gid);
}

function computeUnrefunded(returnNode) {
  const edges = returnNode?.returnLineItems?.edges || [];
  let total = 0;
  for (const e of edges) {
    const li = e.node || {};
    const qty = Number(li.quantity) || 0;
    const refQty = Number(li.refundedQuantity) || 0;
    const remaining = qty - refQty;
    if (remaining <= 0) continue;
    const lineTotal =
      Number(li.withCodeDiscountedTotalPriceSet?.shopMoney?.amount) || 0;
    const unit = qty > 0 ? lineTotal / qty : 0;
    total += unit * remaining;
  }
  return round2(total);
}

async function findSaleId(userId, orderLegacyId) {
  const snap = await db
    .collection("sales")
    .where("user_id", "==", userId)
    .where("external_order_id", "==", String(orderLegacyId))
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0].id;
}

async function processUser(userId, conn) {
  const shop = conn.shop_domain;
  let token;
  try {
    token = decrypt(conn.access_token, ENCRYPTION_KEY);
  } catch (e) {
    console.log(`  ✗ ${userId}: cannot decrypt token`);
    return;
  }
  const q = SINCE ? `created_at:>=${SINCE}` : null;

  let cursor = null;
  let hasNext = true;
  let scanned = 0;
  let upserts = 0;
  let deletes = 0;
  let bookedTotal = 0;
  let accessDenied = false;

  while (hasNext) {
    const resp = await shopifyGraphQL(shop, token, ORDERS_QUERY, {
      cursor,
      q,
    });
    if (resp.errors) {
      const msg = JSON.stringify(resp.errors);
      if (msg.includes("ACCESS_DENIED") || msg.includes("read_returns")) {
        accessDenied = true;
      }
      console.log(`  ✗ GraphQL error: ${msg.slice(0, 300)}`);
      break;
    }
    const conn2 = resp.data?.orders;
    if (!conn2) break;

    for (const edge of conn2.edges) {
      const o = edge.node;
      scanned++;
      const retEdges = o.returns?.edges || [];
      if (retEdges.length === 0) continue;

      const saleId = await findSaleId(userId, o.legacyResourceId);
      if (!saleId) {
        console.log(
          `    ! no sale for order ${o.name} (${o.legacyResourceId})`
        );
        continue;
      }

      for (const re of retEdges) {
        const rn = re.node;
        const returnId = numericId(rn.id);
        const status = String(rn.status || "").toUpperCase();
        const txnId = `sale_return_${saleId}_${returnId}`;
        const txnRef = db.collection("transactions").doc(txnId);

        const isVoid =
          status === "CANCELED" ||
          status === "CANCELLED" ||
          status === "DECLINED";
        const unref = computeUnrefunded(rn);

        if (isVoid || unref <= 0) {
          const existing = await txnRef.get();
          if (existing.exists) {
            deletes++;
            if (!DRY_RUN) await txnRef.delete();
            console.log(
              `    - delete ${txnId} (${status}, unref=${unref})`
            );
          }
          continue;
        }

        upserts++;
        bookedTotal += unref;
        console.log(
          `    + ${txnId}  -${unref}  (${o.name}, ${status})`
        );
        if (!DRY_RUN) {
          await txnRef.set({
            id: txnId,
            user_id: userId,
            title: `Return — ${o.name} — Shopify`,
            amount: -unref,
            date_time: admin.firestore.Timestamp.fromDate(
              new Date(o.createdAt)
            ),
            category_id: "cat_sales_revenue",
            note: `Return (${status.toLowerCase() || "open"})`,
            payment_method: "shopify",
            sale_id: saleId,
            shopify_return_id: returnId,
            exclude_from_pl: false,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
      }
    }

    hasNext = conn2.pageInfo.hasNextPage;
    cursor = conn2.pageInfo.endCursor;
    await sleep(600); // stay within GraphQL cost limits
  }

  if (accessDenied) {
    console.log(
      `  ✗ ${userId}: ACCESS_DENIED — merchant must re-approve read_returns`
    );
    return;
  }
  console.log(
    `  ✓ ${userId}: scanned ${scanned} orders, ` +
      `upserted ${upserts} (-${round2(bookedTotal)}), deleted ${deletes}`
  );
}

async function main() {
  console.log(
    `Returns backfill ${DRY_RUN ? "(DRY RUN)" : "(LIVE)"}` +
      `${SINCE ? `  since ${SINCE}` : ""}` +
      `${ONLY_UID ? `  uid ${ONLY_UID}` : ""}`
  );
  let connSnap;
  if (ONLY_UID) {
    const d = await db.collection("shopify_connections").doc(ONLY_UID).get();
    connSnap = {docs: d.exists ? [d] : [], empty: !d.exists};
  } else {
    connSnap = await db.collection("shopify_connections").get();
  }
  if (connSnap.empty) {
    console.log("No Shopify connections found.");
    return;
  }
  for (const doc of connSnap.docs) {
    const conn = doc.data();
    if (!conn.shop_domain || !conn.access_token) continue;
    console.log(`\nUser ${doc.id} (${conn.shop_domain})`);
    await processUser(doc.id, conn);
  }
  console.log("\nDone.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
