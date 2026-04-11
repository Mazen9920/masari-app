/**
 * One-time migration: Consolidate individual bosta_fee_* transactions
 * into daily bosta_daily_YYYY-MM-DD grouped transactions.
 *
 * Usage: node migrate_bosta_daily.js
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

function round2(n) {
  return Math.round(n * 100) / 100;
}

async function main() {
  console.log("Starting Bosta daily migration for user:", USER_ID);

  // Find all old-style individual bosta transactions
  const oldTxnSnap = await db.collection("transactions")
    .where("user_id", "==", USER_ID)
    .where("payment_method", "==", "bosta")
    .get();

  if (oldTxnSnap.empty) {
    console.log("No Bosta transactions found");
    return;
  }

  // Separate old individual txns from new daily txns
  const oldIndividualTxns = oldTxnSnap.docs.filter(d => d.id.startsWith("bosta_fee_"));
  const existingDailyIds = new Set(
    oldTxnSnap.docs.filter(d => d.id.startsWith("bosta_daily_")).map(d => d.id)
  );

  console.log(`Found ${oldIndividualTxns.length} individual bosta_fee_* transactions`);
  console.log(`Found ${existingDailyIds.size} existing bosta_daily_* transactions`);

  if (oldIndividualTxns.length === 0) {
    console.log("Already migrated — no bosta_fee_* transactions remaining");
    return;
  }

  // Group old txns by date
  const byDate = new Map();
  for (const doc of oldIndividualTxns) {
    const data = doc.data();
    const dt = data.date_time?.toDate?.();
    const dateKey = dt ? dt.toISOString().slice(0, 10) : "unknown";
    const group = byDate.get(dateKey) || [];
    group.push(doc);
    byDate.set(dateKey, group);
  }

  console.log(`Grouped into ${byDate.size} dates`);

  let totalMigrated = 0;
  let dailyCreated = 0;

  for (const [dateKey, txnDocs] of byDate.entries()) {
    if (dateKey === "unknown") {
      console.log(`  Skipping ${txnDocs.length} transactions with unknown date`);
      continue;
    }

    const dailyTxnId = `bosta_daily_${dateKey}`;
    const dailyTxnRef = db.collection("transactions").doc(dailyTxnId);

    // Sum all fees for the day
    const dailyTotal = round2(
      txnDocs.reduce((sum, d) => sum + Math.abs(Number(d.data().amount) || 0), 0)
    );
    const shipmentCount = txnDocs.length;
    const txnDate = Timestamp.fromDate(new Date(`${dateKey}T12:00:00Z`));

    // Write in batches
    let batch = db.batch();
    let ops = 0;

    if (!existingDailyIds.has(dailyTxnId)) {
      batch.set(dailyTxnRef, {
        id: dailyTxnId,
        user_id: USER_ID,
        title: `Bosta Shipping — ${dateKey}`,
        amount: -dailyTotal,
        date_time: txnDate,
        category_id: "cat_shipping_expense",
        note: `Bosta shipping fees — ${shipmentCount} shipment${shipmentCount > 1 ? "s" : ""}`,
        payment_method: "bosta",
        sale_id: null,
        exclude_from_pl: false,
        bosta_shipment_count: shipmentCount,
        created_at: FieldValue.serverTimestamp(),
      });
      ops++;
      dailyCreated++;
      console.log(`  ${dateKey}: Creating daily txn (${shipmentCount} shipments, total=${dailyTotal})`);
    } else {
      console.log(`  ${dateKey}: Daily txn already exists, just deleting old ones (${txnDocs.length} txns)`);
    }

    // Delete old individual transactions
    for (const doc of txnDocs) {
      batch.delete(doc.ref);
      ops++;
      if (ops >= 490) {
        await batch.commit();
        batch = db.batch();
        ops = 0;
      }
    }

    // Update shipment docs to point to daily txn
    // Do in chunks of 30 (Firestore 'in' query limit)
    const txnIds = txnDocs.map(d => d.id);
    for (let i = 0; i < txnIds.length; i += 30) {
      const chunk = txnIds.slice(i, i + 30);
      const shipmentSnap = await db.collection("bosta_shipments")
        .where("user_id", "==", USER_ID)
        .where("expense_transaction_id", "in", chunk)
        .get();

      for (const shipDoc of shipmentSnap.docs) {
        batch.update(shipDoc.ref, {
          expense_transaction_id: dailyTxnId,
        });
        ops++;
        if (ops >= 490) {
          await batch.commit();
          batch = db.batch();
          ops = 0;
        }
      }
    }

    if (ops > 0) {
      await batch.commit();
    }

    totalMigrated += txnDocs.length;
  }

  console.log("\n=== Migration Complete ===");
  console.log(`Migrated: ${totalMigrated} individual transactions`);
  console.log(`Created: ${dailyCreated} daily transactions`);
}

main().then(() => process.exit(0)).catch(e => {
  console.error("Migration failed:", e);
  process.exit(1);
});
