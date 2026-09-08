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

# --- The exact label of your Company UDF that stores the aBILLity Company ID ---
$UdfLabel = "<YOUR_UDF_LABEL>"

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
### 5. Find the aBILLity-ID UDF's udfFieldID
### ---------------------------------------------------------------------

$UdfFields = Invoke-RestMethod -Uri "$AutotaskBaseUri/v1.0/CompanyWebhookUdfFields/entityInformation/fields" `
    -Method Get -Headers $AutotaskAuthHeaders

$AbillityUdfField = $UdfFields.fields |
    Where-Object { $_.name -eq "udfFieldID" } |
    Select-Object -ExpandProperty picklistValues |
    Where-Object { $_.label -eq $UdfLabel }

$AbillityUdfFieldId = [int]$AbillityUdfField.value
Write-Host "aBILLity-ID UDF udfFieldID = $AbillityUdfFieldId"

### ---------------------------------------------------------------------
### 6. Register the UDF as a display-always field (not a trigger)
### ---------------------------------------------------------------------

$UdfTriggerBody = @{
    UdfFieldID           = $AbillityUdfFieldId
    IsSubscribedField    = $false
    IsDisplayAlwaysField = $true
    WebhookID            = $WebhookId
} | ConvertTo-Json

Invoke-RestMethod -Uri "$AutotaskBaseUri/v1.0/CompanyWebhooks/$WebhookId/UdfFields" `
    -Method Post -Headers $AutotaskAuthHeaders -Body $UdfTriggerBody

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
    $AbillityId = $FieldsMap[$UdfLabel]

    if (-not $NewName) { return }                     # this update didn't touch the name
    if (-not $AbillityId) {
        Write-Warning "Autotask company $($Payload.Id) has no linked aBILLity ID — skipping"
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
