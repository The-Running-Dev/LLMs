[CmdletBinding()]
param(
    [string]$StatePath = (Join-Path $PSScriptRoot '../state'),
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-Health {
    param([Parameter(Mandatory)][string]$Url)

    try {
        $null = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
        return $true
    }
    catch {
        return $false
    }
}

$resolvedState = (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Path $StatePath -Force)).Path
$pidFile = Join-Path $resolvedState 'pids.json'
if (-not (Test-Path -LiteralPath $pidFile -PathType Leaf)) {
    Write-Host "No provider state file found at $pidFile"
    return
}

$state = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json
$result = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    providers = @()
}

foreach ($entry in $state.providers) {
    $pid = if ($entry.pid) { [int]$entry.pid } else { $null }
    $process = if ($pid) { Get-Process -Id $pid -ErrorAction SilentlyContinue } else { $null }
    $running = $null -ne $process
    $health = if ($entry.health_url) { Test-Health -Url ([string]$entry.health_url) } else { $false }

    $result.providers += [ordered]@{
        name = $entry.name
        pid = $pid
        running = $running
        healthy = $health
        endpoint = $entry.endpoint
        health_url = $entry.health_url
        stdout_log = $entry.stdout_log
        stderr_log = $entry.stderr_log
    }
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 8
    return
}

Write-Host 'Local inference status:' -ForegroundColor Cyan
foreach ($provider in $result.providers) {
    $status = if ($provider.running -and $provider.healthy) { 'healthy' } elseif ($provider.running) { 'running' } else { 'stopped' }
    Write-Host ("- {0}: {1} (PID {2})" -f $provider.name, $status, $provider.pid)
    Write-Host ("  endpoint: {0}" -f $provider.endpoint)
    Write-Host ("  health:   {0}" -f $provider.health_url)
}
