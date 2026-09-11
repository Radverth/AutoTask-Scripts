using namespace System.Net

param($Request, $TriggerMetadata)

$AbillityIdUdfLabel = $env:AutotaskAbillityIdUdfLabel
$SyncFlagUdfLabel   = $env:AutotaskSyncFlagUdfLabel

# What the sync-flag UDF can say for "yes". Anything else - including blank -
# means don't sync, so a company is never synced by accident.
$AffirmativeValues = @("yes", "y", "true", "1", "on", "checked")

# A PICKLIST UDF sends the id of the selected value, not its label, so the id
# meaning "yes" has to be configured (comma separated).
foreach ($v in ("$($env:AutotaskSyncFlagYesValues)" -split ",")) {
    $v = $v.Trim().ToLower()
    if ($v) { $AffirmativeValues += $v }
}

# Your aBILLity instance decides this host - override with the AbillityApiBase
# app setting if yours differs.
$ApiBase = $env:AbillityApiBase
if (-not $ApiBase) { $ApiBase = "https://api-billing.abillity.co.uk/api" }
$ApiBase = $ApiBase.TrimEnd('/')

$Payload      = $Request.Body
$StatusCode   = [HttpStatusCode]::OK
$ResponseBody = "ok"

# Autotask names this entity "Account" on the wire, even though the UI and the
# API entity are both "Company".
$EntityType = "$($Payload.EntityType)".ToLower()
$Action     = "$($Payload.Action)".ToLower()

if (($EntityType -eq "account" -or $EntityType -eq "company") -and $Action -eq "update") {

    # Autotask sends Fields as an object keyed by field name; the older shape was
    # an array of {name, value}. Accept both.
    $FieldsMap = @{}
    if ($Payload.Fields -is [System.Array]) {
        foreach ($f in $Payload.Fields) { $FieldsMap[$f.name] = $f.value }
    } elseif ($Payload.Fields) {
        foreach ($p in $Payload.Fields.PSObject.Properties) { $FieldsMap[$p.Name] = $p.Value }
    }

    $NewName    = $FieldsMap["CompanyName"]
    $SyncFlag   = $FieldsMap[$SyncFlagUdfLabel]
    $AbillityId = $FieldsMap[$AbillityIdUdfLabel]

    $ShouldSync = $AffirmativeValues -contains ("$SyncFlag").Trim().ToLower()

    if (-not $NewName) {
        # This update didn't touch the name.
    } elseif (-not $ShouldSync) {
        Write-Host "Autotask company $($Payload.Id) is not flagged for aBILLity sync ('$SyncFlagUdfLabel' = '$SyncFlag') - skipping"
    } elseif (-not $AbillityId) {
        Write-Warning "Autotask company $($Payload.Id) is flagged for sync but has no '$AbillityIdUdfLabel' - skipping"
    } else {

        if ($NewName.Length -gt 50) { $NewName = $NewName.Substring(0, 50) }

        $AbillityHeaders = @{
            "SystemInformation" = $env:AbillitySystemInformation
            "username"          = $env:AbillityUserName
            "password"          = $env:AbillityPassword
            "Content-Type"      = "application/json"
            "Accept"            = "application/json"
        }

        $PatchBody = @{ Name = $NewName } | ConvertTo-Json

        try {
            Invoke-RestMethod -Uri "$ApiBase/company/$AbillityId" `
                -Method Patch -Headers $AbillityHeaders -Body $PatchBody
            Write-Host "Synced company $AbillityId -> '$NewName'"
        } catch {
            Write-Error "aBILLity PATCH failed for company $AbillityId : $($_.Exception.Message)"
            $StatusCode   = [HttpStatusCode]::InternalServerError
            $ResponseBody = "sync failed"
        }
    }
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $StatusCode
    Body       = $ResponseBody
})
