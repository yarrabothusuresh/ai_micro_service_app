[CmdletBinding()]
param([string]$ProjectId='ledgermanager', [string]$Region='us-east4', [string]$DatabaseHost,
      [string]$DatabaseName, [string]$DatabaseUsername,
      [string]$FrontendOrigin='https://vijayabhargavidba.github.io',
      [string]$PasswordSecret='ledger-neon-password', [string]$ExistingSecretVersion)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'scripts\cloud-common.ps1')
Assert-LedgerCloudTarget -ProjectId $ProjectId -Region $Region
if (-not $DatabaseHost) { $DatabaseHost = Read-Host 'Neon hostname (no password or connection URI)' }
if (-not $DatabaseName) { $DatabaseName = Read-Host 'Neon database name' }
if (-not $DatabaseUsername) { $DatabaseUsername = Read-Host 'Neon database username' }
$DatabaseHost=$DatabaseHost.Trim(); $DatabaseName=$DatabaseName.Trim(); $DatabaseUsername=$DatabaseUsername.Trim()
if ($DatabaseHost -notmatch '^[a-zA-Z0-9.-]+\.neon\.tech$') { throw 'Enter the hostname from Neon Connect, ending in .neon.tech.' }
if ($DatabaseName -notmatch '^[a-zA-Z0-9_-]{1,63}$' -or [string]::IsNullOrWhiteSpace($DatabaseUsername)) { throw 'A valid database name and username are required.' }
if ($PasswordSecret -notmatch '^[a-zA-Z0-9_-]{1,255}$') { throw 'Invalid Secret Manager secret name.' }
if ($ExistingSecretVersion) {
    if ($ExistingSecretVersion -notmatch '^[1-9][0-9]*$') { throw 'Use a numeric secret version.' }
    Invoke-LedgerGcloud -Arguments @('secrets','versions','describe',$ExistingSecretVersion,"--secret=$PasswordSecret","--project=$ProjectId",'--quiet','--format=none')
    $version = $ExistingSecretVersion
} else {
    Write-Host 'The password will be sent only to Secret Manager in ledgermanager. It will not be written to a local file or printed.'
    $securePassword = Read-Host 'Neon database password' -AsSecureString
    $pointer = [IntPtr]::Zero
    $password = $null; $bytes = $null; $token = $null; $body = $null; $headers = $null
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        if ([string]::IsNullOrEmpty($password)) { throw 'Database password cannot be empty.' }
        $secrets = Invoke-LedgerGcloud -Arguments @('secrets','list',"--project=$ProjectId",'--format=value(name)','--quiet') -Capture
        if (@($secrets -split '\s+' | ForEach-Object { ($_ -split '/')[-1] }) -notcontains $PasswordSecret) {
            Invoke-LedgerGcloud -Arguments @('secrets','create',$PasswordSecret,'--replication-policy=automatic',"--project=$ProjectId",'--quiet','--format=none')
        }
        $token = Invoke-LedgerGcloud -Arguments @('auth','print-access-token',"--project=$ProjectId",'--quiet') -Capture
        $bytes = [Text.Encoding]::UTF8.GetBytes($password)
        $body = @{ payload = @{ data = [Convert]::ToBase64String($bytes) } } | ConvertTo-Json -Depth 4 -Compress
        $headers = @{ Authorization = 'Bearer ' + $token }
        $response = Invoke-RestMethod -Uri "https://secretmanager.googleapis.com/v1/projects/$ProjectId/secrets/${PasswordSecret}:addVersion" -Method Post -Headers $headers -ContentType 'application/json' -Body $body -Verbose:$false
        $version = ($response.name -split '/')[-1]
    } finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
        if ($securePassword) { $securePassword.Dispose() }
        $password=$null; $bytes=$null; $token=$null; $body=$null; $headers=$null
    }
}
$settings = [pscustomobject]@{ projectId=$ProjectId; region=$Region; databaseHost=$DatabaseHost; databaseName=$DatabaseName;
    databaseUsername=$DatabaseUsername; databasePasswordSecret=$PasswordSecret; databasePasswordVersion=[string]$version; frontendOrigin=$FrontendOrigin.TrimEnd('/') }
$file = Join-Path $script:CloudLocal 'cloud-settings.json'
$settings | ConvertTo-Json | Set-Content -LiteralPath $file -Encoding UTF8
Get-LedgerCloudSettings -Path $file | Out-Null
Write-Host 'Cloud settings saved without the password. Run .\publish.ps1 to deploy the server.'
