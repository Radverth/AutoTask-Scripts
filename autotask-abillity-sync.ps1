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
### 1. Resolve your Autotask zone / base URL (only needs doing once)
### ---------------------------------------------------------------------

$AutotaskAuthHeaders = @{
    "ApiIntegrationcode" = $AutotaskApiIntegrationCode
    "UserName"           = $AutotaskUserName
    "Secret"             = $AutotaskSecret
    "Content-Type"       = "application/json"
}

$Version = (Invoke-RestMethod -Uri "https://webservices2.autotask.net/atservicesrest/versioninformation").apiversions | Select-Object -Last 1
$ZoneInfo = Invoke-RestMethod -Uri "https://webservices2.autotask.net/atservicesrest/$Version/zoneInformation?user=$AutotaskUserName"
$AutotaskBaseUri = $ZoneInfo.url.TrimEnd('/')   # e.g. https://webservices14.autotask.net/atservicesrest

Write-Host "Autotask base URI: $AutotaskBaseUri"

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

foreach ($Label in @($AbillityIdUdfLabel, $SyncFlagUdfLabel)) {

    $UdfMatch = $UdfPicklist | Where-Object { $_.label -eq $Label }

    if (-not $UdfMatch) {
        Write-Error "No Company UDF found with the label '$Label' - check the spelling in Autotask (Admin > Features & Settings > Companies & Contacts > Company User-Defined Fields)."
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
