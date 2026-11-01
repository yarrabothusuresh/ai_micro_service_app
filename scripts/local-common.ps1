Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LedgerRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script:LedgerRuntime = Join-Path $script:LedgerRoot '.local'
$script:LedgerState = Join-Path $script:LedgerRuntime 'processes.json'
$script:LedgerServices = @(
    @{ Name = 'rules-service'; Port = 8082; HealthPath = '/actuator/health' },
    @{ Name = 'posting-service'; Port = 8083; HealthPath = '/actuator/health' },
    @{ Name = 'ui-service'; Port = 8081; HealthPath = '/actuator/health' },
    @{ Name = 'gateway'; Port = 8080; HealthPath = '/actuator/health' },
    @{ Name = 'frontend'; Port = 5173; HealthPath = '/' }
)

function Set-LedgerProcessEnvironment {
    param([Parameter(Mandatory)][string]$Name, [AllowNull()]$Value)
    if ($null -eq $Value) {
        # Removing an unset variable explicitly avoids passing PORT="" to Reactor Netty.
        Remove-Item -LiteralPath ('Env:\' + $Name) -ErrorAction SilentlyContinue
    } else {
        [Environment]::SetEnvironmentVariable($Name, [string]$Value, 'Process')
    }
}

function Get-LedgerDatabaseSettings {
    $settings = @{ POSTGRES_DB = 'ledger_demo'; POSTGRES_USER = 'ledger_demo'; POSTGRES_PASSWORD = 'local-demo-only'; POSTGRES_PORT = '15432' }
    $file = Join-Path $script:LedgerRoot '.env'
    if (Test-Path -LiteralPath $file) {
        foreach ($line in Get-Content -LiteralPath $file) {
            if ($line -match '^\s*(POSTGRES_DB|POSTGRES_USER|POSTGRES_PASSWORD|POSTGRES_PORT)\s*=(.*)$') {
                $key = $Matches[1]
                $value = $Matches[2].Trim()
                if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                    $value = $value.Substring(1, $value.Length - 2)
                }
                $settings[$key] = $value
            }
        }
    }
    foreach ($key in @('POSTGRES_DB', 'POSTGRES_USER')) {
        if ($settings[$key] -notmatch '^[a-zA-Z0-9_]{1,63}$') { throw "Use letters, numbers and underscores for $key in .env." }
    }
    $port = 0
    if (-not [int]::TryParse($settings.POSTGRES_PORT, [ref]$port) -or $port -lt 1 -or $port -gt 65535) { throw 'POSTGRES_PORT must be between 1 and 65535.' }
    if ([string]::IsNullOrEmpty($settings.POSTGRES_PASSWORD)) { throw 'POSTGRES_PASSWORD cannot be empty.' }
    return $settings
}

function Get-LedgerProcessRecords {
    if (-not (Test-Path -LiteralPath $script:LedgerState)) { return }
    foreach ($record in @(Get-Content -LiteralPath $script:LedgerState -Raw | ConvertFrom-Json)) {
        if ($null -ne $record) { Write-Output $record }
    }
}

function Save-LedgerProcessRecords {
    param([object[]]$Records = @())
    New-Item -ItemType Directory -Force -Path $script:LedgerRuntime | Out-Null
    ConvertTo-Json -InputObject @($Records) -Depth 5 | Set-Content -LiteralPath $script:LedgerState -Encoding UTF8
}

function Test-LedgerProcessIdentity {
    param([Parameter(Mandatory)]$Record)
    # A PID alone is not proof of ownership: Windows can reuse it after a process exits.
    try {
        $process = Get-Process -Id ([int]$Record.processId) -ErrorAction Stop
        $expectedStart = if ($Record.startedAt -is [DateTime]) { $Record.startedAt.ToUniversalTime() }
            elseif ($Record.startedAt -is [DateTimeOffset]) { $Record.startedAt.UtcDateTime }
            else { [DateTimeOffset]::Parse([string]$Record.startedAt).UtcDateTime }
        if ([Math]::Abs(($process.StartTime.ToUniversalTime() - $expectedStart).TotalMilliseconds) -gt 1) { return $false }
        if (-not [string]::Equals($process.Path, [string]$Record.executable, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $command = Get-CimInstance Win32_Process -Filter ('ProcessId=' + [int]$Record.processId) -ErrorAction Stop
        if (-not $command -or [string]::IsNullOrEmpty($command.CommandLine)) { return $false }
        $expected = [IO.Path]::GetFullPath([string]$Record.entrypoint)
        $prefix = $script:LedgerRoot.TrimEnd('\') + '\'
        if (-not $expected.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        return $command.CommandLine.IndexOf($expected, [StringComparison]::OrdinalIgnoreCase) -ge 0
    } catch { return $false }
}

function Stop-LedgerOwnedProcesses {
    param([object[]]$Records = @(Get-LedgerProcessRecords))
    $retained = @()
    foreach ($record in @($Records | Sort-Object -Property port -Descending)) {
        if (Test-LedgerProcessIdentity -Record $record) {
            try {
                Stop-Process -Id ([int]$record.processId) -ErrorAction Stop
                Write-Host ('Stopped ' + $record.name)
            } catch {
                $retained += $record
                Write-Warning ('Could not stop ' + $record.name + ': ' + $_.Exception.Message)
            }
        } else {
            Write-Host ('Skipped ' + $record.name + ': its recorded process has exited or its identity no longer matches.')
        }
    }
    Save-LedgerProcessRecords -Records $retained
    if ($retained.Count -gt 0) { throw 'Some application processes could not be stopped. Their records have been retained.' }
}

function Assert-LedgerPortAvailable {
    param([Parameter(Mandatory)][int]$Port)
    $listener = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $Port)
    try { $listener.Start() }
    catch { throw "Port $Port is occupied. Run .\status.ps1; stop any conflicting application yourself or change its port." }
    finally { $listener.Stop() }
}

function Start-LedgerProcess {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Executable,
          [Parameter(Mandatory)][string]$Entrypoint, [Parameter(Mandatory)][string[]]$Arguments,
          [Parameter(Mandatory)][int]$Port, [Parameter(Mandatory)][string]$WorkingDirectory)
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $script:LedgerRuntime ($Name + '.out.log')) `
        -RedirectStandardError (Join-Path $script:LedgerRuntime ($Name + '.err.log'))
    return [pscustomobject]@{ name = $Name; processId = $process.Id; port = $Port; executable = $Executable;
        entrypoint = $Entrypoint; startedAt = $process.StartTime.ToUniversalTime().ToString('o') }
}

function Wait-LedgerService {
    param([Parameter(Mandatory)]$Record, [Parameter(Mandatory)][string]$HealthPath, [int]$TimeoutSeconds = 120)
    $url = 'http://127.0.0.1:' + $Record.port + $HealthPath
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        if (-not (Get-Process -Id ([int]$Record.processId) -ErrorAction SilentlyContinue)) {
            throw ($Record.name + ' exited during startup. Read .local\' + $Record.name + '.err.log and .out.log.')
        }
        try {
            $healthy = if ($Record.name -eq 'frontend') {
                (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop).StatusCode -eq 200
            } else {
                (Invoke-RestMethod -Uri $url -TimeoutSec 3 -ErrorAction Stop).status -eq 'UP'
            }
            if ($healthy) {
                Write-Host ('Ready: ' + $Record.name + ' (port ' + $Record.port + ')')
                return
            }
        } catch { }
        Start-Sleep -Milliseconds 500
    }
    throw ($Record.name + ' did not become healthy. Read .local\' + $Record.name + '.out.log and .err.log.')
}

function Get-LedgerJavaHome {
    param([string]$Requested)
    $candidates = @()
    if ($Requested) { $candidates += $Requested }
    if ($env:JAVA_HOME) { $candidates += $env:JAVA_HOME }
    foreach ($pattern in @('C:\Program Files\Java\jdk-21*', 'C:\Program Files\Eclipse Adoptium\jdk-21*', 'C:\Program Files\Microsoft\jdk-21*')) {
        $candidates += @(Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -ExpandProperty FullName)
    }
    foreach ($candidate in @($candidates | Select-Object -Unique)) {
        $java = Join-Path $candidate 'bin\java.exe'
        if (Test-Path -LiteralPath $java) {
            $version = (& $java --version | Out-String)
            if ($LASTEXITCODE -eq 0 -and $version -match '(?m)^(?:openjdk|java) 21(?:\.|\s)') { return [IO.Path]::GetFullPath($candidate) }
        }
        if ($Requested -and $candidate -eq $Requested) { throw 'The supplied JavaHome must point to a Java 21 JDK.' }
    }
    throw 'Java 21 was not found. Set JAVA_HOME or pass -JavaHome with its JDK directory.'
}
