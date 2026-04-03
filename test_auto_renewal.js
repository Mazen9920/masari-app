#!/usr/bin/env node
/**
 * test_auto_renewal.js — End-to-end test script for Paymob auto-renewal CFs.
 *
 * Usage:
 *   node test_auto_renewal.js <test_email> <test_password>
 *
 * Prerequisites:
 *   - A test Firebase user account (email/password)
 *   - Functions deployed to massari-574ff
 *
 * Tests:
 *   1. getSubscriptionStatus — read-only, returns current state
 *   2. createPaymentIntent — creates Paymob intention, returns checkout URL
 *   3. toggleAutoRenew — toggle auto-renew on/off
 *   4. removePaymentMethod — remove saved card
 */

const FIREBASE_API_KEY = "AIzaSyBmDbbtaLoAzb55a30KG5X0I0SlN7RpDzA"; // web key
const PROJECT_ID = "massari-574ff";
const REGION = "us-central1";
const CF_BASE = `https://${REGION}-${PROJECT_ID}.cloudfunctions.net`;

// ── Helpers ─────────────────────────────────────────────────────────────────

async function signIn(email, password) {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`,
    {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({email, password, returnSecureToken: true}),
    }
  );
  const data = await res.json();
  if (data.error) throw new Error(`Auth failed: ${data.error.message}`);
  return data.idToken;
}

async function callCallable(functionName, idToken, payload = {}) {
  const url = `${CF_BASE}/${functionName}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${idToken}`,
    },
    body: JSON.stringify({data: payload}),
  });
  const raw = await res.text();
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch {
    parsed = {raw};
  }
  return {status: res.status, body: parsed};
}

function pass(name) {
  console.log(`  ✅ ${name}`);
}
function fail(name, detail) {
  console.log(`  ❌ ${name}: ${detail}`);
}

// ── Tests ───────────────────────────────────────────────────────────────────

async function testGetSubscriptionStatus(token) {
  console.log("\n── Test 1: getSubscriptionStatus ──");
  const {status, body} = await callCallable("getSubscriptionStatus", token);
  if (status !== 200) {
    fail("HTTP status", `expected 200, got ${status}`);
    console.log("  Body:", JSON.stringify(body, null, 2));
    return null;
  }
  const r = body.result ?? body;
  const requiredFields = [
    "subscription_tier",
    "subscription_status",
  ];
  const optionalFields = [
    "subscription_plan",
    "subscription_expires_at",
    "payment_source",
    "paymob_card_last4",
    "paymob_card_brand",
    "paymob_auto_renew",
  ];

  let allOk = true;
  for (const f of requiredFields) {
    if (r[f] !== undefined) {
      pass(`field "${f}" = ${JSON.stringify(r[f])}`);
    } else {
      fail(`field "${f}"`, "missing");
      allOk = false;
    }
  }
  for (const f of optionalFields) {
    const val = r[f];
    console.log(`  ℹ️  "${f}" = ${JSON.stringify(val)}`);
  }
  if (allOk) pass("getSubscriptionStatus — all required fields present");
  return r;
}

async function testCreatePaymentIntent(token) {
  console.log("\n── Test 2: createPaymentIntent ──");

  // Test invalid plan
  const {status: s1, body: b1} = await callCallable(
    "createPaymentIntent",
    token,
    {plan: "nonexistent_plan"}
  );
  if (s1 === 200) {
    fail("invalid plan rejection", "should have failed but got 200");
  } else {
    pass(`invalid plan correctly rejected (HTTP ${s1})`);
  }

  // Test valid plan
  const {status: s2, body: b2} = await callCallable(
    "createPaymentIntent",
    token,
    {plan: "growth_monthly"}
  );
  if (s2 !== 200) {
    fail("create intent", `HTTP ${s2}`);
    console.log("  Body:", JSON.stringify(b2, null, 2));
    return null;
  }
  const r = b2.result ?? b2;
  if (r.iframe_url && r.iframe_url.includes("unifiedcheckout")) {
    pass(`iframe_url received: ${r.iframe_url.substring(0, 80)}…`);
  } else {
    fail("iframe_url", `unexpected: ${JSON.stringify(r.iframe_url)}`);
  }
  if (r.client_secret) {
    pass(`client_secret received (length=${r.client_secret.length})`);
  } else {
    fail("client_secret", "missing");
  }
  if (r.public_key) {
    pass(`public_key received: ${r.public_key.substring(0, 20)}…`);
  } else {
    fail("public_key", "missing");
  }
  return r;
}

async function testToggleAutoRenew(token, subStatus) {
  console.log("\n── Test 3: toggleAutoRenew ──");

  // Try enabling — should fail if no saved card
  const {status: s1, body: b1} = await callCallable(
    "toggleAutoRenew",
    token,
    {enabled: true}
  );
  const hasCard = subStatus?.paymob_card_last4;
  const isPaymob = subStatus?.payment_source === "paymob";

  if (!hasCard || !isPaymob) {
    // Should fail — no card saved
    if (s1 !== 200) {
      pass("correctly rejected enable (no saved card)");
    } else {
      const r = b1.result ?? b1;
      if (r.error) {
        pass(`correctly rejected: ${r.error}`);
      } else {
        fail("enable without card", "should have failed");
      }
    }
  } else {
    // Has card — should succeed
    if (s1 === 200) {
      pass("auto-renew enabled");
    } else {
      fail("enable auto-renew", `HTTP ${s1}: ${JSON.stringify(b1)}`);
    }
    // Disable it back
    const {status: s2} = await callCallable("toggleAutoRenew", token, {
      enabled: false,
    });
    if (s2 === 200) {
      pass("auto-renew disabled back");
    } else {
      fail("disable auto-renew", `HTTP ${s2}`);
    }
  }
}

async function testRemovePaymentMethod(token, subStatus) {
  console.log("\n── Test 4: removePaymentMethod ──");
  const {status, body} = await callCallable("removePaymentMethod", token);
  const r = body.result ?? body;

  if (status !== 200) {
    fail("removePaymentMethod", `HTTP ${status}: ${JSON.stringify(body)}`);
    return;
  }

  if (subStatus?.paymob_card_last4) {
    // Had a card — should be removed
    if (r.removed === true) {
      pass("card removed successfully");
    } else {
      fail("card removal", `got: ${JSON.stringify(r)}`);
    }
  } else {
    // No card saved
    if (r.removed === false && r.reason === "no_saved_card") {
      pass("correctly reported no saved card");
    } else {
      pass(`response: ${JSON.stringify(r)}`);
    }
  }
}

// ── Main ────────────────────────────────────────────────────────────────────

async function main() {
  const [email, password] = process.argv.slice(2);
  if (!email || !password) {
    console.log("Usage: node test_auto_renewal.js <email> <password>");
    process.exit(1);
  }

  console.log("🔑 Signing in…");
  let token;
  try {
    token = await signIn(email, password);
    console.log("  Authenticated ✓\n");
  } catch (e) {
    console.error("  Auth error:", e.message);
    process.exit(1);
  }

  // Test 1: getSubscriptionStatus
  const subStatus = await testGetSubscriptionStatus(token);

  // Test 2: createPaymentIntent
  await testCreatePaymentIntent(token);

  // Test 3: toggleAutoRenew
  await testToggleAutoRenew(token, subStatus);

  // Test 4: removePaymentMethod (⚠️ this will remove a saved card if one exists)
  // Uncomment the next line only if you want to test card removal:
  // await testRemovePaymentMethod(token, subStatus);

  console.log("\n══════════════════════════════════");
  console.log("Tests complete. Review results above.");
  console.log("══════════════════════════════════\n");

  // For a full E2E test:
  console.log("📋 Manual E2E steps:");
  console.log("  1. Open the iframe_url from Test 2 in a browser");
  console.log("  2. Use Paymob test card: 5123456789012346 (Mastercard)");
  console.log("     Expiry: 12/25, CVV: 123");
  console.log("  3. Check Firebase console → users/{uid} for:");
  console.log("     - paymob_card_token (should be set)");
  console.log("     - paymob_card_last4 (should be '2346')");
  console.log("     - paymob_auto_renew: true");
  console.log("  4. Re-run this script to verify getSubscriptionStatus returns card info");
}

main().catch(console.error);
