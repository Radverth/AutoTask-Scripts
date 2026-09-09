# Autotask → aBILLity Company Name Sync

When a Company's name changes in Autotask, this automatically updates the matching Company's name in aBILLity — but only for companies you've explicitly flagged for syncing.

## How it works

Autotask → fires a webhook → a small hosted endpoint (this repo) → updates aBILLity via its API.

You can host that endpoint on **Cloudflare Workers** or **Azure Functions** — pick one, they do exactly the same thing.

### The two UDFs

The sync reads two Company user-defined fields in Autotask. Both must be right for anything to happen:

| UDF label | What it holds | What it does |
|---|---|---|
| `Sync with aBillity (yes or no)` | `Yes` or `No` | The on switch. Anything other than yes — including blank — means this company is left alone. |
| `aBillity Company ID` | the company's aBILLity ID | Where the update gets sent. |

So a name change syncs only when the flag says yes **and** an aBILLity ID is present. Everything else is skipped and written to the log, never treated as an error. `Yes`, `yes`, `Y`, `True`, `1`, `On` and a ticked checkbox all count as yes; anything else counts as no.

## What's in this repo

- **`autotask-abillity-sync.ps1`** — run this once, at the end, to register the webhook with Autotask. Host-agnostic: it just needs your two endpoint URLs.
- **`test-autotask-credentials.ps1`** — checks your Autotask zone and credentials without running the full setup, and without spending failed login attempts you didn't mean to spend.
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
- `Sync with aBillity (yes or no)`

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
| Text | `AutotaskSyncFlagUdfLabel` | `Sync with aBillity (yes or no)` |

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

Open `autotask-abillity-sync.ps1` and fill in the config block at the top:

- `$WebhookUrl` and `$DeactivationUrl` — the two URLs from step 3
- Your Autotask API credentials
- Your aBILLity credentials (same as step 2.5)
- `$AbillityIdUdfLabel` and `$SyncFlagUdfLabel` — your two UDF labels from step 1

Then run the script in PowerShell, start to finish. It talks to Autotask and sets everything up — you don't need to touch the Autotask UI. It registers the company name as the trigger, and both UDFs as ride-along fields so your Worker can read them.

If a UDF label is wrong, the script says so by name rather than failing silently.

---

## Step 5 — Test it

1. Pick a test company in Autotask. Set `Sync with aBillity (yes or no)` to **Yes** and put a real aBILLity ID in `aBillity Company ID`.
2. In a terminal, start watching the logs: on the Worker's page click **Logs** → **Begin log stream** (or run `npx wrangler tail`).
3. Change that company's name in Autotask.
4. Within a minute or so you should see `Synced company <id> -> '<new name>'` in the log.
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
| `AutotaskSyncFlagUdfLabel` | `Sync with aBillity (yes or no)` |
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

Check the company's `Sync with aBillity (yes or no)` UDF actually says yes. A blank flag is a deliberate skip, and it's logged rather than raised as an error.

---

# A couple of things to know

- **Costs nothing at this scale** — Cloudflare's free tier (100k requests/day) and Azure's free monthly grant (1M runs) are both far more than a name-change webhook will ever use.
- **Never commit your secrets** — `.dev.vars` (Cloudflare) and `local.settings.json` (Azure) are both gitignored. Only the `.example` files belong in git.
- **Names over 50 characters get shortened** automatically — that's aBILLity's own limit, not a bug.
- **Nothing syncs by default.** A company with a blank sync flag is skipped, so switching a company on is a deliberate act. If a sync you expected didn't happen, check that flag first, then the aBILLity ID, then the logs.
- **Switching hosts later** is just a re-run of `autotask-abillity-sync.ps1` with the new URLs (delete the old webhook in Autotask first, under Admin → Extensions & Integrations → Other Extensions & Tools → Webhooks).
