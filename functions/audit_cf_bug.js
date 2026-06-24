const admin = require("firebase-admin");
const path = require("path");
const SA_PATH = path.resolve("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json");
admin.initializeApp({ credential: admin.credential.cert(require(SA_PATH)) });
const db = admin.firestore();
const USER_ID = "EGYQnP7ughdUtTbn04UwUET534i1";
const saleTxnCats = new Set(["cat_sales_revenue", "cat_cogs", "cat_shipping"]);
const plExcluded = new Set(["cat_investments","cat_loan_received","cat_loan_repayment","cat_equity_injection","cat_owner_withdrawal"]);

async function main() {
  const txnSnap = await db.collection("transactions").where("user_id", "==", USER_ID).get();

  // Current BUGGY isCfUserCashTransaction: only excludes positive sale-linked
  let buggyTotal = 0;
  // CORRECT: excludes ALL sale-linked (pos AND neg)
  let fixedTotal = 0;
  // Track what leaks through
  let leakedNegSaleLinked = 0;
  let leakedCount = 0;
  // Also: Bosta shipping expense (cat_shipping_expense, NOT bosta_est/rec) 
  // These are the SAME txns since they ALL start with bosta_est_ or bosta_rec_
  let bostaShipExpense = 0;
  let bostaShipExpenseCount = 0;
  // Non-bosta cat_shipping_expense?
  let nonBostaShipExpense = 0;

  for (const doc of txnSnap.docs) {
    const d = doc.data();
    const catId = d.category_id || "";
    const amt = Number(d.amount) || 0;
    const txnId = d.id || doc.id;
    const isIncome = amt > 0;
    const signed = isIncome ? Math.abs(amt) : -Math.abs(amt);
    const hasSaleId = !!d.sale_id;
    const isSaleCat = saleTxnCats.has(catId);

    // Track cat_shipping_expense
    if (catId === "cat_shipping_expense") {
      if (txnId.startsWith("bosta_est_daily_") || txnId.startsWith("bosta_rec_daily_")) {
        bostaShipExpense += signed;
        bostaShipExpenseCount++;
      } else {
        nonBostaShipExpense += signed;
      }
    }

    // BUGGY filter (current code): exclude positive sale-linked only
    let passesBuggy = true;
    if (hasSaleId && isSaleCat && amt >= 0) passesBuggy = false;
    if (txnId.startsWith("bosta_est_daily_") || txnId.startsWith("bosta_rec_daily_")) passesBuggy = false;
    if (passesBuggy) {
      if (catId === "cat_supplier_payment" || plExcluded.has(catId)) { buggyTotal += signed; }
      else if (d.exclude_from_pl === true) { /* excluded */ }
      else { buggyTotal += signed; }
    }

    // FIXED filter: exclude ALL sale-linked accrual (any sign)
    let passesFixed = true;
    if (hasSaleId && isSaleCat) passesFixed = false;  // ALL sale-linked excluded
    if (txnId.startsWith("bosta_est_daily_") || txnId.startsWith("bosta_rec_daily_")) passesFixed = false;
    if (passesFixed) {
      if (catId === "cat_supplier_payment" || plExcluded.has(catId)) { fixedTotal += signed; }
      else if (d.exclude_from_pl === true) { /* excluded */ }
      else { fixedTotal += signed; }
    }

    // Negative sale-linked that leaks through buggy filter
    if (hasSaleId && isSaleCat && amt < 0) {
      leakedNegSaleLinked += signed;
      leakedCount++;
    }
  }

  console.log("=== CF ENGINE BUG ANALYSIS ===\n");
  console.log(`BUGGY txnCashFlow (current):  ${buggyTotal.toFixed(2)}`);
  console.log(`FIXED txnCashFlow (correct):  ${fixedTotal.toFixed(2)}`);
  console.log(`DIFFERENCE:                   ${(fixedTotal - buggyTotal).toFixed(2)}`);
  console.log(`\nLeaked negative sale-linked:   ${leakedNegSaleLinked.toFixed(2)} (${leakedCount} txns)`);
  console.log(`  → These phantom outflows LOWER Cash & Bank by ${Math.abs(leakedNegSaleLinked).toFixed(2)}`);

  console.log(`\nBosta shipping expense txns:   ${bostaShipExpense.toFixed(2)} (${bostaShipExpenseCount} txns)`);
  console.log(`Non-bosta cat_shipping_expense: ${nonBostaShipExpense.toFixed(2)}`);
  console.log(`  → All bosta shipping starts with bosta_est/rec prefix: ${nonBostaShipExpense === 0 ? "YES ✓" : "NO ✗"}`);

  const cashouts = 230428.64;
  console.log(`\n=== FINAL NUMBERS ===`);
  console.log(`BUGGY:  openingCash + ${buggyTotal.toFixed(2)} + ${cashouts} = openingCash + ${(buggyTotal + cashouts).toFixed(2)}`);
  console.log(`FIXED:  openingCash + ${fixedTotal.toFixed(2)} + ${cashouts} = openingCash + ${(fixedTotal + cashouts).toFixed(2)}`);
  console.log(`\nBuggy Cash & Bank is ${Math.abs(fixedTotal - buggyTotal).toFixed(2)} EGP LOWER than correct`);
}

main().catch(console.error);
