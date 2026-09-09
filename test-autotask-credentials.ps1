<#
    Autotask credential tester
    ==========================

    Diagnoses Autotask API access WITHOUT running the full setup script, and
    without spending failed login attempts you did not intend to spend.

    Step 1 (zone lookup) sends NO credentials, so it can never lock anything.
    Run that on its own first:

        .\test-autotask-credentials.ps1 -UserName "api-user@yourdomain.com" -ZoneOnly

    Step 2 makes exactly ONE authenticated request, and asks before it does:

        .\test-autotask-credentials.ps1 -UserName "api-user@yourdomain.com" `
            -ApiIntegrationCode "..." -Secret "..."

    IMPORTANT: if the account is currently locked, step 2 will fail whatever
    you type, and may extend the lockout. Get it unlocked first.
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $UserName,

    [string] $ApiIntegrationCode,

    [string] $Secret,

    # Only do the safe, credential-free zone lookup and stop.
    [switch] $ZoneOnly
)

$ErrorActionPreference = "Stop"

$AutotaskHosts = @("webservices2.autotask.net", "webservices.autotask.net")

### ---------------------------------------------------------------------
### Step 1 - find your zone. No credentials are sent, so this is safe to
### run as often as you like.
### ---------------------------------------------------------------------

Write-Host ""
Write-Host "STEP 1: looking up your Autotask zone (no credentials sent)" -ForegroundColor Cyan

$EncodedUser = [uri]::EscapeDataString($UserName)
$BaseUri = $null

foreach ($ApiHost in $AutotaskHosts) {

    $Uri = "https://$ApiHost/atservicesrest/V1.0/zoneInformation?user=$EncodedUser"
    Write-Host "  trying $Uri"

    try {
        $Zone = Invoke-RestMethod -Uri $Uri -Method Get -TimeoutSec 30
    } catch {
        Write-Host "    -> $($_.Exception.Message)" -ForegroundColor DarkGray
        continue
    }

    if ($Zone.url) {
        $BaseUri = ([string]$Zone.url).TrimEnd('/')
        break
    }

    Write-Host "    -> answered, but with no zone URL" -ForegroundColor DarkGray
}

if (-not $BaseUri) {
    Write-Host ""
    Write-Host "Could not find a zone for '$UserName'." -ForegroundColor Red
    Write-Host "That usually means the username is not an Autotask API user, or is misspelled."
    Write-Host "It is the API user's Username from Admin > Resources/Users - not your own login."
    return
}

Write-Host ""
Write-Host "  Zone found: $BaseUri" -ForegroundColor Green
Write-Host "  Note it already ends in /ATServicesRest - do not add or remove that."
Write-Host "  Full URL for an API call would be:"
Write-Host "    $BaseUri/V1.0/Companies/entityInformation"

if ($ZoneOnly) {
    Write-Host ""
    Write-Host "-ZoneOnly was set, stopping here. No credentials were sent." -ForegroundColor Cyan
    return
}

if (-not $ApiIntegrationCode -or -not $Secret) {
    Write-Host ""
    Write-Host "No -ApiIntegrationCode / -Secret given, so stopping here." -ForegroundColor Cyan
    Write-Host "Nothing was authenticated, so no login attempt was used."
    return
}

### ---------------------------------------------------------------------
### Step 2 - one authenticated request, with an explicit warning first.
### ---------------------------------------------------------------------

Write-Host ""
Write-Host "STEP 2: test the credentials" -ForegroundColor Cyan
Write-Host ""
Write-Host "  This sends ONE authenticated request." -ForegroundColor Yellow
Write-Host "  A wrong credential counts as a failed login attempt against" -ForegroundColor Yellow
Write-Host "  '$UserName', and enough of those will lock the account." -ForegroundColor Yellow
Write-Host "  If it is already locked, this will fail regardless." -ForegroundColor Yellow
Write-Host ""

$Answer = Read-Host "  Type YES to send it"
if ($Answer -ne "YES") {
    Write-Host "  Cancelled. No login attempt was used." -ForegroundColor Cyan
    return
}

$Headers = @{
    "ApiIntegrationcode" = $ApiIntegrationCode
    "UserName"           = $UserName
    "Secret"             = $Secret
    "Content-Type"       = "application/json"
}

$TestUri = "$BaseUri/V1.0/Companies/entityInformation"
Write-Host ""
Write-Host "  GET $TestUri"

# -SkipHttpErrorCheck (PowerShell 7+) lets us read the real response instead
# of only an exception message. Fall back for Windows PowerShell 5.1.
$SupportsSkip = (Get-Command Invoke-WebRequest).Parameters.ContainsKey("SkipHttpErrorCheck")

try {
    if ($SupportsSkip) {
        $Response = Invoke-WebRequest -Uri $TestUri -Method Get -Headers $Headers `
            -TimeoutSec 30 -SkipHttpErrorCheck
    } else {
        $Response = Invoke-WebRequest -Uri $TestUri -Method Get -Headers $Headers -TimeoutSec 30
    }
    $StatusCode  = [int]$Response.StatusCode
    $ContentType = [string]$Response.Headers["Content-Type"]
    $Body        = [string]$Response.Content
} catch {
    $StatusCode = $null
    try { $StatusCode = [int]$_.Exception.Response.StatusCode } catch { }
    $ContentType = $null
    try { $ContentType = [string]$_.Exception.Response.Content.Headers.ContentType } catch { }
    $Body = $_.ErrorDetails.Message
    if (-not $Body) { $Body = $_.Exception.Message }
}

Write-Host ""
Write-Host "  HTTP status : $StatusCode"
Write-Host "  Content-Type: $ContentType"
Write-Host "  Body (first 500 chars):"
Write-Host "    $((''+$Body).Substring(0, [Math]::Min(500, (''+$Body).Length)))"
Write-Host ""

if ($ContentType -like "*html*") {
    Write-Host "That is an HTML page, not an API response - the request never reached" -ForegroundColor Red
    Write-Host "the API. The URL is wrong rather than the credentials. Check it matches:" -ForegroundColor Red
    Write-Host "  $TestUri"
    return
}

switch ($StatusCode) {

    200 {
        Write-Host "SUCCESS - these credentials work." -ForegroundColor Green
        Write-Host "Put them in autotask-abillity-sync.ps1 and run it."
    }

    401 {
        Write-Host "HTTP 401 - Autotask rejected the credentials." -ForegroundColor Red
        Write-Host "  * UserName must be the API user's Username (Admin > Resources/Users)."
        Write-Host "  * Secret must be that API user's generated Password/Secret."
        Write-Host "  * ApiIntegrationCode is the Tracking Identifier from the Integration"
        Write-Host "    Vendor API user (Admin > Extensions & Integrations)."
        Write-Host "  * A locked account also answers 401 - check whether it is locked"
        Write-Host "    before assuming the values are wrong."
        Write-Host ""
        Write-Host "Do not keep retrying. Each attempt counts toward a lockout." -ForegroundColor Yellow
    }

    403 {
        Write-Host "HTTP 403 - the credentials are VALID but lack permission." -ForegroundColor Yellow
        Write-Host "This is a Security Level problem, not a password problem."
        Write-Host "Retyping the credentials will not help."
    }

    default {
        Write-Host "Unexpected response - see the status and body above." -ForegroundColor Yellow
    }
}
