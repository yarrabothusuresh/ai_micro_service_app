Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:CloudRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$script:CloudLocal = Join-Path $script:CloudRoot '.local'

function Assert-LedgerCloudTarget {
    param([string]$ProjectId, [string]$Region)
    if ($ProjectId -ne 'ledgermanager') { throw 'This demo is scoped to the authorized GCP project ledgermanager.' }
    if ($Region -notmatch '^[a-z]+-[a-z]+[0-9]+$') { throw 'Invalid Cloud Run region.' }
    if (-not (Get-Command gcloud.cmd -ErrorAction SilentlyContinue)) { throw 'Install Google Cloud CLI and run gcloud auth login.' }
    New-Item -ItemType Directory -Force -Path $script:CloudLocal | Out-Null
}

function Invoke-LedgerGcloud {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$Capture)
    if ($Capture) { $output = @(& gcloud.cmd @Arguments); $exitCode = $LASTEXITCODE }
    else { & gcloud.cmd @Arguments | Out-Host; $exitCode = $LASTEXITCODE }
    if ($exitCode -ne 0) { throw ('gcloud failed: ' + ($Arguments[0..([Math]::Min(2, $Arguments.Count - 1))] -join ' ') + '. Review the error above.') }
    if ($Capture) { return ($output -join "`n").Trim() }
}

function Get-LedgerCloudSettings {
    param([string]$Path = (Join-Path $script:CloudLocal 'cloud-settings.json'))
    if (-not (Test-Path -LiteralPath $Path)) { throw 'Run .\configure-cloud.ps1 once to supply Neon connection settings and store its password securely.' }
    $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    foreach ($field in @('projectId','region','databaseHost','databaseName','databaseUsername','databasePasswordSecret','databasePasswordVersion','frontendOrigin')) {
        if (-not $settings.PSObject.Properties[$field] -or [string]::IsNullOrWhiteSpace([string]$settings.$field)) { throw "Cloud configuration is missing $field." }
    }
    Assert-LedgerCloudTarget -ProjectId $settings.projectId -Region $settings.region
    if ($settings.databaseHost -notmatch '^[a-zA-Z0-9.-]+\.neon\.tech$' -or $settings.databaseHost -match '[/:@]') { throw 'Use the Neon database hostname without a scheme, port, username or password.' }
    if ($settings.databaseName -notmatch '^[a-zA-Z0-9_-]{1,63}$') { throw 'Invalid database name.' }
    if ($settings.databasePasswordSecret -notmatch '^[a-zA-Z0-9_-]{1,255}$' -or [string]$settings.databasePasswordVersion -notmatch '^[1-9][0-9]*$') { throw 'Use a secret name and a pinned numeric secret version.' }
    $origin = [uri]$settings.frontendOrigin
    if ($origin.Scheme -ne 'https' -or $origin.UserInfo -or $origin.Query -or $origin.Fragment -or $origin.AbsolutePath -ne '/') { throw 'Frontend origin must be an HTTPS origin without a repository path.' }
    return $settings
}

function Get-LedgerDatabaseUrl {
    param([Parameter(Mandatory)]$Settings, [switch]$Direct)
    $hostName = $Settings.databaseHost
    if ($Direct) { $hostName = $hostName -replace '-pooler\.', '.' }
    return 'jdbc:postgresql://' + $hostName + ':5432/' + $Settings.databaseName + '?sslmode=verify-full&sslfactory=org.postgresql.ssl.DefaultJavaSSLFactory'
}

function Initialize-LedgerCloud {
    param([string]$ProjectId = 'ledgermanager', [string]$Region = 'us-east4')
    Assert-LedgerCloudTarget -ProjectId $ProjectId -Region $Region
    Write-Host "Preparing Cloud Run, builds and secret storage in $ProjectId / $Region..."
    Invoke-LedgerGcloud -Arguments @('services','enable','run.googleapis.com','cloudbuild.googleapis.com','artifactregistry.googleapis.com','secretmanager.googleapis.com','iam.googleapis.com','storage.googleapis.com',"--project=$ProjectId",'--quiet')
    $projectNumber = Invoke-LedgerGcloud -Arguments @('projects','describe',$ProjectId,'--format=value(projectNumber)','--quiet') -Capture
    $repository = 'ledger-demo'
    $existingRepositories = Invoke-LedgerGcloud -Arguments @('artifacts','repositories','list',"--project=$ProjectId","--location=$Region",'--format=value(name)','--quiet') -Capture
    $repositoryNames = @($existingRepositories -split '\s+' | ForEach-Object { ($_ -split '/')[-1] })
    if ($repositoryNames -notcontains $repository) {
        Invoke-LedgerGcloud -Arguments @('artifacts','repositories','create',$repository,'--repository-format=docker',"--location=$Region",'--description=Ledger Manager demo images',"--project=$ProjectId",'--quiet')
    }
    $accounts = @{}
    $existingAccounts = Invoke-LedgerGcloud -Arguments @('iam','service-accounts','list',"--project=$ProjectId",'--format=value(email)','--quiet') -Capture
    foreach ($role in @('build','rules','posting','ui','gateway')) {
        $name = 'ledger-' + $role
        $email = "$name@$ProjectId.iam.gserviceaccount.com"
        if (@($existingAccounts -split '\s+') -notcontains $email) {
            Invoke-LedgerGcloud -Arguments @('iam','service-accounts','create',$name,"--display-name=Ledger Manager $role","--project=$ProjectId",'--quiet')
        }
        $accounts[$role] = $email
    }
    $buildMember = 'serviceAccount:' + $accounts.build
    Invoke-LedgerGcloud -Arguments @('projects','add-iam-policy-binding',$ProjectId,"--member=$buildMember",'--role=roles/logging.logWriter','--condition=None','--quiet','--format=none')
    Invoke-LedgerGcloud -Arguments @('projects','add-iam-policy-binding',$ProjectId,"--member=$buildMember",'--role=roles/serviceusage.serviceUsageConsumer','--condition=None','--quiet','--format=none')
    Invoke-LedgerGcloud -Arguments @('artifacts','repositories','add-iam-policy-binding',$repository,"--location=$Region","--member=$buildMember",'--role=roles/artifactregistry.writer',"--project=$ProjectId",'--quiet','--format=none')
    $bucketName = "$ProjectId-$projectNumber-ledger-source-$Region"
    $buckets = Invoke-LedgerGcloud -Arguments @('storage','buckets','list',"--project=$ProjectId",'--format=value(name)','--quiet') -Capture
    if (@($buckets -split '\s+' | ForEach-Object { ($_.TrimEnd('/') -split '/')[-1] }) -notcontains $bucketName) {
        Invoke-LedgerGcloud -Arguments @('storage','buckets','create',"gs://$bucketName","--location=$Region",'--uniform-bucket-level-access','--public-access-prevention',"--project=$ProjectId",'--quiet')
    }
    Invoke-LedgerGcloud -Arguments @('storage','buckets','add-iam-policy-binding',"gs://$bucketName","--member=$buildMember",'--role=roles/storage.objectViewer',"--project=$ProjectId",'--quiet','--format=none')
    $prepared = [pscustomobject]@{ projectId=$ProjectId; projectNumber=$projectNumber; region=$Region; repository=$repository; sourceBucket=$bucketName; accounts=$accounts }
    $prepared | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $script:CloudLocal 'cloud-prepared.json') -Encoding UTF8
    Write-Host 'Cloud infrastructure preparation complete.'
    return $prepared
}

function Build-LedgerImage {
    param([Parameter(Mandatory)]$Prepared, [Parameter(Mandatory)][string]$Module, [Parameter(Mandatory)][string]$Tag)
    if ($Module -notin @('rules-service','posting-service','ui-service','gateway')) { throw 'Unknown application module.' }
    if ($Tag -notmatch '^[a-zA-Z0-9_.-]+$') { throw 'Invalid image tag.' }
    $image = $Prepared.region + '-docker.pkg.dev/' + $Prepared.projectId + '/' + $Prepared.repository + '/' + $Module + ':' + $Tag
    $buildAccount = 'projects/' + $Prepared.projectId + '/serviceAccounts/' + $Prepared.accounts.build
    Invoke-LedgerGcloud -Arguments @('builds','submit',$script:CloudRoot,('--config=' + (Join-Path $script:CloudRoot 'cloudbuild.yaml')),"--substitutions=_SERVICE=$Module,_IMAGE=$image","--service-account=$buildAccount",('--gcs-source-staging-dir=gs://' + $Prepared.sourceBucket + '/source'),('--project=' + $Prepared.projectId),'--quiet')
    return $image
}

function Publish-LedgerService {
    param([Parameter(Mandatory)]$Prepared, [Parameter(Mandatory)][string]$Name,
          [Parameter(Mandatory)][string]$Account, [Parameter(Mandatory)][string]$Image,
          [Parameter(Mandatory)][hashtable]$Environment, [string]$Memory='512Mi', [string]$PasswordSecret)
    # JSON is valid YAML. This avoids comma/ampersand shell quoting in environment values.
    $file = Join-Path $script:CloudLocal ($Name + '-environment.json')
    $Environment | ConvertTo-Json | Set-Content -LiteralPath $file -Encoding UTF8
    $arguments = @('run','deploy',$Name,"--image=$Image",('--project=' + $Prepared.projectId),('--region=' + $Prepared.region),
        '--platform=managed',"--service-account=$Account",'--port=8080','--cpu=1',"--memory=$Memory",'--min-instances=0','--max-instances=1',
        '--concurrency=10','--timeout=120s','--ingress=all','--no-allow-unauthenticated',"--env-vars-file=$file",'--labels=app=ledger-manager',
        '--startup-probe=httpGet.path=/actuator/health/liveness,httpGet.port=8080,initialDelaySeconds=0,timeoutSeconds=5,periodSeconds=10,failureThreshold=24', '--quiet')
    if ($PasswordSecret) { $arguments += "--set-secrets=DATABASE_PASSWORD=$PasswordSecret" }
    Invoke-LedgerGcloud -Arguments $arguments
    return Invoke-LedgerGcloud -Arguments @('run','services','describe',$Name,('--project=' + $Prepared.projectId),('--region=' + $Prepared.region),'--format=value(status.url)','--quiet') -Capture
}

function Grant-LedgerInvocation {
    param([Parameter(Mandatory)]$Prepared, [Parameter(Mandatory)][string]$Service, [Parameter(Mandatory)][string]$Member)
    Invoke-LedgerGcloud -Arguments @('run','services','add-iam-policy-binding',$Service,"--member=$Member",'--role=roles/run.invoker',('--project=' + $Prepared.projectId),('--region=' + $Prepared.region),'--quiet','--format=none')
}
