using namespace System.Net

param($Request, $TriggerMetadata)

$UdfLabel = $env:AutotaskUdfLabel

$Payload      = $Request.Body
$StatusCode   = [HttpStatusCode]::OK
$ResponseBody = "ok"

if ($Payload.EntityType -eq "Company" -and $Payload.Action -eq "Update") {

    $FieldsMap = @{}
    foreach ($f in $Payload.Fields) { $FieldsMap[$f.name] = $f.value }

    $NewName    = $FieldsMap["CompanyName"]
    $AbillityId = $FieldsMap[$UdfLabel]

    if ($NewName -and $AbillityId) {

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

    } elseif (-not $AbillityId) {
        Write-Warning "Autotask company $($Payload.Id) has no linked aBILLity ID — skipping"
    }
}

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = $StatusCode
    Body       = $ResponseBody
})
