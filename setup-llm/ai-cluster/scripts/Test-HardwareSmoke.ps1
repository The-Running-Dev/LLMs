[CmdletBinding()]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$isCi = ($env:CI -eq 'true') -or ($env:GITHUB_ACTIONS -eq 'true')
$runFlag = $env:AI_CLUSTER_RUN_HARDWARE_SMOKE

if (-not $Force -and $isCi -and $runFlag -ne '1') {
    Write-Host '[SKIP] Hardware smoke requires host GPU/SYCL runtime and is disabled in standard CI.' -ForegroundColor Yellow
    Write-Host '[SKIP] Set AI_CLUSTER_RUN_HARDWARE_SMOKE=1 (or pass -Force locally) to run this suite.' -ForegroundColor Yellow
    exit 0
}

Write-Host '[INFO] Hardware smoke placeholder: run host-native SYCL checks and benchmark capture here.' -ForegroundColor Cyan
Write-Host '[INFO] Current implementation is intentionally non-blocking until hardware runners are configured.' -ForegroundColor Cyan
exit 0
