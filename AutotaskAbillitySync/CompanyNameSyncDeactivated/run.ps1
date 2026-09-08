using namespace System.Net

param($Request, $TriggerMetadata)

Write-Warning "Autotask webhook deactivated: $($Request.Body | ConvertTo-Json -Depth 5)"

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body       = "ok"
})
