[CmdletBinding()]
param([string]$GatewayUrl)
$ErrorActionPreference = 'Stop'
$repo = 'yarrabothusuresh/ai_micro_service_app'
$expectedOrigin = 'https://github.com/yarrabothusuresh/ai_micro_service_app.git'
Set-Location -LiteralPath $PSScriptRoot
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'Install GitHub CLI first.' }
if (-not $GatewayUrl) {
    $deployment = Get-Content -LiteralPath '.local\cloud-deployment.json' -Raw | ConvertFrom-Json
    $GatewayUrl = $deployment.urls.gateway
}
$gateway = [uri]$GatewayUrl
if ($gateway.Scheme -ne 'https' -or -not $gateway.Host.EndsWith('.run.app') -or $gateway.UserInfo -or $gateway.Query -or $gateway.Fragment -or $gateway.AbsolutePath -ne '/') { throw 'Supply the deployed Gateway HTTPS origin.' }
if ((& git remote get-url origin).TrimEnd('/') -ne $expectedOrigin) { throw 'The origin remote does not match the approved repository.' }
if (& git status --porcelain) { throw 'Commit the reviewed source changes before publishing.' }
if ((& git branch --show-current).Trim() -ne 'main') { throw 'Publish from the reviewed main branch.' }

function Invoke-PagesGitHub {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$Capture)
    if ($Capture) { $result = @(& gh @Arguments); $code = $LASTEXITCODE }
    else { & gh @Arguments | Out-Host; $code = $LASTEXITCODE }
    if ($code -ne 0) { throw ('GitHub command failed: ' + $Arguments[0] + '. Review the error above.') }
    if ($Capture) { return ($result -join "`n").Trim() }
}

# Use the existing GitHub CLI login, or Git's cached login for this same account.
# A cached OAuth token stays in process memory and is never printed or saved.
$savedToken = [Environment]::GetEnvironmentVariable('GH_TOKEN', 'Process')
$savedPrompt = [Environment]::GetEnvironmentVariable('GIT_TERMINAL_PROMPT', 'Process')
$savedInteractive = [Environment]::GetEnvironmentVariable('GCM_INTERACTIVE', 'Process')
$credentialLines = $null
$cachedToken = $null
try {
    & gh auth status --hostname github.com *> $null
    if ($LASTEXITCODE -ne 0) {
        $env:GIT_TERMINAL_PROMPT = '0'
        $env:GCM_INTERACTIVE = 'never'
        $credentialLines = @("protocol=https`nhost=github.com`nusername=yarrabothusuresh`n`n" | & git -c credential.interactive=never credential fill 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'Sign in as yarrabothusuresh using gh auth login --hostname github.com --web.' }
        foreach ($line in $credentialLines) {
            if ($line.StartsWith('password=')) { $cachedToken = $line.Substring(9) }
        }
        if (-not $cachedToken) { throw 'No cached GitHub login was available. Run gh auth login --hostname github.com --web.' }
        $env:GH_TOKEN = $cachedToken
    }
    $login = Invoke-PagesGitHub -Arguments @('api','user','--jq','.login') -Capture
    if ($login -ne 'yarrabothusuresh') { throw 'Sign in to GitHub CLI as yarrabothusuresh before publishing this repository.' }
    $repository = Invoke-PagesGitHub -Arguments @('api',"repos/$repo") -Capture | ConvertFrom-Json
    if ($repository.visibility -ne 'public' -or -not $repository.permissions.admin) { throw 'The approved public repository requires administrator access to configure Pages.' }

    # Ordinary push rejects diverged history; no force push or remote-history replacement.
    & git push origin HEAD:refs/heads/main
    if ($LASTEXITCODE -ne 0) { throw 'Git push failed; resolve it without replacing remote history.' }
    $sha = (& git rev-parse HEAD).Trim()
    Invoke-PagesGitHub -Arguments @('variable','set','GATEWAY_URL','--repo',$repo,'--body',$GatewayUrl.TrimEnd('/'))
    $pagesResult = @(& gh api "repos/$repo/pages" 2>$null)
    if ($LASTEXITCODE -eq 0) {
        $pages = ($pagesResult -join "`n") | ConvertFrom-Json
        if ($pages.build_type -ne 'workflow') { Invoke-PagesGitHub -Arguments @('api','--method','PUT',"repos/$repo/pages",'--field','build_type=workflow') }
    } else {
        Invoke-PagesGitHub -Arguments @('api','--method','POST',"repos/$repo/pages",'--field','build_type=workflow')
    }
    Invoke-PagesGitHub -Arguments @('workflow','run','pages.yml','--repo',$repo,'--ref','main')
    $run = $null
    for ($attempt = 1; $attempt -le 12; $attempt++) {
        $runs = Invoke-PagesGitHub -Arguments @('api',"repos/$repo/actions/workflows/pages.yml/runs?event=workflow_dispatch&head_sha=$sha&per_page=5") -Capture | ConvertFrom-Json
        $run = @($runs.workflow_runs | Sort-Object created_at -Descending | Select-Object -First 1)
        if ($run.Count -eq 1) { break }
        Start-Sleep -Seconds 2
    }
    if ($run.Count -ne 1) { throw 'The workflow was dispatched; inspect its run on the repository Actions page.' }
    Invoke-PagesGitHub -Arguments @('run','watch',[string]$run[0].id,'--repo',$repo,'--exit-status','--interval','5')
    Write-Output 'React published: https://yarrabothusuresh.github.io/ai_micro_service_app/'
} finally {
    foreach ($entry in @(@('GH_TOKEN',$savedToken),@('GIT_TERMINAL_PROMPT',$savedPrompt),@('GCM_INTERACTIVE',$savedInteractive))) {
        if ($null -eq $entry[1]) { Remove-Item -LiteralPath ('Env:\' + $entry[0]) -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($entry[0], [string]$entry[1], 'Process') }
    }
    $credentialLines = $null
    $cachedToken = $null
}
