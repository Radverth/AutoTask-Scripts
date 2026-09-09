# Autotask → aBILLity Company Name Sync

When a Company's name changes in Autotask, this automatically updates the matching Company's name in aBILLity.

## How it works

Autotask → fires a webhook → a small hosted endpoint (this repo) → updates aBILLity via its API.

You can host that endpoint on **Azure Functions** or **Cloudflare Workers** — pick one, they do exactly the same thing. Everything after the deployment step is identical either way.

## What's in this repo

- **`autotask-abillity-sync.ps1`** — run this once, at the end, to register the webhook with Autotask. Host-agnostic: it just needs your two endpoint URLs.
- **`AutotaskAbillitySync/`** — the Azure Function (PowerShell):
  - `CompanyNameSync/` — receives the webhook, updates aBILLity.
  - `CompanyNameSyncDeactivated/` — a required callback for if the webhook ever gets deactivated.
  - `local.settings.json.example` — template for your secrets (copy it, don't edit the original).
- **`cloudflare-worker/`** — the same thing as a Cloudflare Worker (JavaScript):
  - `src/index.js` — one Worker serving both endpoints.
  - `wrangler.toml` — the Worker's config.
  - `.dev.vars.example` — template for local testing secrets.

---

## Setup — step by step

### 1. Deploy the endpoint

Do **either** 1A or 1B, not both.

<details open>
<summary><strong>1A. Azure Functions</strong></summary>

**Create the Function App.** Azure Portal → **Create a resource** → **Function App**.
- Hosting: **Consumption (Serverless)** — this stays free at this scale
- Runtime stack: **PowerShell Core**
- Pick any name, e.g. `autotask-abillity-sync`

**Upload the code.** Easiest way: open the Function App → **Deployment Center**, or use the [Azure Functions Core Tools](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local):
```bash
cd AutotaskAbillitySync
func azure functionapp publish autotask-abillity-sync
```
Both `CompanyNameSync` and `CompanyNameSyncDeactivated` will appear as functions inside the app.

**Add your secrets.** Function App → **Configuration** → **Application settings** → add the four from the table below, using your real values.

**Grab the two URLs.** Function App → open **CompanyNameSync** → **Get Function URL** → copy it. Repeat for **CompanyNameSyncDeactivated**. Each looks like:
```
https://autotask-abillity-sync.azurewebsites.net/api/CompanyNameSync?code=AbCdEf123...
```
The `?code=` is Azure's own function key — it's what stops strangers calling your endpoint. You don't have to set it up; it's there already.

</details>

<details>
<summary><strong>1B. Cloudflare Workers</strong></summary>

You'll need a Cloudflare account and [Node.js](https://nodejs.org) installed.

**Set your UDF label.** Open `cloudflare-worker/wrangler.toml` and replace `<YOUR_UDF_LABEL>` with the exact label of your Autotask UDF.

**Add your secrets.** Unlike Azure, Workers have no built-in endpoint key, so you invent one — `WebhookToken` — and it goes in the URL as `?code=`. Make it long and random (e.g. `openssl rand -hex 32`).
```bash
cd cloudflare-worker
npm install
npx wrangler secret put AbillitySystemInformation
npx wrangler secret put AbillityUserName
npx wrangler secret put AbillityPassword
npx wrangler secret put WebhookToken
```
Each command prompts you to paste the value — nothing is written to disk.

**Deploy.**
```bash
npx wrangler deploy
```

**Your two URLs** are the deployed Worker's hostname plus the two paths, with your `WebhookToken` as `?code=`:
```
https://autotask-abillity-sync.<your-subdomain>.workers.dev/api/CompanyNameSync?code=<YOUR_WEBHOOK_TOKEN>
https://autotask-abillity-sync.<your-subdomain>.workers.dev/api/CompanyNameSyncDeactivated?code=<YOUR_WEBHOOK_TOKEN>
```
`wrangler deploy` prints the hostname when it finishes.

To watch it run: `npx wrangler tail`. To test locally: copy `.dev.vars.example` to `.dev.vars`, fill it in, then `npx wrangler dev`.

</details>

### 2. The settings, whichever host you chose

| Name | Value | Azure | Cloudflare |
|---|---|---|---|
| `AutotaskUdfLabel` | the exact label of your Autotask UDF that stores the aBILLity Company ID | App setting | `wrangler.toml` |
| `AbillitySystemInformation` | from your aBILLity account | App setting | secret |
| `AbillityUserName` | your aBILLity API username | App setting | secret |
| `AbillityPassword` | your aBILLity API password | App setting | secret |
| `WebhookToken` | a long random string you invent | — (Azure supplies its own key) | secret |

### 3. Register the webhook with Autotask
Open `autotask-abillity-sync.ps1` and fill in the top config block:
- The two URLs from step 1 (including the `?code=` part)
- Your Autotask API credentials
- Your aBILLity credentials (same as step 2)
- Your UDF label (same as step 2)

Then just run the script in PowerShell, start to finish. It talks to Autotask and sets everything up — you don't need to touch the Autotask UI.

### 4. Test it
- Change a test company's name in Autotask
- Watch the logs — Azure: Function App → **CompanyNameSync** → **Monitor**. Cloudflare: `npx wrangler tail`. You should see it fire within a minute or so.
- Check the aBILLity company — the name should now match

That's it — it runs on its own from here.

---

## A couple of things to know

- **Costs nothing at this scale** — both Azure's free monthly grant (1M runs) and Cloudflare's free tier (100k requests/day) are far more than a name-change webhook will ever use.
- **Never commit your secrets** — `local.settings.json` (Azure) and `.dev.vars` (Cloudflare) are both gitignored. Only the `.example` files belong in git.
- **Names over 50 characters get shortened** automatically — that's aBILLity's own limit, not a bug.
- If a company has no aBILLity ID in its UDF, it's skipped silently rather than erroring — check the logs if you're expecting a sync that didn't happen.
- **Switching hosts later** is just a re-run of `autotask-abillity-sync.ps1` with the new URLs (delete the old webhook in Autotask first, under Admin → Extensions & Integrations → Other Extensions & Tools → Webhooks).
