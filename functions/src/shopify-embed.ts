/**
 * Shopify Embedded App — HTML + API
 *
 * Provides the merchant-facing UI that loads inside the Shopify admin
 * iframe, plus API endpoints for managing integration settings.
 *
 * Authentication: Shopify App Bridge session tokens (HS256 JWTs).
 */

import {getFirestore, FieldValue} from "firebase-admin/firestore";
import {getAuth} from "firebase-admin/auth";
import * as logger from "firebase-functions/logger";
import {createHmac, timingSafeEqual, createDecipheriv} from "crypto";

const SHOPIFY_API_VERSION = "2024-01";

function getDb() {
  return getFirestore();
}

function decrypt(encryptedStr: string, key: string): string {
  const [ivB64, tagB64, dataB64] = encryptedStr.split(":");
  const keyBuf = Buffer.from(key, "hex");
  const iv = Buffer.from(ivB64, "base64");
  const tag = Buffer.from(tagB64, "base64");
  const data = Buffer.from(dataB64, "base64");
  const decipher = createDecipheriv("aes-256-gcm", keyBuf, iv);
  decipher.setAuthTag(tag);
  return decipher.update(data).toString("utf8") + decipher.final("utf8");
}

// ── Session-token verification ─────────────────────────────

/**
 * Verifies a Shopify App Bridge session token (JWT, HS256).
 * Returns the shop hostname on success, null on failure.
 */
export function verifySessionToken(
  token: string,
  secret: string,
  apiKey: string,
): {shop: string} | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    const payload = JSON.parse(
      Buffer.from(parts[1], "base64url").toString("utf8"),
    );

    // Verify HS256 signature
    const signInput = `${parts[0]}.${parts[1]}`;
    const expectedSig = createHmac("sha256", secret)
      .update(signInput)
      .digest("base64url");

    const strip = (s: string) => s.replace(/=+$/, "");
    if (
      !timingSafeEqual(
        Buffer.from(strip(expectedSig)),
        Buffer.from(strip(parts[2])),
      )
    ) {
      logger.warn("Session token signature mismatch");
      return null;
    }

    // Expiry check (allow 60 s leeway)
    const now = Math.floor(Date.now() / 1000);
    if (payload.exp && now > payload.exp + 60) {
      logger.warn("Session token expired");
      return null;
    }

    // Audience must match our API key
    if (payload.aud !== apiKey) {
      logger.warn("Session token audience mismatch", {
        expected: apiKey,
        got: payload.aud,
      });
      return null;
    }

    const destUrl = new URL(payload.dest);
    return {shop: destUrl.hostname};
  } catch (err) {
    logger.warn("Session token verification error", {error: String(err)});
    return null;
  }
}

// ── Helper: find connection by shop domain ─────────────────

async function findConnectionByShop(shop: string) {
  const snap = await getDb()
    .collection("shopify_connections")
    .where("shop_domain", "==", shop)
    .get();

  if (snap.empty) return null;

  // Prefer active, then error, then anything else
  const order: Record<string, number> = {
    active: 0, error: 1, pending: 2, disconnected: 3,
  };
  const sorted = snap.docs.sort((a, b) =>
    (order[a.data().status] ?? 9) - (order[b.data().status] ?? 9)
  );

  return {id: sorted[0].id, data: sorted[0].data()};
}

// ── Helper: find ALL connections by shop domain ────────────

async function findAllConnectionsByShop(shop: string) {
  const snap = await getDb()
    .collection("shopify_connections")
    .where("shop_domain", "==", shop)
    .get();

  return snap.docs
    .filter((d) => !d.data().nonce || d.data().status !== "pending")
    .map((d) => ({id: d.id, data: d.data()}));
}

// ═══════════════════════════════════════════════════════════
// handleEmbedApi — called from storeAuthCallback when _api
//   query param is present.
// ═══════════════════════════════════════════════════════════

/* eslint-disable @typescript-eslint/no-explicit-any */
export async function handleEmbedApi(
  req: any,
  res: any,
  apiKey: string,
  apiSecret: string,
  encryptionKey: string,
): Promise<void> {
  res.set(
    "Content-Security-Policy",
    "frame-ancestors https://*.myshopify.com https://admin.shopify.com;",
  );

  // ── Authenticate via session token ───────────────────────
  const authHeader = req.headers.authorization as string | undefined;
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    res.status(401).json({error: "Missing session token"});
    return;
  }

  const verified = verifySessionToken(
    authHeader.substring(7),
    apiSecret,
    apiKey,
  );
  if (!verified) {
    res.status(401).json({error: "Invalid session token"});
    return;
  }

  const shop = verified.shop;
  const action = (req.query as Record<string, string>)._api;

  logger.info("Embed API request", {action, shop});

  try {
    switch (action) {
    // ── STATUS ──────────────────────────────────────────
    case "status": {
      const conn = await findConnectionByShop(shop);
      logger.info("Status lookup result", {
        shop,
        found: !!conn,
        connId: conn?.id ?? null,
        connStatus: conn?.data?.status ?? null,
      });
      if (!conn) {
        res.json({connected: false});
        return;
      }
      const d = conn.data;
      const userId = d.user_id ?? conn.id;
      const isInstallDoc = conn.id.startsWith("_install_");
      res.json({
        connected: true,
        status: d.status,
        shop_domain: d.shop_domain,
        sync_orders_enabled: d.sync_orders_enabled ?? true,
        sync_inventory_enabled: d.sync_inventory_enabled ?? false,
        inventory_sync_mode: d.inventory_sync_mode ?? "on_demand",
        shopify_location_id: d.shopify_location_id ?? null,
        shopify_location_name: d.shopify_location_name ?? null,
        connected_at: d.connected_at?.toDate?.() ?? d.connected_at,
        last_order_sync_at:
            d.last_order_sync_at?.toDate?.() ?? null,
        last_inventory_sync_at:
            d.last_inventory_sync_at?.toDate?.() ?? null,
        user_linked: !!d.user_id && !isInstallDoc,
        linked_account: {
          id: conn.id,
          user_id: isInstallDoc ? null : userId,
          status: d.status ?? "unknown",
          connected_at: d.connected_at?.toDate?.() ?? d.connected_at ?? null,
          last_order_sync_at:
            d.last_order_sync_at?.toDate?.() ?? null,
          sync_orders_enabled: d.sync_orders_enabled ?? false,
          sync_inventory_enabled: d.sync_inventory_enabled ?? false,
        },
      });
      return;
    }

    // ── UPDATE SETTINGS ─────────────────────────────────
    case "settings": {
      if (req.method !== "POST") {
        res.status(405).json({error: "Method not allowed"});
        return;
      }
      const conn = await findConnectionByShop(shop);
      if (!conn || conn.data.status !== "active") {
        res.status(404).json({error: "No active connection"});
        return;
      }

      const body = req.body as Record<string, unknown>;
      const updates: Record<string, unknown> = {
        updated_at: FieldValue.serverTimestamp(),
      };

      if (typeof body.sync_orders_enabled === "boolean") {
        updates.sync_orders_enabled = body.sync_orders_enabled;
      }
      if (typeof body.sync_inventory_enabled === "boolean") {
        updates.sync_inventory_enabled = body.sync_inventory_enabled;
      }
      if (
        body.inventory_sync_mode === "always" ||
          body.inventory_sync_mode === "on_demand"
      ) {
        updates.inventory_sync_mode = body.inventory_sync_mode;
      }

      await getDb()
        .collection("shopify_connections")
        .doc(conn.id)
        .update(updates);

      logger.info("Settings updated from embedded app", {
        shop,
        keys: Object.keys(updates).filter((k) => k !== "updated_at"),
      });
      res.json({success: true});
      return;
    }

    // ── UPDATE LOCATION ─────────────────────────────────
    case "location": {
      if (req.method !== "POST") {
        res.status(405).json({error: "Method not allowed"});
        return;
      }
      const conn = await findConnectionByShop(shop);
      if (!conn || conn.data.status !== "active") {
        res.status(404).json({error: "No active connection"});
        return;
      }
      const body = req.body as Record<string, unknown>;
      await getDb()
        .collection("shopify_connections")
        .doc(conn.id)
        .update({
          shopify_location_id: body.location_id || null,
          shopify_location_name: body.location_name || null,
          updated_at: FieldValue.serverTimestamp(),
        });
      res.json({success: true});
      return;
    }

    // ── LIST LOCATIONS ──────────────────────────────────
    case "locations": {
      const conn = await findConnectionByShop(shop);
      if (!conn || !conn.data.access_token) {
        res.status(404).json({error: "No active connection"});
        return;
      }
      const accessToken = decrypt(conn.data.access_token, encryptionKey);
      const locRes = await fetch(
        `https://${shop}/admin/api/${SHOPIFY_API_VERSION}/locations.json`,
        {headers: {"X-Shopify-Access-Token": accessToken}},
      );
      if (!locRes.ok) {
        res.status(502).json({error: "Failed to fetch locations"});
        return;
      }
      const {locations} = (await locRes.json()) as {
          locations: Array<{id: number; name: string; active: boolean}>;
        };
      res.json({
        locations: locations
          .filter((l) => l.active)
          .map((l) => ({id: String(l.id), name: l.name})),
      });
      return;
    }

    // ── DISCONNECT ──────────────────────────────────────
    case "disconnect": {
      if (req.method !== "POST") {
        res.status(405).json({error: "Method not allowed"});
        return;
      }
      const conn = await findConnectionByShop(shop);
      if (!conn) {
        res.status(404).json({error: "No connection found"});
        return;
      }

      // Unregister webhooks
      const enc = conn.data.access_token as string | undefined;
      const whIds = conn.data.webhook_ids as
          Record<string, string> | undefined;
      if (enc && whIds) {
        try {
          const at = decrypt(enc, encryptionKey);
          await Promise.all(
            Object.entries(whIds).map(async ([topic, id]) => {
              try {
                await fetch(
                  `https://${shop}/admin/api/${SHOPIFY_API_VERSION}/webhooks/${id}.json`,
                  {method: "DELETE", headers: {"X-Shopify-Access-Token": at}},
                );
              } catch (e) {
                logger.warn(`Webhook delete ${topic}`, {error: String(e)});
              }
            }),
          );
        } catch (e) {
          logger.error("Decrypt for webhook cleanup", {error: String(e)});
        }
      }

      await getDb()
        .collection("shopify_connections")
        .doc(conn.id)
        .update({
          status: "disconnected",
          access_token: null,
          webhook_ids: null,
          disconnected_at: FieldValue.serverTimestamp(),
          updated_at: FieldValue.serverTimestamp(),
        });

      logger.info("Disconnected from embedded app", {shop});
      res.json({success: true});
      return;
    }

    // ── CONNECTED ACCOUNTS ──────────────────────────────
    // (Kept for backward compat — returns single linked account)
    case "accounts": {
      const conn = await findConnectionByShop(shop);
      if (!conn) {
        res.json({accounts: []});
        return;
      }
      const d = conn.data;
      const accUserId = d.user_id ?? conn.id;
      let accEmail: string | null = null;
      try {
        const ur = await getAuth().getUser(accUserId);
        accEmail = ur.email ?? null;
      } catch (_) { /* user may not exist */ }
      res.json({
        accounts: [{
          id: conn.id,
          user_id: accUserId,
          email: accEmail,
          status: d.status ?? "unknown",
          connected_at: d.connected_at?.toDate?.() ?? d.connected_at ?? null,
          last_order_sync_at:
            d.last_order_sync_at?.toDate?.() ?? null,
          sync_orders_enabled: d.sync_orders_enabled ?? false,
          sync_inventory_enabled: d.sync_inventory_enabled ?? false,
        }],
      });
      return;
    }

    // ── DISCONNECT SPECIFIC ACCOUNT ─────────────────────
    case "disconnect-account": {
      if (req.method !== "POST") {
        res.status(405).json({error: "Method not allowed"});
        return;
      }
      const body = req.body as Record<string, unknown>;
      const docId = body.account_id as string;
      if (!docId) {
        res.status(400).json({error: "account_id required"});
        return;
      }

      // Verify this account belongs to this shop
      const accDoc = await getDb()
        .collection("shopify_connections")
        .doc(docId)
        .get();
      if (!accDoc.exists || accDoc.data()?.shop_domain !== shop) {
        res.status(404).json({error: "Account not found for this shop"});
        return;
      }

      // Unregister webhooks for this specific account
      const accEnc = accDoc.data()?.access_token as string | undefined;
      const accWh = accDoc.data()?.webhook_ids as
        Record<string, string> | undefined;
      if (accEnc && accWh) {
        try {
          const at = decrypt(accEnc, encryptionKey);
          await Promise.all(
            Object.entries(accWh).map(async ([topic, id]) => {
              try {
                await fetch(
                  `https://${shop}/admin/api/${SHOPIFY_API_VERSION}/webhooks/${id}.json`,
                  {method: "DELETE", headers: {"X-Shopify-Access-Token": at}},
                );
              } catch (e) {
                logger.warn(`Webhook delete ${topic}`, {error: String(e)});
              }
            }),
          );
        } catch (e) {
          logger.error("Decrypt for account webhook cleanup", {
            error: String(e),
          });
        }
      }

      await getDb()
        .collection("shopify_connections")
        .doc(docId)
        .update({
          status: "disconnected",
          access_token: null,
          webhook_ids: null,
          disconnected_at: FieldValue.serverTimestamp(),
          updated_at: FieldValue.serverTimestamp(),
        });

      logger.info("Account disconnected from embedded app", {
        shop,
        docId,
      });
      res.json({success: true});
      return;
    }

    // ── SYNC HISTORY ────────────────────────────────────
    case "sync-history": {
      // Get all user IDs connected to this shop
      const allConns = await findAllConnectionsByShop(shop);
      const userIds = allConns
        .map((c) => c.data.user_id as string)
        .filter(Boolean);

      if (userIds.length === 0) {
        res.json({logs: []});
        return;
      }

      // Firestore "in" queries support max 30 values
      const idsToQuery = userIds.slice(0, 30);
      const logSnap = await getDb()
        .collection("shopify_sync_log")
        .where("user_id", "in", idsToQuery)
        .orderBy("created_at", "desc")
        .limit(50)
        .get();

      // Look up emails for all user IDs
      const uniqueIds = [...new Set(logSnap.docs.map((d) => d.data().user_id).filter(Boolean))];
      const emailMap: Record<string, string> = {};
      for (const uid of uniqueIds) {
        try {
          const ur = await getAuth().getUser(uid as string);
          if (ur.email) emailMap[uid as string] = ur.email;
        } catch (_) { /* skip */ }
      }

      const logs = logSnap.docs.map((d) => {
        const ld = d.data();
        return {
          id: d.id,
          action: ld.action ?? "unknown",
          direction: ld.direction ?? "unknown",
          status: ld.status ?? "unknown",
          error: ld.error ?? null,
          user_id: ld.user_id,
          email: emailMap[ld.user_id] ?? null,
          created_at: ld.created_at?.toDate?.() ?? null,
        };
      });
      res.json({logs});
      return;
    }

    default:
      res.status(400).json({error: "Unknown action"});
    }
  } catch (error) {
    logger.error("handleEmbedApi error", {action, shop, error: String(error)});
    res.status(500).json({error: "Internal server error"});
  }
}
/* eslint-enable @typescript-eslint/no-explicit-any */

// ═══════════════════════════════════════════════════════════
// getEmbeddedAppHtml — full embedded-app SPA
// ═══════════════════════════════════════════════════════════

export function getEmbeddedAppHtml(
  apiKey: string,
  initialStatus?: Record<string, unknown> | null,
): string {
  const statusJson = initialStatus
    ? JSON.stringify(initialStatus)
      .replace(/&/g, "&amp;")
      .replace(/"/g, "&quot;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
    : "";
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="shopify-api-key" content="${apiKey}" />
  <title>Revvo</title>
  <script src="https://cdn.shopify.com/shopifycloud/app-bridge.js"></script>
  <style>
    :root {
      --p-surface:#f6f6f7;--p-bg:#fff;--p-text:#202223;
      --p-subdued:#6d7175;--p-green:#008060;--p-green-h:#006e52;
      --p-red:#d72c0d;--p-red-h:#bc2200;--p-border:#e1e3e5;
      --p-radius:12px;
      --p-shadow:0 1px 1px rgba(0,0,0,.04),0 2px 4px 1px rgba(0,0,0,.04);
      --p-font:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
    }
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:var(--p-font);background:var(--p-surface);color:var(--p-text);padding:20px;line-height:1.5}
    .page{max-width:720px;margin:0 auto}
    .page-header{display:flex;align-items:center;justify-content:space-between;margin-bottom:20px}
    .page-title{font-size:24px;font-weight:700}
    .badge{display:inline-flex;align-items:center;gap:6px;padding:4px 12px;border-radius:20px;font-size:13px;font-weight:500}
    .badge-ok{background:#e3f5ef;color:#008060}
    .badge-off{background:#fce5e0;color:#d72c0d}
    .dot{width:8px;height:8px;border-radius:50%}
    .dot-ok{background:#008060}
    .dot-off{background:#d72c0d}
    .card{background:var(--p-bg);border-radius:var(--p-radius);box-shadow:var(--p-shadow);border:1px solid var(--p-border);margin-bottom:16px}
    .card-hd{padding:16px 20px;border-bottom:1px solid var(--p-border);display:flex;align-items:center;justify-content:space-between}
    .card-tt{font-size:16px;font-weight:600}
    .card-bd{padding:20px}
    .info-grid{display:grid;grid-template-columns:1fr 1fr;gap:16px}
    .info-item label{font-size:12px;color:var(--p-subdued);text-transform:uppercase;letter-spacing:.5px;display:block;margin-bottom:4px}
    .info-item .val{font-size:14px;font-weight:500}
    .srow{display:flex;align-items:center;justify-content:space-between;padding:14px 0}
    .srow+.srow{border-top:1px solid var(--p-border)}
    .slbl{font-size:14px;font-weight:500}
    .sdsc{font-size:13px;color:var(--p-subdued);margin-top:2px}
    .toggle{position:relative;width:44px;height:24px;cursor:pointer;flex-shrink:0}
    .toggle input{display:none}
    .toggle .sl{position:absolute;inset:0;background:#babec3;border-radius:24px;transition:.2s}
    .toggle .sl::before{content:'';position:absolute;width:18px;height:18px;left:3px;top:3px;background:#fff;border-radius:50%;transition:.2s}
    .toggle input:checked+.sl{background:var(--p-green)}
    .toggle input:checked+.sl::before{transform:translateX(20px)}
    .sel-w{position:relative}
    select{width:100%;padding:8px 32px 8px 12px;font-size:14px;border:1px solid var(--p-border);border-radius:8px;background:#fff;appearance:none;font-family:var(--p-font);cursor:pointer}
    select:focus{outline:2px solid var(--p-green);outline-offset:1px}
    .sel-w::after{content:'\\25BE';position:absolute;right:12px;top:50%;transform:translateY(-50%);pointer-events:none;color:var(--p-subdued)}
    .btn{padding:8px 16px;font-size:14px;font-weight:500;border-radius:8px;border:none;cursor:pointer;font-family:var(--p-font);transition:.15s}
    .btn-p{background:var(--p-green);color:#fff}
    .btn-p:hover{background:var(--p-green-h)}
    .btn-d{background:var(--p-red);color:#fff}
    .btn-d:hover{background:var(--p-red-h)}
    .btn-o{background:none;border:1px solid var(--p-border);color:var(--p-text)}
    .btn-o:hover{background:#f6f6f7}
    .btn:disabled{opacity:.5;cursor:not-allowed}
    .banner{padding:14px 20px;border-radius:var(--p-radius);margin-bottom:16px;font-size:14px;display:flex;align-items:flex-start;gap:12px}
    .banner-i{background:#eaf5fe;border:1px solid #b4d4f1;color:#1f5199}
    .banner-s{background:#e3f5ef;border:1px solid #9cd9bb;color:#006e4a}
    .danger .card-hd{background:#fefbfb}
    .danger{border-color:#fdd}
    .loading{text-align:center;padding:60px;color:var(--p-subdued)}
    .spinner{width:32px;height:32px;border:3px solid var(--p-border);border-top-color:var(--p-green);border-radius:50%;animation:spin .6s linear infinite;margin:0 auto 16px}
    @keyframes spin{to{transform:rotate(360deg)}}
    .disc-state{text-align:center;padding:40px 20px}
    .disc-state .ic{font-size:48px;margin-bottom:16px}
    .disc-state h2{font-size:20px;margin-bottom:8px}
    .disc-state p{color:var(--p-subdued);margin-bottom:20px}
    .modal-bg{position:fixed;inset:0;background:rgba(0,0,0,.35);display:flex;align-items:center;justify-content:center;z-index:100}
    .modal{background:#fff;border-radius:var(--p-radius);box-shadow:0 8px 32px rgba(0,0,0,.2);width:420px;max-width:90%}
    .modal-hd{padding:16px 20px;border-bottom:1px solid var(--p-border);font-weight:600;font-size:16px}
    .modal-bd{padding:20px;font-size:14px;color:var(--p-subdued)}
    .modal-ft{padding:12px 20px;border-top:1px solid var(--p-border);display:flex;justify-content:flex-end;gap:8px}
    .hidden{display:none!important}
    .toast{position:fixed;bottom:20px;left:50%;transform:translateX(-50%);padding:10px 20px;border-radius:8px;font-size:14px;font-weight:500;box-shadow:0 4px 16px rgba(0,0,0,.15);z-index:200;transition:opacity .3s}
    .toast-ok{background:#008060;color:#fff}
    .toast-err{background:#d72c0d;color:#fff}
    table{width:100%;border-collapse:collapse;font-size:13px}
    th{text-align:left;padding:10px 12px;font-size:12px;color:var(--p-subdued);text-transform:uppercase;letter-spacing:.5px;border-bottom:2px solid var(--p-border);font-weight:600}
    td{padding:10px 12px;border-bottom:1px solid var(--p-border);vertical-align:middle}
    tr:last-child td{border-bottom:none}
    .st{display:inline-block;padding:2px 8px;border-radius:6px;font-size:11px;font-weight:600}
    .st-active{background:#e3f5ef;color:#008060}
    .st-disconnected{background:#fce5e0;color:#d72c0d}
    .st-error{background:#fff3cd;color:#856404}
    .st-success{background:#e3f5ef;color:#008060}
    .st-skipped{background:#f0f0f0;color:#6d7175}
    .btn-sm{padding:4px 10px;font-size:12px;border-radius:6px}
    .empty-st{text-align:center;padding:32px 20px;color:var(--p-subdued);font-size:14px}
    .dir-arrow{font-size:11px;color:var(--p-subdued)}
  </style>
</head>
<body>
<div class="page">
  <!-- Loading -->
  <div id="v-load" class="loading"><div class="spinner"></div>Loading integration settings&hellip;</div>
  <div id="revvo-data" style="display:none" data-status="${statusJson}"></div>

  <!-- Disconnected / Not Connected -->
  <div id="v-disc" class="hidden">
    <div class="page-header">
      <h1 class="page-title">Revvo</h1>
      <span class="badge badge-off"><span class="dot dot-off"></span>Not Connected</span>
    </div>

    <div class="card">
      <div class="card-hd"><span class="card-tt">Welcome to Revvo</span></div>
      <div class="card-bd">
        <p style="font-size:15px;margin-bottom:16px">Revvo syncs your Shopify orders and inventory to a mobile app where you can track <strong>COGS</strong>, calculate <strong>profit per order</strong>, and manage <strong>two-way inventory</strong>.</p>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px">
          <div style="padding:14px;background:var(--p-surface);border-radius:10px;text-align:center">
            <div style="font-size:24px;margin-bottom:4px">&#x1F4E6;</div>
            <div style="font-size:13px;font-weight:600">Order Sync</div>
            <div style="font-size:12px;color:var(--p-subdued)">Auto-import orders via webhooks</div>
          </div>
          <div style="padding:14px;background:var(--p-surface);border-radius:10px;text-align:center">
            <div style="font-size:24px;margin-bottom:4px">&#x1F4CA;</div>
            <div style="font-size:13px;font-weight:600">COGS &amp; Profit</div>
            <div style="font-size:12px;color:var(--p-subdued)">Track cost of goods per order</div>
          </div>
          <div style="padding:14px;background:var(--p-surface);border-radius:10px;text-align:center">
            <div style="font-size:24px;margin-bottom:4px">&#x1F504;</div>
            <div style="font-size:13px;font-weight:600">Two-Way Inventory</div>
            <div style="font-size:12px;color:var(--p-subdued)">Push &amp; pull stock levels</div>
          </div>
          <div style="padding:14px;background:var(--p-surface);border-radius:10px;text-align:center">
            <div style="font-size:24px;margin-bottom:4px">&#x1F4F1;</div>
            <div style="font-size:13px;font-weight:600">Mobile App</div>
            <div style="font-size:12px;color:var(--p-subdued)">Manage everything from your phone</div>
          </div>
        </div>
      </div>
    </div>

    <div class="card">
      <div class="card-hd"><span class="card-tt">How to connect your store</span></div>
      <div class="card-bd">
        <div style="display:flex;flex-direction:column;gap:16px">
          <div style="display:flex;gap:14px;align-items:flex-start">
            <div style="width:28px;height:28px;border-radius:50%;background:var(--p-green);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:14px;flex-shrink:0">1</div>
            <div>
              <div style="font-size:14px;font-weight:600">Open the Revvo mobile app</div>
              <div style="font-size:13px;color:var(--p-subdued);margin-top:2px">Launch <strong>Revvo</strong> on your iOS or Android device and sign in to your account.</div>
            </div>
          </div>
          <div style="display:flex;gap:14px;align-items:flex-start">
            <div style="width:28px;height:28px;border-radius:50%;background:var(--p-green);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:14px;flex-shrink:0">2</div>
            <div>
              <div style="font-size:14px;font-weight:600">Connect your Shopify store</div>
              <div style="font-size:13px;color:var(--p-subdued);margin-top:2px">Go to <strong>Manage &rarr; Shopify Integration</strong>, tap <strong>Connect Store</strong>, enter your store domain, and authorize access.</div>
            </div>
          </div>
          <div style="display:flex;gap:14px;align-items:flex-start">
            <div style="width:28px;height:28px;border-radius:50%;background:var(--p-green);color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700;font-size:14px;flex-shrink:0">3</div>
            <div>
              <div style="font-size:14px;font-weight:600">Manage settings here</div>
              <div style="font-size:13px;color:var(--p-subdued);margin-top:2px">Once connected, return to this page to toggle sync settings, change your Shopify location, view sync history, or disconnect.</div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="banner banner-i">
      &#x2139;&#xFE0F;&ensp;Need help? Contact us at <strong>support@revvo-app.com</strong>
    </div>
  </div>

  <!-- Connected -->
  <div id="v-conn" class="hidden">
    <div class="page-header">
      <h1 class="page-title">Revvo</h1>
      <span id="st-badge" class="badge badge-ok"><span class="dot dot-ok"></span>Connected</span>
    </div>

    <div id="link-banner" class="banner banner-i hidden">
      &#x1F4F1;&ensp;Manage product mappings, import orders, and view detailed analytics in the <strong>Revvo</strong> mobile app.
    </div>

    <!-- Connection info -->
    <div class="card">
      <div class="card-hd"><span class="card-tt">Connection Details</span></div>
      <div class="card-bd"><div class="info-grid">
        <div class="info-item"><label>Store</label><div class="val" id="i-shop">&mdash;</div></div>
        <div class="info-item"><label>Connected</label><div class="val" id="i-conn">&mdash;</div></div>
        <div class="info-item"><label>Last Order Sync</label><div class="val" id="i-osync">&mdash;</div></div>
        <div class="info-item"><label>Last Inventory Sync</label><div class="val" id="i-isync">&mdash;</div></div>
      </div></div>
    </div>

    <!-- Sync settings -->
    <div class="card">
      <div class="card-hd"><span class="card-tt">Sync Settings</span></div>
      <div class="card-bd">
        <div class="srow">
          <div><div class="slbl">Order Sync</div><div class="sdsc">Automatically sync new orders to Revvo</div></div>
          <label class="toggle"><input type="checkbox" id="t-orders" checked><span class="sl"></span></label>
        </div>
        <div class="srow">
          <div><div class="slbl">Inventory Sync</div><div class="sdsc">Keep inventory levels in sync between Shopify and Revvo</div></div>
          <label class="toggle"><input type="checkbox" id="t-inv"><span class="sl"></span></label>
        </div>
        <div id="inv-mode-row" class="srow hidden">
          <div><div class="slbl">Sync Mode</div><div class="sdsc">How inventory syncs between platforms</div></div>
          <div class="sel-w" style="width:160px">
            <select id="s-mode"><option value="on_demand">On Demand</option><option value="always">Always On</option></select>
          </div>
        </div>
      </div>
    </div>

    <!-- Location -->
    <div class="card">
      <div class="card-hd"><span class="card-tt">Shopify Location</span></div>
      <div class="card-bd">
        <p style="margin-bottom:12px;font-size:13px;color:var(--p-subdued)">Select which Shopify location to use for inventory operations.</p>
        <div class="sel-w"><select id="s-loc"><option value="">Loading locations&hellip;</option></select></div>
      </div>
    </div>

    <!-- Linked Account -->
    <div class="card">
      <div class="card-hd"><span class="card-tt">Linked Revvo Account</span><button class="btn btn-o btn-sm" id="btn-refresh-acc">Refresh</button></div>
      <div class="card-bd" id="acc-body">
        <div class="empty-st" id="acc-load">Loading account info&hellip;</div>
      </div>
    </div>

    <!-- Sync History -->
    <div class="card">
      <div class="card-hd"><span class="card-tt">Sync History</span><button class="btn btn-o btn-sm" id="btn-refresh-hist">Refresh</button></div>
      <div class="card-bd" style="padding:0;overflow-x:auto" id="hist-body">
        <div class="empty-st" id="hist-load" style="padding:32px">Loading sync history&hellip;</div>
      </div>
    </div>

    <!-- Danger zone -->
    <div class="card danger">
      <div class="card-hd"><span class="card-tt" style="color:var(--p-red)">Danger Zone</span></div>
      <div class="card-bd">
        <div style="display:flex;align-items:center;justify-content:space-between">
          <div><div class="slbl">Disconnect Store</div><div class="sdsc">Remove all webhooks and stop syncing data</div></div>
          <button class="btn btn-d" id="btn-disc">Disconnect</button>
        </div>
      </div>
    </div>
  </div>

  <!-- Disconnect account modal -->
  <div id="modal-disc-acc" class="modal-bg hidden">
    <div class="modal">
      <div class="modal-hd">Disconnect this account?</div>
      <div class="modal-bd">This will remove webhooks and stop syncing for account <strong id="disc-acc-name"></strong>. The user's data in Revvo will be preserved.</div>
      <div class="modal-ft">
        <button class="btn btn-o" id="btn-acc-cancel">Cancel</button>
        <button class="btn btn-d" id="btn-acc-confirm">Disconnect</button>
      </div>
    </div>
  </div>

  <!-- Disconnect modal -->
  <div id="modal-disc" class="modal-bg hidden">
    <div class="modal">
      <div class="modal-hd">Disconnect from Revvo?</div>
      <div class="modal-bd">This will remove all webhooks and stop syncing orders and inventory. Your existing data in Revvo will be preserved.<br><br>You can reconnect at any time.</div>
      <div class="modal-ft">
        <button class="btn btn-o" id="btn-cancel">Cancel</button>
        <button class="btn btn-d" id="btn-confirm">Disconnect</button>
      </div>
    </div>
  </div>

  <div id="toast" class="toast hidden"></div>
</div>

<script>
(function(){
  var shopDomain = '';

  function show(id){document.getElementById(id).classList.remove('hidden')}
  function hide(id){document.getElementById(id).classList.add('hidden')}

  function toast(msg, ok){
    var t=document.getElementById('toast');
    t.textContent=msg;
    t.className='toast '+(ok!==false?'toast-ok':'toast-err');
    setTimeout(function(){t.classList.add('hidden')},3000);
  }

  function fmtDate(v){
    if(!v) return 'Never';
    var d=new Date(v);
    return d.toLocaleDateString('en-US',{month:'short',day:'numeric',year:'numeric',hour:'2-digit',minute:'2-digit'});
  }

  function api(action, opts){
    opts = opts || {};
    try {
      var tp = shopify.idToken();
    } catch(e) {
      return Promise.reject(e);
    }
    return tp.then(function(token){
      var base = window.location.origin + window.location.pathname;
      // Ensure we never double-slash and always have the right path
      if(base.charAt(base.length-1)==='/') base = base.slice(0,-1);
      var url = base + '?_api=' + action;
      console.log('[Revvo] API call:', action, url);
      return fetch(url, {
        method: opts.method || 'GET',
        headers: {
          'Authorization': 'Bearer ' + token,
          'Content-Type': 'application/json'
        },
        body: opts.body ? JSON.stringify(opts.body) : undefined
      });
    }).then(function(r){
      console.log('[Revvo] API response:', action, r.status);
      if(!r.ok) throw new Error('API ' + r.status);
      return r.json();
    });
  }

  function showDisconnected(){
    hide('v-load');
    show('v-disc');
  }

  function el(id){return document.getElementById(id);}
  function on(id,evt,fn){var e=el(id);if(e)e.addEventListener(evt,fn);}

  function applyStatus(d){
    hide('v-load');
    if(!d || !d.connected || d.status==='disconnected'){
      show('v-disc');
      if(d && d.shop_domain) shopDomain = d.shop_domain;
      return;
    }
    shopDomain = d.shop_domain || '';
    document.getElementById('i-shop').textContent = d.shop_domain;
    document.getElementById('i-conn').textContent = fmtDate(d.connected_at);
    document.getElementById('i-osync').textContent = fmtDate(d.last_order_sync_at);
    document.getElementById('i-isync').textContent = fmtDate(d.last_inventory_sync_at);
    document.getElementById('t-orders').checked = d.sync_orders_enabled;
    document.getElementById('t-inv').checked = d.sync_inventory_enabled;
    document.getElementById('s-mode').value = d.inventory_sync_mode || 'on_demand';
    if(d.sync_inventory_enabled) show('inv-mode-row');
    if(d.user_linked) show('link-banner');
    if(d.linked_account){
      var a = d.linked_account;
      var sid = a.email || a.user_id || a.id || '';
      var stCls = a.status==='active'?'st-active':a.status==='error'?'st-error':'st-disconnected';
      var c = document.getElementById('acc-body');
      var h='<table><thead><tr><th>Account</th><th>Status</th><th>Orders</th><th>Inventory</th><th>Last Sync</th><th></th></tr></thead><tbody>';
      h+='<tr>';
      h+='<td style="font-weight:500">' + esc(sid.length>20 ? sid.slice(0,8)+'\\u2026'+sid.slice(-4) : sid) + '</td>';
      h+='<td><span class="st '+stCls+'">' + esc(a.status) + '</span></td>';
      h+='<td>' + (a.sync_orders_enabled?'\\u2705':'\\u274C') + '</td>';
      h+='<td>' + (a.sync_inventory_enabled?'\\u2705':'\\u274C') + '</td>';
      h+='<td>' + fmtDate(a.last_order_sync_at) + '</td>';
      h+='<td></td></tr>';
      h+='</tbody></table>';
      c.innerHTML=h;
    }
    show('v-conn');
    loadLocations(d.shopify_location_id);
    loadHistory();
  }

  function init(){
    // Use server-injected status if available (no API call needed)
    var dataEl = document.getElementById('revvo-data');
    var raw = dataEl && dataEl.getAttribute('data-status');
    if(raw){
      try { applyStatus(JSON.parse(raw)); return; } catch(e){}
    }
    // Fallback: fetch via API
    if(typeof shopify === 'undefined' || !shopify.idToken){
      showDisconnected();
      return;
    }
    var timer = setTimeout(showDisconnected, 8000);
    api('status').then(function(d){
      clearTimeout(timer);
      applyStatus(d);
    }).catch(function(e){
      clearTimeout(timer);
      console.error('init',e);
      showDisconnected();
    });
  }

  function loadLocations(cur){
    api('locations').then(function(d){
      var sel=document.getElementById('s-loc');
      sel.innerHTML='<option value="">Select a location</option>';
      d.locations.forEach(function(l){
        var o=document.createElement('option');
        o.value=l.id; o.textContent=l.name;
        if(l.id===cur) o.selected=true;
        sel.appendChild(o);
      });
    }).catch(function(){});
  }

  // ── Event listeners ─────────────────────────────

  on('t-orders','change',function(e){
    var v=e.target.checked;
    api('settings',{method:'POST',body:{sync_orders_enabled:v}})
      .then(function(){toast('Order sync '+(v?'enabled':'disabled'))})
      .catch(function(){e.target.checked=!v;toast('Failed to update','err')});
  });

  on('t-inv','change',function(e){
    var v=e.target.checked;
    api('settings',{method:'POST',body:{sync_inventory_enabled:v}})
      .then(function(){
        if(v) show('inv-mode-row'); else hide('inv-mode-row');
        toast('Inventory sync '+(v?'enabled':'disabled'));
      })
      .catch(function(){e.target.checked=!v;toast('Failed to update',false)});
  });

  on('s-mode','change',function(e){
    api('settings',{method:'POST',body:{inventory_sync_mode:e.target.value}})
      .then(function(){toast('Sync mode updated')})
      .catch(function(){toast('Failed to update',false)});
  });

  on('s-loc','change',function(e){
    var opt=e.target.options[e.target.selectedIndex];
    api('location',{method:'POST',body:{location_id:e.target.value,location_name:opt.textContent}})
      .then(function(){toast('Location updated')})
      .catch(function(){toast('Failed to update',false)});
  });

  on('btn-disc','click',function(){show('modal-disc')});
  on('btn-cancel','click',function(){hide('modal-disc')});

  on('btn-confirm','click',function(){
    var b=el('btn-confirm');
    b.disabled=true; b.textContent='Disconnecting\\u2026';
    api('disconnect',{method:'POST'}).then(function(){
      hide('modal-disc'); hide('v-conn'); show('v-disc');
      toast('Store disconnected');
    }).catch(function(){
      b.disabled=false; b.textContent='Disconnect';
      toast('Failed to disconnect',false);
    });
  });

  // ── Connected Accounts ─────────────────────────
  var pendingDiscId = null;

  function loadAccounts(){
    api('accounts').then(function(d){
      var c = document.getElementById('acc-body');
      if(!d.accounts || d.accounts.length===0){
        c.innerHTML='<div class="empty-st">No accounts connected to this store.</div>';
        return;
      }
      var h='<table><thead><tr><th>Account</th><th>Status</th><th>Orders</th><th>Inventory</th><th>Last Sync</th><th></th></tr></thead><tbody>';
      d.accounts.forEach(function(a){
        var sid = a.email || a.user_id || a.id;
        var stCls = a.status==='active'?'st-active':a.status==='error'?'st-error':'st-disconnected';
        h+='<tr>';
        h+='<td style="font-weight:500">' + esc(sid.indexOf('@')>-1 ? sid : (sid.length>20 ? sid.slice(0,8)+'\u2026'+sid.slice(-4) : sid)) + '</td>';
        h+='<td><span class="st '+stCls+'">' + esc(a.status) + '</span></td>';
        h+='<td>' + (a.sync_orders_enabled?'\u2705':'\u274C') + '</td>';
        h+='<td>' + (a.sync_inventory_enabled?'\u2705':'\u274C') + '</td>';
        h+='<td>' + fmtDate(a.last_order_sync_at) + '</td>';
        h+='<td>';
        if(a.status==='active'){
          h+='<button class="btn btn-d btn-sm" data-disc-id="'+esc(a.id)+'">Disconnect</button>';
        }
        h+='</td></tr>';
      });
      h+='</tbody></table>';
      c.innerHTML=h;
      c.querySelectorAll('[data-disc-id]').forEach(function(btn){
        btn.addEventListener('click',function(){
          pendingDiscId = btn.getAttribute('data-disc-id');
          document.getElementById('disc-acc-name').textContent = pendingDiscId.length>20 ? pendingDiscId.slice(0,8)+'\u2026'+pendingDiscId.slice(-4) : pendingDiscId;
          show('modal-disc-acc');
        });
      });
    }).catch(function(){
      document.getElementById('acc-body').innerHTML='<div class="empty-st">Failed to load accounts.</div>';
    });
  }

  on('btn-refresh-acc','click', loadAccounts);

  on('btn-acc-cancel','click',function(){hide('modal-disc-acc'); pendingDiscId=null;});
  on('btn-acc-confirm','click',function(){
    if(!pendingDiscId) return;
    var b=el('btn-acc-confirm');
    b.disabled=true; b.textContent='Disconnecting\u2026';
    api('disconnect-account',{method:'POST',body:{account_id:pendingDiscId}}).then(function(){
      hide('modal-disc-acc');
      b.disabled=false; b.textContent='Disconnect';
      pendingDiscId=null;
      toast('Account disconnected');
      loadAccounts();
    }).catch(function(){
      b.disabled=false; b.textContent='Disconnect';
      toast('Failed to disconnect account',false);
    });
  });

  // ── Sync History ───────────────────────────────
  function fmtAction(a){
    var map={order_created:'Order Created',order_updated:'Order Updated',order_cancelled:'Order Cancelled',inventory_pull:'Inventory Pull',inventory_push:'Inventory Push',product_imported:'Product Imported',product_updated:'Product Updated',product_deleted:'Product Deleted',webhook_received:'Webhook'};
    return map[a]||a;
  }
  function fmtDir(d){
    if(d==='shopify_to_masari') return '<span class="dir-arrow">Shopify \u2192 Revvo</span>';
    if(d==='masari_to_shopify') return '<span class="dir-arrow">Revvo \u2192 Shopify</span>';
    if(d==='webhook') return '<span class="dir-arrow">Webhook</span>';
    return '<span class="dir-arrow">' + esc(d) + '</span>';
  }

  function loadHistory(){
    api('sync-history').then(function(d){
      var c=document.getElementById('hist-body');
      if(!d.logs || d.logs.length===0){
        c.innerHTML='<div class="empty-st" style="padding:32px">No sync activity yet.</div>';
        return;
      }
      var h='<table><thead><tr><th>Time</th><th>Action</th><th>Direction</th><th>Status</th><th>Account</th></tr></thead><tbody>';
      d.logs.forEach(function(l){
        var stCls = l.status==='success'?'st-success':l.status==='error'?'st-disconnected':'st-skipped';
        var uid = l.email || l.user_id||'';
        h+='<tr>';
        h+='<td style="white-space:nowrap">' + fmtDate(l.created_at) + '</td>';
        h+='<td>' + esc(fmtAction(l.action)) + '</td>';
        h+='<td>' + fmtDir(l.direction) + '</td>';
        h+='<td><span class="st '+stCls+'">' + esc(l.status) + '</span>';
        if(l.error) h+=' <span title="'+esc(l.error)+'" style="cursor:help">\u26A0\uFE0F</span>';
        h+='</td>';
        h+='<td style="font-size:11px;color:var(--p-subdued)">' + esc(uid) + '</td>';
        h+='</tr>';
      });
      h+='</tbody></table>';
      c.innerHTML=h;
    }).catch(function(){
      document.getElementById('hist-body').innerHTML='<div class="empty-st" style="padding:32px">Failed to load sync history.</div>';
    });
  }

  on('btn-refresh-hist','click', loadHistory);

  function esc(s){if(!s)return '';var d=document.createElement('div');d.textContent=String(s);return d.innerHTML;}

  init();
})();
</script>
</body>
</html>`;
}
