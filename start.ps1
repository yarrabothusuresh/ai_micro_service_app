[CmdletBinding()]
param([switch]$SkipBuild, [switch]$Verify, [switch]$NoBrowser, [switch]$SmokeTest, [string]$JavaHome)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\local-common.ps1')
if ($SkipBuild -and $Verify) { throw 'Choose either -SkipBuild or -Verify.' }

$frontendUrl = 'http://127.0.0.1:5173'
$previousLocation = Get-Location
$savedEnvironment = @{}
$started = @()
try {
    Set-Location -LiteralPath $script:LedgerRoot
    New-Item -ItemType Directory -Force -Path $script:LedgerRuntime | Out-Null
    $existing = @(Get-LedgerProcessRecords)
    $owned = @($existing | Where-Object { Test-LedgerProcessIdentity -Record $_ })
    if ($owned.Count -gt 0) {
        if ($owned.Count -eq $script:LedgerServices.Count) {
            foreach ($service in $script:LedgerServices) {
                $record = @($owned | Where-Object name -eq $service.Name)
                if ($record.Count -ne 1) { throw 'Saved process state is inconsistent. Run .\stop.ps1 before starting again.' }
                Wait-LedgerService -Record $record[0] -HealthPath $service.HealthPath -TimeoutSeconds 15
            }
            Write-Host "Already running: $frontendUrl"
            if (-not $NoBrowser) { Start-Process $frontendUrl }
            return
        }
        Write-Host 'Restarting the previously recorded partial application.'
        Stop-LedgerOwnedProcesses -Records $owned
    }
    foreach ($service in $script:LedgerServices) { Assert-LedgerPortAvailable -Port $service.Port }
    foreach ($command in @('docker.exe', 'mvn.cmd', 'node.exe', 'npm.cmd')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Install $command or add it to PATH." }
    }
    $selectedJava = Get-LedgerJavaHome -Requested $JavaHome
    $database = Get-LedgerDatabaseSettings
    $environment = @{
        JAVA_HOME = $selectedJava; PATH = (Join-Path $selectedJava 'bin') + ';' + $env:PATH
        DATABASE_URL = 'jdbc:postgresql://127.0.0.1:' + $database.POSTGRES_PORT + '/' + $database.POSTGRES_DB
        DATABASE_USERNAME = $database.POSTGRES_USER; DATABASE_PASSWORD = $database.POSTGRES_PASSWORD
        RULES_SERVICE_URL = 'http://127.0.0.1:8082'; POSTING_SERVICE_URL = 'http://127.0.0.1:8083'; UI_SERVICE_URL = 'http://127.0.0.1:8081'
        CLOUD_AUTH_ENABLED = 'false'; FRONTEND_ORIGINS = 'http://127.0.0.1:5173,http://localhost:5173'
        VITE_API_BASE_URL = 'http://127.0.0.1:8080'; VITE_BASE_PATH = '/'; PORT = $null
    }
    foreach ($key in $database.Keys) { $environment[$key] = $database[$key] }
    foreach ($key in $environment.Keys) {
        $savedEnvironment[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        Set-LedgerProcessEnvironment -Name $key -Value $environment[$key]
    }
    Write-Host 'Checking Docker Desktop...'
    & docker.exe info --format '{{.ServerVersion}}'
    if ($LASTEXITCODE -ne 0) { throw 'Start Docker Desktop and wait for its Linux engine before running this script.' }
    & docker.exe compose version --short
    if ($LASTEXITCODE -ne 0) { throw 'Docker Compose v2 is required.' }

    if (-not $SkipBuild) {
        Write-Host 'Building Java applications...'
        if ($Verify) { & mvn.cmd -B -ntp verify } else { & mvn.cmd -B -ntp package -DskipTests }
        if ($LASTEXITCODE -ne 0) { throw 'Java build failed. No application processes were started.' }
    }
    foreach ($service in @($script:LedgerServices | Where-Object Name -ne 'frontend')) {
        $jar = Join-Path $script:LedgerRoot ($service.Name + '\target\' + $service.Name + '-0.1.0-SNAPSHOT.jar')
        if (-not (Test-Path -LiteralPath $jar)) { throw "Missing $jar. Run .\start.ps1 without -SkipBuild." }
    }
    Push-Location -LiteralPath (Join-Path $script:LedgerRoot 'frontend')
    try {
        $vite = Join-Path (Get-Location).Path 'node_modules\vite\bin\vite.js'
        $lockHash = (Get-FileHash -LiteralPath 'package-lock.json' -Algorithm SHA256).Hash
        $stamp = Join-Path $script:LedgerRuntime 'frontend-lock.sha256'
        $installedHash = if (Test-Path -LiteralPath $stamp) { (Get-Content -LiteralPath $stamp -Raw).Trim() } else { '' }
        if (-not $SkipBuild -and ((-not (Test-Path -LiteralPath $vite)) -or $installedHash -ne $lockHash)) {
            Write-Host 'Installing frontend dependencies...'
            & npm.cmd ci
            if ($LASTEXITCODE -ne 0) { throw 'Frontend dependency installation failed.' }
            Set-Content -LiteralPath $stamp -Value $lockHash
        }
        if (-not (Test-Path -LiteralPath $vite)) { throw 'Frontend dependencies are missing. Run .\start.ps1 without -SkipBuild.' }
        if (-not $SkipBuild) {
            & npm.cmd run build
            if ($LASTEXITCODE -ne 0) { throw 'Frontend build failed.' }
        }
    } finally { Pop-Location }

    Write-Host ('Starting local PostgreSQL on port ' + $database.POSTGRES_PORT + '...')
    & docker.exe compose up -d --wait --wait-timeout 90 postgres
    if ($LASTEXITCODE -ne 0) { throw 'PostgreSQL startup failed. Check Docker Desktop and the configured database port.' }
    Save-LedgerProcessRecords -Records @()
    $java = Join-Path $selectedJava 'bin\java.exe'
    foreach ($service in @($script:LedgerServices | Where-Object Name -ne 'frontend')) {
        $jar = Join-Path $script:LedgerRoot ($service.Name + '\target\' + $service.Name + '-0.1.0-SNAPSHOT.jar')
        $started += Start-LedgerProcess -Name $service.Name -Executable $java -Entrypoint $jar -Port $service.Port -WorkingDirectory $script:LedgerRoot `
            -Arguments @('-Xmx384m', '-jar', ('"' + $jar + '"'), '--server.address=127.0.0.1', ('--server.port=' + $service.Port))
        Save-LedgerProcessRecords -Records $started
    }
    foreach ($service in @($script:LedgerServices | Where-Object Name -ne 'frontend')) {
        $record = $started | Where-Object name -eq $service.Name
        Wait-LedgerService -Record $record -HealthPath $service.HealthPath
    }
    $node = (Get-Command node.exe).Source
    $vite = Join-Path $script:LedgerRoot 'frontend\node_modules\vite\bin\vite.js'
    $started += Start-LedgerProcess -Name 'frontend' -Executable $node -Entrypoint $vite -Port 5173 -WorkingDirectory (Join-Path $script:LedgerRoot 'frontend') `
        -Arguments @(('"' + $vite + '"'), '--host', '127.0.0.1', '--port', '5173', '--strictPort')
    Save-LedgerProcessRecords -Records $started
    Wait-LedgerService -Record ($started | Where-Object name -eq 'frontend') -HealthPath '/'
    $dashboard = Invoke-RestMethod -Uri 'http://127.0.0.1:8080/api/ui/dashboard' -TimeoutSec 30
    Write-Host ('Gateway dashboard verified. Saved postings: ' + $dashboard.totalPostings)
    if ($SmokeTest) { & (Join-Path $script:LedgerRoot 'scripts\smoke-test.ps1') -GatewayUrl 'http://127.0.0.1:8080' }
    Write-Host "Application ready: $frontendUrl"
    Write-Host 'Gateway: http://127.0.0.1:8080'
    Write-Host 'Status: .\status.ps1   Stop: .\stop.ps1   Logs: .local\'
    if (-not $NoBrowser) { Start-Process $frontendUrl }
} catch {
    if ($started.Count -gt 0) {
        Write-Warning 'Startup did not complete; stopping the application processes started by this command.'
        Stop-LedgerOwnedProcesses -Records $started
    }
    throw
} finally {
    foreach ($key in $savedEnvironment.Keys) { Set-LedgerProcessEnvironment -Name $key -Value $savedEnvironment[$key] }
    Set-Location -LiteralPath $previousLocation
}
