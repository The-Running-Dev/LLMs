[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$InitializeEnv,
    [switch]$InitializeLocalInferenceConfig,
    [switch]$RunHeadlessConfigTest,
    [switch]$RunDoctor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$clusterRoot = Join-Path $repoRoot 'ai-cluster'
$composeFile = Join-Path $clusterRoot 'compose.yaml'
$envExample = Join-Path $clusterRoot '.env.example'
$envFile = Join-Path $clusterRoot '.env'
$localInferenceExample = Join-Path $clusterRoot 'config/local-inference.example.json'
$localInferenceConfig = Join-Path $clusterRoot 'config/local-inference.json'
$doctorScript = Join-Path $PSScriptRoot 'doctor-ai-cluster.ps1'
$testScript = Join-Path $clusterRoot 'scripts/Test-AiCluster.ps1'

if (-not (Test-Path -LiteralPath $composeFile -PathType Leaf)) {
    throw "AI cluster compose file was not found: $composeFile"
}
if (-not (Test-Path -LiteralPath $envExample -PathType Leaf)) {
    throw "AI cluster .env example was not found: $envExample"
}
if (-not (Test-Path -LiteralPath $localInferenceExample -PathType Leaf)) {
    throw "AI cluster local inference template was not found: $localInferenceExample"
}

Write-Host 'Preparing Local AI Compute Cluster (opt-in).' -ForegroundColor Cyan
Write-Host 'This entry point does not download models or modify default workstation setup.'

if ($InitializeEnv) {
    if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
        if ($PSCmdlet.ShouldProcess($envFile, 'Create from .env.example')) {
            Copy-Item -LiteralPath $envExample -Destination $envFile -Force
            Write-Host "[OK] Created $envFile from .env.example" -ForegroundColor Green
        }
    }
    else {
        Write-Host "[INFO] $envFile already exists; leaving it unchanged." -ForegroundColor Yellow
    }
}

if ($InitializeLocalInferenceConfig) {
    if (-not (Test-Path -LiteralPath $localInferenceConfig -PathType Leaf)) {
        if ($PSCmdlet.ShouldProcess($localInferenceConfig, 'Create from local-inference.example.json')) {
            Copy-Item -LiteralPath $localInferenceExample -Destination $localInferenceConfig -Force
            Write-Host "[OK] Created $localInferenceConfig from template" -ForegroundColor Green
        }
    }
    else {
        Write-Host "[INFO] $localInferenceConfig already exists; leaving it unchanged." -ForegroundColor Yellow
    }
}

if ($RunHeadlessConfigTest) {
    if ($WhatIfPreference) {
        Write-Host '[INFO] Skipping RunHeadlessConfigTest during -WhatIf preview.' -ForegroundColor Yellow
        Write-Host '[INFO] Re-run without -WhatIf to execute Test-AiCluster.' -ForegroundColor Yellow
    }

    if (-not $WhatIfPreference) {
    if (-not (Test-Path -LiteralPath $testScript -PathType Leaf)) {
        throw "Missing validation script: $testScript"
    }

    & $testScript
    if ($LASTEXITCODE -ne 0) {
        throw 'Test-AiCluster failed.'
    }
    }
}

if ($RunDoctor) {
    if (-not (Test-Path -LiteralPath $doctorScript -PathType Leaf)) {
        throw "Missing doctor script: $doctorScript"
    }

    & $doctorScript
    if ($LASTEXITCODE -ne 0) {
        throw 'doctor-ai-cluster reported errors.'
    }
}

Write-Host '[OK] AI cluster setup entry point completed.' -ForegroundColor Green
