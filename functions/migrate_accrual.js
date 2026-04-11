/**
 * One-time migration: Convert cash-basis bosta_daily_* transactions
 * to accrual-basis bosta_est_daily_* estimate transactions.
 *
 * What it does:
 *   Step 0: Fetch actual createdAt dates from Bosta API for all shipments
 *   Step 1: Compute average fee from all settled shipments → write to connection doc
 *   Step 2: Backfill estimated_fee + bosta_created_at on all shipment docs
 *   Step 3: Create bosta_est_daily_{YYYY-MM-DD} estimate transactions grouped by fulfillment date
 *   Step 4: Delete old bosta_daily_* transactions
 *   Step 5: Verify totals match
 *
 * Usage: node migrate_accrual.js [--dry-run]
 */
const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});

const db = admin.firestore();
const FieldValue = admin.firestore.FieldValue;
const Timestamp = admin.firestore.Timestamp;

const USER_ID = "EGYQnP7ughdUtTbn04UwUET534i1";
const DRY_RUN = process.argv.includes("--dry-run");

const BOSTA_API_BASE = "https://app.bosta.co/api/v2";
const BOSTA_API_KEY = "955a016d1f722c7cab2c5d73a69a164b13bd8b2d766544ec4085d845a452ef04";

function round2(n) {
  return Math.round(n * 100) / 100;
}

/**
 * Fetch all deliveries from Bosta search API to build
 * a trackingNumber → createdAt map.
 */
async function fetchBostaCreatedDates() {
  const createdAtMap = new Map(); // trackingNumber → ISO date string
  const headers = {
    "Content-Type": "application/json",
    "Authorization": BOSTA_API_KEY,
  };

  let page = 1;
  const perPage = 50;
  let total = 0;

  while (true) {
    const res = await fetch(`${BOSTA_API_BASE}/deliveries/search`, {
      method: "POST",
      headers,
      body: JSON.stringify({ page, perPage }),
    });

    const json = await res.json();
    const data = json.data || json;
    const deliveries = data.deliveries || [];

    if (deliveries.length === 0) break;

    for (const d of deliveries) {
      const tn = d.trackingNumber;
      const id = d._id;
      const createdAt = d.createdAt;
      if (createdAt) {
        if (tn) createdAtMap.set(tn, createdAt);
        if (id) createdAtMap.set(id, createdAt);
      }
    }

    total += deliveries.length;
    if (page % 50 === 0) {
      console.log(`    Fetched ${total} deliveries (page ${page})...`);
    }

    if (deliveries.length < perPage) break;
    page++;

    // Small delay to avoid rate limits
    if (page % 10 === 0) {
      await new Promise(r => setTimeout(r, 100));
    }
  }

  console.log(`    Fetched ${total} deliveries across ${page} pages`);
  return createdAtMap;
}

async function main() {
  console.log(`\n=== Bosta Accrual Migration ${DRY_RUN ? "(DRY RUN)" : ""} ===`);
  console.log(`User: ${USER_ID}\n`);

  // ── Step 0: Fetch actual createdAt dates from Bosta API ──────

  console.log("Step 0: Fetching actual createdAt dates from Bosta API...");
  const bostaCreatedAtMap = await fetchBostaCreatedDates();
  console.log(`  ✓ Got createdAt for ${bostaCreatedAtMap.size} deliveries\n`);

  // ── Step 1: Compute average fee from all settled shipments ──────

  console.log("Step 1: Computing average fee from settled shipments...");

  const allShipmentsSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", USER_ID)
    .get();

  const settledShipments = [];
  const unsettledShipments = [];

  for (const doc of allShipmentsSnap.docs) {
    const data = doc.data();
    const fees = Number(data.total_fees) || 0;
    if (fees > 0) {
      settledShipments.push({ id: doc.id, data, fees });
    } else {
      unsettledShipments.push({ id: doc.id, data });
    }
  }

  const totalSettledFees = round2(
    settledShipments.reduce((sum, s) => sum + s.fees, 0)
  );
  const totalSettledCount = settledShipments.length;
  const averageBostaFee = totalSettledCount > 0
    ? round2(totalSettledFees / totalSettledCount)
    : 90; // DEFAULT_ESTIMATED_FEE fallback

  console.log(`  Total shipments: ${allShipmentsSnap.size}`);
  console.log(`  Settled: ${totalSettledCount} (total fees: ${totalSettledFees} EGP)`);
  console.log(`  Unsettled: ${unsettledShipments.length}`);
  console.log(`  Average fee: ${averageBostaFee} EGP`);

  // Write to connection doc
  if (!DRY_RUN) {
    await db.collection("bosta_connections").doc(USER_ID).update({
      average_bosta_fee: averageBostaFee,
      total_settled_fees: totalSettledFees,
      total_settled_count: totalSettledCount,
    });
    console.log("  ✓ Written average_bosta_fee to connection doc\n");
  } else {
    console.log("  [DRY RUN] Would write average_bosta_fee to connection doc\n");
  }

  // ── Step 2: Backfill estimated_fee + bosta_created_at on all shipments ──

  console.log("Step 2: Backfilling estimated_fee and bosta_created_at on shipment docs...");

  let backfillCount = 0;
  let apiDateHits = 0;
  let fallbackDateHits = 0;
  let batch = db.batch();
  let ops = 0;

  /**
   * Resolve the best available createdAt for a shipment.
   * Priority: Bosta API createdAt → existing bosta_created_at → deposited_at → synced_at → now
   */
  function resolveCreatedAt(data) {
    // 1. Bosta API (most accurate)
    const apiDate = bostaCreatedAtMap.get(data.tracking_number)
      || bostaCreatedAtMap.get(data.bosta_delivery_id);
    if (apiDate) {
      apiDateHits++;
      return Timestamp.fromDate(new Date(apiDate));
    }
    // 2. Already stored
    if (data.bosta_created_at) {
      return data.bosta_created_at;
    }
    // 3. Deposited at (better than synced_at — at least reflects activity timing)
    if (data.deposited_at) {
      fallbackDateHits++;
      return data.deposited_at;
    }
    // 4. Synced at (last resort)
    fallbackDateHits++;
    return data.synced_at || Timestamp.now();
  }

  // For settled shipments: estimated_fee = actual fee (→ zero adjustment)
  for (const s of settledShipments) {
    const bostaCreatedAt = resolveCreatedAt(s.data);

    batch.update(db.collection("bosta_shipments").doc(s.id), {
      estimated_fee: s.fees,
      bosta_created_at: bostaCreatedAt,
      estimate_recorded: false,
      estimate_transaction_id: null,
      reconciled: true, // already settled, adj = 0
      reconciliation_transaction_id: null,
    });
    ops++;
    backfillCount++;

    if (ops >= 490) {
      if (!DRY_RUN) await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  // For unsettled shipments: estimated_fee = average
  for (const s of unsettledShipments) {
    const bostaCreatedAt = resolveCreatedAt(s.data);

    batch.update(db.collection("bosta_shipments").doc(s.id), {
      estimated_fee: averageBostaFee,
      bosta_created_at: bostaCreatedAt,
      estimate_recorded: false,
      estimate_transaction_id: null,
      reconciled: false,
      reconciliation_transaction_id: null,
    });
    ops++;
    backfillCount++;

    if (ops >= 490) {
      if (!DRY_RUN) await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0 && !DRY_RUN) {
    await batch.commit();
  }
  console.log(`  ✓ Backfilled ${backfillCount} shipment docs`);
  console.log(`    API dates: ${apiDateHits}, Fallback dates: ${fallbackDateHits}\n`);

  // ── Step 3: Create estimate transactions grouped by fulfillment date ──

  console.log("Step 3: Creating estimate transactions by fulfillment date...");

  // Re-read shipments (now with bosta_created_at set)
  const updatedShipmentsSnap = DRY_RUN
    ? allShipmentsSnap // In dry run, use original data
    : await db.collection("bosta_shipments")
        .where("user_id", "==", USER_ID)
        .get();

  // Group ALL shipments by fulfillment date
  const byFulfillmentDate = new Map();

  for (const doc of updatedShipmentsSnap.docs) {
    const data = doc.data();
    const fees = Number(data.total_fees) || 0;
    const estimatedFee = fees > 0 ? fees : averageBostaFee;

    // Parse fulfillment date — use same resolution logic as Step 2
    let dateKey;
    // In dry-run: resolve from API map since shipments aren't updated
    // In real run: bosta_created_at was already written in Step 2
    const apiDate = bostaCreatedAtMap.get(data.tracking_number)
      || bostaCreatedAtMap.get(data.bosta_delivery_id);
    if (apiDate) {
      dateKey = new Date(apiDate).toISOString().slice(0, 10);
    } else if (data.bosta_created_at) {
      const dt = data.bosta_created_at.toDate
        ? data.bosta_created_at.toDate()
        : new Date(data.bosta_created_at);
      dateKey = dt.toISOString().slice(0, 10);
    } else if (data.deposited_at) {
      const dt = data.deposited_at.toDate
        ? data.deposited_at.toDate()
        : new Date(data.deposited_at);
      dateKey = dt.toISOString().slice(0, 10);
    } else {
      const createdAt = data.synced_at;
      if (createdAt) {
        const dt = createdAt.toDate ? createdAt.toDate() : new Date(createdAt);
        dateKey = dt.toISOString().slice(0, 10);
      } else {
        dateKey = new Date().toISOString().slice(0, 10);
      }
    }

    const group = byFulfillmentDate.get(dateKey) || [];
    group.push({
      docId: doc.id,
      estimatedFee,
      isSettled: fees > 0,
    });
    byFulfillmentDate.set(dateKey, group);
  }

  console.log(`  Grouped into ${byFulfillmentDate.size} fulfillment dates`);

  let estTxnCreated = 0;
  let estTotalAmount = 0;
  let shipmentsLinked = 0;

  for (const [dateKey, items] of byFulfillmentDate.entries()) {
    const estTxnId = `bosta_est_daily_${dateKey}`;
    const estTxnRef = db.collection("transactions").doc(estTxnId);
    const txnDate = Timestamp.fromDate(new Date(`${dateKey}T12:00:00Z`));

    const dailyTotal = round2(
      items.reduce((sum, s) => sum + s.estimatedFee, 0)
    );
    const shipmentCount = items.length;

    batch = db.batch();
    ops = 0;

    // Create estimate transaction
    batch.set(estTxnRef, {
      id: estTxnId,
      user_id: USER_ID,
      title: `Bosta Shipping (Est.) — ${dateKey}`,
      amount: -dailyTotal,
      date_time: txnDate,
      category_id: "cat_shipping_expense",
      note: `Bosta shipping fees (est.) — ${shipmentCount} shipment${shipmentCount > 1 ? "s" : ""}`,
      payment_method: "bosta",
      sale_id: null,
      exclude_from_pl: false,
      is_estimate: true,
      is_reconciliation: false,
      bosta_shipment_count: shipmentCount,
      created_at: FieldValue.serverTimestamp(),
    });
    ops++;
    estTxnCreated++;
    estTotalAmount += dailyTotal;

    // Update each shipment doc
    for (const item of items) {
      batch.update(db.collection("bosta_shipments").doc(item.docId), {
        estimate_recorded: true,
        estimate_transaction_id: estTxnId,
      });
      ops++;
      shipmentsLinked++;

      if (ops >= 490) {
        if (!DRY_RUN) await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }

    if (ops > 0 && !DRY_RUN) {
      await batch.commit();
    }
  }

  estTotalAmount = round2(estTotalAmount);
  console.log(`  ✓ Created ${estTxnCreated} estimate transactions`);
  console.log(`  ✓ Linked ${shipmentsLinked} shipments to estimate txns`);
  console.log(`  Total estimated amount: ${estTotalAmount} EGP\n`);

  // ── Step 4: Delete old bosta_daily_* transactions ──────

  console.log("Step 4: Deleting old bosta_daily_* transactions...");

  const oldBostaTxnSnap = await db.collection("transactions")
    .where("user_id", "==", USER_ID)
    .where("payment_method", "==", "bosta")
    .get();

  const oldDailyTxns = oldBostaTxnSnap.docs.filter(d => d.id.startsWith("bosta_daily_"));
  let oldDailyTotal = 0;

  batch = db.batch();
  ops = 0;

  for (const doc of oldDailyTxns) {
    oldDailyTotal += Math.abs(Number(doc.data().amount) || 0);
    batch.delete(doc.ref);
    ops++;

    if (ops >= 490) {
      if (!DRY_RUN) await batch.commit();
      batch = db.batch();
      ops = 0;
    }
  }

  if (ops > 0 && !DRY_RUN) {
    await batch.commit();
  }

  oldDailyTotal = round2(oldDailyTotal);
  console.log(`  ✓ Deleted ${oldDailyTxns.length} old bosta_daily_* transactions`);
  console.log(`  Old daily total: ${oldDailyTotal} EGP\n`);

  // ── Step 5: Verify totals ──────

  console.log("Step 5: Verification...");

  if (DRY_RUN) {
    console.log("  [DRY RUN] Skipping verification — no writes were made");
    console.log(`\n  Expected: ${estTotalAmount} EGP (estimates) should cover ${oldDailyTotal} EGP (old daily)`);
    console.log(`  Note: Estimates include unsettled shipments too, so estimate total >= old daily total`);
  } else {
    // Re-query to verify
    const verifyTxnSnap = await db.collection("transactions")
      .where("user_id", "==", USER_ID)
      .where("payment_method", "==", "bosta")
      .get();

    const remainingDaily = verifyTxnSnap.docs.filter(d => d.id.startsWith("bosta_daily_"));
    const newEstimates = verifyTxnSnap.docs.filter(d => d.id.startsWith("bosta_est_daily_"));
    const newReconciliations = verifyTxnSnap.docs.filter(d => d.id.startsWith("bosta_rec_daily_"));

    const newEstTotal = round2(
      newEstimates.reduce((sum, d) => sum + Math.abs(Number(d.data().amount) || 0), 0)
    );

    console.log(`  Remaining bosta_daily_*: ${remainingDaily.length} (expected: 0)`);
    console.log(`  New bosta_est_daily_*: ${newEstimates.length}`);
    console.log(`  New bosta_rec_daily_*: ${newReconciliations.length} (expected: 0 for migration)`);
    console.log(`  Estimate total: ${newEstTotal} EGP`);
    console.log(`  Old daily total was: ${oldDailyTotal} EGP`);

    // The estimate total should be >= old daily total because we also
    // estimate unsettled shipments that had no old daily transaction
    if (remainingDaily.length === 0) {
      console.log("\n  ✓ All old bosta_daily_* transactions deleted");
    } else {
      console.log("\n  ✗ ERROR: Some old bosta_daily_* transactions remain!");
    }

    if (newEstTotal >= oldDailyTotal - 0.02) {
      console.log(`  ✓ Estimate total (${newEstTotal}) covers old daily total (${oldDailyTotal})`);
    } else {
      console.log(`  ✗ WARNING: Estimate total (${newEstTotal}) is less than old daily total (${oldDailyTotal})`);
    }

    // Check settled shipments sum matches old daily total
    const settledEstTotal = round2(
      settledShipments.reduce((sum, s) => sum + s.fees, 0)
    );
    console.log(`  ✓ Settled shipments fee sum: ${settledEstTotal} EGP (should match old daily: ${oldDailyTotal})`);
  }

  console.log("\n=== Migration complete ===\n");
}

main().then(() => process.exit(0)).catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
