[CmdletBinding()]
param([ValidateSet('Prepare','Rules','All')][string]$Stage='All', [switch]$Plan, [switch]$Continue,
      [string]$ProjectId='ledgermanager', [string]$Region='us-east4')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\cloud-common.ps1')
if ($Plan) {
    Write-Output "Target: $ProjectId / $Region; stage: $Stage"
    Write-Output 'Prepare: enable required APIs; create ledger-demo image repository, scoped build/runtime identities and private source bucket.'
    Write-Output 'Rules: build and deploy ledger-rules with authenticated invocation.'
    Write-Output 'All: deploy rules -> posting (Neon TLS and pinned password secret) -> UI API -> Gateway; grant only required invocation paths.'
    Write-Output 'Publish only ledger-gateway to allUsers; leave rules, posting and UI API protected by Cloud Run IAM.'
    Write-Output 'Minimum instances: 0; maximum instances per service: 1. Cloud usage beyond free allowances is billable.'
    return
}
Assert-LedgerCloudTarget -ProjectId $ProjectId -Region $Region
$settings = $null
if ($Stage -eq 'All') {
    $settings = Get-LedgerCloudSettings
    if ($settings.projectId -ne $ProjectId -or $settings.region -ne $Region) { throw 'The configured database target and requested deployment target must match.' }
}
$prepared = Initialize-LedgerCloud -ProjectId $ProjectId -Region $Region
if ($Stage -eq 'Prepare') { return }
$tag = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
$state = [ordered]@{ projectId=$ProjectId; region=$Region; release=$tag; urls=@{}; images=@{} }
$stateFile = Join-Path $script:CloudLocal 'cloud-deployment.json'
if ($Continue) {
    if (-not (Test-Path -LiteralPath $stateFile)) { throw 'No saved deployment exists to continue.' }
    $previous = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($previous.projectId -ne $ProjectId -or $previous.region -ne $Region) { throw 'Saved deployment belongs to another target.' }
    foreach ($kind in @('urls','images')) {
        foreach ($property in $previous.$kind.PSObject.Properties) { $state[$kind][$property.Name] = $property.Value }
    }
}
function Save-DeploymentState { $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $stateFile -Encoding UTF8 }
if ($Continue -and $state.urls.ContainsKey('rules') -and $state.images.ContainsKey('rules')) {
    $current = Invoke-LedgerGcloud -Arguments @('run','services','describe','ledger-rules',"--project=$ProjectId","--region=$Region",'--format=json','--quiet') -Capture | ConvertFrom-Json
    if (@($current.status.conditions | Where-Object { $_.type -eq 'Ready' -and $_.status -eq 'True' }).Count -ne 1 -or $current.status.url -ne $state.urls.rules -or $current.spec.template.spec.containers[0].image -ne $state.images.rules) {
        throw 'The saved rules deployment no longer matches the ready Cloud Run service. Publish without -Continue to rebuild.'
    }
    Write-Host 'Reusing the verified ready rules-service image and URL.'
} else {
    $state.images.rules = Build-LedgerImage -Prepared $prepared -Module 'rules-service' -Tag $tag
    $state.urls.rules = Publish-LedgerService -Prepared $prepared -Name 'ledger-rules' -Account $prepared.accounts.rules -Image $state.images.rules -Memory '1Gi' -Environment @{ SPRING_PROFILES_ACTIVE='cloud' }
}
Save-DeploymentState
if ($Stage -eq 'Rules') { Write-Host ('Authenticated rules service deployed: ' + $state.urls.rules); return }

Invoke-LedgerGcloud -Arguments @('secrets','add-iam-policy-binding',$settings.databasePasswordSecret,('--member=serviceAccount:' + $prepared.accounts.posting),'--role=roles/secretmanager.secretAccessor',"--project=$ProjectId",'--quiet','--format=none')
$state.images.posting = Build-LedgerImage -Prepared $prepared -Module 'posting-service' -Tag $tag
$state.urls.posting = Publish-LedgerService -Prepared $prepared -Name 'ledger-posting' -Account $prepared.accounts.posting -Image $state.images.posting -Environment @{
    SPRING_PROFILES_ACTIVE='cloud'; RULES_SERVICE_URL=$state.urls.rules; DATABASE_URL=(Get-LedgerDatabaseUrl -Settings $settings); DATABASE_MIGRATION_URL=(Get-LedgerDatabaseUrl -Settings $settings -Direct); DATABASE_USERNAME=$settings.databaseUsername
} -PasswordSecret ($settings.databasePasswordSecret + ':' + $settings.databasePasswordVersion)
Grant-LedgerInvocation -Prepared $prepared -Service 'ledger-rules' -Member ('serviceAccount:' + $prepared.accounts.posting)
Save-DeploymentState
$state.images.ui = Build-LedgerImage -Prepared $prepared -Module 'ui-service' -Tag $tag
$state.urls.ui = Publish-LedgerService -Prepared $prepared -Name 'ledger-ui' -Account $prepared.accounts.ui -Image $state.images.ui -Environment @{
    SPRING_PROFILES_ACTIVE='cloud'; POSTING_SERVICE_URL=$state.urls.posting
}
Grant-LedgerInvocation -Prepared $prepared -Service 'ledger-posting' -Member ('serviceAccount:' + $prepared.accounts.ui)
Save-DeploymentState
$state.images.gateway = Build-LedgerImage -Prepared $prepared -Module 'gateway' -Tag $tag
$state.urls.gateway = Publish-LedgerService -Prepared $prepared -Name 'ledger-gateway' -Account $prepared.accounts.gateway -Image $state.images.gateway -Environment @{
    SPRING_PROFILES_ACTIVE='cloud'; POSTING_SERVICE_URL=$state.urls.posting; UI_SERVICE_URL=$state.urls.ui; FRONTEND_ORIGINS=$settings.frontendOrigin
}
Grant-LedgerInvocation -Prepared $prepared -Service 'ledger-ui' -Member ('serviceAccount:' + $prepared.accounts.gateway)
Grant-LedgerInvocation -Prepared $prepared -Service 'ledger-posting' -Member ('serviceAccount:' + $prepared.accounts.gateway)
Grant-LedgerInvocation -Prepared $prepared -Service 'ledger-gateway' -Member 'allUsers'
Save-DeploymentState
Write-Host ('Gateway published: ' + $state.urls.gateway)
$gatewayReady = $false
for ($attempt = 1; $attempt -le 12; $attempt++) {
    try {
        $info = Invoke-RestMethod -Uri ($state.urls.gateway + '/') -TimeoutSec 10
        if ($info.application -ne 'Ledger Manager API') { throw 'Unexpected Gateway response.' }
        $gatewayReady = $true
        break
    } catch {
        # Public invocation policy may need a few seconds to reach the serving frontend.
        if ($attempt -lt 12) { Start-Sleep -Seconds 5 }
    }
}
if (-not $gatewayReady) { throw 'Gateway was deployed, but public readiness could not be verified. Run verify-cloud.ps1 to diagnose.' }
& (Join-Path $script:CloudRoot 'scripts\smoke-test.ps1') -GatewayUrl $state.urls.gateway
& (Join-Path $script:CloudRoot 'verify-cloud.ps1')
Write-Host ('Set the GitHub repository variable GATEWAY_URL to ' + $state.urls.gateway + ' and run the Pages deployment workflow for React.')
