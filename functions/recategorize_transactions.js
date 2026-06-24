/**
 * recategorize_transactions.js
 *
 * Creates 4 new categories and recategorizes all 30 uncategorized / cat_other
 * transactions for user EGYQnP7ughdUtTbn04UwUET534i1 with correct accounting
 * categories on an accurate accrual basis.
 *
 * New categories: cat_rent, cat_fixed_assets, cat_maintenance, cat_utilities
 *
 * Usage: node recategorize_transactions.js [--dry-run]
 */
const admin = require("firebase-admin");
admin.initializeApp({
  credential: admin.credential.cert(
    require("/Users/mazen/Downloads/massari-574ff-firebase-adminsdk-fbsvc-66d5e2a49a.json")
  ),
});
const db = admin.firestore();
const UID = "EGYQnP7ughdUtTbn04UwUET534i1";
const DRY = process.argv.includes("--dry-run");

// ── Mapping: doc id → { category_id, exclude_from_pl? }
// Key is Firestore transaction doc ID; confirmed from live query output.
const UPDATES = {
  // ── Office furniture & equipment ──────────────────────────
  "1c37019b-b1fa-4fa2-8204-ccd190ca1239": { category_id: "cat_office_furniture" },          // ba2y flos el mokett (carpet balance) -5900
  "f0192b02-a1a8-4c9c-bf2f-1f689971de51": { category_id: "cat_office_furniture" },          // office furniture -3500 (Apr 12)
  "04f7395f-fedd-4322-8308-ec2e4397795c": { category_id: "cat_office_furniture" },          // office furniture -3500 (Apr 14)
  "3d939374-7f3e-4576-9fa5-26c499bc82d2": { category_id: "cat_office_furniture" },          // office furniture -900  (Apr 15)
  "91ee853f-4333-412f-9463-d5373b13a521": { category_id: "cat_office_furniture" },          // hagat mn amazon lel office -800
  "f04f0c31-ee14-4d2c-8b1e-e528d1d0cd12": { category_id: "cat_office_furniture" },          // amazon products -135
  "28195846-606e-4f77-8636-4ece548d3cd7": { category_id: "cat_office_furniture" },          // office -150
  "5458b459-1639-4af2-8ba7-a6bbe1214572": { category_id: "cat_office_furniture" },          // office furniture -2171 (Jun 19)

  // ── Fixed assets (capitalised equipment) ─────────────────
  "2491d0fa-9840-4eda-bf85-5051a0bb5239": { category_id: "cat_fixed_assets" },              // air conditioners (2) -20000

  // ── Rent ──────────────────────────────────────────────────
  "d075bf62-759b-4a7c-8f42-9141ae5dc413": { category_id: "cat_rent" },                      // rent payment -11610

  // ── Marketing ─────────────────────────────────────────────
  "a80574c0-e2fa-477c-8ced-2ce560e50c99": { category_id: "cat_marketing" },                 // ads -5065
  "93790b81-ffbe-419e-8a13-c17663fa3fb6": { category_id: "cat_meta_ads" },                  // marketing (meta ads) -5065
  "44f6f499-962c-4428-9c73-1ff274905c70": { category_id: "cat_marketing" },                 // ugc videos -9000

  // ── Food allowances ───────────────────────────────────────
  "a0ddfaa0-8c7b-4f7b-8609-e2d057634275": { category_id: "cat_food_allowance" },            // ziad allowance -200
  "bf5a26ca-120c-484d-bbf8-285486276be2": { category_id: "cat_food_allowance" },            // karam allowance -200
  "d847f850-8838-4e16-9d63-9155a7245203": { category_id: "cat_food_allowance" },            // allowance food office -1500
  "06cf40c9-ca1c-4b38-87af-027c9fbbb7e0": { category_id: "cat_food_allowance" },            // meeting allowance -1000

  // ── مراضيات (gratuities / small allowances) ───────────────
  "65a45f52-3a3c-473a-bc6e-e8e634359aae": { category_id: "cat________" },                   // meradyat -150
  "f4ed85fb-c04f-48c1-b612-27bce4be1d42": { category_id: "cat________" },                   // allowance يوم تنضيف -300

  // ── سلفه (salary advance) ─────────────────────────────────
  "0d7a3b23-0da4-49c9-9fc7-31e2be384a83": { category_id: "cat_____" },                      // solfa karam -250

  // ── Maintenance & repairs ─────────────────────────────────
  "b45f5b22-573c-4c5e-b1c6-e8380aa7226b": { category_id: "cat_maintenance" },               // transportation w syana takeef (AC maintenance) -5500
  "c41987a6-dca0-4e49-9bf2-456a15b718a0": { category_id: "cat_maintenance" },               // تصليح لاب توب (laptop repair) -2100

  // ── Utilities & communications ────────────────────────────
  "795c36e6-19ca-4943-a89f-d49af45b40c4": { category_id: "cat_utilities" },                 // sim card for rpe -500

  // ── COGS ──────────────────────────────────────────────────
  "04ebfffa-c71b-4460-9a13-11836341d988": { category_id: "cat_cogs" },                      // liquid chalk production -3900

  // ── Sales revenue (non-Shopify) ───────────────────────────
  "a76f5341-b79f-4872-8adf-e8b771ceed95": { category_id: "cat_sales_revenue" },             // supplements sales +800

  // ── Refunds to customers ──────────────────────────────────
  "955ce034-e31c-4ad7-a137-d1021b9dde4c": { category_id: "cat_refunds" },                   // refunds -1050

  // ── Owner loan repayments (exclude from P&L) ─────────────
  "0fa4d361-3dbf-47a8-8363-7610ea4fa2bd": { category_id: "cat_loan_repayment", exclude_from_pl: true }, // دفع فلوس كرم -20000
  "f97057b6-5fcb-4602-8619-e50c17086226": { category_id: "cat_loan_repayment", exclude_from_pl: true }, // payed karam dept -2000

  // ── Charity / personal (exclude from P&L) ────────────────
  "d56a4273-4b23-4110-99d4-31c4f5d30f96": { category_id: "cat_other", exclude_from_pl: true }, // صدقه -13260
  "941a6a03-4fd4-45b4-9b5b-516148ecd3b3": { category_id: "cat_other", exclude_from_pl: true }, // صدقه -2000
};

async function main() {
  console.log(`Recategorize ${DRY ? "(DRY RUN)" : "(LIVE)"} — ${Object.keys(UPDATES).length} transactions`);

  // ── Step 1: create missing categories ──────────────────────
  const newCats = [
    { id: "cat_rent",         name: "Rent",                       icon: "home",      color: "#FF6B6B" },
    { id: "cat_fixed_assets", name: "Fixed Assets",               icon: "computer",  color: "#4ECDC4" },
    { id: "cat_maintenance",  name: "Maintenance & Repairs",      icon: "build",     color: "#95A5A6" },
    { id: "cat_utilities",    name: "Utilities & Communications", icon: "wifi",      color: "#45B7D1" },
  ];
  for (const cat of newCats) {
    const ref = db.collection("categories").doc(cat.id);
    const existing = await ref.get();
    if (!existing.exists) {
      if (!DRY) {
        await ref.set({
          ...cat,
          user_id: UID,
          type: "expense",
          is_default: false,
          created_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
      console.log(`  + created category: ${cat.id} (${cat.name})`);
    } else {
      console.log(`  = category exists: ${cat.id}`);
    }
  }

  // ── Step 2: apply transaction updates ───────────────────────
  // Fetch the transactions to verify title/amount before updating
  const snap = await db.collection("transactions")
    .where("user_id", "==", UID)
    .get();
  const txById = {};
  for (const doc of snap.docs) txById[doc.id] = { doc, data: doc.data() };

  let updated = 0, missed = 0;
  for (const [txId, patch] of Object.entries(UPDATES)) {
    const entry = txById[txId];
    if (!entry) {
      console.log(`  ! NOT FOUND: ${txId}`);
      missed++;
      continue;
    }
    const d = entry.data;
    const updateFields = { category_id: patch.category_id };
    if (patch.exclude_from_pl !== undefined) {
      updateFields.exclude_from_pl = patch.exclude_from_pl;
    }
    const note = `"${d.title}" (${d.amount}) → ${patch.category_id}${patch.exclude_from_pl ? " [excl P&L]" : ""}`;
    if (!DRY) {
      await entry.doc.ref.update(updateFields);
    }
    console.log(`  ✓ ${note}`);
    updated++;
  }

  console.log(`\nDone: ${updated} updated, ${missed} not found.`);
}

main().catch((e) => { console.error(e); process.exit(1); });
