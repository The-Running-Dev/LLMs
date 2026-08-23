[CmdletBinding()]
param(
    [switch]$RunContracts,
    [switch]$RunHardwareSmoke,
    [switch]$FailOnWarnings,
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-EnvMap {
    param([Parameter(Mandatory)][string]$Path)

    $result = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $result
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }

        $parts = $trimmed -split '=', 2
        if ($parts.Count -ne 2) {
            continue
        }

        $result[$parts[0].Trim()] = $parts[1].Trim()
    }

    return $result
}

function Test-PlaceholderValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    return ($Value -match '(?i)replace[_-]?me|changeme|example|your[_-]?key|todo')
}

function Add-Check {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('ok', 'warning', 'error', 'skipped')][string]$Status,
        [Parameter(Mandatory)][string]$Message
    )

    $script:checks += [ordered]@{
        name = $Name
        status = $Status
        message = $Message
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$clusterRoot = Join-Path $repoRoot 'ai-cluster'
$composeFile = Join-Path $clusterRoot 'compose.yaml'
$envFile = Join-Path $clusterRoot '.env'
$localInferenceConfig = Join-Path $clusterRoot 'config/local-inference.json'
$testAiCluster = Join-Path $clusterRoot 'scripts/Test-AiCluster.ps1'
$testOperationalControls = Join-Path $clusterRoot 'scripts/Test-OperationalControls.ps1'
$testGateway = Join-Path $clusterRoot 'scripts/Test-GatewayContract.ps1'
$testEmbeddings = Join-Path $clusterRoot 'scripts/Test-EmbeddingsContract.ps1'
$testProviderReplacement = Join-Path $clusterRoot 'scripts/Test-ProviderReplacementAndFailure.ps1'
$testAutonomousOrchestration = Join-Path $repoRoot 'scripts/Test-AutonomousOrchestrationContract.ps1'
$testHardwareSmoke = Join-Path $clusterRoot 'scripts/Test-HardwareSmoke.ps1'

$checks = @()

if (-not (Test-Path -LiteralPath $composeFile -PathType Leaf)) {
    Add-Check -Name 'compose-file' -Status 'error' -Message "Missing compose file: $composeFile"
}
else {
    Add-Check -Name 'compose-file' -Status 'ok' -Message 'compose.yaml found'
}

if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
    Add-Check -Name 'docker-cli' -Status 'warning' -Message 'Docker CLI not found; contract tests cannot run.'
}
else {
    Add-Check -Name 'docker-cli' -Status 'ok' -Message 'Docker CLI available'

    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        Add-Check -Name 'docker-engine' -Status 'warning' -Message 'Docker engine not reachable; start Docker Desktop or Docker Engine.'
    }
    else {
        Add-Check -Name 'docker-engine' -Status 'ok' -Message 'Docker engine reachable'
    }
}

if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    Add-Check -Name 'runtime-env' -Status 'warning' -Message '.env not found. Copy .env.example before running gateway contracts.'
}
else {
    $envMap = Get-EnvMap -Path $envFile
    $master = if ($envMap.ContainsKey('LITELLM_MASTER_KEY')) { [string]$envMap['LITELLM_MASTER_KEY'] } else { '' }
    $backend = if ($envMap.ContainsKey('LOCAL_INFERENCE_API_KEY')) { [string]$envMap['LOCAL_INFERENCE_API_KEY'] } else { '' }

    if (Test-PlaceholderValue -Value $master) {
        Add-Check -Name 'runtime-env-master-key' -Status 'warning' -Message 'LITELLM_MASTER_KEY is missing or placeholder in .env'
    }
    else {
        Add-Check -Name 'runtime-env-master-key' -Status 'ok' -Message 'LITELLM_MASTER_KEY looks configured'
    }

    if (Test-PlaceholderValue -Value $backend) {
        Add-Check -Name 'runtime-env-backend-key' -Status 'warning' -Message 'LOCAL_INFERENCE_API_KEY is missing or placeholder in .env'
    }
    else {
        Add-Check -Name 'runtime-env-backend-key' -Status 'ok' -Message 'LOCAL_INFERENCE_API_KEY looks configured'
    }
}

if (-not (Test-Path -LiteralPath $localInferenceConfig -PathType Leaf)) {
    Add-Check -Name 'local-inference-config' -Status 'warning' -Message 'local-inference.json not found. Create it from local-inference.example.json before host-native runs.'
}
else {
    Add-Check -Name 'local-inference-config' -Status 'ok' -Message 'local-inference.json found'
}

$mustRun = @($testAiCluster, $testOperationalControls)
foreach ($scriptPath in $mustRun) {
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Add-Check -Name ([IO.Path]::GetFileNameWithoutExtension($scriptPath)) -Status 'error' -Message "Missing script: $scriptPath"
        continue
    }

    try {
        & $scriptPath
        Add-Check -Name ([IO.Path]::GetFileNameWithoutExtension($scriptPath)) -Status 'ok' -Message 'Pass'
    }
    catch {
        Add-Check -Name ([IO.Path]::GetFileNameWithoutExtension($scriptPath)) -Status 'error' -Message $_.Exception.Message
    }
}

if ($RunContracts) {
    foreach ($scriptPath in @($testGateway, $testEmbeddings, $testProviderReplacement, $testAutonomousOrchestration)) {
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            Add-Check -Name ([IO.Path]::GetFileNameWithoutExtension($scriptPath)) -Status 'error' -Message "Missing script: $scriptPath"
            continue
        }

        try {
            & $scriptPath
            Add-Check -Name ([IO.Path]::GetFileNameWithoutExtension($scriptPath)) -Status 'ok' -Message 'Pass'
        }
        catch {
            Add-Check -Name ([IO.Path]::GetFileNameWithoutExtension($scriptPath)) -Status 'error' -Message $_.Exception.Message
        }
    }
}
else {
    Add-Check -Name 'contract-suite' -Status 'skipped' -Message 'Use -RunContracts to execute deterministic gateway/embeddings/provider contract tests.'
}

if ($RunHardwareSmoke) {
    if (-not (Test-Path -LiteralPath $testHardwareSmoke -PathType Leaf)) {
        Add-Check -Name 'hardware-smoke' -Status 'error' -Message "Missing script: $testHardwareSmoke"
    }
    else {
        try {
            & $testHardwareSmoke -Force
            if ($LASTEXITCODE -eq 0) {
                Add-Check -Name 'hardware-smoke' -Status 'ok' -Message 'Hardware smoke invocation completed.'
            }
            else {
                Add-Check -Name 'hardware-smoke' -Status 'error' -Message "Exited with code $LASTEXITCODE"
            }
        }
        catch {
            Add-Check -Name 'hardware-smoke' -Status 'error' -Message $_.Exception.Message
        }
    }
}
else {
    Add-Check -Name 'hardware-smoke' -Status 'skipped' -Message 'Use -RunHardwareSmoke to force hardware smoke checks.'
}

$summary = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    checks = $checks
    totals = [ordered]@{
        ok = @($checks | Where-Object { $_.status -eq 'ok' }).Count
        warning = @($checks | Where-Object { $_.status -eq 'warning' }).Count
        error = @($checks | Where-Object { $_.status -eq 'error' }).Count
        skipped = @($checks | Where-Object { $_.status -eq 'skipped' }).Count
    }
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-Host 'AI cluster doctor summary:' -ForegroundColor Cyan
    foreach ($entry in $checks) {
        $color = switch ($entry.status) {
            'ok' { 'Green' }
            'warning' { 'Yellow' }
            'error' { 'Red' }
            default { 'Gray' }
        }

        Write-Host ("[{0}] {1}: {2}" -f $entry.status.ToUpperInvariant(), $entry.name, $entry.message) -ForegroundColor $color
    }

    Write-Host ("Totals -> ok: {0}, warning: {1}, error: {2}, skipped: {3}" -f $summary.totals.ok, $summary.totals.warning, $summary.totals.error, $summary.totals.skipped)
}

$hasErrors = $summary.totals.error -gt 0
$hasWarnings = $summary.totals.warning -gt 0

if ($hasErrors -or ($FailOnWarnings -and $hasWarnings)) {
    exit 1
}

exit 0
