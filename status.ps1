$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\local-common.ps1')
$records = @(Get-LedgerProcessRecords)
$rows = foreach ($service in $script:LedgerServices) {
    $record = @($records | Where-Object name -eq $service.Name)
    $state = 'Stopped'
    $processId = $null
    if ($record.Count -eq 1 -and (Test-LedgerProcessIdentity -Record $record[0])) {
        $processId = $record[0].processId
        $state = 'Running; health check failed'
        try {
            $url = 'http://127.0.0.1:' + $service.Port + $service.HealthPath
            $healthy = if ($service.Name -eq 'frontend') {
                (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200
            } else {
                (Invoke-RestMethod -Uri $url -TimeoutSec 3).status -eq 'UP'
            }
            if ($healthy) { $state = 'Healthy' }
        } catch { }
    }
    [pscustomobject]@{ Service = $service.Name; Port = $service.Port; Status = $state; ProcessId = $processId }
}
$rows | Format-Table -AutoSize
Write-Host 'Database container:'
$previousLocation = Get-Location
try {
    Set-Location -LiteralPath $script:LedgerRoot
    if (Get-Command docker.exe -ErrorAction SilentlyContinue) { & docker.exe compose ps -a postgres }
} finally { Set-Location -LiteralPath $previousLocation }
Write-Host 'UI: http://127.0.0.1:5173   Gateway: http://127.0.0.1:8080   Logs: .local\'
