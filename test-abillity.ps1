<#
    aBILLity API tester
    ===================

    Tests the aBILLity half of the sync on its own - credentials, company ID,
    and the name update the Worker performs - without involving Autotask or
    Cloudflare at all.

    READ-ONLY by default. It looks the company up and shows you its current
    name. Nothing is changed unless you pass -NewName AND type the
    confirmation, and it offers to put the original name back afterwards.

    Look up a company (changes nothing):

        .\test-abillity.ps1 -CompanyId 789 -SystemInformation "..." -UserName "..."

    Test the rename the Worker would do:

        .\test-abillity.ps1 -CompanyId 789 -SystemInformation "..." -UserName "..." `
            -NewName "Test Rename - safe to ignore"

    THIS WRITES TO LIVE BILLING DATA. Use a company you are willing to rename,
    and let it restore the original name when it offers.
#>

param(
    [Parameter(Mandatory = $true)]
    [string] $CompanyId,

    [Parameter(Mandatory = $true)]
    [string] $SystemInformation,

    [Parameter(Mandatory = $true)]
    [string] $UserName,

    # Prompted for if omitted, so it stays out of your shell history.
    [string] $Password,

    # Supply this to test the rename. Without it the script only reads.
    [string] $NewName,

    # Use if aBILLity has no GET for a single company - skips the read step.
    [switch] $SkipRead
)

$ErrorActionPreference = "Stop"

$ApiBase = "https://api.abillity.co.uk/api"

# aBILLity caps Company Name at 50 characters - the Worker truncates to match.
$NameMaxLength = 50

if (-not $Password) {
    $Secure = Read-Host "aBILLity password" -AsSecureString
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure))
}

$Headers = @{
    "SystemInformation" = $SystemInformation
    "username"          = $UserName
    "password"          = $Password
    "Content-Type"      = "application/json"
    "Accept"            = "application/json"
}

$CompanyUri = "$ApiBase/company/$([uri]::EscapeDataString($CompanyId))"

$SupportsSkip = (Get-Command Invoke-WebRequest).Parameters.ContainsKey("SkipHttpErrorCheck")

function Invoke-Abillity {
    param(
        [string] $Method,
        [string] $Uri,
        [string] $Body
    )

    # Not $Args - that shadows PowerShell's automatic $args variable.
    $RequestArgs = @{
        Uri        = $Uri
        Method     = $Method
        Headers    = $Headers
        TimeoutSec = 30
    }
    if ($Body) { $RequestArgs["Body"] = $Body }
    if ($SupportsSkip) { $RequestArgs["SkipHttpErrorCheck"] = $true }

    try {
        $Response = Invoke-WebRequest @RequestArgs
        return [pscustomobject]@{
            StatusCode  = [int]$Response.StatusCode
            ContentType = [string]$Response.Headers["Content-Type"]
            Body        = [string]$Response.Content
        }
    } catch {
        $Status = $null
        try { $Status = [int]$_.Exception.Response.StatusCode } catch { }
        $Body2 = $_.ErrorDetails.Message
        if (-not $Body2) { $Body2 = $_.Exception.Message }
        return [pscustomobject]@{
            StatusCode  = $Status
            ContentType = $null
            Body        = [string]$Body2
        }
    }
}

function Show-Result {
    param($Result, [string] $Label)

    Write-Host ""
    Write-Host "  $Label"
    Write-Host "    HTTP status : $($Result.StatusCode)"
    if ($Result.ContentType) { Write-Host "    Content-Type: $($Result.ContentType)" }

    if ([string]::IsNullOrWhiteSpace($Result.Body)) {
        Write-Host "    Body        : (empty)"
    } else {
        $Snippet = $Result.Body
        if ($Snippet.Length -gt 500) { $Snippet = $Snippet.Substring(0, 500) + " ..." }
        Write-Host "    Body        : $Snippet"
    }

    if ($Result.ContentType -like "*html*") {
        Write-Host ""
        Write-Host "    That is HTML, not JSON - the request never reached the API." -ForegroundColor Red
        Write-Host "    The URL is wrong rather than the credentials." -ForegroundColor Red
    }
}

function Get-CompanyName {
    param([string] $Json)
    if ([string]::IsNullOrWhiteSpace($Json)) { return $null }
    try {
        $Parsed = $Json | ConvertFrom-Json
    } catch {
        return $null
    }
    foreach ($Candidate in @($Parsed, $Parsed.company, $Parsed.data, ($Parsed.items | Select-Object -First 1))) {
        if ($Candidate -and $Candidate.Name) { return [string]$Candidate.Name }
    }
    return $null
}

Write-Host ""
Write-Host "aBILLity test - company $CompanyId" -ForegroundColor Cyan
Write-Host "  $CompanyUri"

### ---------------------------------------------------------------------
### 1. Read the company. Changes nothing.
### ---------------------------------------------------------------------

$OriginalName = $null

if (-not $SkipRead) {

    Write-Host ""
    Write-Host "STEP 1: look up the company (read-only)" -ForegroundColor Cyan

    $Read = Invoke-Abillity -Method "GET" -Uri $CompanyUri
    Show-Result -Result $Read -Label "GET response"

    switch ($Read.StatusCode) {
        200 {
            $OriginalName = Get-CompanyName -Json $Read.Body
            Write-Host ""
            if ($OriginalName) {
                Write-Host "  Current name: '$OriginalName'" -ForegroundColor Green
            } else {
                Write-Host "  Read succeeded, but no Name field was found in the response." -ForegroundColor Yellow
                Write-Host "  Check the body above - the field may be nested differently."
            }
        }
        401 {
            Write-Host ""
            Write-Host "  HTTP 401 - aBILLity rejected the credentials." -ForegroundColor Red
            Write-Host "  Check SystemInformation, UserName and Password."
            return
        }
        403 {
            Write-Host ""
            Write-Host "  HTTP 403 - credentials valid but not permitted to read this company." -ForegroundColor Yellow
            return
        }
        404 {
            Write-Host ""
            Write-Host "  HTTP 404 - no company with ID $CompanyId." -ForegroundColor Red
            Write-Host "  This is the value that goes in the 'aBillity Company ID' UDF -"
            Write-Host "  if it is wrong, the Worker will fail the same way."
            return
        }
        405 {
            Write-Host ""
            Write-Host "  HTTP 405 - aBILLity does not support GET on this endpoint." -ForegroundColor Yellow
            Write-Host "  Re-run with -SkipRead to go straight to the update test."
            return
        }
        default {
            Write-Host ""
            Write-Host "  Unexpected status - see above. Stopping rather than guessing." -ForegroundColor Yellow
            return
        }
    }
}

if (-not $NewName) {
    Write-Host ""
    Write-Host "No -NewName given, so stopping here. Nothing was changed." -ForegroundColor Cyan
    Write-Host "To test the rename the Worker performs, re-run with -NewName ""Some Test Name""."
    return
}

### ---------------------------------------------------------------------
### 2. The rename. Writes to live data, so it asks first.
### ---------------------------------------------------------------------

$TargetName = $NewName
if ($TargetName.Length -gt $NameMaxLength) {
    $TargetName = $TargetName.Substring(0, $NameMaxLength)
    Write-Host ""
    Write-Host "  Name is over $NameMaxLength characters, truncated to '$TargetName'" -ForegroundColor Yellow
    Write-Host "  (the Worker does exactly this - it is aBILLity's limit)"
}

Write-Host ""
Write-Host "STEP 2: rename the company" -ForegroundColor Cyan
Write-Host ""
Write-Host "  THIS CHANGES LIVE BILLING DATA." -ForegroundColor Yellow
if ($OriginalName) {
    Write-Host "    from: '$OriginalName'" -ForegroundColor Yellow
}
Write-Host "    to  : '$TargetName'" -ForegroundColor Yellow
Write-Host ""

$Answer = Read-Host "  Type RENAME to go ahead"
if ($Answer -ne "RENAME") {
    Write-Host "  Cancelled. Nothing was changed." -ForegroundColor Cyan
    return
}

$PatchBody = @{ Name = $TargetName } | ConvertTo-Json
$Patch = Invoke-Abillity -Method "PATCH" -Uri $CompanyUri -Body $PatchBody
Show-Result -Result $Patch -Label "PATCH response"

if ($Patch.StatusCode -ge 200 -and $Patch.StatusCode -lt 300) {
    Write-Host ""
    Write-Host "  Rename accepted. This is exactly the call the Worker makes." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  Rename failed - the Worker would log this and return 'sync failed'." -ForegroundColor Red
    if (-not $OriginalName) { return }
}

### ---------------------------------------------------------------------
### 3. Confirm, then offer to put the original name back.
### ---------------------------------------------------------------------

if (-not $SkipRead) {
    Write-Host ""
    Write-Host "STEP 3: read it back" -ForegroundColor Cyan
    $Verify = Invoke-Abillity -Method "GET" -Uri $CompanyUri
    $NowName = Get-CompanyName -Json $Verify.Body
    if ($NowName) {
        Write-Host "  Name is now: '$NowName'"
        if ($NowName -eq $TargetName) {
            Write-Host "  Matches what we sent." -ForegroundColor Green
        } else {
            Write-Host "  Does NOT match what we sent - aBILLity may have altered it." -ForegroundColor Yellow
        }
    }
}

if ($OriginalName) {
    Write-Host ""
    Write-Host "STEP 4: restore the original name" -ForegroundColor Cyan
    Write-Host "  The company was called '$OriginalName' before this test."
    Write-Host ""

    $Restore = Read-Host "  Type RESTORE to set it back (anything else leaves the test name)"

    if ($Restore -eq "RESTORE") {
        $RestoreBody = @{ Name = $OriginalName } | ConvertTo-Json
        $RestoreResult = Invoke-Abillity -Method "PATCH" -Uri $CompanyUri -Body $RestoreBody
        Show-Result -Result $RestoreResult -Label "Restore response"
        if ($RestoreResult.StatusCode -ge 200 -and $RestoreResult.StatusCode -lt 300) {
            Write-Host ""
            Write-Host "  Restored to '$OriginalName'." -ForegroundColor Green
        } else {
            Write-Host ""
            Write-Host "  RESTORE FAILED. The company is still called '$TargetName'." -ForegroundColor Red
            Write-Host "  Put it back by hand in aBILLity." -ForegroundColor Red
        }
    } else {
        Write-Host "  Left as '$TargetName'. Change it back in aBILLity when you are done." -ForegroundColor Yellow
    }
}

Write-Host ""
