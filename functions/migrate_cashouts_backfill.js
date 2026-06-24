/**
 * Migration: Backfill Bosta cashouts from Dashboard API.
 *
 * One-time script to:
 *   1. Login to Bosta Dashboard using encrypted stored credentials
 *   2. Fetch ALL historical cashouts from /wallet/cashouts
 *   3. Store each in bosta_cashouts/{transaction_id}
 *   4. Match pending shipments to cashouts by date range
 *   5. Compute and save the pre-computed summary on bosta_connections
 *
 * Usage:
 *   node migrate_cashouts_backfill.js          # dry run
 *   node migrate_cashouts_backfill.js --commit # apply changes
 */

const admin = require("firebase-admin");
const crypto = require("crypto");
const serviceAccount = require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

// ── Configuration ──────────────────────────────────────────

const TARGET_USER_ID = "EGYQnP7ughdUtTbn04UwUET534i1";
const ENCRYPTION_KEY = "9c89214208efdf03058c8665652fe07220a72d903e0ba620b1e7bafce2005332";
const BOSTA_DASHBOARD_API = "https://app.bosta.co/api/v2";
const FETCH_START_DATE = "2025-01-01";

// AR cutoff: orders before this date are excluded from AR calculation.
// This should be set to when the Bosta integration started tracking.
const AR_CUTOFF_DATE = new Date("2025-03-01T00:00:00Z");

// ── Decryption (mirrors functions/src/shopify-auth.ts) ─────

function decrypt(ciphertext, key) {
  const [ivB64, tagB64, encB64] = ciphertext.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const encrypted = Buffer.from(encB64, "base64");
  const decipher = crypto.createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(encrypted, null, "utf8") + decipher.final("utf8");
}

// ── Helpers ────────────────────────────────────────────────

function round2(n) {
  return Math.round(n * 100) / 100;
}

// ── Dashboard Login ────────────────────────────────────────

async function loginDashboard(email, password) {
  const res = await fetch(`${BOSTA_DASHBOARD_API}/users/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Dashboard login failed (${res.status}): ${body.substring(0, 200)}`);
  }

  const json = await res.json();
  const token = json.token || json.data?.token;
  if (!token) throw new Error("No token in login response");
  return token;
}

// ── Fetch Cashouts ─────────────────────────────────────────

async function fetchAllCashouts(token, startDate, endDate) {
  const all = [];
  let page = 1;
  let totalPages = 1;

  while (page <= totalPages) {
    const url = `${BOSTA_DASHBOARD_API}/wallet/cashouts?start_date=${startDate}&end_date=${endDate}&page=${page}`;
    console.log(`  Fetching page ${page}/${totalPages}: ${url}`);

    const res = await fetch(url, {
      method: "GET",
      headers: {
        "Content-Type": "application/json",
        "Authorization": token,
      },
    });

    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`Cashout fetch failed (${res.status}): ${body.substring(0, 200)}`);
    }

    const json = await res.json();

    let pageCashouts = [];
    if (json.data && Array.isArray(json.data.list)) {
      pageCashouts = json.data.list;
      if (typeof json.data.pages === "number") totalPages = json.data.pages;
    } else if (Array.isArray(json)) {
      pageCashouts = json;
      totalPages = page;
    } else if (Array.isArray(json.data)) {
      pageCashouts = json.data;
      totalPages = page;
    } else if (json.cashouts && Array.isArray(json.cashouts)) {
      pageCashouts = json.cashouts;
      totalPages = page;
    } else {
      console.log("  WARNING: Unexpected response shape, keys:", Object.keys(json));
      break;
    }

    all.push(...pageCashouts);
    if (pageCashouts.length === 0) break;
    page++;
  }

  return all;
}

// ── Main Migration ─────────────────────────────────────────

async function migrate() {
  const commit = process.argv.includes("--commit");
  console.log(commit ? "=== COMMIT MODE ===" : "=== DRY RUN (add --commit to apply) ===");
  console.log();

  // ── Step 1: Read encrypted credentials ───────────────────

  const connRef = db.collection("bosta_connections").doc(TARGET_USER_ID);
  const connDoc = await connRef.get();

  if (!connDoc.exists) {
    console.error(`ERROR: No bosta_connections doc for user ${TARGET_USER_ID}`);
    process.exit(1);
  }

  const connData = connDoc.data();
  if (!connData.dashboard_email_encrypted || !connData.dashboard_password_encrypted) {
    console.error("ERROR: No dashboard credentials stored. Run migrate_dashboard_creds.js first.");
    process.exit(1);
  }

  const email = decrypt(connData.dashboard_email_encrypted, ENCRYPTION_KEY);
  const password = decrypt(connData.dashboard_password_encrypted, ENCRYPTION_KEY);
  console.log(`Dashboard email: ${email}`);
  console.log();

  // ── Step 2: Login to Dashboard ───────────────────────────

  console.log("Logging in to Bosta Dashboard...");
  const token = await loginDashboard(email, password);
  console.log("  Login successful, got JWT token");
  console.log();

  // ── Step 3: Fetch all cashouts ───────────────────────────

  const endDate = new Date().toISOString().slice(0, 10);
  console.log(`Fetching cashouts from ${FETCH_START_DATE} to ${endDate}...`);
  const cashouts = await fetchAllCashouts(token, FETCH_START_DATE, endDate);
  console.log(`  Fetched ${cashouts.length} cashouts`);
  console.log();

  // Display cashouts
  let totalAmount = 0;
  for (const c of cashouts) {
    const amt = Number(c.amount) || 0;
    totalAmount += amt;
    console.log(`  ${c.transaction_id || "no-id"}  ${c.transaction_date || "no-date"}  ${amt.toFixed(2)}`);
  }
  console.log(`  TOTAL: ${round2(totalAmount).toFixed(2)}`);
  console.log();

  // ── Step 4: Store cashouts ───────────────────────────────

  if (!commit) {
    console.log("Would store cashouts in bosta_cashouts collection. Re-run with --commit to apply.");
    console.log();
  } else {
    console.log("Storing cashouts...");
    let stored = 0;
    const batch = db.batch();

    for (const c of cashouts) {
      if (!c.transaction_id) {
        console.log("  SKIP: Missing transaction_id");
        continue;
      }

      const docRef = db.collection("bosta_cashouts").doc(c.transaction_id);
      batch.set(docRef, {
        user_id: TARGET_USER_ID,
        transaction_id: c.transaction_id,
        amount: Number(c.amount) || 0,
        transaction_date: c.transaction_date || null,
        synced_at: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      stored++;
    }

    if (stored > 0) {
      await batch.commit();
    }
    console.log(`  Stored ${stored} cashouts`);
    console.log();
  }

  // ── Step 4b: Backfill cashout_status on ALL shipments ────

  console.log("Backfilling cashout_status on shipments missing it...");
  const allShipsSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", TARGET_USER_ID)
    .get();

  let backfilled = 0;
  let backfillBatch = db.batch();
  let backfillOps = 0;

  for (const doc of allShipsSnap.docs) {
    const data = doc.data();
    // Skip if already has cashout_status set
    if (data.cashout_status) continue;

    const update = {
      cashout_status: "pending",
      cashout_id: null,
      next_cashout_date: null,
    };

    if (commit) {
      backfillBatch.update(doc.ref, update);
      backfillOps++;
      if (backfillOps >= 490) {
        await backfillBatch.commit();
        backfillBatch = db.batch();
        backfillOps = 0;
      }
    }
    backfilled++;
  }

  if (commit && backfillOps > 0) {
    await backfillBatch.commit();
  }

  console.log(`  Total shipments: ${allShipsSnap.size}`);
  console.log(`  Backfilled cashout_status: ${backfilled}`);
  console.log();

  // ── Step 5: Match shipments to cashouts ──────────────────

  console.log("Matching shipments to cashouts...");

  // Load cashouts (from DB if committed, or from fetched data for dry-run display)
  let cashoutRecords;
  if (commit) {
    const cashoutsSnap = await db.collection("bosta_cashouts")
      .where("user_id", "==", TARGET_USER_ID)
      .orderBy("transaction_date", "asc")
      .get();
    cashoutRecords = cashoutsSnap.docs.map((d) => ({
      id: d.id,
      date: d.data().transaction_date,
    }));
  } else {
    cashoutRecords = cashouts
      .filter((c) => c.transaction_id)
      .map((c) => ({ id: c.transaction_id, date: c.transaction_date }))
      .sort((a, b) => (a.date || "").localeCompare(b.date || ""));
  }

  // Find shipments that might be matchable (have deposited_at)
  const allShipmentsSnap = await db.collection("bosta_shipments")
    .where("user_id", "==", TARGET_USER_ID)
    .get();

  // Filter in-app to avoid needing composite index on deposited_at != null
  const pendingDocs = allShipmentsSnap.docs.filter((doc) => {
    const d = doc.data();
    return d.deposited_at != null;
  });

  let matched = 0;
  let alreadyPaid = 0;
  let noMatch = 0;
  let matchBatch = db.batch();
  let batchOps = 0;

  for (const shipDoc of pendingDocs) {
    const data = shipDoc.data();

    if (data.cashout_status === "paid") {
      alreadyPaid++;
      continue;
    }

    const depositedAt = data.deposited_at?.toDate?.()
      ? data.deposited_at.toDate()
      : null;
    if (!depositedAt) continue;

    const depositDateStr = depositedAt.toISOString().slice(0, 10);
    const matchingCashout = cashoutRecords.find((c) => c.date >= depositDateStr);

    if (matchingCashout) {
      console.log(`  ${shipDoc.id} (deposited ${depositDateStr}) → cashout ${matchingCashout.id} (${matchingCashout.date})`);

      if (commit) {
        matchBatch.update(shipDoc.ref, {
          cashout_status: "paid",
          cashout_id: matchingCashout.id,
        });
        batchOps++;

        if (batchOps >= 490) {
          await matchBatch.commit();
          matchBatch = db.batch();
          batchOps = 0;
        }
      }

      matched++;
    } else {
      noMatch++;
    }
  }

  if (commit && batchOps > 0) {
    await matchBatch.commit();
  }

  console.log(`  Total shipments with deposited_at: ${pendingDocs.length}`);
  console.log(`  Already paid: ${alreadyPaid}`);
  console.log(`  Newly matched: ${matched}`);
  console.log(`  No matching cashout: ${noMatch}`);
  console.log();

  // ── Step 6: Compute summary ──────────────────────────────

  console.log("Computing summary...");

  const cfTotalCashouts = round2(totalAmount);
  let cfLastCashoutDate = null;
  for (const c of cashouts) {
    const d = c.transaction_date;
    if (d && (!cfLastCashoutDate || d > cfLastCashoutDate)) {
      cfLastCashoutDate = d;
    }
  }

  // ── Pending AR: start from COD SALES (correct direction) ──
  // Build shipment lookup: saleId → { hasPaid, allRto }
  const allShipmentsSnap2 = await db.collection("bosta_shipments")
    .where("user_id", "==", TARGET_USER_ID).get();

  const saleShipmentMap = {};
  for (const doc of allShipmentsSnap2.docs) {
    const data = doc.data();
    const saleId = data.sale_id;
    if (!saleId) continue;
    if (!saleShipmentMap[saleId]) {
      saleShipmentMap[saleId] = { hasPaid: false, allRto: true };
    }
    const state = Number(data.state) || 0;
    if (data.cashout_status === "paid") saleShipmentMap[saleId].hasPaid = true;
    if (state !== 60 && state !== 46) saleShipmentMap[saleId].allRto = false;
  }

  // Query COD sales
  const codSalesSnap = await db.collection("sales")
    .where("user_id", "==", TARGET_USER_ID)
    .where("payment_method", "==", "Cash on Delivery (COD)")
    .get();

  let cfPendingAr = 0;
  let cfPendingArCount = 0;

  for (const saleDoc of codSalesSnap.docs) {
    const data = saleDoc.data();
    // order_status is numeric: 4 = cancelled
    const orderStatus = Number(data.order_status) || 0;
    if (orderStatus === 4) continue;

    // AR cutoff
    const saleDate = data.date && data.date.toDate
      ? data.date.toDate()
      : (data.date ? new Date(data.date) : null);
    if (saleDate && saleDate < AR_CUTOFF_DATE) continue;

    // Compute total from items (not stored in Firestore)
    const items = data.items || [];
    const subtotal = items.reduce((s, i) => s + (Number(i.quantity) || 0) * (Number(i.unit_price) || 0), 0);
    const total = round2(subtotal + (Number(data.tax_amount) || 0) - (Number(data.discount_amount) || 0) + (Number(data.shipping_cost) || 0));
    if (total <= 0) continue;

    // Check shipment status
    const shipInfo = saleShipmentMap[saleDoc.id];
    if (shipInfo) {
      if (shipInfo.hasPaid) continue;
      if (shipInfo.allRto) continue;
    }

    cfPendingAr += total;
    cfPendingArCount++;
  }

  cfPendingAr = round2(cfPendingAr);

  console.log(`  cf_total_cashouts: ${cfTotalCashouts}`);
  console.log(`  cf_pending_ar: ${cfPendingAr}`);
  console.log(`  cf_pending_ar_count: ${cfPendingArCount}`);
  console.log(`  cf_last_cashout_date: ${cfLastCashoutDate}`);
  console.log();

  console.log(`  cf_ar_cutoff_date: ${AR_CUTOFF_DATE.toISOString().slice(0, 10)}`);

  if (commit) {
    await connRef.update({
      cf_total_cashouts: cfTotalCashouts,
      cf_pending_ar: cfPendingAr,
      cf_pending_ar_count: cfPendingArCount,
      cf_last_cashout_date: cfLastCashoutDate,
      cf_last_cashout_sync_at: admin.firestore.FieldValue.serverTimestamp(),
      cf_ar_cutoff_date: admin.firestore.Timestamp.fromDate(AR_CUTOFF_DATE),
    });
    console.log("Summary + cf_ar_cutoff_date written to bosta_connections.");
  } else {
    console.log("Would write summary + cf_ar_cutoff_date to bosta_connections. Re-run with --commit to apply.");
  }

  console.log("\nDone.");
}

migrate().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
