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
 * The payload Autotask actually sends:
 *
 *   {
 *     "Action": "Update",
 *     "EntityType": "Account",          <- Account, not Company
 *     "Id": 1301,
 *     "Fields": {                       <- an object, not an array
 *       "CompanyName": "Acme Ltd",
 *       "aBillity Company ID": "97",
 *       "Sync with aBillity": "29683107" <- a picklist VALUE id, not "Yes"
 *     },
 *     "EventTime": "...", "SequenceNumber": 32, "PersonId": 29682945
 *   }
 *
 * Azure Functions authenticate callers with a built-in `?code=` key. Workers
 * have no equivalent, so we check the same-shaped `?code=` against the
 * WebhookToken secret ourselves.
 *
 * Checked against aBILLity's published API (the GettingStarted page on your
 * own aBILLity API host):
 *   PATCH api/company/{id}  updates selected details   <- what we use
 *   PUT   api/company/{id}  updates ALL details        <- do not use
 *   headers: SystemInformation, username, password
 *   Name: string, 0-50 characters. id: integer.
 */

// Your aBILLity instance decides this host. Override with the AbillityApiBase
// variable if yours differs - hardcoding it is what sent every call to the
// wrong server and produced unexplained 500s.
const DEFAULT_ABILLITY_API_BASE = "https://api-billing.abillity.co.uk/api";

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

    // Tolerate a doubled or trailing slash - a base URL ending in "/" turns
    // ".../health" into "//health", which would otherwise match nothing.
    const path = url.pathname.replace(/\/{2,}/g, "/").replace(/\/+$/, "") || "/";

    // Log every arrival first. Without this an empty log is ambiguous - it
    // cannot tell "Autotask never called us" from "we rejected the call".
    console.log(`Request: ${request.method} ${path}`);

    const missing = REQUIRED_SETTINGS.filter((name) => !env[name]);
    if (missing.length > 0) {
      console.error(
        `Missing configuration: ${missing.join(", ")}. ` +
          `Set these under Settings > Variables and Secrets, then redeploy.`
      );
      return text(500, "not configured");
    }

    const tokenOk = timingSafeEqual(
      url.searchParams.get("code") ?? "",
      env.WebhookToken
    );

    // A health check you can hit from a browser to prove the Worker is live
    // and configured. Reports only whether each setting is present.
    if (request.method === "GET" && path === "/health") {
      if (!tokenOk) {
        console.warn("Health check rejected: bad or missing ?code=");
        return text(401, "unauthorized");
      }
      console.log("Health check OK");
      return text(
        200,
        [
          "ok",
          `settings present: ${REQUIRED_SETTINGS.join(", ")}`,
          `sync flag UDF: "${env.AutotaskSyncFlagUdfLabel}"`,
          `aBILLity id UDF: "${env.AutotaskAbillityIdUdfLabel}"`,
          `aBILLity API base: ${(env.AbillityApiBase || DEFAULT_ABILLITY_API_BASE).replace(/\/+$/, "")}`,
        ].join("\n")
      );
    }

    if (request.method !== "POST") {
      console.warn(
        `Rejected ${request.method} ${path} - the webhook endpoints accept POST only. ` +
          `The one thing you can GET is /health?code=<WebhookToken>.`
      );
      return text(
        405,
        `method not allowed: ${request.method} ${path}\n` +
          `The webhook endpoints are POST only. For a browser check use /health?code=<WebhookToken>.`
      );
    }

    if (!tokenOk) {
      console.warn(
        `Rejected: the ?code= on the URL does not match WebhookToken. ` +
          `Check the URL registered in Autotask against the WebhookToken secret. ` +
          `(code was ${url.searchParams.get("code") ? "present but wrong" : "missing entirely"})`
      );
      return text(401, "unauthorized");
    }

    switch (path) {
      case "/api/CompanyNameSync":
        return handleCompanyNameSync(request, env);
      case "/api/CompanyNameSyncDeactivated":
        return handleDeactivated(request);
      default:
        console.warn(
          `Rejected: nothing serves ${path}. ` +
            `Expected /api/CompanyNameSync or /api/CompanyNameSyncDeactivated ` +
            `(both are case-sensitive).`
        );
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

  // Autotask names this entity "Account" on the wire, even though the UI and the
  // API entity are both "Company". Accept either.
  const entityType = String(payload?.EntityType ?? "").toLowerCase();
  const action = String(payload?.Action ?? "").toLowerCase();

  if ((entityType !== "account" && entityType !== "company") || action !== "update") {
    console.log(
      `Ignoring payload: EntityType=${JSON.stringify(payload?.EntityType)} ` +
        `Action=${JSON.stringify(payload?.Action)} (wanted "Company"/"Update"). ` +
        `Top-level keys received: ${Object.keys(payload ?? {}).join(", ") || "(none)"}`
    );
    return text(200, "ok");
  }

  const fields = toFieldMap(payload.Fields);

  let newName = fields.get("CompanyName");
  const syncFlag = fields.get(env.AutotaskSyncFlagUdfLabel);
  const abillityId = fields.get(env.AutotaskAbillityIdUdfLabel);

  // This update didn't touch the name. Log the field names anyway - if the
  // payload shape or a UDF label is wrong, this is the line that shows it.
  if (!newName) {
    console.log(
      `No CompanyName for company ${payload.Id} - nothing to sync. ` +
        `Fields received: ${[...fields.keys()].map((k) => JSON.stringify(k)).join(", ") || "(none)"}`
    );
    return text(200, "ok");
  }

  const configuredYes = configuredYesValues(env);

  if (!isAffirmative(syncFlag, configuredYes)) {
    const raw = String(syncFlag ?? "");
    let hint = "";

    // A picklist UDF sends the id of the chosen value. Nobody can guess which id
    // means yes, so say so rather than skipping silently.
    if (/^\d{4,}$/.test(raw.trim())) {
      hint =
        ` - that looks like a picklist value id rather than a yes/no. If ${raw.trim()}` +
        ` is your "yes" value, add it to the AutotaskSyncFlagYesValues variable` +
        ` (comma separated) and redeploy.`;
    }

    console.log(
      `Autotask company ${payload.Id} is not flagged for aBILLity sync ` +
        `("${env.AutotaskSyncFlagUdfLabel}" = "${raw}")${hint} - skipping`
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

  // aBILLity documents the company id as an integer. A non-numeric UDF value
  // would otherwise fail obscurely inside aBILLity.
  if (!/^\d+$/.test(String(abillityId).trim())) {
    console.error(
      `Autotask company ${payload.Id} has a non-numeric ` +
        `"${env.AutotaskAbillityIdUdfLabel}" of ${JSON.stringify(abillityId)}. ` +
        `aBILLity company ids are whole numbers - fix the UDF value.`
    );
    return text(200, "ok");
  }

  if (newName.length > ABILLITY_NAME_MAX_LENGTH) {
    newName = newName.slice(0, ABILLITY_NAME_MAX_LENGTH);
  }

  // PATCH updates selected fields. Do NOT change this to PUT: aBILLity
  // documents PUT as updating ALL details of a company, so a body carrying
  // only Name would blank its flags and dates.
  const apiBase = (env.AbillityApiBase || DEFAULT_ABILLITY_API_BASE).replace(/\/+$/, "");

  const response = await fetch(
    `${apiBase}/company/${encodeURIComponent(abillityId)}`,
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
    let hint = "";
    if (response.status === 401) {
      hint =
        " - aBILLity returns 401 both for bad credentials and for a user without" +
        " company permissions, so check the permissions as well as the secrets.";
    } else if (response.status === 404) {
      hint = ` - no company ${abillityId} in aBILLity. Check the UDF value.`;
    } else if (response.status === 409) {
      hint = " - aBILLity rejected the company's flag combination.";
    }
    console.error(
      `aBILLity PATCH failed for company ${abillityId}: ${response.status} ${detail}${hint}`
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

/**
 * Autotask sends Fields as an object keyed by field name. Older payloads (and the
 * PowerShell this was ported from) used an array of {name, value}. Accept both.
 */
function toFieldMap(fields) {
  if (Array.isArray(fields)) {
    return new Map(fields.map((field) => [field.name, field.value]));
  }
  if (fields && typeof fields === "object") {
    return new Map(Object.entries(fields));
  }
  return new Map();
}

/**
 * True only for an explicit yes.
 *
 * A checkbox or text UDF sends Yes/True/1/On. A PICKLIST UDF sends the numeric id
 * of the selected value, not its label - so the id meaning "yes" has to be
 * configured, in AutotaskSyncFlagYesValues (comma separated).
 */
function isAffirmative(value, configuredYes) {
  if (value === true) return true;
  if (value === null || value === undefined) return false;

  const text = String(value).trim().toLowerCase();
  if (!text) return false;

  return configuredYes.has(text) || AFFIRMATIVE_VALUES.has(text);
}

/** The extra values that count as yes, from AutotaskSyncFlagYesValues. */
function configuredYesValues(env) {
  return new Set(
    String(env.AutotaskSyncFlagYesValues ?? "")
      .split(",")
      .map((v) => v.trim().toLowerCase())
      .filter(Boolean)
  );
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
