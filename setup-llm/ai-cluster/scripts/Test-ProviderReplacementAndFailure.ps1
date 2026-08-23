[CmdletBinding()]
param(
    [string]$ComposeFile = (Join-Path $PSScriptRoot '../compose.yaml')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @()
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed: $FilePath $($ArgumentList -join ' ')"
    }
}

function Wait-ForHttp {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter()][hashtable]$Headers = @{},
        [int]$TimeoutSeconds = 90
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        try {
            $null = Invoke-WebRequest -Uri $Url -Headers $Headers -UseBasicParsing -TimeoutSec 3
            return
        }
        catch {
            Start-Sleep -Seconds 1
        }
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Timed out waiting for $Url"
}

function Invoke-Scenario {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$GatewayPort,
        [Parameter(Mandatory)][string]$CodingBaseUrl,
        [Parameter(Mandatory)][string[]]$Services,
        [Parameter(Mandatory)][scriptblock]$AssertBlock
    )

    $composePath = (Resolve-Path -LiteralPath $ComposeFile).Path
    $composeDir = Split-Path -Parent $composePath
    $projectName = "ai-cluster-t7-$Name"
    $tempEnvFile = Join-Path $composeDir ".env.$projectName"
    $composeEnvFile = Join-Path $composeDir '.env'
    $hadComposeEnv = Test-Path -LiteralPath $composeEnvFile -PathType Leaf
    $composeEnvBackup = Join-Path $composeDir ".env.$projectName.backup"

    $masterKey = "master-$([guid]::NewGuid().ToString('N'))"
    $backendKey = "backend-$([guid]::NewGuid().ToString('N'))"
    $webUiSecretKey = "webui-$([guid]::NewGuid().ToString('N'))"

    $envLines = @(
        "LITELLM_MASTER_KEY=$masterKey"
        "LOCAL_INFERENCE_API_KEY=$backendKey"
        "WEBUI_SECRET_KEY=$webUiSecretKey"
        "GATEWAY_BIND_PORT=$GatewayPort"
        "LOCAL_CODING_BASE_URL=$CodingBaseUrl"
        'LOCAL_EMBEDDINGS_BASE_URL=http://embeddings-backend:8082/v1'
    )

    $envLines | Set-Content -LiteralPath $tempEnvFile -Encoding UTF8
    if ($hadComposeEnv) {
        Copy-Item -LiteralPath $composeEnvFile -Destination $composeEnvBackup -Force
    }
    $envLines | Set-Content -LiteralPath $composeEnvFile -Encoding UTF8

    $baseComposeArgs = @(
        'compose',
        '--file', $composePath,
        '--project-name', $projectName,
        '--env-file', $tempEnvFile
    )

    Push-Location $composeDir
    try {
        try {
            & docker @($baseComposeArgs + @('down', '--volumes', '--remove-orphans')) *> $null
        }
        catch {
            Write-Warning "Scenario '$Name' pre-cleanup returned a non-fatal error: $_"
        }

        Invoke-CheckedCommand -FilePath 'docker' -ArgumentList ($baseComposeArgs + @('--profile', 'headless', '--profile', 'cloud', 'up', '-d') + $Services)

        $auth = @{ Authorization = "Bearer $masterKey" }
        Wait-ForHttp -Url "http://127.0.0.1:$GatewayPort/health" -Headers $auth

        & $AssertBlock $GatewayPort $masterKey
        Write-Host "[OK] Scenario '$Name' passed." -ForegroundColor Green
    }
    finally {
        try {
            Invoke-CheckedCommand -FilePath 'docker' -ArgumentList ($baseComposeArgs + @('down', '--volumes', '--remove-orphans'))
        }
        catch {
            Write-Warning "Scenario '$Name' cleanup failed: $_"
        }

        if (Test-Path -LiteralPath $tempEnvFile -PathType Leaf) {
            Remove-Item -LiteralPath $tempEnvFile -Force -ErrorAction SilentlyContinue
        }

        if ($hadComposeEnv) {
            if (Test-Path -LiteralPath $composeEnvBackup -PathType Leaf) {
                Move-Item -LiteralPath $composeEnvBackup -Destination $composeEnvFile -Force
            }
        }
        else {
            if (Test-Path -LiteralPath $composeEnvFile -PathType Leaf) {
                Remove-Item -LiteralPath $composeEnvFile -Force -ErrorAction SilentlyContinue
            }
        }

        Pop-Location
    }
}

if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is required for provider replacement/failure tests.'
}

# Scenario 1: same client request, default coding backend.
Invoke-Scenario -Name 'provider-default' -GatewayPort 4030 -CodingBaseUrl 'http://coding-backend:8081/v1' -Services @('gateway', 'coding-backend', 'embeddings-backend') -AssertBlock {
    param($gatewayPort, $masterKey)

    $auth = @{ Authorization = "Bearer $masterKey" }
    $body = @{ model = 'coding'; messages = @(@{ role = 'user'; content = 'switch-test' }) } | ConvertTo-Json -Depth 8
    $result = Invoke-RestMethod -Uri "http://127.0.0.1:$gatewayPort/v1/chat/completions" -Headers $auth -Method Post -ContentType 'application/json' -Body $body

    $content = [string]$result.choices[0].message.content
    if ($content -notmatch 'mock\[local-coding\]') {
        throw "Expected default provider identity in response, got: $content"
    }
}

# Scenario 2: same client request, alternate coding backend.
Invoke-Scenario -Name 'provider-alternate' -GatewayPort 4031 -CodingBaseUrl 'http://coding-backend-alt:8083/v1' -Services @('gateway', 'coding-backend', 'coding-backend-alt', 'embeddings-backend') -AssertBlock {
    param($gatewayPort, $masterKey)

    $auth = @{ Authorization = "Bearer $masterKey" }
    $body = @{ model = 'coding'; messages = @(@{ role = 'user'; content = 'switch-test' }) } | ConvertTo-Json -Depth 8
    $result = Invoke-RestMethod -Uri "http://127.0.0.1:$gatewayPort/v1/chat/completions" -Headers $auth -Method Post -ContentType 'application/json' -Body $body

    $content = [string]$result.choices[0].message.content
    if ($content -notmatch 'mock\[local-coding-alt\]') {
        throw "Expected alternate provider identity in response, got: $content"
    }
}

# Scenario 3: unreachable coding backend should fail (no silent cloud fallback).
Invoke-Scenario -Name 'failure-unreachable' -GatewayPort 4032 -CodingBaseUrl 'http://no-such-host.invalid:8099/v1' -Services @('gateway', 'coding-backend', 'embeddings-backend') -AssertBlock {
    param($gatewayPort, $masterKey)

    $auth = @{ Authorization = "Bearer $masterKey" }
    $body = @{ model = 'coding'; messages = @(@{ role = 'user'; content = 'should fail' }) } | ConvertTo-Json -Depth 8

    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:$gatewayPort/v1/chat/completions" -Headers $auth -Method Post -ContentType 'application/json' -Body $body -UseBasicParsing -TimeoutSec 30
        throw 'Expected request to fail when backend is unreachable.'
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -lt 400) {
            throw "Expected failure status for unreachable backend, got $status"
        }
    }
}

# Scenario 4: backend rate-limit propagation.
Invoke-Scenario -Name 'failure-rate-limit' -GatewayPort 4033 -CodingBaseUrl 'http://coding-backend-rate-limit:8084/v1' -Services @('gateway', 'coding-backend', 'coding-backend-rate-limit', 'embeddings-backend') -AssertBlock {
    param($gatewayPort, $masterKey)

    $auth = @{ Authorization = "Bearer $masterKey" }
    $body = @{ model = 'coding'; messages = @(@{ role = 'user'; content = 'rate limit test' }) } | ConvertTo-Json -Depth 8

    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:$gatewayPort/v1/chat/completions" -Headers $auth -Method Post -ContentType 'application/json' -Body $body -UseBasicParsing -TimeoutSec 30
        throw 'Expected rate-limited backend request to fail.'
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -ne 429) {
            throw "Expected 429 status from rate-limited backend, got $status"
        }
    }
}

# Scenario 5: malformed backend response should fail with normalized error status.
Invoke-Scenario -Name 'failure-malformed' -GatewayPort 4034 -CodingBaseUrl 'http://coding-backend-malformed:8085/v1' -Services @('gateway', 'coding-backend', 'coding-backend-malformed', 'embeddings-backend') -AssertBlock {
    param($gatewayPort, $masterKey)

    $auth = @{ Authorization = "Bearer $masterKey" }
    $body = @{ model = 'coding'; messages = @(@{ role = 'user'; content = 'malformed test' }) } | ConvertTo-Json -Depth 8

    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:$gatewayPort/v1/chat/completions" -Headers $auth -Method Post -ContentType 'application/json' -Body $body -UseBasicParsing -TimeoutSec 30
        throw 'Expected malformed backend response to fail.'
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -lt 400) {
            throw "Expected normalized failure status for malformed backend response, got $status"
        }
    }
}

Write-Host '[OK] Provider replacement and failure scenarios passed.' -ForegroundColor Green
