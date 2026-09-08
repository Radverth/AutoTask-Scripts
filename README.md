# Autotask → aBILLity Company Name Sync

When a Company's name changes in Autotask, this automatically updates the matching Company's name in aBILLity.

## How it works

Autotask → fires a webhook → Azure Function (this repo) → updates aBILLity via its API.

## What's in this repo

- **`autotask-abillity-sync.ps1`** — run this once, at the end, to register the webhook with Autotask.
- **`AutotaskAbillitySync/`** — the Azure Function itself:
  - `CompanyNameSync/` — receives the webhook, updates aBILLity.
  - `CompanyNameSyncDeactivated/` — a required callback for if the webhook ever gets deactivated.
  - `local.settings.json.example` — template for your secrets (copy it, don't edit the original).

---

## Setup — step by step

### 1. Create the Azure Function App
Azure Portal → **Create a resource** → **Function App**.
- Hosting: **Consumption (Serverless)** — this stays free at this scale
- Runtime stack: **PowerShell Core**
- Pick any name, e.g. `autotask-abillity-sync`

### 2. Upload the code
Easiest way: open the Function App → **Deployment Center**, or use the [Azure Functions Core Tools](https://learn.microsoft.com/en-us/azure/azure-functions/functions-run-local):
```bash
cd AutotaskAbillitySync
func azure functionapp publish autotask-abillity-sync
```
Both `CompanyNameSync` and `CompanyNameSyncDeactivated` will appear as functions inside the app.

### 3. Add your secrets
Function App → **Configuration** → **Application settings** → add these four, using your real values:

| Name | Value |
|---|---|
| `AutotaskUdfLabel` | the exact label of your Autotask UDF that stores the aBILLity Company ID |
| `AbillitySystemInformation` | from your aBILLity account |
| `AbillityUserName` | your aBILLity API username |
| `AbillityPassword` | your aBILLity API password |

(`local.settings.json.example` shows the same four, for reference or local testing.)

### 4. Grab the two function URLs
Function App → open **CompanyNameSync** → **Get Function URL** → copy it.
Repeat for **CompanyNameSyncDeactivated**.

Each one looks like:
```
https://autotask-abillity-sync.azurewebsites.net/api/CompanyNameSync?code=AbCdEf123...
```

### 5. Register the webhook with Autotask
Open `autotask-abillity-sync.ps1` and fill in the top config block:
- The two URLs from step 4
- Your Autotask API credentials
- Your aBILLity credentials (same as step 3)
- Your UDF label (same as step 3)

Then just run the script in PowerShell, start to finish. It talks to Autotask and sets everything up — you don't need to touch the Autotask UI.

### 6. Test it
- Change a test company's name in Autotask
- Function App → **CompanyNameSync** → **Monitor** — you should see it fire within a minute or so
- Check the aBILLity company — the name should now match

That's it — it runs on its own from here.

---

## A couple of things to know

- **Costs nothing at this scale** — Azure's free monthly grant (1M runs) is far more than a name-change webhook will ever use.
- **Never commit `local.settings.json`** (only `local.settings.json.example`) — it's already excluded via `.gitignore`.
- **Names over 50 characters get shortened** automatically — that's aBILLity's own limit, not a bug.
- If a company has no aBILLity ID in its UDF, it's skipped silently rather than erroring — check the Monitor logs if you're expecting a sync that didn't happen.
