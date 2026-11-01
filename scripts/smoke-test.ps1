param([string]$GatewayUrl = 'http://localhost:8080')
$ErrorActionPreference = 'Stop'
# A fresh deployment can briefly return 503 while invocation grants propagate.
# Every retry uses the same body and idempotency key.
function Invoke-DemoRequest {
    param([Parameter(Mandatory)][hashtable]$Request)
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try { return Invoke-RestMethod @Request -TimeoutSec 120 }
        catch {
            $response = if ($_.Exception.PSObject.Properties['Response']) { $_.Exception.Response } else { $null }
            $status = if ($response) { [int]$response.StatusCode } else { 0 }
            if ($attempt -eq 4 -or $status -notin @(0,408,429,502,503,504)) { throw }
            Start-Sleep -Seconds (2 * $attempt)
        }
    }
}
$taskBase = $GatewayUrl.TrimEnd('/')
$taskKey = [guid]::NewGuid().ToString()
$taskBody = @{ reference = 'DEMO-' + (Get-Date -Format 'yyyyMMddHHmmss'); amount = '123.45'; currency = 'INR'; transactionType = 'SALE'; narration = 'Synthetic smoke test' } | ConvertTo-Json
$taskHeaders = @{ 'Idempotency-Key' = $taskKey }
$taskRequest = @{ Uri=($taskBase + '/api/postings'); Method='Post'; ContentType='application/json'; Headers=$taskHeaders; Body=$taskBody }
$taskFirst = Invoke-DemoRequest -Request $taskRequest
$taskReplay = Invoke-DemoRequest -Request $taskRequest
if ($taskFirst.id -ne $taskReplay.id) { throw 'Duplicate prevention failed.' }
if ($taskFirst.accountCode -ne 'DEMO-4001') { throw 'Account selection failed.' }
if ([string]::IsNullOrWhiteSpace($taskFirst.ruleId) -or [string]::IsNullOrWhiteSpace($taskFirst.ruleVersion)) { throw 'Saved rule audit is missing.' }
$taskSaved = Invoke-DemoRequest -Request @{ Uri=($taskBase + '/api/postings/' + $taskFirst.id) }
if ($taskSaved.id -ne $taskFirst.id -or $taskSaved.ruleVersion -ne $taskFirst.ruleVersion) { throw 'Saved posting could not be read with its decision audit.' }
$taskDashboard = Invoke-DemoRequest -Request @{ Uri=($taskBase + '/api/ui/dashboard') }
if ($taskDashboard.totalPostings -lt 1) { throw 'Dashboard did not return the saved posting.' }
Write-Output ('Passed: posting ' + $taskFirst.id + ', account ' + $taskFirst.accountCode + ', rule ' + $taskFirst.ruleVersion + ', retry returned the same posting, saved audit and dashboard loaded.')
