[CmdletBinding()]
param(
    [string]$ComposeFile = (Join-Path $PSScriptRoot '../compose.yaml'),
    [string]$EnvFile = (Join-Path $PSScriptRoot '../.env'),
    [int]$GatewayPort = 4000,
    [switch]$ProbeGateway,
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

        $key = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (-not [string]::IsNullOrWhiteSpace($key)) {
            $result[$key] = $value
        }
    }

    return $result
}

function Get-RedactedEnvSummary {
    param([Parameter(Mandatory)][hashtable]$EnvMap)

    $result = [ordered]@{}
    foreach ($key in ($EnvMap.Keys | Sort-Object)) {
        $value = [string]$EnvMap[$key]
        $isSecret = $key -match '(?i)key|token|secret|password'
        $isPlaceholder = $value -match '(?i)replace[_-]?me|changeme|example|your[_-]?key|todo'

        if ($isSecret) {
            $result[$key] = [ordered]@{
                is_set = -not [string]::IsNullOrWhiteSpace($value)
                length = if ([string]::IsNullOrWhiteSpace($value)) { 0 } else { $value.Length }
                placeholder = $isPlaceholder
                preview = if ([string]::IsNullOrWhiteSpace($value)) { '' } else { ($value.Substring(0, [Math]::Min(4, $value.Length)) + '...') }
            }
        }
        else {
            $result[$key] = [ordered]@{
                value = $value
                placeholder = $isPlaceholder
            }
        }
    }

    return $result
}

function Get-DockerServicesSnapshot {
    param([Parameter(Mandatory)][string]$ComposePath)

    $snapshot = @()
    if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
        return $snapshot
    }

    $composeDir = Split-Path -Parent $ComposePath
    Push-Location $composeDir
    try {
        $jsonLines = docker compose --file $ComposePath ps --format json 2>$null
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($jsonLines -join ''))) {
            return $snapshot
        }

        foreach ($line in $jsonLines) {
            if ([string]::IsNullOrWhiteSpace([string]$line)) {
                continue
            }

            $row = $line | ConvertFrom-Json
            $snapshot += [ordered]@{
                name = $row.Name
                service = $row.Service
                state = $row.State
                health = $row.Health
                ports = $row.Publishers
            }
        }
    }
    finally {
        Pop-Location
    }

    return $snapshot
}

function Invoke-GatewayProbe {
    param(
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][string]$MasterKey
    )

    $headers = @{ Authorization = "Bearer $MasterKey" }
    $result = [ordered]@{
        gateway_health = [ordered]@{}
        models = [ordered]@{}
        coding_route_probe = [ordered]@{}
    }

    $healthStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $healthResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -Headers $headers -UseBasicParsing -TimeoutSec 5
        $healthStopwatch.Stop()
        $result.gateway_health = [ordered]@{
            status_code = [int]$healthResponse.StatusCode
            latency_ms = [Math]::Round($healthStopwatch.Elapsed.TotalMilliseconds, 2)
        }
    }
    catch {
        $healthStopwatch.Stop()
        $result.gateway_health = [ordered]@{
            status_code = -1
            latency_ms = [Math]::Round($healthStopwatch.Elapsed.TotalMilliseconds, 2)
            error = $_.Exception.Message
        }
        return $result
    }

    $modelsStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $models = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/models" -Headers $headers -Method Get
    $modelsStopwatch.Stop()
    $result.models = [ordered]@{
        status = 'ok'
        latency_ms = [Math]::Round($modelsStopwatch.Elapsed.TotalMilliseconds, 2)
        count = if ($models.data) { [int]$models.data.Count } else { 0 }
    }

    $body = @{
        model = 'coding'
        messages = @(@{ role = 'user'; content = 'diagnostic token accounting request' })
        max_tokens = 24
    } | ConvertTo-Json -Depth 8

    $chatStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $chat = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/v1/chat/completions" -Headers $headers -Method Post -ContentType 'application/json' -Body $body
    $chatStopwatch.Stop()

    $assistantMessage = ''
    if ($chat.choices -and $chat.choices[0].message -and $chat.choices[0].message.content) {
        $assistantMessage = [string]$chat.choices[0].message.content
    }

    $backend = 'unknown'
    if ($assistantMessage -match '^([^:]+):') {
        $backend = $Matches[1]
    }

    $result.coding_route_probe = [ordered]@{
        route = 'coding'
        backend = $backend
        status = 'ok'
        latency_ms = [Math]::Round($chatStopwatch.Elapsed.TotalMilliseconds, 2)
        token_usage = [ordered]@{
            prompt_tokens = if ($chat.usage.prompt_tokens) { [int]$chat.usage.prompt_tokens } else { $null }
            completion_tokens = if ($chat.usage.completion_tokens) { [int]$chat.usage.completion_tokens } else { $null }
            total_tokens = if ($chat.usage.total_tokens) { [int]$chat.usage.total_tokens } else { $null }
        }
    }

    return $result
}

$composePath = (Resolve-Path -LiteralPath $ComposeFile).Path
$envMap = Get-EnvMap -Path $EnvFile
$diagnostics = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    compose_file = $composePath
    env_file_present = (Test-Path -LiteralPath $EnvFile -PathType Leaf)
    env = Get-RedactedEnvSummary -EnvMap $envMap
    docker_services = Get-DockerServicesSnapshot -ComposePath $composePath
    gateway_probe = [ordered]@{ status = 'not-run' }
    notes = @(
        'Diagnostic output is redacted and does not include raw secret values or prompt payloads.',
        'MCP access remains a separate authenticated tool plane from gateway bearer-key auth.'
    )
}

if ($ProbeGateway) {
    if (-not $envMap.ContainsKey('LITELLM_MASTER_KEY') -or [string]::IsNullOrWhiteSpace([string]$envMap['LITELLM_MASTER_KEY'])) {
        $diagnostics.gateway_probe = [ordered]@{
            status = 'skipped'
            reason = 'LITELLM_MASTER_KEY missing in .env'
        }
    }
    elseif ([string]$envMap['LITELLM_MASTER_KEY'] -match '(?i)replace[_-]?me|changeme|example|your[_-]?key|todo') {
        $diagnostics.gateway_probe = [ordered]@{
            status = 'skipped'
            reason = 'LITELLM_MASTER_KEY still placeholder in .env'
        }
    }
    else {
        try {
            $diagnostics.gateway_probe = Invoke-GatewayProbe -Port $GatewayPort -MasterKey ([string]$envMap['LITELLM_MASTER_KEY'])
        }
        catch {
            $diagnostics.gateway_probe = [ordered]@{
                status = 'error'
                error = $_.Exception.Message
            }
        }
    }
}

if ($AsJson) {
    $diagnostics | ConvertTo-Json -Depth 12
    return
}

Write-Host 'AI cluster diagnostics (redacted):' -ForegroundColor Cyan
Write-Host ("- Generated at: {0}" -f $diagnostics.generated_at_utc)
Write-Host ("- Compose file: {0}" -f $diagnostics.compose_file)
Write-Host ("- Env file present: {0}" -f $diagnostics.env_file_present)
Write-Host ("- Docker services observed: {0}" -f $diagnostics.docker_services.Count)

if ($ProbeGateway) {
    if ($diagnostics.gateway_probe.status -eq 'ok' -or $diagnostics.gateway_probe.coding_route_probe) {
        $routeProbe = $diagnostics.gateway_probe.coding_route_probe
        Write-Host ("- Gateway coding probe backend: {0}" -f $routeProbe.backend)
        Write-Host ("- Gateway coding probe latency ms: {0}" -f $routeProbe.latency_ms)
        Write-Host ("- Gateway coding probe total tokens: {0}" -f $routeProbe.token_usage.total_tokens)
    }
    else {
        Write-Host ("- Gateway probe status: {0}" -f $diagnostics.gateway_probe.status)
    }
}
