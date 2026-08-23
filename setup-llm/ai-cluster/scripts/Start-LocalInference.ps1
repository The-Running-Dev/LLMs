[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot '../config/local-inference.json'),
    [string]$StatePath = (Join-Path $PSScriptRoot '../state'),
    [string]$LogsPath = (Join-Path $PSScriptRoot '../logs'),
    [switch]$ForceRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-OrCreateDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $item = New-Item -ItemType Directory -Path $Path -Force
    return (Resolve-Path -LiteralPath $item.FullName).Path
}

function Get-Sha256 {
    param([Parameter(Mandatory)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Test-ProviderHealth {
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$TimeoutSeconds = 4
    )

    try {
        $null = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds
        return $true
    }
    catch {
        return $false
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    $example = Join-Path $PSScriptRoot '../config/local-inference.example.json'
    throw "Local inference config is missing: $ConfigPath. Copy $example to local-inference.json and fill in real paths."
}

$resolvedState = Resolve-OrCreateDirectory -Path $StatePath
$resolvedLogs = Resolve-OrCreateDirectory -Path $LogsPath
$pidFile = Join-Path $resolvedState 'pids.json'

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not $config.providers -or $config.providers.Count -eq 0) {
    throw "No providers were defined in $ConfigPath"
}

$existingState = @{}
if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
    $prior = Get-Content -LiteralPath $pidFile -Raw | ConvertFrom-Json
    foreach ($entry in $prior.providers) {
        $existingState[$entry.name] = $entry
    }
}

$nextState = [ordered]@{
    version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    providers = @()
}

Write-Host 'Starting local inference providers...' -ForegroundColor Cyan
Write-Host "State directory: $resolvedState"
Write-Host "Logs directory:  $resolvedLogs"

foreach ($provider in $config.providers) {
    $name = [string]$provider.name
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw 'Each provider requires a non-empty name.'
    }

    $exePath = [string]$provider.executable_path
    $modelPath = [string]$provider.model_path
    $host = if ([string]::IsNullOrWhiteSpace([string]$provider.listen_host)) { '127.0.0.1' } else { [string]$provider.listen_host }
    $port = [int]$provider.port
    $healthPath = if ([string]::IsNullOrWhiteSpace([string]$provider.health_path)) { '/health' } else { [string]$provider.health_path }
    $apiKeyEnvVar = [string]$provider.api_key_env_var

    if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
        throw "Provider '$name' executable was not found: $exePath"
    }
    if (-not (Test-Path -LiteralPath $modelPath -PathType Leaf)) {
        throw "Provider '$name' model file was not found: $modelPath"
    }

    $expectedSha = [string]$provider.expected_sha256
    if (-not [string]::IsNullOrWhiteSpace($expectedSha) -and $expectedSha -notmatch 'replace_me') {
        $actualSha = Get-Sha256 -Path $modelPath
        if ($actualSha -ne $expectedSha.ToLowerInvariant()) {
            throw "Provider '$name' model hash mismatch for $modelPath"
        }
    }

    $apiKey = [Environment]::GetEnvironmentVariable($apiKeyEnvVar)
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "Provider '$name' requires environment variable '$apiKeyEnvVar' to be set."
    }

    $existingEntry = $existingState[$name]
    if ($null -ne $existingEntry -and $existingEntry.pid) {
        $existingPid = [int]$existingEntry.pid
        $existingProc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($null -ne $existingProc -and -not $ForceRestart) {
            Write-Host "Provider '$name' is already running (PID $existingPid). Use -ForceRestart to replace it." -ForegroundColor Yellow
            $nextState.providers += $existingEntry
            continue
        }

        if ($null -ne $existingProc -and $ForceRestart) {
            if ($PSCmdlet.ShouldProcess("PID $existingPid", "Restart provider '$name'")) {
                Stop-Process -Id $existingPid -ErrorAction Stop
            }
        }
    }

    $args = @(
        '--host', $host,
        '--port', "$port",
        '--model', $modelPath,
        '--api-key', $apiKey,
        '--metrics'
    )

    if ($provider.default_ctx) {
        $args += @('--ctx-size', "$([int]$provider.default_ctx)")
    }
    if ($provider.default_gpu_layers -ne $null) {
        $args += @('--n-gpu-layers', "$([int]$provider.default_gpu_layers)")
    }
    if ($provider.embeddings -eq $true) {
        $args += '--embeddings'
    }
    foreach ($extraArg in @($provider.extra_args)) {
        if (-not [string]::IsNullOrWhiteSpace([string]$extraArg)) {
            $args += [string]$extraArg
        }
    }

    $stdoutLog = Join-Path $resolvedLogs "$name.stdout.log"
    $stderrLog = Join-Path $resolvedLogs "$name.stderr.log"

    if ($PSCmdlet.ShouldProcess($name, 'Start local inference provider process')) {
        $process = Start-Process -FilePath $exePath -ArgumentList $args -RedirectStandardOutput $stdoutLog -RedirectStandardError $stderrLog -PassThru -WindowStyle Hidden

        $healthUrl = "http://$host:$port$healthPath"
        $healthy = $false
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            Start-Sleep -Seconds 1
            if (Test-ProviderHealth -Url $healthUrl) {
                $healthy = $true
                break
            }
            if ($process.HasExited) {
                break
            }
        }

        $nextState.providers += [ordered]@{
            name = $name
            pid = $process.Id
            executable_path = $exePath
            model_path = $modelPath
            endpoint = "http://$host:$port/v1"
            health_url = $healthUrl
            status = if ($healthy) { 'healthy' } else { 'starting' }
            started_at_utc = (Get-Date).ToUniversalTime().ToString('o')
            stdout_log = $stdoutLog
            stderr_log = $stderrLog
        }

        Write-Host "Started '$name' (PID $($process.Id), status: $($(if ($healthy) { 'healthy' } else { 'starting' })))." -ForegroundColor Green
    }
}

$nextState | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $pidFile -Encoding UTF8
Write-Host "Wrote provider state: $pidFile"
