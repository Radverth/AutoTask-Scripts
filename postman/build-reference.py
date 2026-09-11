#!/usr/bin/env python3
"""
Regenerates postman/README.md from the collection files.

The reference is generated so it cannot drift from what you actually import.
After changing any collection, run:

    python3 postman/build-reference.py

from the repository root.
"""

import json
import io
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))

COLLECTIONS = [
    ("autotask-abillity-sync.postman_collection.json",
     "Set up the Autotask webhook",
     "One-time setup. Registers the webhook that fires when a company name changes, and tells "
     "Autotask to include your two UDFs in the payload. Its Utilities folder is also where you "
     "diagnose a webhook that isn't firing.",
     "Run once when first setting the sync up, or after moving the Worker to a new URL."),
    ("cloudflare-worker-test.postman_collection.json",
     "Test the Cloudflare Worker",
     "Health-checks the Worker and fires simulated webhooks at it. No Autotask involved.",
     "First stop when a sync doesn't happen."),
    ("autotask-company-update.postman_collection.json",
     "Rename an Autotask company",
     "Reads and renames a company through the Autotask API. Renaming is what fires the webhook.",
     "End-to-end testing, without clicking through the Autotask UI."),
    ("abillity-test.postman_collection.json",
     "Check and rename in aBILLity",
     "Talks to aBILLity directly — credentials, company lookup, and the rename the Worker performs.",
     "Checking what aBILLity holds, and isolating whether a failure is aBILLity's side."),
]

VARIABLE_HELP = {
    "userName": "the Autotask **API user's** username — usually an email address, not your own login",
    "apiIntegrationCode": "Tracking Identifier from Admin → Extensions & Integrations → Integration Vendor API user",
    "secret": "the API user's generated Password/Secret",
    "webhookUrl": "`https://<worker>.workers.dev/api/CompanyNameSync?code=<WebhookToken>`",
    "deactivationUrl": "`https://<worker>.workers.dev/api/CompanyNameSyncDeactivated?code=<WebhookToken>`",
    "notificationEmail": "where Autotask emails if the webhook starts failing",
    "companySearch": "part of a company name to search for",
    "ownerResourceId": "the webhook's `ownerResourceID` — from *List webhooks*",
    "workerBaseUrl": "`https://<worker>.workers.dev` — **no trailing slash**",
    "webhookToken": "the `WebhookToken` secret set on the Worker",
    "testAbillityCompanyId": "a real aBILLity company id — request 4 renames it",
    "systemInformation": "from your aBILLity administrator. **Not the literal word `SYSTEM`** — that's a placeholder in their docs",
    "abillityUserName": "your aBILLity API username",
    "abillityPassword": "your aBILLity API password",
    "companyId": "the aBILLity company id to look at",
}

# Writes that change configuration rather than customer data.
CONFIG_WRITES = {
    "2. Create the webhook",
    "4. Register CompanyName as the trigger field",
    "6. Register UDF: {{abillityIdUdfLabel}}",
    "7. Register UDF: {{syncFlagUdfLabel}}",
    "Update webhook URLs",
    "Delete webhook {{webhookId}}",
}

WRITE_METHODS = {"POST", "PATCH", "PUT", "DELETE"}


def captured_by(collection):
    """Which request sets each collection variable, read from the test scripts."""
    found = {}

    def walk(items):
        for item in items:
            if "item" in item:
                walk(item["item"])
                continue
            for event in item.get("event", []):
                for line in event["script"]["exec"]:
                    for match in re.finditer(
                            r"collectionVariables\.set\(['\"]([A-Za-z0-9_]+)['\"]", line):
                        found.setdefault(match.group(1), item["name"])

    walk(collection["item"])
    return found


def flatten(collection):
    """Every request, paired with the folder it sits in."""
    out = []

    def walk(items, folder=None):
        for item in items:
            if "item" in item:
                walk(item["item"], item["name"])
            else:
                out.append((folder, item))

    walk(collection["item"])
    return out


def as_curl(request):
    lines = [f"curl -X {request['method']} '{request['url']['raw']}'"]
    for header in request.get("header", []):
        lines.append(f"  -H '{header['key']}: {header['value']}'")
    if "body" in request:
        compact = json.dumps(json.loads(request["body"]["raw"]), separators=(",", ":"))
        lines.append(f"  -d '{compact}'")
    return " \\\n".join(lines)


def paragraphs(text):
    if not text:
        return []
    out = []
    for para in text.split("\n\n"):
        para = para.strip()
        if not para:
            continue
        if para.startswith("***") and para.endswith("***"):
            out.append("> ⚠️ **" + para.strip("* ") + "**")
        else:
            out.append(para.replace("\n", "  \n"))
        out.append("")
    return out


def build():
    lines = []
    add = lines.append

    add("<!-- Generated by postman/build-reference.py - do not edit by hand. -->")
    add("")
    add("# Postman collections")
    add("")
    add("Four collections, each standalone. **Import → File.**")
    add("")
    add("Every request below is laid out to copy straight out: the URL, the headers, the body, "
        "and a cURL you can paste into Postman's import box to build the request without typing "
        "anything.")
    add("")
    add("> **The aBILLity API host differs between instances.** `abillityApiBase` defaults to "
        "`https://api-billing.abillity.co.uk/api`. Check the `/GettingStarted` page on your own "
        "aBILLity API host — a wrong host gives unexplained 500s, not a clean error.")
    add("")
    add("## Which one do I want?")
    add("")
    add("| Collection | What it's for | When |")
    add("|---|---|---|")
    for filename, title, what, when in COLLECTIONS:
        add(f"| [`{filename}`](./{filename}) | **{title}.** {what} | {when} |")
    add("")
    add("## Building a request by pasting")
    add("")
    add("Postman turns a cURL command into a request for you:")
    add("")
    add("1. **Import → Raw text**")
    add("2. Paste the `curl ...` block from any request below")
    add("3. **Continue → Import**")
    add("")
    add("The `{{variables}}` come through intact, so the new request picks up whatever you've set "
        "on the Variables tab.")
    add("")
    add("## Before you start")
    add("")
    add("1. **Open the console** — **View → Show Postman Console.** Most requests log what they "
        "found or captured.")
    add("2. **Authorization tab must be \"No Auth\".** Both APIs authenticate with plain headers; "
        "anything else adds a competing header.")
    add("3. **Fill in variables on the Variables tab, then Save.**")
    add("4. **Leave the captured variables blank** — earlier requests fill them in.")
    add("")
    add("> Requests that change live data are marked **WRITES LIVE DATA**. Read-only ones can be "
        "run freely.")
    add("")

    for filename, title, what, _when in COLLECTIONS:
        collection = json.load(io.open(os.path.join(HERE, filename), encoding="utf-8"))
        captured = captured_by(collection)
        requests = flatten(collection)

        add("---")
        add("")
        add(f"# {title}")
        add("")
        add(f"`{filename}`")
        add("")
        add(what)
        add("")
        add("## Variables")
        add("")
        add("**You fill in:**")
        add("")
        add("| Variable | Set it to |")
        add("|---|---|")
        for variable in collection["variable"]:
            if variable["key"] in captured:
                continue
            if variable["value"]:
                add(f"| `{variable['key']}` | defaults to `{variable['value']}` |")
            else:
                add(f"| `{variable['key']}` | "
                    f"{VARIABLE_HELP.get(variable['key'], '*(see the requests below)*')} |")
        add("")
        if captured:
            add("**Filled in for you — leave blank:**")
            add("")
            add("| Variable | Captured by |")
            add("|---|---|")
            for key, by in captured.items():
                add(f"| `{key}` | {by} |")
            add("")

        header_sets = {tuple((h["key"], h["value"]) for h in item["request"].get("header", []))
                       for _folder, item in requests}
        common = max(header_sets, key=len) if header_sets else ()
        if common:
            add("## Headers")
            add("")
            add("Used by every request in this collection except where a request says otherwise:")
            add("")
            add("```")
            for key, value in common:
                add(f"{key}: {value}")
            add("```")
            add("")

        add("## Requests")
        add("")

        current_folder = None
        for folder, item in requests:
            if folder != current_folder:
                if folder:
                    add(f"## {folder}")
                    add("")
                current_folder = folder

            request = item["request"]
            method = request["method"]
            if method in WRITE_METHODS:
                tag = (" — *writes configuration*" if item["name"] in CONFIG_WRITES
                       else " — **WRITES LIVE DATA**")
            else:
                tag = " — *read-only*"

            add(f"### {item['name']}{tag}")
            add("")
            for line in paragraphs(request.get("description")):
                add(line)

            add("**URL**")
            add("")
            add("```")
            add(request["url"]["raw"])
            add("```")
            add("")

            headers = tuple((h["key"], h["value"]) for h in request.get("header", []))
            if headers != common:
                add("**Headers** (different from the collection default above)")
                add("")
                add("```")
                if headers:
                    for key, value in headers:
                        add(f"{key}: {value}")
                else:
                    add("(none)")
                add("```")
                add("")

            if "body" in request:
                add("**Body** — raw / JSON")
                add("")
                add("```json")
                add(request["body"]["raw"])
                add("```")
                add("")

            add("**cURL** — paste into Import → Raw text")
            add("")
            add("```bash")
            add(as_curl(request))
            add("```")
            add("")

    add("---")
    add("")
    add("# Common problems")
    add("")
    add("| Symptom | Cause |")
    add("|---|---|")
    add("| `500` from aBILLity | **Check the host first** — it differs between instances "
        "(`api-billing.abillity.co.uk`, not `api.abillity.co.uk`). Then `SystemInformation`, "
        "where **`SYSTEM` is a placeholder, not a value**. |")
    add("| **The webhook never calls the Worker** | Work through *Why isn't it firing? 1–4* under "
        "Utilities. |")
    add("| `401` from aBILLity | Bad credentials *or* a user without company permissions. "
        "aBILLity uses 401 for both. |")
    add("| `401` from Autotask | Wrong credentials *or* a locked account — indistinguishable. "
        "Don't retry repeatedly; each attempt counts toward a lockout. |")
    add("| `405` from the Worker | The path didn't match. The log's `Request: GET /...` line shows "
        "what actually arrived. |")
    add("| HTML instead of JSON | The request never reached the API. The URL is wrong, not the "
        "credentials. |")
    add("| Autotask `PATCH` seems to do nothing | The id goes in the **body**, not the URL. |")
    add("")
    add("# The webhook isn't firing at all")
    add("")
    add("All read-only. Prove the receiving end first, then work back into Autotask:")
    add("")
    add("1. **POST to the Worker by hand** (Worker collection, request 3, or a curl). A `200 ok` "
        "means the URL, token and method handling are all fine.")
    add("2. **Find that request in the Worker's log.** If it's there, the log works — so silence "
        "during a rename is real evidence. If it isn't, your log view is the problem: turn on "
        "**Settings → Observability → Workers Logs**, because a live tail shows nothing "
        "retrospectively.")
    add("3. **Utilities → List webhooks.** Exists? `isActive` true? Only one?")
    add("4. **Utilities → Why isn't it firing? 1 — trigger fields.** No subscribed field means it "
        "fires on nothing.")
    add("5. **Utilities → Why isn't it firing? 3 — excluded resources.** A listed resource's "
        "changes never fire it — so your own renames would be silent while a colleague's work.")
    add("6. **Utilities → Why isn't it firing? 4 — the owner resource.** A webhook owned by an "
        "inactive or locked resource can stop dispatching while still reporting `isActive: true`.")
    add("")
    add("If all six are clean, the configuration is exhaustively verified and the fault is in "
        "Autotask's dispatch — raise it with Autotask support, quoting the webhook id, that a "
        "manual POST to the registered URL returns 200 and appears in the endpoint's logs, and "
        "that renames produce no delivery attempt at all.")
    add("")
    add("# It fires but nothing reaches aBILLity")
    add("")
    add("1. **Worker → request 4** (simulated webhook, flagged). Makes the Worker call aBILLity "
        "directly; the log carries the exact status and body aBILLity returned.")
    add("2. **aBILLity → request 0.** Credentials and host good?")
    add("3. **Check `AbillityApiBase`** on the Worker matches the host that worked in step 2.")
    add("")

    io.open(os.path.join(HERE, "README.md"), "w", encoding="utf-8").write("\n".join(lines))
    return len("\n".join(lines))


if __name__ == "__main__":
    print(f"postman/README.md regenerated, {build()} bytes")
