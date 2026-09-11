# Autotask → aBILLity Company Name Sync

When a Company's name changes in Autotask, this automatically updates the matching Company's name in aBILLity — but only for companies you've explicitly flagged for syncing.

## How it works

Autotask → fires a webhook → a small hosted endpoint (this repo) → updates aBILLity via its API.

You can host that endpoint on **Cloudflare Workers** or **Azure Functions** — pick one, they do exactly the same thing.

### The two UDFs

The sync reads two Company user-defined fields in Autotask. Both must be right for anything to happen:

| UDF label | What it holds | What it does |
|---|---|---|
| `Sync with aBillity` | `Yes` / `No`, or a picklist selection | The on switch. Anything other than yes — including blank — means this company is left alone. **If it's a picklist**, Autotask sends the selected value's numeric id rather than its label, so that id must go in `AutotaskSyncFlagYesValues`. The log names the id it saw. |
| `aBillity Company ID` | the company's aBILLity ID | Where the update gets sent. |

So a name change syncs only when the flag says yes **and** an aBILLity ID is present. Everything else is skipped and written to the log, never treated as an error. `Yes`, `yes`, `Y`, `True`, `1`, `On` and a ticked checkbox all count as yes; anything else counts as no.

## What's in this repo

- **`autotask-abillity-sync.ps1`** — run this once, at the end, to register the webhook with Autotask. Host-agnostic: it just needs your two endpoint URLs.
- **`test-autotask-credentials.ps1`** — checks your Autotask zone and credentials without running the full setup, and without spending failed login attempts you didn't mean to spend.
- **`postman/autotask-abillity-sync.postman_collection.json`** — the same webhook setup as an importable Postman collection, if you'd rather click than run PowerShell.
- **`postman/autotask-company-update.postman_collection.json`** — standalone: read and rename an Autotask company through the API. Renaming one is what fires the sync, so this is how you test end to end without clicking through the Autotask UI.
- **`postman/cloudflare-worker-test.postman_collection.json`** — health-check the Worker and fire simulated webhooks at it, with no Autotask involved.
- **`postman/README.md`** — reference for all four Postman collections: what every request does, its URL and body, and which variables it needs or captures.
- **`test-abillity.ps1`** and **`postman/abillity-test.postman_collection.json`** — test the aBILLity side on its own: credentials, company id, and the rename the Worker performs.
- **`cloudflare-worker/`** — the Cloudflare Worker (JavaScript):
  - `src/index.js` — one Worker serving both endpoints. This is the file you paste into the dashboard.
  - `wrangler.toml` — config, if you deploy from the command line instead.
  - `.dev.vars.example` — template for local testing secrets.
- **`AutotaskAbillitySync/`** — the same thing as an Azure Function (PowerShell):
  - `CompanyNameSync/` — receives the webhook, updates aBILLity.
  - `CompanyNameSyncDeactivated/` — a required callback for if the webhook ever gets deactivated.
  - `local.settings.json.example` — template for your secrets (copy it, don't edit the original).

---

# Setup

## Step 1 — Check your two UDFs in Autotask

In Autotask: **Admin → Features & Settings → Companies & Contacts → Company User-Defined Fields**.

Confirm both of these exist and write down their labels **exactly** as they appear — capitals, spaces and brackets included. `aBillity Company ID` and `abillity company id` are different fields as far as this sync is concerned.

- `aBillity Company ID`
- `Sync with aBillity`

If your labels differ even slightly from the two above, use your real ones everywhere below.

---

## Step 2 — Create the Worker in the Cloudflare dashboard

*(Prefer the command line? Skip to [Deploying with Wrangler instead](#deploying-with-wrangler-instead).)*

### 2.1 — Make up your webhook token

You need one long random string. This is what stops strangers POSTing to your Worker — Azure hands you one automatically, Cloudflare doesn't, so you invent it.

Generate one any way you like:
- macOS/Linux terminal: `openssl rand -hex 32`
- Or a password manager's generator — 40+ characters, letters and numbers, no spaces or punctuation.

Copy it somewhere safe for now. You'll paste it twice: once as a secret in step 2.5, once into the URLs in step 3.

### 2.2 — Create the Worker

1. Go to **https://dash.cloudflare.com** and sign in.
2. In the left sidebar, click **Workers & Pages**. *(On newer dashboards this lives under **Compute**.)*
3. Click **Create application** → **Create Worker**. *(Some versions show this as **Create** → **Workers** → **Start with Hello World!**)*
4. In **Name**, type: `autotask-abillity-sync`
5. Underneath, note the URL it shows you — `autotask-abillity-sync.<your-subdomain>.workers.dev`. **Write this down**, you need it in step 3.
6. Click **Deploy**.

This deploys Cloudflare's placeholder "Hello World" Worker. You replace it next.

### 2.3 — Paste in the real code

1. On the Worker's page, click **Edit code**. *(Top right — some versions label it `</>` **Edit code**.)* The online editor opens.
2. Open [`cloudflare-worker/src/index.js`](cloudflare-worker/src/index.js) from this repo. Click into it, select everything (Ctrl+A / Cmd+A) and copy.
3. Back in the Cloudflare editor, click into the code pane on the left, select everything (Ctrl+A / Cmd+A), delete it, and paste.
4. Click **Deploy** at the top right, then confirm.

You'll see an error in the editor's preview pane — that's expected. The Worker refuses to run until you've added its settings, which is the next step.

### 2.4 — Add the two plain-text variables

1. Leave the editor (**←** back arrow, top left) to return to the Worker's page.
2. Go to the **Settings** tab → **Variables and Secrets**. *(Older dashboards: **Settings** → **Variables** → **Environment Variables**.)*
3. Click **Add**, leave the type as **Text**, and add each of these:

| Type | Variable name | Value |
|---|---|---|
| Text | `AutotaskAbillityIdUdfLabel` | `aBillity Company ID` |
| Text | `AutotaskSyncFlagUdfLabel` | `Sync with aBillity` |
| Text | `AbillityApiBase` | *optional* — only if your aBILLity API host isn't `https://api-billing.abillity.co.uk/api` |
| Text | `AutotaskSyncFlagYesValues` | *required for a picklist sync flag* — the value id(s) that mean yes, comma separated |

These are your two UDF labels from step 1, character for character. Get one wrong and that field simply reads as blank — for the sync flag that means every company is skipped, silently.

### 2.5 — Add the four secrets

Same screen. Click **Add** again, but this time set the type to **Secret** for each:

| Type | Variable name | Value |
|---|---|---|
| Secret | `AbillitySystemInformation` | from your aBILLity account |
| Secret | `AbillityUserName` | your aBILLity API username |
| Secret | `AbillityPassword` | your aBILLity API password |
| Secret | `WebhookToken` | the random string you generated in step 2.1 |

Secrets are write-only — once saved, the dashboard will never show you the value again, only that it exists. Keep your own copy of the webhook token.

### 2.6 — Save

Click **Deploy** (or **Save and deploy**) to apply the variables. The Worker restarts with its settings in place.

---

## Step 3 — Build your two URLs

Take the `workers.dev` hostname from step 2.2 and add the paths and your token:

```
https://autotask-abillity-sync.<your-subdomain>.workers.dev/api/CompanyNameSync?code=<YOUR_WEBHOOK_TOKEN>
https://autotask-abillity-sync.<your-subdomain>.workers.dev/api/CompanyNameSyncDeactivated?code=<YOUR_WEBHOOK_TOKEN>
```

Both paths are **case-sensitive**, and both need the `?code=` on the end.

Quick check that it's alive — this should come back `unauthorized`, which means the Worker is running and rejecting a bad token:

```bash
curl -X POST "https://autotask-abillity-sync.<your-subdomain>.workers.dev/api/CompanyNameSync?code=wrong" -d '{}'
```

If you get `not configured` instead, a variable or secret from steps 2.4/2.5 is missing or misspelled.

---

## Step 4 — Register the webhook with Autotask

You can do this with PowerShell **or** Postman — they make the same API calls. If PowerShell is giving you trouble (corporate proxy, TLS interception, execution policy), use Postman.

### Option A — Postman

Import [`postman/autotask-abillity-sync.postman_collection.json`](postman/autotask-abillity-sync.postman_collection.json) (**Import → File**), fill in the collection's Variables tab, open **View → Show Postman Console**, and run requests **0 → 7 in order**. Each one stores what the next needs.

**[→ Full Postman reference](postman/README.md)** — every collection and request, with URLs, bodies, variables and what each one does.

There are four collections in all: webhook setup (this one), Worker health and webhook simulation, renaming an Autotask company, and checking aBILLity. The reference explains when to reach for each.

Then skip to step 6 to test it.

### Option B — PowerShell

Open `autotask-abillity-sync.ps1` and fill in the config block at the top:

- `$WebhookUrl` and `$DeactivationUrl` — the two URLs from step 3
- Your Autotask API credentials
- Your aBILLity credentials (same as step 2.5)
- `$AbillityIdUdfLabel` and `$SyncFlagUdfLabel` — your two UDF labels from step 1

Then run the script in PowerShell, start to finish. It talks to Autotask and sets everything up — you don't need to touch the Autotask UI. It registers the company name as the trigger, and both UDFs as ride-along fields so your Worker can read them.

If a UDF label is wrong, the script says so by name rather than failing silently.

---

## Step 5 — Where to see the logs

Everything the Worker does — every sync, every skip and why — goes to its log. There are two ways to read it, and the difference matters.

### Live tail (nothing is kept)

Cloudflare dashboard → **Workers & Pages** → your Worker → **Logs** tab → **Begin log stream**.

This streams events *while you watch*. It shows nothing that happened before you opened it, and stops when you close the tab. Fine for testing, useless for "why didn't that company sync yesterday".

From a terminal, the same thing: `npx wrangler tail`

### Stored logs (searchable after the fact)

Worker → **Settings** → **Observability** → enable **Workers Logs**.

Once on, invocations are kept and you can search them in the **Logs** tab without streaming. Retention and volume limits depend on your plan — the Observability screen states yours. Turn this on if you want to diagnose anything you weren't watching live.

*(Cloudflare moves these around fairly often. If the menu names differ, look for **Logs** on the Worker and **Observability** in its Settings.)*

### Is the Worker even live?

Import [`postman/cloudflare-worker-test.postman_collection.json`](postman/cloudflare-worker-test.postman_collection.json) — it health-checks the Worker and can fire simulated webhooks at it, so you can test the Worker and aBILLity together while the Autotask side is still being sorted out.

| # | Request | Writes anything? |
|---|---|---|
| 1 | Health check | No |
| 2 | Health check, wrong token — **401 is the pass** | No |
| 3 | Simulate a webhook, *not* flagged for sync | No — the Worker skips it by design |
| 4 | Simulate a webhook, flagged | **Yes — renames a company in aBILLity** |
| 5 | Simulate the deactivation callback | No |

Request 3 is the useful one: it exercises routing, the token check, JSON parsing and the flag logic without touching anything.

> Requests 3 and 4 send the payload shape the Worker *expects*. Passing them proves the Worker and aBILLity work together — it does **not** prove Autotask sends that shape. Only a real webhook shows that, and the Worker logs whatever actually arrives.

Or just open this in a browser — it needs no Autotask involvement:

```
https://autotask-abillity-sync.<your-subdomain>.workers.dev/health?code=<YOUR_WEBHOOK_TOKEN>
```

- **`ok` plus a list of settings** — the Worker is deployed, configured, and your token is right. Any problem is upstream in Autotask.
- **`unauthorized`** — the Worker is live but your `WebhookToken` doesn't match the `?code=` you used. The registered webhook URL has the same problem.
- **`not configured`** — a variable or secret from step 2.4/2.5 is missing; the message names which.
- **`method not allowed`** — you're running a build of the Worker from before `/health` existed. Redeploy `cloudflare-worker/src/index.js`. (If the log shows `Request: GET /health` and you still get this, you're on an even older build — the log line is new too.)
- **Nothing / a Cloudflare error** — the Worker isn't deployed at that hostname.

It reports only *whether* each setting is present, never its value.

### What Autotask actually sends

Captured from a live webhook, because it differs from what you'd expect:

```json
{
  "Action": "Update",
  "EntityType": "Account",
  "Id": 1301,
  "Fields": {
    "CompanyName": "Acme Ltd",
    "aBillity Company ID": "97",
    "Sync with aBillity": "29683107"
  },
  "EventTime": "...", "SequenceNumber": 32, "PersonId": 29682945
}
```

Three things worth knowing:

- **`EntityType` is `Account`**, not `Company` — the entity is called Company everywhere else.
- **`Fields` is an object** keyed by field name, not an array of `{name, value}`.
- **A picklist UDF sends the selected value's numeric id**, not its label. `"29683107"` is not the word "Yes". Put that id in `AutotaskSyncFlagYesValues`, or the company is skipped as unflagged. The log tells you the id it saw.

The Worker accepts both `Account` and `Company`, and both the object and array shapes.

### What you'll see

| Log line | Meaning |
|---|---|
| `Synced company <id> -> '<name>'` | Worked. |
| `... is not flagged for aBILLity sync ("Sync with aBillity" = "No")` | Normal skip — the flag isn't yes. |
| `... is flagged for sync but has no "aBillity Company ID"` | **Warning.** Someone switched this company on but left the ID blank. |
| `aBILLity PATCH failed for company <id>: <status>` | **Error.** Reached aBILLity, which refused. Status and body are included. |
| `Missing configuration: ...` | A variable or secret from step 2.4/2.5 isn't set. |
| `Request: POST /api/CompanyNameSync` | Something arrived. Every request logs this first. |
| `Rejected: the ?code= ... does not match WebhookToken` | Autotask called, but the token in the registered URL is wrong. |
| `Rejected: nothing serves /...` | Autotask called the wrong path — both are case-sensitive. |
| `Ignoring payload: EntityType=... Action=...` | Arrived, but not a Company update. Shows what was actually sent. |
| `No CompanyName ... Fields received: ...` | Arrived, but no name field. **The list of fields is what diagnoses a wrong UDF label.** |
| `... has a non-numeric "aBillity Company ID"` | The UDF holds something that isn't a whole number. |
| *nothing at all* | Autotask never called the Worker. Check the webhook in Autotask, not the Worker. |

That last row is now meaningful: every request logs its arrival before anything else, so an empty log genuinely means Autotask never called. Check the webhook in Autotask rather than the Worker.

## Step 6 — Test it

1. Pick a test company in Autotask. Set `Sync with aBillity` to **Yes** and put a real aBILLity ID in `aBillity Company ID`.
2. Start the log stream (above) **before** you make the change — a live tail won't show you anything retrospectively.
3. Change that company's name — in the Autotask UI, or by importing [`postman/autotask-company-update.postman_collection.json`](postman/autotask-company-update.postman_collection.json) and running requests 0 → 4. That collection finds a company, shows its UDF values, renames it, and puts the name back.
4. Within a minute or so you should see `Synced company <id> -> '<new name>'`.
5. Check the company in aBILLity — the name should match.

Then test the off switch: set the flag to **No** on another company and rename it. The log should say it's *not flagged for aBILLity sync* and aBILLity should be untouched.

That's it — it runs on its own from here.

---

# Deploying with Wrangler instead

If you'd rather not use the dashboard. Needs [Node.js](https://nodejs.org) and a Cloudflare account.

The two UDF labels live in `cloudflare-worker/wrangler.toml` — edit them there if yours differ. Then:

```bash
cd cloudflare-worker
npm install
npx wrangler secret put AbillitySystemInformation
npx wrangler secret put AbillityUserName
npx wrangler secret put AbillityPassword
npx wrangler secret put WebhookToken
npx wrangler deploy
```

Each `secret put` prompts you to paste the value — nothing is written to disk. `deploy` prints your hostname when it finishes; carry on from step 3 above.

To watch it run: `npx wrangler tail`. To test locally: copy `.dev.vars.example` to `.dev.vars`, fill it in, then `npx wrangler dev`.

---

# Hosting on Azure Functions instead

**Create the Function App.** Azure Portal → **Create a resource** → **Function App**.
- Hosting: **Consumption (Serverless)** — this stays free at this scale
- Runtime stack: **PowerShell Core**
- Pick any name, e.g. `autotask-abillity-sync`

**Upload the code.** Open the Function App → **Deployment Center**, or use the [Azure Functions Core Tools](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local):
```bash
cd AutotaskAbillitySync
func azure functionapp publish autotask-abillity-sync
```
Both `CompanyNameSync` and `CompanyNameSyncDeactivated` will appear as functions inside the app.

**Add your settings.** Function App → **Configuration** → **Application settings** → add these five:

| Name | Value |
|---|---|
| `AutotaskAbillityIdUdfLabel` | `aBillity Company ID` |
| `AutotaskSyncFlagUdfLabel` | `Sync with aBillity` |
| `AbillitySystemInformation` | from your aBILLity account |
| `AbillityUserName` | your aBILLity API username |
| `AbillityPassword` | your aBILLity API password |

There's no `WebhookToken` here — Azure supplies its own function key instead.

**Grab the two URLs.** Function App → open **CompanyNameSync** → **Get Function URL** → copy it. Repeat for **CompanyNameSyncDeactivated**. Each looks like:
```
https://autotask-abillity-sync.azurewebsites.net/api/CompanyNameSync?code=AbCdEf123...
```
That `?code=` is Azure's own function key — it's already there, you don't set it up. Carry on from step 4 above.

To watch it run: Function App → **CompanyNameSync** → **Monitor**.

---

# Testing the aBILLity side on its own

If a sync doesn't work, it helps to know which half is broken. These test aBILLity directly — no Autotask, no Cloudflare.

All of it is checked against aBILLity's published API (the `/GettingStarted` page on your own aBILLity API host): `PATCH api/company/{id}` updates selected details (`PUT` would replace *all* of them), `GET api/company/{id}` returns a `CompanyView` with `Name` at the top level, the id is an integer, and `Name` is capped at 50 characters.

> **The API host differs between aBILLity instances.** The default is `https://api-billing.abillity.co.uk/api`; set the `AbillityApiBase` variable on the Worker if yours differs. A wrong host gives unexplained 500s rather than a clean error, so check the `/GettingStarted` page on *your* instance rather than assuming.

> **These write to live billing data.** Request 2 / `-NewName` genuinely renames a company in aBILLity. Use one you're willing to rename, and restore it afterwards. The read step alone is enough to check credentials and a company id.

### Postman

Import [`postman/abillity-test.postman_collection.json`](postman/abillity-test.postman_collection.json). Fill in `systemInformation`, `abillityUserName`, `abillityPassword`, `companyId`, and `testName`.

| # | Request | Does |
|---|---|---|
| 0 | Check credentials (`GET /site`) | **Read-only.** The endpoint aBILLity's own examples use. Run it first when anything fails — it separates bad credentials from a bad request. |
| 1 | Get company — check its name | **Read-only.** Prints `Name`, `LastUpdated`, the flags and dates from `CompanyView`, and stores the name in `originalName`. Run it alone any time you just want to see what aBILLity holds. |
| 2 | Rename company | **Writes.** The exact PATCH the Worker makes. |
| 3 | Restore original name | Puts back what request 1 captured. |

Run 1 first — it's what makes 3 possible. To just check a company's name, or only the credentials, run 1 and stop.

`LastUpdated` is the field to watch when testing a sync: rename the company in Autotask, run request 1, and it should read a moment ago. A name that changed with an old `LastUpdated` means you're looking at a different company than the one that synced.

### PowerShell

Read-only — looks the company up, changes nothing:

```powershell
.\test-abillity.ps1 -CompanyId 789 -SystemInformation "..." -UserName "..."
```

Test the rename (asks for a typed `RENAME`, then offers to restore):

```powershell
.\test-abillity.ps1 -CompanyId 789 -SystemInformation "..." -UserName "..." -NewName "Test Rename - safe to ignore"
```

Omit `-Password` and it prompts, so it stays out of your shell history. If aBILLity has no GET for a single company, add `-SkipRead`.

### Getting a 500 from aBILLity?

A 500 isn't in aBILLity's documented errors (401, 404, 409) — it means the API threw rather than rejected you. Run request 0 first to see whether auth works at all, then check in this order:

1. **`SystemInformation` is wrong.** This is the most likely cause. It selects *which system* the API connects to, so a wrong or missing value can fail deep inside the API rather than come back as a clean 401.

   In particular, **`SYSTEM` is a placeholder, not a value.** aBILLity's code samples use `SYSTEM`, `USERNAME` and `PASSWORD` together as all-caps stand-ins to be replaced — sending `SYSTEM` literally is as wrong as sending `USERNAME` as your username. The real value is issued with your API credentials; get it from whoever administers your aBILLity instance, or Union Street support.
2. **Header names.** `SystemInformation`, `username`, `password` — check for typos and trailing spaces. Postman keeps disabled/duplicate headers around; look at the actual sent headers under the response's **Headers** tab.
3. **Postman's Authorization tab set to anything but "No Auth"** adds a competing `Authorization` header.
4. **`Content-Type` on a bodyless GET.** Request 0 deliberately omits it; some ASP.NET stacks object.

If the body comes back as HTML, read it — ASP.NET error pages often name the underlying fault.

**On the `api_key` in the docs:** the C# sample declares `var urlParameters = "?api_key=123";` and then never uses it — it's boilerplate from Microsoft's "Call a Web API From a .NET Client" tutorial. aBILLity documents only two authentication methods: the header credentials used here, and a token from `POST /api/Authenticate`. There's no API-key option to switch to.

### What the results mean

| Result | Meaning |
|---|---|
| Read works, rename works | aBILLity is fine. Any failure is on the Autotask or Worker side. |
| `401` | Bad credentials **or** a user without company permissions — aBILLity uses 401 for both, so check the permissions too. |
| `403` | Credentials valid, but not permitted for this company. |
| `404` | No such company, or no companies in the database. Usually the `aBillity Company ID` UDF is wrong; the Worker fails identically. |
| HTML instead of JSON | The request never reached the API. |

---

# Troubleshooting the setup script

**`404 - File or directory not found` at the zone lookup**

This is Autotask saying "that URL doesn't exist here" before the script has done anything. It's almost always one of:

| Cause | Fix |
|---|---|
| `$AutotaskUserName` isn't the API user | It must be the **API user's** username exactly as Autotask lists it under **Admin → Resources/Users** — usually an email address, and *not* your own Autotask login. |
| That user isn't an API user | Its Security Level must be **API User (system)**. |
| `$AutotaskApiIntegrationCode` is wrong | It's the tracking identifier from **Admin → Extensions & Integrations → Other Extensions & Tools → Integration Vendor API user**. |
| The machine can't reach `*.autotask.net` | Corporate proxy or firewall. Test with `curl https://webservices2.autotask.net/atservicesrest/versioninformation`. |

The script tries several host and version combinations and prints each URL as it goes, so the last few lines tell you exactly what was attempted.

**One error used to become six.** Earlier versions carried on after a failure, so an empty base URL produced a cascade of `Invalid URI: The hostname could not be parsed` messages and a misleading `No Company UDF found...` at the end. The script now stops at the first real problem — if you see UDF errors now, they're genuine.

**Test credentials safely with `test-autotask-credentials.ps1`**

Don't debug credentials by re-running the setup script — every failed attempt counts toward locking the account. Use the tester instead.

The zone lookup sends no credentials at all, so this can never lock anything:

```powershell
.\test-autotask-credentials.ps1 -UserName "api-user@yourdomain.com" -ZoneOnly
```

It prints the zone URL your account lives on. Note it already ends in `/ATServicesRest` — a very common mistake is dropping that, which gives you a **blank HTML page** instead of JSON. HTML always means the request never reached the API, so the URL is wrong, not the credentials.

Once you're confident, test the credentials with exactly one authenticated request (it asks before sending):

```powershell
.\test-autotask-credentials.ps1 -UserName "api-user@yourdomain.com" -ApiIntegrationCode "..." -Secret "..."
```

It prints the HTTP status, content type and response body, and tells you what each status means.

**If the account is locked**, none of this will work until an Autotask admin unlocks it, and further attempts may extend the lockout. Unlock first, test once, then run the setup script.

**`Autotask rejected the credentials`**

The script makes two test calls before it creates anything, and prints the HTTP status and Autotask's own response body for whichever one failed. The status tells you which problem you have:

| Status | Meaning | Fix |
|---|---|---|
| **401** | The credentials themselves are wrong. | Check all three below. |
| **403** | The credentials are *valid*, but this API user isn't allowed to do that. | A permissions problem, not a password problem — see below. |

For a 401, check all three in the API user's own record (**Admin → Resources/Users →** find the API user **→ Edit**):

- `$AutotaskUserName` — the API user's Username exactly as Autotask shows it. Usually an email address, and **not** your own Autotask login.
- `$AutotaskSecret` — that API user's generated Password/Secret. Not a person's password, and not the integration code.
- `$AutotaskApiIntegrationCode` — the Tracking Identifier from **Admin → Extensions & Integrations → Other Extensions & Tools → Integration Vendor API user**.
- The API user's Security Level must be **API User (system)**.

If you've just created or reset the API user, wait a minute and retry — new credentials aren't always live immediately.

For a 403, the credentials are fine but the Security Level lacks access to the entity named in the error. Webhook permissions in particular aren't granted to every API user by default. Check the Security Level under **Admin → Resources/Users**, or ask whoever administers your Autotask instance.

**`No Company UDF found with the label ...`**

The script prints every Company UDF label Autotask actually reports. Copy the two you want out of that list into the config block, character for character.

Note that if this fires, the webhook has already been created. Either fix the labels and re-run just section 6, or delete the webhook in Autotask (**Admin → Extensions & Integrations → Other Extensions & Tools → Webhooks**) and run the whole script again.

**Nothing syncs, but no errors anywhere**

Check the company's `Sync with aBillity` UDF actually says yes. A blank flag is a deliberate skip, and it's logged rather than raised as an error.

---

# A couple of things to know

- **Costs nothing at this scale** — Cloudflare's free tier (100k requests/day) and Azure's free monthly grant (1M runs) are both far more than a name-change webhook will ever use.
- **Never commit your secrets** — `.dev.vars` (Cloudflare) and `local.settings.json` (Azure) are both gitignored. Only the `.example` files belong in git.
- **Names over 50 characters get shortened** automatically — that's aBILLity's own limit, not a bug.
- **Nothing syncs by default.** A company with a blank sync flag is skipped, so switching a company on is a deliberate act. If a sync you expected didn't happen, check that flag first, then the aBILLity ID, then the logs.
- **Switching hosts later** is just a re-run of `autotask-abillity-sync.ps1` with the new URLs (delete the old webhook in Autotask first, under Admin → Extensions & Integrations → Other Extensions & Tools → Webhooks).
