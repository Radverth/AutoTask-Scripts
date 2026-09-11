# Postman collections

Four collections, each standalone. **Import → File.**

Every request below is laid out to copy straight out: the URL, the headers, the body, and a cURL you can paste into Postman's import box to build the request without typing anything.

## Which one do I want?

| Collection | What it's for | When |
|---|---|---|
| [`autotask-abillity-sync.postman_collection.json`](./autotask-abillity-sync.postman_collection.json) | **Set up the Autotask webhook.** One-time setup. Registers the webhook that fires when a company name changes, and tells Autotask to include your two UDFs in the payload. | Run once, when first setting the sync up, or after moving the Worker to a new URL. |
| [`cloudflare-worker-test.postman_collection.json`](./cloudflare-worker-test.postman_collection.json) | **Test the Cloudflare Worker.** Health-checks the Worker and fires simulated webhooks at it. No Autotask involved. | First stop when a sync doesn't happen. |
| [`autotask-company-update.postman_collection.json`](./autotask-company-update.postman_collection.json) | **Rename an Autotask company.** Reads and renames a company through the Autotask API. Renaming is what fires the webhook. | End-to-end testing, without clicking through the Autotask UI. |
| [`abillity-test.postman_collection.json`](./abillity-test.postman_collection.json) | **Check and rename in aBILLity.** Talks to aBILLity directly — credentials, company lookup, and the rename the Worker performs. | Checking what aBILLity holds, and isolating whether a failure is aBILLity's side. |

## Building a request by pasting

Postman turns a cURL command into a request for you:

1. **Import → Raw text**
2. Paste the `curl ...` block from any request below
3. **Continue → Import**

The `{{variables}}` come through intact, so the new request picks up whatever you've set on the Variables tab.

## Before you start

1. **Open the console** — **View → Show Postman Console.** Most requests log what they found or captured.
2. **Authorization tab must be "No Auth".** Both APIs authenticate with plain headers; anything else adds a competing header.
3. **Fill in variables on the Variables tab, then Save.**
4. **Leave the captured variables blank** — earlier requests fill them in.

> Requests that change live data are marked **WRITES LIVE DATA**. Read-only ones can be run freely.

---

# Set up the Autotask webhook

`autotask-abillity-sync.postman_collection.json`

One-time setup. Registers the webhook that fires when a company name changes, and tells Autotask to include your two UDFs in the payload.

## Variables

**You fill in:**

| Variable | Set it to |
|---|---|
| `userName` | the Autotask **API user's** username — usually an email address, not your own login |
| `apiIntegrationCode` | Tracking Identifier from Admin → Extensions & Integrations → Integration Vendor API user |
| `secret` | the API user's generated Password/Secret |
| `webhookUrl` | `https://<worker>.workers.dev/api/CompanyNameSync?code=<WebhookToken>` |
| `deactivationUrl` | `https://<worker>.workers.dev/api/CompanyNameSyncDeactivated?code=<WebhookToken>` |
| `notificationEmail` | where Autotask emails if the webhook starts failing |
| `abillityIdUdfLabel` | defaults to `aBillity Company ID` |
| `syncFlagUdfLabel` | defaults to `Sync with aBillity (yes or no)` |

**Filled in for you — leave blank:**

| Variable | Captured by |
|---|---|
| `baseUrl` | 0. Get zone information (no credentials sent) |
| `webhookId` | 2. Create the webhook |
| `companyNameFieldId` | 3. Find the CompanyName fieldID |
| `abillityIdUdfFieldId` | 5. Find both UDF field IDs |
| `syncFlagUdfFieldId` | 5. Find both UDF field IDs |

## Headers

Used by every request in this collection except where a request says otherwise:

```
ApiIntegrationcode: {{apiIntegrationCode}}
UserName: {{userName}}
Secret: {{secret}}
Content-Type: application/json
```

## Requests

### 0. Get zone information (no credentials sent) — *read-only*

Finds which Autotask server your account lives on and stores it as {{baseUrl}}.

This request sends NO credentials, so it cannot lock anything. Run it first.

If it does not return a url, the username is not a recognised Autotask API user.

**URL**

```
https://webservices2.autotask.net/atservicesrest/V1.0/zoneInformation?user={{userName}}
```

**Headers** (different from the collection default above)

```
Content-Type: application/json
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET 'https://webservices2.autotask.net/atservicesrest/V1.0/zoneInformation?user={{userName}}' \
  -H 'Content-Type: application/json'
```

### 1. Test credentials — *read-only*

One authenticated request, to confirm the credentials before creating anything.

200 = credentials good.  
401 = rejected (wrong values, OR the account is locked - both look the same).  
403 = credentials valid but this API user lacks permission.

Do not hammer this. Each failure counts toward a lockout.

**URL**

```
{{baseUrl}}/V1.0/Companies/entityInformation
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/Companies/entityInformation' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### 2. Create the webhook — *writes configuration*

Creates the webhook and stores its id as {{webhookId}}.

Only run this ONCE. Running it again creates a duplicate webhook - use 'List webhooks' and 'Delete webhook' at the bottom to tidy up.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks
```

**Body** — raw / JSON

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

**cURL** — paste into Import → Raw text

```bash
curl -X POST '{{baseUrl}}/V1.0/CompanyWebhooks' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json' \
  -d '{"IsActive":true,"DeactivationUrl":"{{deactivationUrl}}","IsSubscribedToUpdateEvents":true,"Name":"Company Name -> aBILLity Sync","SecretKey":"{{$guid}}","SendThresholdExceededNotification":true,"WebhookUrl":"{{webhookUrl}}","NotificationEmailAddress":"{{notificationEmail}}"}'
```

### 3. Find the CompanyName fieldID — *read-only*

Looks up the numeric id Autotask uses for the CompanyName field, and stores it as {{companyNameFieldId}}.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhookFields/entityInformation/fields
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/CompanyWebhookFields/entityInformation/fields' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### 4. Register CompanyName as the trigger field — *writes configuration*

Makes a change to the company name the thing that fires the webhook.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/Fields
```

**Body** — raw / JSON

```json
{
  "FieldID": "{{companyNameFieldId}}",
  "IsSubscribedField": true,
  "IsDisplayAlwaysField": true,
  "WebhookID": "{{webhookId}}"
}
```

**cURL** — paste into Import → Raw text

```bash
curl -X POST '{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/Fields' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json' \
  -d '{"FieldID":"{{companyNameFieldId}}","IsSubscribedField":true,"IsDisplayAlwaysField":true,"WebhookID":"{{webhookId}}"}'
```

### 5. Find both UDF field IDs — *read-only*

Finds the numeric ids for your two Company UDFs, matching on the labels in {{abillityIdUdfLabel}} and {{syncFlagUdfLabel}}.

If either is not found, the console lists every Company UDF label Autotask reports - copy the exact spelling from there into the collection variables.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhookUdfFields/entityInformation/fields
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/CompanyWebhookUdfFields/entityInformation/fields' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### 6. Register UDF: {{abillityIdUdfLabel}} — *writes configuration*

Adds this UDF to the webhook payload as a display-always field. It does not trigger the webhook - it just rides along so the receiver can read it.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/UdfFields
```

**Body** — raw / JSON

```json
{
  "UdfFieldID": "{{abillityIdUdfFieldId}}",
  "IsSubscribedField": false,
  "IsDisplayAlwaysField": true,
  "WebhookID": "{{webhookId}}"
}
```

**cURL** — paste into Import → Raw text

```bash
curl -X POST '{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/UdfFields' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json' \
  -d '{"UdfFieldID":"{{abillityIdUdfFieldId}}","IsSubscribedField":false,"IsDisplayAlwaysField":true,"WebhookID":"{{webhookId}}"}'
```

### 7. Register UDF: {{syncFlagUdfLabel}} — *writes configuration*

Adds this UDF to the webhook payload as a display-always field. It does not trigger the webhook - it just rides along so the receiver can read it.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/UdfFields
```

**Body** — raw / JSON

```json
{
  "UdfFieldID": "{{syncFlagUdfFieldId}}",
  "IsSubscribedField": false,
  "IsDisplayAlwaysField": true,
  "WebhookID": "{{webhookId}}"
}
```

**cURL** — paste into Import → Raw text

```bash
curl -X POST '{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/UdfFields' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json' \
  -d '{"UdfFieldID":"{{syncFlagUdfFieldId}}","IsSubscribedField":false,"IsDisplayAlwaysField":true,"WebhookID":"{{webhookId}}"}'
```

## Utilities

### List webhooks — *read-only*

Shows every Company webhook on the account. Use it to confirm what was created, or to find the id of a duplicate you want to remove.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks/query?search={"filter":[{"op":"gte","field":"id","value":0}]}
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/CompanyWebhooks/query?search={"filter":[{"op":"gte","field":"id","value":0}]}' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### Get webhook {{webhookId}} — *read-only*

Shows the webhook's current settings. Run it before and after an update to confirm the change landed.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### Why isn't it firing? 1 - trigger fields — *read-only*

Lists the fields registered on the webhook.

A webhook with no subscribed field fires on nothing, which looks exactly like a broken endpoint. Creating the webhook (request 2) and registering the trigger (request 4) are separate calls - if request 4 never succeeded, this is your answer.

Read-only.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/Fields/query?search={"filter":[{"op":"gte","field":"id","value":0}]}
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/Fields/query?search={"filter":[{"op":"gte","field":"id","value":0}]}' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### Why isn't it firing? 2 - UDF fields — *read-only*

Lists the UDFs riding along in the payload. There should be two.

This does not stop the webhook firing - it stops the Worker acting on it, which looks different in the log: the request arrives but reports a missing field.

Read-only.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/UdfFields/query?search={"filter":[{"op":"gte","field":"id","value":0}]}
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/UdfFields/query?search={"filter":[{"op":"gte","field":"id","value":0}]}' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### Why isn't it firing? 3 - excluded resources — *read-only*

Lists resources whose changes do NOT fire this webhook.

Autotask can exclude a resource to stop a webhook re-triggering on its own writes. If your API user is excluded, a rename made through the API will not fire the webhook while the same rename made in the UI will - which is exactly the symptom of 'nothing happens when I test with Postman'.

Read-only.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/ExcludedResources/query?search={"filter":[{"op":"gte","field":"id","value":0}]}
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}/ExcludedResources/query?search={"filter":[{"op":"gte","field":"id","value":0}]}' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### Update webhook URLs — *writes configuration*

Changes an existing webhook's two URLs without deleting and recreating it, so the trigger field and UDF registrations from requests 4, 6 and 7 are kept.

Set the webhookUrl and deactivationUrl collection variables to the new values first, and make sure webhookId is the webhook you mean to change - 'List webhooks' shows them all.

If the webhook has been deactivated (Autotask switches off webhooks whose endpoint keeps failing), add "IsActive": true to the body to turn it back on.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks
```

**Body** — raw / JSON

```json
{
  "id": "{{webhookId}}",
  "WebhookUrl": "{{webhookUrl}}",
  "DeactivationUrl": "{{deactivationUrl}}"
}
```

**cURL** — paste into Import → Raw text

```bash
curl -X PATCH '{{baseUrl}}/V1.0/CompanyWebhooks' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json' \
  -d '{"id":"{{webhookId}}","WebhookUrl":"{{webhookUrl}}","DeactivationUrl":"{{deactivationUrl}}"}'
```

### Delete webhook {{webhookId}} — *writes configuration*

Deletes the webhook currently in {{webhookId}}. Use this to clean up a duplicate or start over.

Set {{webhookId}} by hand first if you want to delete a different one.

**URL**

```
{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}
```

**cURL** — paste into Import → Raw text

```bash
curl -X DELETE '{{baseUrl}}/V1.0/CompanyWebhooks/{{webhookId}}' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

---

# Test the Cloudflare Worker

`cloudflare-worker-test.postman_collection.json`

Health-checks the Worker and fires simulated webhooks at it. No Autotask involved.

## Variables

**You fill in:**

| Variable | Set it to |
|---|---|
| `workerBaseUrl` | `https://<worker>.workers.dev` — **no trailing slash** |
| `webhookToken` | the `WebhookToken` secret set on the Worker |
| `syncFlagUdfLabel` | defaults to `Sync with aBillity (yes or no)` |
| `abillityIdUdfLabel` | defaults to `aBillity Company ID` |
| `testAutotaskCompanyId` | defaults to `12345` |
| `testAbillityCompanyId` | a real aBILLity company id — request 4 renames it |
| `testNewName` | defaults to `Worker Test - safe to rename back` |

## Headers

Used by every request in this collection except where a request says otherwise:

```
Content-Type: application/json
```

## Requests

### 1. Health check — *read-only*

Proves the Worker is deployed, configured and that your token matches. Involves no Autotask and no aBILLity.

Reports only WHETHER each setting is present, never its value.

Run this before anything else - if it fails, nothing downstream can work.

**URL**

```
{{workerBaseUrl}}/health?code={{webhookToken}}
```

**Headers** (different from the collection default above)

```
(none)
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{workerBaseUrl}}/health?code={{webhookToken}}'
```

### 2. Health check with a wrong token (expect 401) — *read-only*

Confirms the Worker actually rejects a bad token - that the auth check works rather than letting everything through.

A 401 here is the PASS.

**URL**

```
{{workerBaseUrl}}/health?code=deliberately-wrong
```

**Headers** (different from the collection default above)

```
(none)
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{workerBaseUrl}}/health?code=deliberately-wrong'
```

### 3. Simulate a webhook - NOT flagged for sync (safe) — **WRITES LIVE DATA**

Sends a webhook-shaped payload with the sync flag set to No.

Safe: the Worker should skip it, so NOTHING is written to aBILLity. It still exercises routing, the token check, JSON parsing and the flag logic.

Run this before request 4.

Expect 200, and in the Worker log:  
  Request: POST /api/CompanyNameSync  
  ... is not flagged for aBILLity sync ... - skipping

**URL**

```
{{workerBaseUrl}}/api/CompanyNameSync?code={{webhookToken}}
```

**Body** — raw / JSON

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

**cURL** — paste into Import → Raw text

```bash
curl -X POST '{{workerBaseUrl}}/api/CompanyNameSync?code={{webhookToken}}' \
  -H 'Content-Type: application/json' \
  -d '{"EntityType":"Company","Action":"Update","Id":"{{testAutotaskCompanyId}}","Fields":[{"name":"CompanyName","value":"{{testNewName}}"},{"name":"{{syncFlagUdfLabel}}","value":"No"},{"name":"{{abillityIdUdfLabel}}","value":"{{testAbillityCompanyId}}"}]}'
```

### 4. Simulate a webhook - flagged, real sync (WRITES TO aBILLITY) — **WRITES LIVE DATA**

The same payload with the flag set to Yes, so the Worker performs the real aBILLity rename.

> ⚠️ **THIS RENAMES A COMPANY IN aBILLity - LIVE BILLING DATA.**

Set testAbillityCompanyId to a company you are willing to rename, and put the name back afterwards with the aBILLity collection.

Expect 200 and 'Synced company ... ->' in the Worker log.  
A 500 with 'sync failed' means the Worker reached aBILLity and aBILLity refused - the log carries the status and body.

NOTE: this proves the Worker and aBILLity work together. It does NOT prove Autotask sends this payload shape - only a real webhook shows that.

**URL**

```
{{workerBaseUrl}}/api/CompanyNameSync?code={{webhookToken}}
```

**Body** — raw / JSON

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

**cURL** — paste into Import → Raw text

```bash
curl -X POST '{{workerBaseUrl}}/api/CompanyNameSync?code={{webhookToken}}' \
  -H 'Content-Type: application/json' \
  -d '{"EntityType":"Company","Action":"Update","Id":"{{testAutotaskCompanyId}}","Fields":[{"name":"CompanyName","value":"{{testNewName}}"},{"name":"{{syncFlagUdfLabel}}","value":"Yes"},{"name":"{{abillityIdUdfLabel}}","value":"{{testAbillityCompanyId}}"}]}'
```

### 5. Simulate the deactivation callback — **WRITES LIVE DATA**

The endpoint Autotask calls if it ever deactivates the webhook. It only logs.

Writes nothing anywhere. Expect 200 and 'Autotask webhook deactivated: ...' in the log.

**URL**

```
{{workerBaseUrl}}/api/CompanyNameSyncDeactivated?code={{webhookToken}}
```

**Body** — raw / JSON

```json
{
  "reason": "manual test from Postman"
}
```

**cURL** — paste into Import → Raw text

```bash
curl -X POST '{{workerBaseUrl}}/api/CompanyNameSyncDeactivated?code={{webhookToken}}' \
  -H 'Content-Type: application/json' \
  -d '{"reason":"manual test from Postman"}'
```

---

# Rename an Autotask company

`autotask-company-update.postman_collection.json`

Reads and renames a company through the Autotask API. Renaming is what fires the webhook.

## Variables

**You fill in:**

| Variable | Set it to |
|---|---|
| `userName` | the Autotask **API user's** username — usually an email address, not your own login |
| `apiIntegrationCode` | Tracking Identifier from Admin → Extensions & Integrations → Integration Vendor API user |
| `secret` | the API user's generated Password/Secret |
| `companySearch` | part of a company name to search for |
| `newCompanyName` | defaults to `Rename Test - safe to change back` |

**Filled in for you — leave blank:**

| Variable | Captured by |
|---|---|
| `baseUrl` | 0. Get zone information (no credentials sent) |
| `companyId` | 1. Find a company by name |
| `originalCompanyName` | 2. Get company {{companyId}} (read-only) |

## Headers

Used by every request in this collection except where a request says otherwise:

```
ApiIntegrationcode: {{apiIntegrationCode}}
UserName: {{userName}}
Secret: {{secret}}
Content-Type: application/json
```

## Requests

### 0. Get zone information (no credentials sent) — *read-only*

Finds which Autotask server your account lives on and stores it as {{baseUrl}}.

Sends NO credentials - safe to run at will.

**URL**

```
https://webservices2.autotask.net/atservicesrest/V1.0/zoneInformation?user={{userName}}
```

**Headers** (different from the collection default above)

```
Content-Type: application/json
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET 'https://webservices2.autotask.net/atservicesrest/V1.0/zoneInformation?user={{userName}}' \
  -H 'Content-Type: application/json'
```

### 1. Find a company by name — *read-only*

Lists companies whose name contains {{companySearch}}, with their ids.

Read-only. Copy the id you want into {{companyId}} (or if there is exactly one match it is set for you).

**URL**

```
{{baseUrl}}/V1.0/Companies/query?search={"filter":[{"op":"contains","field":"companyName","value":"{{companySearch}}"}]}
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/Companies/query?search={"filter":[{"op":"contains","field":"companyName","value":"{{companySearch}}"}]}' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### 2. Get company {{companyId}} (read-only) — *read-only*

Shows the company's current name and every user-defined field on it.

Read-only. Stores the current name in {{originalCompanyName}} so request 4 can put it back.

**URL**

```
{{baseUrl}}/V1.0/Companies/{{companyId}}
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET '{{baseUrl}}/V1.0/Companies/{{companyId}}' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json'
```

### 3. Update the company name — **WRITES LIVE DATA**

Renames the company.

> ⚠️ **THIS CHANGES LIVE AUTOTASK DATA.**

Run request 2 first so the original name is captured, then request 4 to put it back.

Note the id goes in the BODY, not the URL - that is Autotask's PATCH convention.

**URL**

```
{{baseUrl}}/V1.0/Companies
```

**Body** — raw / JSON

```json
{
  "id": "{{companyId}}",
  "companyName": "{{newCompanyName}}"
}
```

**cURL** — paste into Import → Raw text

```bash
curl -X PATCH '{{baseUrl}}/V1.0/Companies' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json' \
  -d '{"id":"{{companyId}}","companyName":"{{newCompanyName}}"}'
```

### 4. Restore the original name — **WRITES LIVE DATA**

Puts the name back to whatever request 2 captured.

If {{originalCompanyName}} is empty, request 2 did not capture it - set the name by hand instead of running this.

**URL**

```
{{baseUrl}}/V1.0/Companies
```

**Body** — raw / JSON

```json
{
  "id": "{{companyId}}",
  "companyName": "{{originalCompanyName}}"
}
```

**cURL** — paste into Import → Raw text

```bash
curl -X PATCH '{{baseUrl}}/V1.0/Companies' \
  -H 'ApiIntegrationcode: {{apiIntegrationCode}}' \
  -H 'UserName: {{userName}}' \
  -H 'Secret: {{secret}}' \
  -H 'Content-Type: application/json' \
  -d '{"id":"{{companyId}}","companyName":"{{originalCompanyName}}"}'
```

---

# Check and rename in aBILLity

`abillity-test.postman_collection.json`

Talks to aBILLity directly — credentials, company lookup, and the rename the Worker performs.

## Variables

**You fill in:**

| Variable | Set it to |
|---|---|
| `systemInformation` | from your aBILLity administrator. **Not the literal word `SYSTEM`** — that's a placeholder in their docs |
| `abillityUserName` | your aBILLity API username |
| `abillityPassword` | your aBILLity API password |
| `companyId` | the aBILLity company id to look at |
| `testName` | defaults to `Test Rename - safe to ignore` |

**Filled in for you — leave blank:**

| Variable | Captured by |
|---|---|
| `originalName` | 1. Get company — check its name (read-only) |

## Headers

Used by every request in this collection except where a request says otherwise:

```
SystemInformation: {{systemInformation}}
username: {{abillityUserName}}
password: {{abillityPassword}}
Content-Type: application/json
Accept: application/json
```

## Requests

### 0. Check credentials (GET /site) — *read-only*

The endpoint every example in aBILLity's own docs uses. Run it FIRST when something is wrong - it separates 'my credentials/headers are wrong' from 'something is wrong with the company endpoint'.

Read-only.

Note there is no Content-Type header here. This is a GET with no body, and sending Content-Type on a bodyless request upsets some ASP.NET stacks.

200 - auth works. The problem is elsewhere.  
401 - credentials or permissions.  
500 - aBILLity threw an unhandled error. Most often SystemInformation is wrong or missing, since that is what selects which system to connect to - a bad value can fail inside the API rather than come back as a clean 401.

**URL**

```
https://api.abillity.co.uk/api/site
```

**Headers** (different from the collection default above)

```
SystemInformation: {{systemInformation}}
username: {{abillityUserName}}
password: {{abillityPassword}}
Accept: application/json
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET 'https://api.abillity.co.uk/api/site' \
  -H 'SystemInformation: {{systemInformation}}' \
  -H 'username: {{abillityUserName}}' \
  -H 'password: {{abillityPassword}}' \
  -H 'Accept: application/json'
```

### 1. Get company — check its name (read-only) — *read-only*

GET api/company/{id} - the details of one company. Read-only, changes nothing, so run it as often as you like.

Use it on its own to check what aBILLity currently holds for a company, or before requests 2 and 3 so the original name is captured.

LastUpdated is the useful one when testing the sync: after renaming the company in Autotask, this should show a timestamp of a moment ago. If the name changed but LastUpdated is old, you are looking at the wrong company.

401 = bad credentials OR no company permissions (aBILLity uses 401 for both).  
404 = no such company, or no companies in this database.

**URL**

```
https://api.abillity.co.uk/api/company/{{companyId}}
```

**cURL** — paste into Import → Raw text

```bash
curl -X GET 'https://api.abillity.co.uk/api/company/{{companyId}}' \
  -H 'SystemInformation: {{systemInformation}}' \
  -H 'username: {{abillityUserName}}' \
  -H 'password: {{abillityPassword}}' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json'
```

### 2. Rename company (WRITES LIVE DATA) — **WRITES LIVE DATA**

The exact call the Worker makes when an Autotask company is renamed.

> ⚠️ **THIS CHANGES LIVE BILLING DATA.**

Run request 1 first so the original name is captured, then request 3 to put it back.

aBILLity caps the name at 50 characters and the Worker truncates to match - keep {{testName}} under 50 unless you are deliberately testing that.

**URL**

```
https://api.abillity.co.uk/api/company/{{companyId}}
```

**Body** — raw / JSON

```json
{
  "Name": "{{testName}}"
}
```

**cURL** — paste into Import → Raw text

```bash
curl -X PATCH 'https://api.abillity.co.uk/api/company/{{companyId}}' \
  -H 'SystemInformation: {{systemInformation}}' \
  -H 'username: {{abillityUserName}}' \
  -H 'password: {{abillityPassword}}' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{"Name":"{{testName}}"}'
```

### 3. Restore original name — **WRITES LIVE DATA**

Puts the name back to whatever request 1 captured in {{originalName}}.

If {{originalName}} is empty, request 1 did not capture it - set the name by hand in aBILLity instead of running this.

**URL**

```
https://api.abillity.co.uk/api/company/{{companyId}}
```

**Body** — raw / JSON

```json
{
  "Name": "{{originalName}}"
}
```

**cURL** — paste into Import → Raw text

```bash
curl -X PATCH 'https://api.abillity.co.uk/api/company/{{companyId}}' \
  -H 'SystemInformation: {{systemInformation}}' \
  -H 'username: {{abillityUserName}}' \
  -H 'password: {{abillityPassword}}' \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -d '{"Name":"{{originalName}}"}'
```

---

# Common problems

| Symptom | Cause |
|---|---|
| **The webhook never calls the Worker** | Run *Why isn't it firing? 1* — a webhook with no subscribed trigger field fires on nothing. Then check `isActive` with *Get webhook*, and *Why isn't it firing? 3* for an excluded resource. |
| `500` from aBILLity | Usually `SystemInformation`. **`SYSTEM` is a placeholder in aBILLity's docs, not a value.** |
| `401` from aBILLity | Bad credentials *or* a user without company permissions. aBILLity uses 401 for both. |
| `401` from Autotask | Wrong credentials *or* a locked account — indistinguishable. Don't retry repeatedly. |
| `405` from the Worker | The path didn't match. The log's `Request: GET /...` line shows what arrived. |
| HTML instead of JSON | The request never reached the API. The URL is wrong, not the credentials. |
| Autotask `PATCH` seems to do nothing | The id goes in the **body**, not the URL. |

# The webhook isn't firing at all

In order, all read-only:

1. **Utilities → List webhooks.** Does it exist? Is `isActive` true? Is there more than one?
2. **Utilities → Why isn't it firing? 1 — trigger fields.** **The most common cause.** Creating the webhook and registering `CompanyName` as its trigger are separate calls; with nothing subscribed it fires on nothing. Fix by running requests 3 then 4.
3. **Utilities → Why isn't it firing? 3 — excluded resources.** If your API user is excluded, renames made *through the API* don't fire it while UI renames do.
4. **Try renaming in the Autotask UI** rather than through the API. If the UI fires it and the API doesn't, it's step 3.
5. **Utilities → Get webhook.** Do `webhookUrl` and `deactivationUrl` match the deployed Worker, `?code=` included?
6. **Worker → request 1.** Health check: is the Worker live at that URL?

# Diagnosing a sync that fires but does nothing

1. **Worker** → request 3 (simulated webhook, not flagged). Routing and parsing work? Writes nothing.
2. **aBILLity** → request 0 (credentials), then request 1 on the id from the UDF.
3. **Autotask company update** → requests 0–2. Are both UDFs actually set on the company?
4. **Utilities → Why isn't it firing? 2 — UDF fields.** Both UDFs registered on the webhook? Without them the payload arrives missing a field and every company is skipped.
