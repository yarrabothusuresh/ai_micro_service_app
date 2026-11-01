$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $taskRoot
if (Test-Path -LiteralPath 'C:\Program Files\Java\jdk-21.0.12.1') {
    $env:JAVA_HOME = 'C:\Program Files\Java\jdk-21.0.12.1'
}
if (-not $env:JAVA_HOME) { throw 'Set JAVA_HOME to a Java 21 JDK before building.' }
$env:PATH = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:PATH
& mvn.cmd -B -ntp verify
if ($LASTEXITCODE -ne 0) { throw 'Backend verification failed.' }
Push-Location -LiteralPath (Join-Path $taskRoot 'frontend')
try {
    if (Test-Path -LiteralPath 'package-lock.json') { & npm.cmd ci } else { & npm.cmd install }
    if ($LASTEXITCODE -ne 0) { throw 'Frontend dependency installation failed.' }
    & npm.cmd run build
    if ($LASTEXITCODE -ne 0) { throw 'Frontend build failed.' }
} finally { Pop-Location }
Write-Output 'Backend tests and frontend production build passed.'
