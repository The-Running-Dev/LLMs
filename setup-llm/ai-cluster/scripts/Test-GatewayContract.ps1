[CmdletBinding()]
param(
    [string]$ComposeFile = (Join-Path $PSScriptRoot '../compose.yaml'),
    [string]$ProjectName = 'ai-cluster-contract',
    [int]$GatewayPort = 4000
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
        [hashtable]$Headers = @{},
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

function Remove-StaleComposeArtifacts {
    param([Parameter(Mandatory)][string]$ProjectName)

    # Recover from interrupted runs where containers survive detached from the compose network.
    $containerIds = @(docker ps -aq --filter "label=com.docker.compose.project=$ProjectName" 2>$null)
    foreach ($id in $containerIds) {
        if (-not [string]::IsNullOrWhiteSpace([string]$id)) {
            & docker rm -f $id *> $null
        }
    }

    $networkNames = @(
        "$ProjectName-ai-cluster-net"
        "$ProjectName`_ai-cluster-net"
    )

    foreach ($networkName in $networkNames) {
        & docker network rm $networkName *> $null
    }
}

if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is required for gateway contract tests.'
}

$composePath = (Resolve-Path -LiteralPath $ComposeFile).Path
$composeDir = Split-Path -Parent $composePath
$tempEnvFile = Join-Path $composeDir '.env.contract'
$composeEnvFile = Join-Path $composeDir '.env'
$hadComposeEnv = Test-Path -LiteralPath $composeEnvFile -PathType Leaf
$composeEnvBackup = Join-Path $composeDir '.env.contract.backup'
$masterKey = "master-$([guid]::NewGuid().ToString('N'))"
$backendKey = "backend-$([guid]::NewGuid().ToString('N'))"
$webUiSecretKey = "webui-$([guid]::NewGuid().ToString('N'))"

$envLines = @(
    "LITELLM_MASTER_KEY=$masterKey"
    "LOCAL_INFERENCE_API_KEY=$backendKey"
    "WEBUI_SECRET_KEY=$webUiSecretKey"
    "GATEWAY_BIND_PORT=$GatewayPort"
    'LOCAL_CODING_BASE_URL=http://coding-backend:8081/v1'
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
    '--project-name', $ProjectName,
    '--env-file', $tempEnvFile
)

Push-Location $composeDir
try {
    try {
        & docker @($baseComposeArgs + @('down', '--volumes', '--remove-orphans')) *> $null
    }
    catch {
        Write-Warning "Pre-cleanup before gateway contract run returned a non-fatal error: $_"
    }

    Remove-StaleComposeArtifacts -ProjectName $ProjectName

    Invoke-CheckedCommand -FilePath 'docker' -ArgumentList ($baseComposeArgs + @('--profile', 'headless', 'up', '-d', 'gateway', 'coding-backend', 'embeddings-backend'))

    $authHeader = @{ Authorization = "Bearer $masterKey" }
    Wait-ForHttp -Url "http://127.0.0.1:$GatewayPort/health" -Headers $authHeader -TimeoutSeconds 180

    $models = Invoke-RestMethod -Uri "http://127.0.0.1:$GatewayPort/v1/models" -Headers $authHeader -Method Get
    if (-not $models.data) { throw '/v1/models returned no model data.' }

    $modelIds = @($models.data | ForEach-Object { [string]$_.id })
    foreach ($requiredModel in @('coding', 'general', 'vision', 'multimodal', 'embeddings')) {
        if ($modelIds -notcontains $requiredModel) {
            throw "Expected model list to include alias '$requiredModel'."
        }
    }

    try {
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:$GatewayPort/v1/models" -UseBasicParsing -Method Get -TimeoutSec 5
        throw 'Unauthenticated /v1/models request unexpectedly succeeded.'
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -ne 401) {
            throw "Expected 401 for unauthenticated /v1/models, got: $($_.Exception.Message)"
        }
    }

    $chatBody = @{
        model = 'coding'
        messages = @(@{ role = 'user'; content = 'say hello' })
    } | ConvertTo-Json -Depth 8

    $chat = Invoke-RestMethod -Uri "http://127.0.0.1:$GatewayPort/v1/chat/completions" -Headers $authHeader -Method Post -ContentType 'application/json' -Body $chatBody
    if (-not $chat.choices -or -not $chat.choices[0].message.content) {
        throw 'Chat completion response did not include assistant content.'
    }

    $multimodalBody = @{
        model = 'vision'
        messages = @(
            @{
                role = 'user'
                content = @(
                    @{ type = 'text'; text = 'describe this image' },
                    @{ type = 'image_url'; image_url = @{ url = 'https://example.invalid/image.png' } }
                )
            }
        )
    } | ConvertTo-Json -Depth 8

    $multimodal = Invoke-RestMethod -Uri "http://127.0.0.1:$GatewayPort/v1/chat/completions" -Headers $authHeader -Method Post -ContentType 'application/json' -Body $multimodalBody
    if (-not $multimodal.choices -or -not $multimodal.choices[0].message.content) {
        throw 'Multimodal request did not return assistant content.'
    }
    if ($multimodal.choices[0].message.content -notmatch 'image_url') {
        throw 'Multimodal request did not preserve multimodal-shaped content through the gateway.'
    }

    $streamBody = @{
        model = 'coding'
        stream = $true
        messages = @(@{ role = 'user'; content = 'stream test' })
    } | ConvertTo-Json -Depth 8

    $streamResponse = Invoke-WebRequest -Uri "http://127.0.0.1:$GatewayPort/v1/chat/completions" -Headers $authHeader -Method Post -ContentType 'application/json' -Body $streamBody
    if ($streamResponse.Content -notmatch 'data:') {
        throw 'Streaming response did not contain expected SSE payload markers.'
    }

    $embeddingsBody = @{
        model = 'embeddings'
        input = @('alpha', 'beta')
    } | ConvertTo-Json -Depth 8

    $embeddings = Invoke-RestMethod -Uri "http://127.0.0.1:$GatewayPort/v1/embeddings" -Headers $authHeader -Method Post -ContentType 'application/json' -Body $embeddingsBody
    if (-not $embeddings.data -or $embeddings.data.Count -lt 2) {
        throw 'Embeddings response did not return expected vectors.'
    }

    try {
        $badBody = @{ model = 'unknown'; messages = @(@{ role = 'user'; content = 'x' }) } | ConvertTo-Json -Depth 8
        $null = Invoke-WebRequest -Uri "http://127.0.0.1:$GatewayPort/v1/chat/completions" -Headers $authHeader -Method Post -ContentType 'application/json' -Body $badBody
        throw 'Unknown model request unexpectedly succeeded.'
    }
    catch {
        if ($_.Exception.Response.StatusCode.value__ -lt 400) {
            throw "Expected normalized error status for unknown model, got: $($_.Exception.Message)"
        }
    }

    Write-Host '[OK] Gateway contract checks passed.' -ForegroundColor Green
}
finally {
    try {
        Invoke-CheckedCommand -FilePath 'docker' -ArgumentList ($baseComposeArgs + @('down', '--volumes', '--remove-orphans'))
    }
    catch {
        Write-Warning "docker compose down failed: $_"
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
