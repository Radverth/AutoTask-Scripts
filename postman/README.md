# Postman collections

Four collections, each standalone. Import with **Import → File**.

Generated from the collection files themselves, so what's described here is what you'll actually import.

## Which one do I want?

| Collection | What it's for | When |
|---|---|---|
| [`autotask-abillity-sync.postman_collection.json`](./autotask-abillity-sync.postman_collection.json) | **Set up the Autotask webhook.** One-time setup. Registers the webhook that fires when a company name changes, and tells Autotask to include your two UDFs in the payload. | Run once, when first setting the sync up, or after moving the Worker to a new URL. |
| [`cloudflare-worker-test.postman_collection.json`](./cloudflare-worker-test.postman_collection.json) | **Test the Cloudflare Worker.** Health-checks the Worker and fires simulated webhooks at it. No Autotask involved. | First stop when a sync doesn't happen. Proves the Worker is live, configured and parsing correctly. |
| [`autotask-company-update.postman_collection.json`](./autotask-company-update.postman_collection.json) | **Rename an Autotask company.** Reads and renames a company through the Autotask API. Renaming is what fires the webhook. | End-to-end testing, without clicking through the Autotask UI. |
| [`abillity-test.postman_collection.json`](./abillity-test.postman_collection.json) | **Check and rename in aBILLity.** Talks to aBILLity directly — credentials, company lookup, and the rename the Worker performs. | Checking what aBILLity holds, and isolating whether a failure is aBILLity's side. |

## Before you start

Four things that cause most of the confusion:

1. **Open the console.** **View → Show Postman Console.** Nearly every request logs what it found or captured — the response pane alone often isn't the whole answer.
2. **Authorization tab must be "No Auth".** Both APIs authenticate with plain headers; anything in the Authorization tab adds a competing header.
3. **Fill in variables on the collection's Variables tab, then Save.** Requests read `{{variableName}}` from there.
4. **Leave the captured variables blank.** Earlier requests fill them in — each table below says which.

> Requests that change live data are marked **WRITES LIVE DATA**. Read-only ones can be run freely.

---

# Set up the Autotask webhook

`autotask-abillity-sync.postman_collection.json`

One-time setup. Registers the webhook that fires when a company name changes, and tells Autotask to include your two UDFs in the payload.

### Variables you fill in

| Variable | Set it to |
|---|---|
| `userName` | the Autotask **API user's** username — usually an email address, not your own login |
| `apiIntegrationCode` | Tracking Identifier from Admin → Extensions & Integrations → Integration Vendor API user |
| `secret` | the API user's generated Password/Secret |
| `webhookUrl` | `https://<worker>.workers.dev/api/CompanyNameSync?code=<WebhookToken>` |
| `deactivationUrl` | `https://<worker>.workers.dev/api/CompanyNameSyncDeactivated?code=<WebhookToken>` |
| `notificationEmail` | where Autotask emails if the webhook starts failing |
| `abillityIdUdfLabel` | defaults to `aBillity Company ID` — change if yours differs |
| `syncFlagUdfLabel` | defaults to `Sync with aBillity (yes or no)` — change if yours differs |

### Variables filled in for you

| Variable | Captured by |
|---|---|
| `baseUrl` | 0. Get zone information (no credentials sent) |
| `webhookId` | 2. Create the webhook |
| `companyNameFieldId` | 3. Find the CompanyName fieldID |
| `abillityIdUdfFieldId` | 5. Find both UDF field IDs |
| `syncFlagUdfFieldId` | 5. Find both UDF field IDs |

Leave these blank to start.

### Requests

#### `GET` 0. Get zone information (no credentials sent) — *read-only*

```
https://webservices2.autotask.net/atservicesrest/V1.0/zoneInformation?user={{userName}}
```

Finds which Autotask server your account lives on and stores it as {{baseUrl}}.

This request sends NO credentials, so it cannot lock anything. Run it first.

If it does not return a url, the username is not a recognised Autotask API user.

#### `GET` 1. Test credentials — *read-only*

```
{{baseUrl}}/V1.0/Companies/entityInformation
```

One authenticated request, to confirm the credentials before creating anything.

200 = credentials good.  
401 = rejected (wrong values, OR the account is locked - both look the same).  
403 = credentials valid but this API user lacks permission.

Do not hammer this. Each failure counts toward a lockout.

#### `POST` 2. Create the webhook — *writes configuration*

```
{{baseUrl}}/V1.0/CompanyWebhooks
```

Creates the webhook and stores its id as {{webhookId}}.

Only run this ONCE. Running it again creates a duplicate webhook - use 'List webhooks' and 'Delete webhook' at the bottom to tidy up.

<details><summary>Request body</summary>

```json
{
  "IsActive": true,
  "DeactivationUrl": "{{deactivationUrl}}",
  "IsSubscribedToUpdateEvents": true,
  "Name": "Company Name -> aBILLity Sync",
  "SecretKey": "{{$guid}}",
  "SendThresholdExceededNotification": true,
  "WebhookUrl": "{{webhookUrl}}",
  "NotificationEmailAddress": "{{notificationEmail}}"
}
```

</details>

#### `GET` 3. Find the CompanyName fieldID — *read-only*

```
{{baseUrl}}/V1.0/CompanyWebhookFields/entityInformation/fields
```

Looks up the numeric id Autotask uses for the CompanyName field, and stores it as {{companyNameFieldId}}.

#### `POST` 4. Register CompanyName as the trigger field — *writes configuration*

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/Fields
```

Makes a change to the company name the thing that fires the webhook.

<details><summary>Request body</summary>

```json
{
  "FieldID": "{{companyNameFieldId}}",
  "IsSubscribedField": true,
  "IsDisplayAlwaysField": true,
  "WebhookID": "{{webhookId}}"
}
```

</details>

#### `GET` 5. Find both UDF field IDs — *read-only*

```
{{baseUrl}}/V1.0/CompanyWebhookUdfFields/entityInformation/fields
```

Finds the numeric ids for your two Company UDFs, matching on the labels in {{abillityIdUdfLabel}} and {{syncFlagUdfLabel}}.

If either is not found, the console lists every Company UDF label Autotask reports - copy the exact spelling from there into the collection variables.

#### `POST` 6. Register UDF: {{abillityIdUdfLabel}} — *writes configuration*

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/UdfFields
```

Adds this UDF to the webhook payload as a display-always field. It does not trigger the webhook - it just rides along so the receiver can read it.

<details><summary>Request body</summary>

```json
{
  "UdfFieldID": "{{abillityIdUdfFieldId}}",
  "IsSubscribedField": false,
  "IsDisplayAlwaysField": true,
  "WebhookID": "{{webhookId}}"
}
```

</details>

#### `POST` 7. Register UDF: {{syncFlagUdfLabel}} — *writes configuration*

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/UdfFields
```

Adds this UDF to the webhook payload as a display-always field. It does not trigger the webhook - it just rides along so the receiver can read it.

<details><summary>Request body</summary>

```json
{
  "UdfFieldID": "{{syncFlagUdfFieldId}}",
  "IsSubscribedField": false,
  "IsDisplayAlwaysField": true,
  "WebhookID": "{{webhookId}}"
}
```

</details>

#### Utilities

#### `GET` List webhooks — *read-only*

```
{{baseUrl}}/V1.0/CompanyWebhooks/query?search={"filter":[{"op":"gte","field":"id","value":0}]}
```

Shows every Company webhook on the account. Use it to confirm what was created, or to find the id of a duplicate you want to remove.

#### `GET` Get webhook {{webhookId}} — *read-only*

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}
```

Shows the webhook's current settings. Run it before and after an update to confirm the change landed.

#### `PATCH` Update webhook URLs — *writes configuration*

```
{{baseUrl}}/V1.0/CompanyWebhooks
```

Changes an existing webhook's two URLs without deleting and recreating it, so the trigger field and UDF registrations from requests 4, 6 and 7 are kept.

Set the webhookUrl and deactivationUrl collection variables to the new values first, and make sure webhookId is the webhook you mean to change - 'List webhooks' shows them all.

If the webhook has been deactivated (Autotask switches off webhooks whose endpoint keeps failing), add "IsActive": true to the body to turn it back on.

<details><summary>Request body</summary>

```json
{
  "id": "{{webhookId}}",
  "WebhookUrl": "{{webhookUrl}}",
  "DeactivationUrl": "{{deactivationUrl}}"
}
```

</details>

#### `DELETE` Delete webhook {{webhookId}} — *writes configuration*

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}
```

Deletes the webhook currently in {{webhookId}}. Use this to clean up a duplicate or start over.

Set {{webhookId}} by hand first if you want to delete a different one.

---

# Test the Cloudflare Worker

`cloudflare-worker-test.postman_collection.json`

Health-checks the Worker and fires simulated webhooks at it. No Autotask involved.

### Variables you fill in

| Variable | Set it to |
|---|---|
| `workerBaseUrl` | `https://<worker>.workers.dev` — **no trailing slash** |
| `webhookToken` | the `WebhookToken` secret set on the Worker |
| `syncFlagUdfLabel` | defaults to `Sync with aBillity (yes or no)` — change if yours differs |
| `abillityIdUdfLabel` | defaults to `aBillity Company ID` — change if yours differs |
| `testAutotaskCompanyId` | defaults to `12345` — change if yours differs |
| `testAbillityCompanyId` | a real aBILLity company id — request 4 renames it |
| `testNewName` | defaults to `Worker Test - safe to rename back` — change if yours differs |

### Requests

#### `GET` 1. Health check — *read-only*

```
{{workerBaseUrl}}/health?code={{webhookToken}}
```

Proves the Worker is deployed, configured and that your token matches. Involves no Autotask and no aBILLity.

Reports only WHETHER each setting is present, never its value.

Run this before anything else - if it fails, nothing downstream can work.

#### `GET` 2. Health check with a wrong token (expect 401) — *read-only*

```
{{workerBaseUrl}}/health?code=deliberately-wrong
```

Confirms the Worker actually rejects a bad token - that the auth check works rather than letting everything through.

A 401 here is the PASS.

#### `POST` 3. Simulate a webhook - NOT flagged for sync (safe) — **WRITES LIVE DATA**

```
{{workerBaseUrl}}/api/CompanyNameSync?code={{webhookToken}}
```

Sends a webhook-shaped payload with the sync flag set to No.

Safe: the Worker should skip it, so NOTHING is written to aBILLity. It still exercises routing, the token check, JSON parsing and the flag logic.

Run this before request 4.

Expect 200, and in the Worker log:  
  Request: POST /api/CompanyNameSync  
  ... is not flagged for aBILLity sync ... - skipping

<details><summary>Request body</summary>

```json
{
  "EntityType": "Company",
  "Action": "Update",
  "Id": "{{testAutotaskCompanyId}}",
  "Fields": [
    {
      "name": "CompanyName",
      "value": "{{testNewName}}"
    },
    {
      "name": "{{syncFlagUdfLabel}}",
      "value": "No"
    },
    {
      "name": "{{abillityIdUdfLabel}}",
      "value": "{{testAbillityCompanyId}}"
    }
  ]
}
```

</details>

#### `POST` 4. Simulate a webhook - flagged, real sync (WRITES TO aBILLITY) — **WRITES LIVE DATA**

```
{{workerBaseUrl}}/api/CompanyNameSync?code={{webhookToken}}
```

The same payload with the flag set to Yes, so the Worker performs the real aBILLity rename.

> ⚠️ **THIS RENAMES A COMPANY IN aBILLity - LIVE BILLING DATA.**

Set testAbillityCompanyId to a company you are willing to rename, and put the name back afterwards with the aBILLity collection.

Expect 200 and 'Synced company ... ->' in the Worker log.  
A 500 with 'sync failed' means the Worker reached aBILLity and aBILLity refused - the log carries the status and body.

NOTE: this proves the Worker and aBILLity work together. It does NOT prove Autotask sends this payload shape - only a real webhook shows that.

<details><summary>Request body</summary>

```json
{
  "EntityType": "Company",
  "Action": "Update",
  "Id": "{{testAutotaskCompanyId}}",
  "Fields": [
    {
      "name": "CompanyName",
      "value": "{{testNewName}}"
    },
    {
      "name": "{{syncFlagUdfLabel}}",
      "value": "Yes"
    },
    {
      "name": "{{abillityIdUdfLabel}}",
      "value": "{{testAbillityCompanyId}}"
    }
  ]
}
```

</details>

#### `POST` 5. Simulate the deactivation callback — **WRITES LIVE DATA**

```
{{workerBaseUrl}}/api/CompanyNameSyncDeactivated?code={{webhookToken}}
```

The endpoint Autotask calls if it ever deactivates the webhook. It only logs.

Writes nothing anywhere. Expect 200 and 'Autotask webhook deactivated: ...' in the log.

<details><summary>Request body</summary>

```json
{
  "reason": "manual test from Postman"
}
```

</details>

---

# Rename an Autotask company

`autotask-company-update.postman_collection.json`

Reads and renames a company through the Autotask API. Renaming is what fires the webhook.

### Variables you fill in

| Variable | Set it to |
|---|---|
| `userName` | the Autotask **API user's** username — usually an email address, not your own login |
| `apiIntegrationCode` | Tracking Identifier from Admin → Extensions & Integrations → Integration Vendor API user |
| `secret` | the API user's generated Password/Secret |
| `companySearch` | part of a company name to search for |
| `newCompanyName` | defaults to `Rename Test - safe to change back` — change if yours differs |

### Variables filled in for you

| Variable | Captured by |
|---|---|
| `baseUrl` | 0. Get zone information (no credentials sent) |
| `companyId` | 1. Find a company by name |
| `originalCompanyName` | 2. Get company {{companyId}} (read-only) |

Leave these blank to start.

### Requests

#### `GET` 0. Get zone information (no credentials sent) — *read-only*

```
https://webservices2.autotask.net/atservicesrest/V1.0/zoneInformation?user={{userName}}
```

Finds which Autotask server your account lives on and stores it as {{baseUrl}}.

Sends NO credentials - safe to run at will.

#### `GET` 1. Find a company by name — *read-only*

```
{{baseUrl}}/V1.0/Companies/query?search={"filter":[{"op":"contains","field":"companyName","value":"{{companySearch}}"}]}
```

Lists companies whose name contains {{companySearch}}, with their ids.

Read-only. Copy the id you want into {{companyId}} (or if there is exactly one match it is set for you).

#### `GET` 2. Get company {{companyId}} (read-only) — *read-only*

```
{{baseUrl}}/V1.0/Companies/{{companyId}}
```

Shows the company's current name and every user-defined field on it.

Read-only. Stores the current name in {{originalCompanyName}} so request 4 can put it back.

#### `PATCH` 3. Update the company name — **WRITES LIVE DATA**

```
{{baseUrl}}/V1.0/Companies
```

Renames the company.

> ⚠️ **THIS CHANGES LIVE AUTOTASK DATA.**

Run request 2 first so the original name is captured, then request 4 to put it back.

Note the id goes in the BODY, not the URL - that is Autotask's PATCH convention.

<details><summary>Request body</summary>

```json
{
  "id": "{{companyId}}",
  "companyName": "{{newCompanyName}}"
}
```

</details>

#### `PATCH` 4. Restore the original name — **WRITES LIVE DATA**

```
{{baseUrl}}/V1.0/Companies
```

Puts the name back to whatever request 2 captured.

If {{originalCompanyName}} is empty, request 2 did not capture it - set the name by hand instead of running this.

<details><summary>Request body</summary>

```json
{
  "id": "{{companyId}}",
  "companyName": "{{originalCompanyName}}"
}
```

</details>

---

# Check and rename in aBILLity

`abillity-test.postman_collection.json`

Talks to aBILLity directly — credentials, company lookup, and the rename the Worker performs.

### Variables you fill in

| Variable | Set it to |
|---|---|
| `systemInformation` | from your aBILLity administrator. **Not the literal word `SYSTEM`** — that's a placeholder in their docs |
| `abillityUserName` | your aBILLity API username |
| `abillityPassword` | your aBILLity API password |
| `companyId` | the aBILLity company id to look at |
| `testName` | defaults to `Test Rename - safe to ignore` — change if yours differs |

### Variables filled in for you

| Variable | Captured by |
|---|---|
| `originalName` | 1. Get company — check its name (read-only) |

Leave these blank to start.

### Requests

#### `GET` 0. Check credentials (GET /site) — *read-only*

```
https://api.abillity.co.uk/api/site
```

The endpoint every example in aBILLity's own docs uses. Run it FIRST when something is wrong - it separates 'my credentials/headers are wrong' from 'something is wrong with the company endpoint'.

Read-only.

Note there is no Content-Type header here. This is a GET with no body, and sending Content-Type on a bodyless request upsets some ASP.NET stacks.

200 - auth works. The problem is elsewhere.  
401 - credentials or permissions.  
500 - aBILLity threw an unhandled error. Most often SystemInformation is wrong or missing, since that is what selects which system to connect to - a bad value can fail inside the API rather than come back as a clean 401.

#### `GET` 1. Get company — check its name (read-only) — *read-only*

```
https://api.abillity.co.uk/api/company/{{companyId}}
```

GET api/company/{id} - the details of one company. Read-only, changes nothing, so run it as often as you like.

Use it on its own to check what aBILLity currently holds for a company, or before requests 2 and 3 so the original name is captured.

LastUpdated is the useful one when testing the sync: after renaming the company in Autotask, this should show a timestamp of a moment ago. If the name changed but LastUpdated is old, you are looking at the wrong company.

401 = bad credentials OR no company permissions (aBILLity uses 401 for both).  
404 = no such company, or no companies in this database.

#### `PATCH` 2. Rename company (WRITES LIVE DATA) — **WRITES LIVE DATA**

```
https://api.abillity.co.uk/api/company/{{companyId}}
```

The exact call the Worker makes when an Autotask company is renamed.

> ⚠️ **THIS CHANGES LIVE BILLING DATA.**

Run request 1 first so the original name is captured, then request 3 to put it back.

aBILLity caps the name at 50 characters and the Worker truncates to match - keep {{testName}} under 50 unless you are deliberately testing that.

<details><summary>Request body</summary>

```json
{
  "Name": "{{testName}}"
}
```

</details>

#### `PATCH` 3. Restore original name — **WRITES LIVE DATA**

```
https://api.abillity.co.uk/api/company/{{companyId}}
```

Puts the name back to whatever request 1 captured in {{originalName}}.

If {{originalName}} is empty, request 1 did not capture it - set the name by hand in aBILLity instead of running this.

<details><summary>Request body</summary>

```json
{
  "Name": "{{originalName}}"
}
```

</details>

---

# Common problems

| Symptom | Cause |
|---|---|
| `500` from aBILLity | Usually `SystemInformation`. **`SYSTEM` is a placeholder in aBILLity's docs, not a value** — get the real one from your aBILLity administrator. |
| `401` from aBILLity | Bad credentials *or* a user without company permissions. aBILLity uses 401 for both. |
| `401` from Autotask | Wrong credentials *or* a locked account — indistinguishable. Don't retry repeatedly; each attempt counts toward a lockout. |
| `405 method not allowed` from the Worker | The path didn't match. The log's `Request: GET /...` line shows what actually arrived — usually a trailing slash on `workerBaseUrl`, or `/api/health` instead of `/health`. |
| HTML instead of JSON | The request never reached the API. The URL is wrong, not the credentials. |
| Autotask `PATCH` seems to do nothing | The id goes in the **body**, not the URL. That's Autotask's convention. |
| A variable reads as empty | Saved on the Variables tab? Requests read the saved value. |

# Diagnosing a sync that didn't happen

In order — each step rules out one layer:

1. **Worker** → request 1 (health check). Live and configured?
2. **Worker** → request 3 (simulated webhook, not flagged). Routing and parsing work? Writes nothing.
3. **aBILLity** → request 0 (credentials). Auth good?
4. **aBILLity** → request 1, using the id from the company's UDF. Does that company exist?
5. **Autotask setup** → *List webhooks*. Does the webhook exist, and is it active?
6. **Autotask company update** → requests 0–2. Are both UDFs actually set on the company?
7. With the Worker log open, **Autotask company update** → request 3. Watch for `Request: POST /api/CompanyNameSync`.

No log line at step 7 means Autotask never called the Worker — go back to step 5.
