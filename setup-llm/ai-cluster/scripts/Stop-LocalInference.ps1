[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$StatePath = (Join-Path $PSScriptRoot '../state'),
    [string[]]$Provider = @(),
    [switch]$KeepStateFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedState = (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Path $StatePath -Force)).Path
$pidFile = Join-Path $resolvedState 'pids.json'

Write-Host 'Stopping local inference providers...' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $pidFile -PathType Leaf)) {
    Write-Host "No PID state file found at $pidFile"
    return
}

$pids = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json
$target = @($Provider)

foreach ($entry in $pids.providers) {
    if ($target.Count -gt 0 -and $entry.name -notin $target) { continue }
    if (-not $entry.pid) { continue }
    $processId = [int]$entry.pid
    $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue

    if ($null -eq $proc) {
        Write-Host "Provider '$($entry.name)' PID $processId is not running (stale state)." -ForegroundColor Yellow
        continue
    }

    if ($PSCmdlet.ShouldProcess("PID $processId", "Stop provider '$($entry.name)'")) {
        try {
            Stop-Process -Id $processId -ErrorAction Stop
            Write-Host "Stopped $($entry.name) (PID $processId)." -ForegroundColor Green
        }
        catch {
            Write-Warning "Could not stop $($entry.name) PID ${processId}: $_"
        }
    }
}

if (-not $KeepStateFile -and $PSCmdlet.ShouldProcess($pidFile, 'Remove provider state file')) {
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}
