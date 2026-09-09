### =========================================================================
### Autotask -> aBILLity Company Name Sync
### PowerShell: setup calls (run once) + the ongoing sync calls
### =========================================================================

### ---------------------------------------------------------------------
### 0. CONFIG — fill these in
### ---------------------------------------------------------------------

# --- Autotask ---
$AutotaskApiIntegrationCode = "<YOUR_API_INTEGRATION_CODE>"
$AutotaskUserName           = "<api-user@yourdomain.com>"
$AutotaskSecret             = "<YOUR_API_USER_SECRET>"

# --- aBILLity ---
$AbillitySystemInformation  = "<YOUR_SYSTEM_INFORMATION>"
$AbillityUserName           = "<YOUR_ABILLITY_USERNAME>"
$AbillityPassword           = "<YOUR_ABILLITY_PASSWORD>"

# --- Your webhook receiver ---
$WebhookUrl         = "https://yourhost.example.com/webhooks/autotask-company"
$DeactivationUrl    = "https://yourhost.example.com/webhooks/autotask-company/deactivated"
$NotificationEmail  = "you@yourdomain.com"

# --- The exact labels of your two Company UDFs ---
# These must match Autotask character for character, capitals included.
$AbillityIdUdfLabel = "aBillity Company ID"
$SyncFlagUdfLabel   = "Sync with aBillity (yes or no)"

# What the sync-flag UDF can say for "yes". Anything else - including blank -
# means don't sync, so a company is never synced by accident.
$AffirmativeValues = @("yes", "y", "true", "1", "on", "checked")

### ---------------------------------------------------------------------
### 0b. Stop at the first problem, and check the config is actually filled in
###
### Without this the script used to carry on after a failure, so one broken
### call turned into a screenful of misleading follow-on errors.
### ---------------------------------------------------------------------

$ErrorActionPreference = "Stop"

$Config = [ordered]@{
    AutotaskApiIntegrationCode = $AutotaskApiIntegrationCode
    AutotaskUserName           = $AutotaskUserName
    AutotaskSecret             = $AutotaskSecret
    AbillitySystemInformation  = $AbillitySystemInformation
    AbillityUserName           = $AbillityUserName
    AbillityPassword           = $AbillityPassword
    WebhookUrl                 = $WebhookUrl
    DeactivationUrl            = $DeactivationUrl
    NotificationEmail          = $NotificationEmail
    AbillityIdUdfLabel         = $AbillityIdUdfLabel
    SyncFlagUdfLabel           = $SyncFlagUdfLabel
}

$Unfilled = $Config.GetEnumerator() | Where-Object {
    [string]::IsNullOrWhiteSpace($_.Value) -or
    $_.Value -match '^<.*>$' -or
    $_.Value -like "*yourhost.example.com*" -or
    $_.Value -like "*yourdomain.com*"
} | ForEach-Object { $_.Key }

if ($Unfilled) {
    throw "Fill in the CONFIG block at the top of this script first. Still on placeholder values: $($Unfilled -join ', ')"
}

### ---------------------------------------------------------------------
### 1. Resolve your Autotask zone / base URL (only needs doing once)
###
### Autotask splits customers across numbered zones, so before anything else
### we ask it which server your account lives on.
### ---------------------------------------------------------------------

$AutotaskAuthHeaders = @{
    "ApiIntegrationcode" = $AutotaskApiIntegrationCode
    "UserName"           = $AutotaskUserName
    "Secret"             = $AutotaskSecret
    "Content-Type"       = "application/json"
}

$AutotaskHosts = @("webservices2.autotask.net", "webservices.autotask.net")

function Get-AutotaskBaseUri {
    param([Parameter(Mandatory = $true)][string] $UserName)

    # The username goes in a query string, so it has to be encoded - an
    # unencoded '@' or space is enough to turn this into a 404.
    $EncodedUser = [uri]::EscapeDataString($UserName)

    # Ask which API versions exist. If that endpoint is unavailable or answers
    # in an unexpected shape we fall back to the known-good V1.0, rather than
    # interpolating an empty version and requesting '/atservicesrest//zone...'
    # - which is exactly what produces a bare IIS 404.
    $DiscoveredVersion = $null
    foreach ($ApiHost in $AutotaskHosts) {
        try {
            $Info = Invoke-RestMethod -Uri "https://$ApiHost/atservicesrest/versioninformation" -Method Get -TimeoutSec 30
            $DiscoveredVersion = @($Info.apiVersions | Where-Object { $_ }) | Select-Object -Last 1
            if ($DiscoveredVersion) { break }
        } catch {
            # Try the next host.
        }
    }

    if ($DiscoveredVersion) {
        Write-Host "Autotask reports API version $DiscoveredVersion"
    } else {
        Write-Host "Could not read the API version list - falling back to V1.0"
    }

    $Versions = @($DiscoveredVersion, "V1.0") | Where-Object { $_ } | Select-Object -Unique

    $Candidates = @()
    foreach ($ApiHost in $AutotaskHosts) {
        foreach ($ApiVersion in $Versions) {
            $Candidates += "https://$ApiHost/atservicesrest/$ApiVersion/zoneInformation?user=$EncodedUser"
        }
    }
    $Candidates = $Candidates | Select-Object -Unique

    foreach ($Uri in $Candidates) {
        Write-Host "Looking up your zone: $Uri"
        try {
            $Zone = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 30
        } catch {
            Write-Host "  -> $($_.Exception.Message)"
            continue
        }
        if ($Zone.url) { return ([string]$Zone.url).TrimEnd('/') }
        Write-Host "  -> answered, but with no zone URL in the response"
    }

    throw @"
Could not work out your Autotask zone. Tried:
  $($Candidates -join "`n  ")

Check each of these:
  * `$AutotaskUserName must be the API user's username exactly as Autotask
    shows it (Admin > Resources/Users). It is usually an email address, and it
    is NOT your own Autotask login.
  * That user's Security Level must be 'API User (system)'.
  * `$AutotaskApiIntegrationCode must be the tracking identifier from
    Admin > Extensions & Integrations > Other Extensions & Tools > Integration
    Vendor API user.
  * This machine must be able to reach *.autotask.net (proxy or firewall?).
"@
}

$AutotaskBaseUri = Get-AutotaskBaseUri -UserName $AutotaskUserName
Write-Host "Autotask base URI: $AutotaskBaseUri"

### ---------------------------------------------------------------------
### 1b. Prove the credentials work before we start creating things
###
### Two probes, because they fail for different reasons: Companies tests the
### credentials themselves, CompanyWebhooks tests whether this API user is
### allowed to manage webhooks. A 401 on the first is a bad credential; a 403
### on the second is a good credential without enough permission.
### ---------------------------------------------------------------------

function Get-AutotaskErrorDetail {
    param($ErrorRecord)

    $StatusCode = $null
    try { $StatusCode = [int]$ErrorRecord.Exception.Response.StatusCode } catch { }

    # Autotask puts the useful part in the response body, which PowerShell
    # hides in different places depending on version.
    $Body = $null
    if ($ErrorRecord.ErrorDetails -and $ErrorRecord.ErrorDetails.Message) {
        $Body = $ErrorRecord.ErrorDetails.Message
    } else {
        try { $Body = $ErrorRecord.Exception.Response.Content.ReadAsStringAsync().Result } catch { }
    }

    $Parts = @()
    if ($StatusCode) { $Parts += "HTTP $StatusCode" }
    if ($ErrorRecord.Exception.Message) { $Parts += $ErrorRecord.Exception.Message }
    if ($Body) { $Parts += "Response body: $Body" }

    return [pscustomobject]@{
        StatusCode = $StatusCode
        Detail     = ($Parts -join " | ")
    }
}

$CredentialAdvice = @"
Check all three, in the API user's own record in Autotask
(Admin > Resources/Users > find the API user > Edit):

  * AutotaskUserName is the API user's Username exactly as Autotask shows it.
    It is usually an email address, and it is NOT your own Autotask login.
  * AutotaskSecret is that API user's generated Password/Secret - not a
    person's password, and not the integration code.
  * AutotaskApiIntegrationCode is the Tracking Identifier from
    Admin > Extensions & Integrations > Other Extensions & Tools >
    Integration Vendor API user.
  * The API user's Security Level must be 'API User (system)'.

If you have just created or reset the API user, give Autotask a minute and
try again - new credentials are not always live immediately.
"@

$Probes = [ordered]@{
    "Companies (are the credentials valid?)"       = "$AutotaskBaseUri/V1.0/Companies/entityInformation"
    "CompanyWebhooks (may this user use webhooks?)" = "$AutotaskBaseUri/V1.0/CompanyWebhooks/entityInformation"
}

foreach ($Probe in $Probes.GetEnumerator()) {

    Write-Host "Checking $($Probe.Key)"

    $Failure = $null
    try {
        $null = Invoke-RestMethod -Uri $Probe.Value -Method Get -Headers $AutotaskAuthHeaders -TimeoutSec 30
    } catch {
        $Failure = Get-AutotaskErrorDetail $_
    }

    if (-not $Failure) {
        Write-Host "  -> OK"
        continue
    }

    Write-Host "  -> FAILED: $($Failure.Detail)"

    switch ($Failure.StatusCode) {

        401 {
            throw @"
Autotask rejected the credentials (HTTP 401 Unauthorized).

$($Failure.Detail)

$CredentialAdvice
"@
        }

        403 {
            throw @"
Autotask accepted the credentials but refused the request (HTTP 403 Forbidden)
on: $($Probe.Value)

$($Failure.Detail)

The credentials are valid, so this is a permissions problem rather than a
password problem. The API user's Security Level needs access to the entity
above - for CompanyWebhooks that means webhook permissions, which are not
granted to every API user by default. Check the Security Level under
Admin > Resources/Users, or ask whoever administers your Autotask instance.
"@
        }

        default {
            throw @"
Autotask would not answer a test request on: $($Probe.Value)

$($Failure.Detail)

$CredentialAdvice
"@
        }
    }
}

Write-Host "Autotask credentials accepted."

### ---------------------------------------------------------------------
### 2. Create the webhook
### ---------------------------------------------------------------------

$WebhookBody = @{
    IsActive                           = $true
    DeactivationUrl                    = $DeactivationUrl
    IsSubscribedToUpdateEvents         = $true
    Name                               = "Company Name -> aBILLity Sync"
    SecretKey                          = [guid]::NewGuid().ToString()   # store this somewhere safe
    SendThresholdExceededNotification  = $true
    WebhookUrl                         = $WebhookUrl
    NotificationEmailAddress           = $NotificationEmail
} | ConvertTo-Json

$WebhookResult = Invoke-RestMethod -Uri "$AutotaskBaseUri/v1.0/CompanyWebhooks" `
    -Method Post -Headers $AutotaskAuthHeaders -Body $WebhookBody

$WebhookId = $WebhookResult.itemId
if (-not $WebhookId) { throw "Autotask accepted the webhook but returned no ID. Response: $($WebhookResult | ConvertTo-Json -Depth 5)" }
Write-Host "Created webhook, WebhookID = $WebhookId"

### ---------------------------------------------------------------------
### 3. Find the CompanyName fieldID
### ---------------------------------------------------------------------

$CompanyFields = Invoke-RestMethod -Uri "$AutotaskBaseUri/v1.0/CompanyWebhookFields/entityInformation/fields" `
    -Method Get -Headers $AutotaskAuthHeaders

$CompanyNameField = $CompanyFields.fields |
    Where-Object { $_.name -eq "fieldID" } |
    Select-Object -ExpandProperty picklistValues |
    Where-Object { $_.label -eq "CompanyName" }

if (-not $CompanyNameField) { throw "Autotask did not report a 'CompanyName' webhook field. Cannot continue." }

$CompanyNameFieldId = [int]$CompanyNameField.value
Write-Host "CompanyName fieldID = $CompanyNameFieldId"

### ---------------------------------------------------------------------
### 4. Register CompanyName as a trigger field on the webhook
### ---------------------------------------------------------------------

$TriggerFieldBody = @{
    FieldID              = $CompanyNameFieldId
    IsSubscribedField    = $true
    IsDisplayAlwaysField = $true
    WebhookID            = $WebhookId
} | ConvertTo-Json

Invoke-RestMethod -Uri "$AutotaskBaseUri/v1.0/CompanyWebhooks/$WebhookId/Fields" `
    -Method Post -Headers $AutotaskAuthHeaders -Body $TriggerFieldBody

### ---------------------------------------------------------------------
### 5. Find both UDFs' udfFieldIDs
### ---------------------------------------------------------------------

$UdfFields = Invoke-RestMethod -Uri "$AutotaskBaseUri/v1.0/CompanyWebhookUdfFields/entityInformation/fields" `
    -Method Get -Headers $AutotaskAuthHeaders

$UdfPicklist = $UdfFields.fields |
    Where-Object { $_.name -eq "udfFieldID" } |
    Select-Object -ExpandProperty picklistValues

### ---------------------------------------------------------------------
### 6. Register both UDFs as display-always fields (not triggers)
###
### The name change is the only thing that fires the webhook; these two just
### ride along in the payload so the receiver can read them.
### ---------------------------------------------------------------------

$MissingLabels = @()

foreach ($Label in @($AbillityIdUdfLabel, $SyncFlagUdfLabel)) {

    $UdfMatch = $UdfPicklist | Where-Object { $_.label -eq $Label }

    if (-not $UdfMatch) {
        $MissingLabels += $Label
        continue
    }

    $UdfFieldId = [int]$UdfMatch.value
    Write-Host "UDF '$Label' udfFieldID = $UdfFieldId"

    $UdfTriggerBody = @{
        UdfFieldID           = $UdfFieldId
        IsSubscribedField    = $false
        IsDisplayAlwaysField = $true
        WebhookID            = $WebhookId
    } | ConvertTo-Json

    Invoke-RestMethod -Uri "$AutotaskBaseUri/v1.0/CompanyWebhooks/$WebhookId/UdfFields" `
        -Method Post -Headers $AutotaskAuthHeaders -Body $UdfTriggerBody
}

if ($MissingLabels) {
    throw @"
These UDF labels do not exist on Company in Autotask:
  $($MissingLabels -join "`n  ")

The Company UDFs Autotask actually reports are:
  $((@($UdfPicklist.label) | Sort-Object) -join "`n  ")

Copy the labels from that list into the CONFIG block exactly - capitals and
spacing included. Webhook $WebhookId has been created; either fix the labels
and re-run step 6, or delete the webhook in Autotask and run this again.
"@
}

Write-Host "Setup complete. Check Admin > Extensions & Integrations > Other Extensions & Tools > Webhooks in Autotask to confirm status."


### =========================================================================
### 7. RECEIVER-SIDE LOGIC (run this against each incoming webhook payload)
### =========================================================================
### Wire this into whatever's hosting your endpoint (Azure Function, IIS,
### an n8n Execute Command / PowerShell node, etc). $Payload below is the
### deserialized JSON body Autotask POSTs to your WebhookUrl.

function Sync-CompanyNameToAbillity {
    param(
        [Parameter(Mandatory = $true)] $Payload
    )

    if ($Payload.EntityType -ne "Company" -or $Payload.Action -ne "Update") { return }

    $FieldsMap = @{}
    foreach ($f in $Payload.Fields) { $FieldsMap[$f.name] = $f.value }

    $NewName    = $FieldsMap["CompanyName"]
    $SyncFlag   = $FieldsMap[$SyncFlagUdfLabel]
    $AbillityId = $FieldsMap[$AbillityIdUdfLabel]

    if (-not $NewName) { return }                     # this update didn't touch the name

    if ($AffirmativeValues -notcontains ("$SyncFlag").Trim().ToLower()) {
        Write-Host "Autotask company $($Payload.Id) is not flagged for aBILLity sync ('$SyncFlagUdfLabel' = '$SyncFlag') - skipping"
        return
    }

    if (-not $AbillityId) {
        Write-Warning "Autotask company $($Payload.Id) is flagged for sync but has no '$AbillityIdUdfLabel' - skipping"
        return
    }

    # aBILLity caps Name at 50 characters
    if ($NewName.Length -gt 50) { $NewName = $NewName.Substring(0, 50) }

    $AbillityHeaders = @{
        "SystemInformation" = $AbillitySystemInformation
        "username"           = $AbillityUserName
        "password"           = $AbillityPassword
        "Content-Type"       = "application/json"
        "Accept"             = "application/json"
    }

    $PatchBody = @{ Name = $NewName } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri "https://api.abillity.co.uk/api/company/$AbillityId" `
            -Method Patch -Headers $AbillityHeaders -Body $PatchBody
        Write-Host "Synced company $AbillityId -> '$NewName'"
    } catch {
        Write-Error "aBILLity PATCH failed for company $AbillityId : $($_.Exception.Message)"
    }
}

# Example of calling it once you've deserialized the incoming POST body:
# $Payload = $Request.Body | ConvertFrom-Json
# Sync-CompanyNameToAbillity -Payload $Payload
