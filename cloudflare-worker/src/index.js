/**
 * Autotask -> aBILLity Company Name Sync (Cloudflare Worker)
 *
 * Same job as the Azure Function in ../AutotaskAbillitySync, on Cloudflare
 * instead. One Worker serves both endpoints Autotask needs:
 *
 *   POST /api/CompanyNameSync             <- the name-change webhook
 *   POST /api/CompanyNameSyncDeactivated  <- Autotask's deactivation callback
 *
 * A company is only synced when BOTH of its UDFs say so: the sync-flag UDF
 * reads yes, and the ID UDF holds an aBILLity Company ID. Anything else is
 * skipped and logged.
 *
 * Azure Functions authenticate callers with a built-in `?code=` key. Workers
 * have no equivalent, so we check the same-shaped `?code=` against the
 * WebhookToken secret ourselves.
 */

const ABILLITY_API_BASE = "https://api.abillity.co.uk/api";

// aBILLity caps Company Name at 50 characters.
const ABILLITY_NAME_MAX_LENGTH = 50;

// What the sync-flag UDF can say for "yes". Anything else - including blank -
// means don't sync, so a company is never synced by accident.
const AFFIRMATIVE_VALUES = new Set(["yes", "y", "true", "1", "on", "checked"]);

const REQUIRED_SETTINGS = [
  "AutotaskAbillityIdUdfLabel",
  "AutotaskSyncFlagUdfLabel",
  "AbillitySystemInformation",
  "AbillityUserName",
  "AbillityPassword",
  "WebhookToken",
];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return text(405, "method not allowed");
    }

    const missing = REQUIRED_SETTINGS.filter((name) => !env[name]);
    if (missing.length > 0) {
      console.error(`Missing configuration: ${missing.join(", ")}`);
      return text(500, "not configured");
    }

    if (!timingSafeEqual(url.searchParams.get("code") ?? "", env.WebhookToken)) {
      return text(401, "unauthorized");
    }

    switch (url.pathname) {
      case "/api/CompanyNameSync":
        return handleCompanyNameSync(request, env);
      case "/api/CompanyNameSyncDeactivated":
        return handleDeactivated(request);
      default:
        return text(404, "not found");
    }
  },
};

async function handleCompanyNameSync(request, env) {
  let payload;
  try {
    payload = await request.json();
  } catch {
    return text(400, "invalid json");
  }

  if (payload?.EntityType !== "Company" || payload?.Action !== "Update") {
    return text(200, "ok");
  }

  const fields = new Map(
    (payload.Fields ?? []).map((field) => [field.name, field.value])
  );

  let newName = fields.get("CompanyName");
  const syncFlag = fields.get(env.AutotaskSyncFlagUdfLabel);
  const abillityId = fields.get(env.AutotaskAbillityIdUdfLabel);

  // This update didn't touch the name.
  if (!newName) return text(200, "ok");

  if (!isAffirmative(syncFlag)) {
    console.log(
      `Autotask company ${payload.Id} is not flagged for aBILLity sync ` +
        `("${env.AutotaskSyncFlagUdfLabel}" = "${syncFlag ?? ""}") - skipping`
    );
    return text(200, "ok");
  }

  if (!abillityId) {
    console.warn(
      `Autotask company ${payload.Id} is flagged for sync but has no ` +
        `"${env.AutotaskAbillityIdUdfLabel}" - skipping`
    );
    return text(200, "ok");
  }

  if (newName.length > ABILLITY_NAME_MAX_LENGTH) {
    newName = newName.slice(0, ABILLITY_NAME_MAX_LENGTH);
  }

  const response = await fetch(
    `${ABILLITY_API_BASE}/company/${encodeURIComponent(abillityId)}`,
    {
      method: "PATCH",
      headers: {
        SystemInformation: env.AbillitySystemInformation,
        username: env.AbillityUserName,
        password: env.AbillityPassword,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({ Name: newName }),
    }
  );

  if (!response.ok) {
    const detail = await response.text().catch(() => "");
    console.error(
      `aBILLity PATCH failed for company ${abillityId}: ${response.status} ${detail}`
    );
    return text(500, "sync failed");
  }

  console.log(`Synced company ${abillityId} -> '${newName}'`);
  return text(200, "ok");
}

async function handleDeactivated(request) {
  const body = await request.text();
  console.warn(`Autotask webhook deactivated: ${body}`);
  return text(200, "ok");
}

/** True only for an explicit yes - a checkbox tick, or Yes/True/1/On as text. */
function isAffirmative(value) {
  if (value === true) return true;
  if (value === null || value === undefined) return false;
  return AFFIRMATIVE_VALUES.has(String(value).trim().toLowerCase());
}

function text(status, body) {
  return new Response(body, {
    status,
    headers: { "Content-Type": "text/plain" },
  });
}

/** Compares two strings without leaking where they diverge. */
function timingSafeEqual(a, b) {
  const encoder = new TextEncoder();
  const aBytes = encoder.encode(a);
  const bBytes = encoder.encode(b);

  if (aBytes.length !== bBytes.length) return false;

  let difference = 0;
  for (let i = 0; i < aBytes.length; i++) {
    difference |= aBytes[i] ^ bBytes[i];
  }
  return difference === 0;
}
