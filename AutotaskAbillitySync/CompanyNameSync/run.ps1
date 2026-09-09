using namespace System.Net

param($Request, $TriggerMetadata)

$AbillityIdUdfLabel = $env:AutotaskAbillityIdUdfLabel
$SyncFlagUdfLabel   = $env:AutotaskSyncFlagUdfLabel

# What the sync-flag UDF can say for "yes". Anything else - including blank -
# means don't sync, so a company is never synced by accident.
$AffirmativeValues = @("yes", "y", "true", "1", "on", "checked")

$Payload      = $Request.Body
$StatusCode   = [HttpStatusCode]::OK
$ResponseBody = "ok"

if ($Payload.EntityType -eq "Company" -and $Payload.Action -eq "Update") {

    $FieldsMap = @{}
    foreach ($f in $Payload.Fields) { $FieldsMap[$f.name] = $f.value }

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
            Invoke-RestMethod -Uri "https://api.abillity.co.uk/api/company/$AbillityId" `
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
