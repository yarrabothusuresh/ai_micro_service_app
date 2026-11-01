[CmdletBinding()]
param([switch]$KeepDatabase)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\local-common.ps1')
Stop-LedgerOwnedProcesses
if (-not $KeepDatabase) {
    if (-not (Get-Command docker.exe -ErrorAction SilentlyContinue)) { throw 'Docker was not found; application processes stopped but the database container was not checked.' }
    $previousLocation = Get-Location
    try {
        Set-Location -LiteralPath $script:LedgerRoot
        & docker.exe compose stop postgres
        if ($LASTEXITCODE -ne 0) { throw 'Application processes stopped, but the database container could not be stopped.' }
    } finally { Set-Location -LiteralPath $previousLocation }
}
Write-Host 'Application stopped. Saved database records are preserved.'
