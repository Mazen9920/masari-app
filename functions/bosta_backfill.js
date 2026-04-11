#!/usr/bin/env node
/**
 * Bosta Historical Backfill — One-time migration script
 *
 * Paginates through ALL Bosta deliveries (~16,726), fetches each one's
 * wallet.cashCycle, and creates expense transactions for any with
 * bosta_fees > 0. Matches to Revvo sales via businessReference when
 * possible.
 *
 * State-agnostic: follows Cash Cycles, not delivery states.
 *
 * Idempotent: skips deliveries that already have an expense transaction.
 *
 * Usage:
 *   node bosta_backfill.js              # dry-run (default)
 *   node bosta_backfill.js --commit     # actually write changes
 */
const {Firestore, FieldValue, Timestamp} = require("@google-cloud/firestore");

const PROJECT_ID = "massari-574ff";
const SA_PATH = "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json";
const DRY_RUN = !process.argv.includes("--commit");

// RPE-Gear user
const USER_ID = "EGYQnP7ughdUtTbn04UwUET534i1";

// Bosta API
const BOSTA_API_BASE = "https://app.bosta.co/api/v2";
const SEARCH_PAGE_LIMIT = 50;
const PER_DELIVERY_DELAY_MS = 250;

const FEE_BREAKDOWN_FIELDS = [
  "shipping_fees", "fulfillment_fees", "vat", "cod_fees",
  "insurance_fees", "expedite_fees", "opening_package_fees",
  "flex_ship_fees", "pos_fees", "collection_fees",
];

function round2(v) { return Math.round(v * 100) / 100; }
function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function bostaFetch(url, options) {
  const maxRetries = 3;
  for (let attempt = 0; attempt <= maxRetries; attempt++) {
    const res = await fetch(url, options);
    if (res.status === 429 || res.status >= 500) {
      if (attempt < maxRetries) {
        const backoff = 1000 * Math.pow(2, attempt);
        console.log(`  Retry ${attempt + 1} after ${backoff}ms (status ${res.status})`);
        await sleep(backoff);
        continue;
      }
    }
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`Bosta API ${res.status}: ${body.substring(0, 200)}`);
    }
    return res.json();
  }
}

async function main() {
  console.log(DRY_RUN ? "=== DRY RUN ===" : "=== COMMITTING ===");
  console.log(`User: ${USER_ID}`);

  const db = new Firestore({projectId: PROJECT_ID, keyFilename: SA_PATH});

  // Load Bosta connection to get API key
  const connDoc = await db.collection("bosta_connections").doc(USER_ID).get();
  if (!connDoc.exists) {
    console.error("No bosta_connections doc found for user. Connect Bosta first.");
    process.exit(1);
  }

  // For backfill, we need the decrypted API key.
  // The encryption key must be passed via environment variable.
  const encryptionKey = process.env.BOSTA_ENCRYPTION_KEY;
  if (!encryptionKey) {
    console.error("Set BOSTA_ENCRYPTION_KEY env var (the SHOPIFY_TOKEN_ENCRYPTION_KEY value)");
    process.exit(1);
  }

  const crypto = require("crypto");
  const encryptedApiKey = connDoc.data().api_key_encrypted;
  const [ivB64, tagB64, dataB64] = encryptedApiKey.split(":");
  const keyBuf = Buffer.from(encryptionKey, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  const apiKey = decipher.update(data, null, "utf8") + decipher.final("utf8");

  console.log("API key decrypted successfully.");

  const headers = {
    "Content-Type": "application/json",
    "Authorization": apiKey,
  };

  // Pre-load sales index: shopify_order_number → saleId
  console.log("Loading sales index...");
  const salesSnap = await db.collection("sales")
    .where("user_id", "==", USER_ID)
    .select("shopify_order_number", "notes")
    .get();

  const salesByOrderNum = new Map();
  for (const doc of salesSnap.docs) {
    const d = doc.data();
    const num = d.shopify_order_number;
    if (num) salesByOrderNum.set(String(num), doc.id);
  }
  console.log(`Sales indexed: ${salesByOrderNum.size} with order numbers`);

  // Pre-load existing expense transaction IDs to avoid re-checking Firestore per-delivery
  console.log("Loading existing Bosta expenses...");
  const existingTxnSnap = await db.collection("transactions")
    .where("user_id", "==", USER_ID)
    .where("category_id", "==", "cat_shipping_expense")
    .select()
    .get();
  const existingTxnIds = new Set(existingTxnSnap.docs.map(d => d.id));
  console.log(`Existing Bosta expense transactions: ${existingTxnIds.size}`);

  // Stats
  let totalSearched = 0;
  let totalFetched = 0;
  let newExpenses = 0;
  let awaitingSettlement = 0;
  let alreadyRecorded = 0;
  let matchedToSale = 0;
  let unlinked = 0;
  let errors = 0;
  let totalFeesRecorded = 0;

  // Paginate through ALL deliveries (no state filter)
  let page = 1;
  let hasMore = true;

  while (hasMore) {
    console.log(`\n--- Page ${page} ---`);

    let searchResult;
    try {
      searchResult = await bostaFetch(
        `${BOSTA_API_BASE}/deliveries/search`,
        {
          method: "POST",
          headers,
          body: JSON.stringify({
            pageNumber: page,
            pageLimit: SEARCH_PAGE_LIMIT,
          }),
        }
      );
    } catch (err) {
      console.error(`Search failed on page ${page}: ${err.message}`);
      errors++;
      break;
    }

    const deliveries = searchResult.deliveries || [];
    if (deliveries.length === 0) {
      console.log("No more deliveries.");
      break;
    }

    totalSearched += deliveries.length;
    console.log(`Found ${deliveries.length} deliveries (total so far: ${totalSearched})`);

    for (const delivery of deliveries) {
      const trackingNumber = delivery.trackingNumber;
      if (!trackingNumber) continue;

      // Quick check: would the transaction ID already exist?
      const businessRef = delivery.businessReference || null;
      let possibleSaleId = null;
      if (businessRef) {
        const orderNum = businessRef.trim().replace(/^#/, "");
        possibleSaleId = salesByOrderNum.get(orderNum) || null;
      }
      const possibleTxnId = possibleSaleId
        ? `bosta_fee_${possibleSaleId}`
        : `bosta_fee_${trackingNumber}`;

      if (existingTxnIds.has(possibleTxnId)) {
        alreadyRecorded++;
        continue;
      }

      // Fetch full detail for wallet.cashCycle
      totalFetched++;
      let detail;
      try {
        detail = await bostaFetch(
          `${BOSTA_API_BASE}/deliveries/business/${encodeURIComponent(trackingNumber)}`,
          {method: "GET", headers}
        );
      } catch (err) {
        console.error(`  FAIL ${trackingNumber}: ${err.message}`);
        errors++;
        await sleep(PER_DELIVERY_DELAY_MS);
        continue;
      }

      const bostaDeliveryId = detail._id;
      const state = detail.state?.value || 0;
      const stateValue = detail.state?.name || "";
      const type = detail.type?.value || "";
      const cod = Number(detail.cod) || 0;

      const cashCycle = detail.wallet?.cashCycle || null;
      const bostaFees = cashCycle ? Number(cashCycle.bosta_fees) || 0 : 0;

      if (!cashCycle || bostaFees <= 0) {
        awaitingSettlement++;

        if (!DRY_RUN) {
          const shipDocId = bostaDeliveryId || trackingNumber;
          await db.collection("bosta_shipments").doc(shipDocId).set({
            user_id: USER_ID,
            bosta_delivery_id: bostaDeliveryId,
            tracking_number: trackingNumber,
            business_reference: businessRef,
            state: state,
            state_value: stateValue,
            type: type,
            total_fees: null,
            fee_breakdown: null,
            deposited_at: null,
            awaiting_settlement: true,
            cod: cod,
            expense_recorded: false,
            expense_transaction_id: null,
            matched: false,
            sale_id: null,
            synced_at: FieldValue.serverTimestamp(),
          }, {merge: true});
        }

        await sleep(PER_DELIVERY_DELAY_MS);
        continue;
      }

      // Extract fee breakdown
      const feeBreakdown = {};
      for (const field of FEE_BREAKDOWN_FIELDS) {
        const val = Number(cashCycle[field]) || 0;
        if (val > 0) feeBreakdown[field] = val;
      }

      const depositedAt = cashCycle.deposited_at
        ? Timestamp.fromDate(new Date(cashCycle.deposited_at))
        : Timestamp.now();

      // Match to sale
      let saleId = possibleSaleId;
      let orderLabel = "";
      if (saleId) {
        const orderNum = businessRef.trim().replace(/^#/, "");
        orderLabel = `#${orderNum}`;
      }
      const matched = saleId !== null;

      const txnId = matched
        ? `bosta_fee_${saleId}`
        : `bosta_fee_${trackingNumber}`;
      const txnTitle = matched
        ? `Bosta Shipping - ${orderLabel}`
        : `Bosta Shipping - TN:${trackingNumber}`;

      // Double check idempotency
      if (existingTxnIds.has(txnId)) {
        alreadyRecorded++;
        await sleep(PER_DELIVERY_DELAY_MS);
        continue;
      }

      console.log(
        `  ${matched ? "MATCHED" : "UNLINKED"} ${trackingNumber} → ${txnId} ` +
        `state=${stateValue} fees=${bostaFees}`
      );

      if (!DRY_RUN) {
        const batch = db.batch();
        const shipDocId = bostaDeliveryId || trackingNumber;

        // Transaction
        batch.set(db.collection("transactions").doc(txnId), {
          id: txnId,
          user_id: USER_ID,
          title: txnTitle,
          amount: -round2(bostaFees),
          date_time: depositedAt,
          category_id: "cat_shipping_expense",
          note: `Bosta ${stateValue} — TN:${trackingNumber}`,
          payment_method: "bosta",
          sale_id: saleId,
          exclude_from_pl: false,
          bosta_tracking: trackingNumber,
          created_at: FieldValue.serverTimestamp(),
        });

        // Shipment
        batch.set(db.collection("bosta_shipments").doc(shipDocId), {
          user_id: USER_ID,
          bosta_delivery_id: bostaDeliveryId,
          tracking_number: trackingNumber,
          business_reference: businessRef,
          state: state,
          state_value: stateValue,
          type: type,
          total_fees: round2(bostaFees),
          fee_breakdown: feeBreakdown,
          deposited_at: depositedAt,
          awaiting_settlement: false,
          cod: cod,
          expense_recorded: true,
          expense_transaction_id: txnId,
          matched: matched,
          sale_id: saleId,
          synced_at: FieldValue.serverTimestamp(),
        }, {merge: true});

        // Update sale
        if (saleId) {
          batch.update(db.collection("sales").doc(saleId), {
            bosta_delivery_id: bostaDeliveryId,
            bosta_state: state,
            bosta_state_value: stateValue,
            bosta_fees: round2(bostaFees),
            bosta_fee_breakdown: feeBreakdown,
            bosta_synced_at: FieldValue.serverTimestamp(),
            updated_at: FieldValue.serverTimestamp(),
          });
        }

        await batch.commit();
      }

      existingTxnIds.add(txnId);
      newExpenses++;
      totalFeesRecorded += bostaFees;
      if (matched) matchedToSale++;
      else unlinked++;

      await sleep(PER_DELIVERY_DELAY_MS);
    }

    if (deliveries.length < SEARCH_PAGE_LIMIT) {
      hasMore = false;
    } else {
      page++;
    }
  }

  console.log("\n========== BACKFILL SUMMARY ==========");
  console.log(`Total searched:       ${totalSearched}`);
  console.log(`Total fetched (GET):  ${totalFetched}`);
  console.log(`New expenses:         ${newExpenses}`);
  console.log(`  Matched to sale:    ${matchedToSale}`);
  console.log(`  Unlinked:           ${unlinked}`);
  console.log(`Already recorded:     ${alreadyRecorded}`);
  console.log(`Awaiting settlement:  ${awaitingSettlement}`);
  console.log(`Errors:               ${errors}`);
  console.log(`Total fees recorded:  ${round2(totalFeesRecorded)} EGP`);
  console.log(DRY_RUN
    ? "\n(DRY RUN — no changes written. Use --commit to apply.)"
    : "\n(COMMITTED — changes written to Firestore.)");
}

main().catch(err => {
  console.error("Fatal error:", err);
  process.exit(1);
});
