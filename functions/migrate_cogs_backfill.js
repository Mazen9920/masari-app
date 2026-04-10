#!/usr/bin/env node
/**
 * Migration: Backfill zero cost_price sale items from current product costs.
 *
 * For sale items where cost_price == 0 but the Revvo product variant now
 * has a cost > 0, this script:
 * 1. Updates the item's cost_price in the sale document
 * 2. Recalculates and updates the COGS transaction
 *
 * Idempotent: safe to run multiple times (skips items already fixed).
 *
 * Usage:
 *   node migrate_cogs_backfill.js              # dry-run (default)
 *   node migrate_cogs_backfill.js --commit     # actually write changes
 */
const {Firestore} = require("@google-cloud/firestore");

const PROJECT_ID = "massari-574ff";
const SA_PATH = "/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json";
const DRY_RUN = !process.argv.includes("--commit");

function round2(v) { return Math.round(v * 100) / 100; }

async function main() {
  console.log(DRY_RUN ? "=== DRY RUN ===" : "=== COMMITTING ===");

  const db = new Firestore({ projectId: PROJECT_ID, keyFilename: SA_PATH });

  // Load all product variant costs
  const prodsSnap = await db.collection("products").get();
  const variantCosts = new Map(); // variantId → costPrice
  for (const doc of prodsSnap.docs) {
    const prod = doc.data();
    for (const v of (prod.variants || [])) {
      const cost = Number(v.cost_price) || 0;
      if (v.id && cost > 0) variantCosts.set(v.id, cost);
    }
  }
  console.log(`Products with costs: ${variantCosts.size} variants`);

  // Process sales
  const salesSnap = await db.collection("sales").get();
  console.log(`Total sales: ${salesSnap.size}`);

  let salesFixed = 0;
  let itemsFixed = 0;
  let cogsRecovered = 0;

  for (const saleDoc of salesSnap.docs) {
    const sale = saleDoc.data();
    const items = sale.items || [];
    let changed = false;
    let newTotalCogs = 0;

    const updatedItems = items.map(item => {
      const qty = Number(item.quantity) || 0;
      let costPrice = Number(item.cost_price) || 0;

      if (costPrice <= 0 && qty > 0 && item.variant_id) {
        const currentCost = variantCosts.get(item.variant_id) || 0;
        if (currentCost > 0) {
          console.log(`  FIX ${saleDoc.id}: "${item.product_name}" ${qty}x cost 0 → ${currentCost}`);
          costPrice = currentCost;
          changed = true;
          itemsFixed++;
          cogsRecovered += round2(qty * currentCost);
        }
      }

      newTotalCogs += round2(qty * costPrice);
      return { ...item, cost_price: costPrice };
    });

    if (!changed) continue;
    salesFixed++;
    newTotalCogs = round2(newTotalCogs);

    if (!DRY_RUN) {
      // Update sale items
      await db.collection("sales").doc(saleDoc.id).update({
        items: updatedItems,
        updated_at: Firestore.Timestamp.now(),
      });

      // Update COGS transaction
      const cogsTxnId = `sale_cogs_${saleDoc.id}`;
      const cogsRef = db.collection("transactions").doc(cogsTxnId);
      const cogsSnap = await cogsRef.get();
      if (cogsSnap.exists) {
        await cogsRef.update({
          amount: -newTotalCogs,
          updated_at: Firestore.Timestamp.now(),
        });
        console.log(`    Updated COGS txn: ${cogsTxnId} → ${-newTotalCogs}`);
      }
    }
  }

  console.log(`\n${"=".repeat(50)}`);
  console.log(`Sales fixed:        ${salesFixed}`);
  console.log(`Items fixed:        ${itemsFixed}`);
  console.log(`COGS recovered:     ${round2(cogsRecovered)}`);
  if (DRY_RUN) console.log("\nDRY RUN — run with --commit to apply.");
}

main().catch(e => { console.error(e); process.exit(1); });
