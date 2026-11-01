[CmdletBinding()]
param([switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\cloud-common.ps1')
$settings = Get-LedgerCloudSettings
$stateFile = Join-Path $script:CloudLocal 'cloud-deployment.json'
if (-not (Test-Path -LiteralPath $stateFile)) { throw 'Run publish.ps1 first.' }
$deployment = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
if ($deployment.projectId -ne $settings.projectId -or $deployment.region -ne $settings.region) { throw 'Deployment and cloud settings targets differ.' }
foreach ($name in @('rules','posting','ui','gateway')) {
    if (-not $deployment.urls.PSObject.Properties[$name]) { throw "Deployment is missing the $name URL. Finish publish.ps1 first." }
    $url = [uri]$deployment.urls.$name
    if ($url.Scheme -ne 'https' -or -not $url.Host.EndsWith('.run.app') -or $url.UserInfo -or $url.Query -or $url.Fragment -or $url.AbsolutePath -ne '/') { throw "Invalid Cloud Run URL for $name." }
}
$gateway = $deployment.urls.gateway.TrimEnd('/')
$info = Invoke-RestMethod -Uri ($gateway + '/') -TimeoutSec 120
if ($info.application -ne 'Ledger Manager API') { throw 'Unexpected Gateway root response.' }
$health = Invoke-RestMethod -Uri ($gateway + '/actuator/health') -TimeoutSec 120
if ($health.status -ne 'UP') { throw 'Gateway is not healthy.' }
$dashboard = Invoke-RestMethod -Uri ($gateway + '/api/ui/dashboard') -TimeoutSec 120
Write-Output ('Gateway and dashboard healthy: ' + $gateway + '; saved postings: ' + $dashboard.totalPostings)

foreach ($name in @('rules','posting','ui')) {
    $status = 0
    try {
        $response = Invoke-WebRequest -Uri ($deployment.urls.$name + '/actuator/health/liveness') -UseBasicParsing -TimeoutSec 30
        $status = [int]$response.StatusCode
    } catch {
        if (-not $_.Exception.PSObject.Properties['Response'] -or -not $_.Exception.Response) { throw }
        $status = [int]$_.Exception.Response.StatusCode
    }
    if ($status -notin @(401,403)) { throw "$name is not rejecting unauthenticated access (HTTP $status)." }
    Write-Output ("Protected backend: $name (unauthenticated HTTP $status)")
}
$cors = Invoke-WebRequest -Uri ($gateway + '/api/postings') -Method Options -UseBasicParsing -TimeoutSec 30 -Headers @{
    Origin=$settings.frontendOrigin; 'Access-Control-Request-Method'='POST'; 'Access-Control-Request-Headers'='content-type,idempotency-key'
}
if ([string]$cors.Headers['Access-Control-Allow-Origin'] -ne $settings.frontendOrigin) { throw 'Frontend CORS origin was not allowed.' }
Write-Output ('CORS allows frontend origin: ' + $settings.frontendOrigin)
if ($SmokeTest) { & (Join-Path $PSScriptRoot 'scripts\smoke-test.ps1') -GatewayUrl $gateway }
