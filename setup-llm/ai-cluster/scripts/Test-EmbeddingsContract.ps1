[CmdletBinding()]
param(
    [string]$ComposeFile = (Join-Path $PSScriptRoot '../compose.yaml'),
    [string]$ContractFile = (Join-Path $PSScriptRoot '../config/embeddings-contract.example.json'),
    [string]$ProjectName = 'ai-cluster-embeddings-contract',
    [int]$GatewayPort = 4010
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

function Get-CosineSimilarity {
    param(
        [double[]]$A,
        [double[]]$B
    )

    if ($A.Count -ne $B.Count) {
        throw 'Vectors must have the same dimension for cosine similarity.'
    }

    $dot = 0.0
    $normA = 0.0
    $normB = 0.0
    for ($i = 0; $i -lt $A.Count; $i++) {
        $dot += $A[$i] * $B[$i]
        $normA += $A[$i] * $A[$i]
        $normB += $B[$i] * $B[$i]
    }

    if ($normA -eq 0 -or $normB -eq 0) {
        throw 'Zero-length vector norm encountered.'
    }

    return $dot / ([Math]::Sqrt($normA) * [Math]::Sqrt($normB))
}

if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker is required for embeddings contract tests.'
}

if (-not (Test-Path -LiteralPath $ContractFile -PathType Leaf)) {
    throw "Embeddings contract file was not found: $ContractFile"
}

$contract = Get-Content -LiteralPath $ContractFile -Raw | ConvertFrom-Json
$expectedDimension = [int]$contract.vector.dimension
$expectsNormalized = [bool]$contract.vector.normalized

$composePath = (Resolve-Path -LiteralPath $ComposeFile).Path
$composeDir = Split-Path -Parent $composePath
$tempEnvFile = Join-Path $composeDir '.env.embeddings-contract'
$composeEnvFile = Join-Path $composeDir '.env'
$hadComposeEnv = Test-Path -LiteralPath $composeEnvFile -PathType Leaf
$composeEnvBackup = Join-Path $composeDir '.env.embeddings-contract.backup'
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
        Write-Warning "Pre-cleanup before embeddings contract run returned a non-fatal error: $_"
    }

    Invoke-CheckedCommand -FilePath 'docker' -ArgumentList ($baseComposeArgs + @('--profile', 'headless', 'up', '-d', 'gateway', 'coding-backend', 'embeddings-backend'))

    $authHeader = @{ Authorization = "Bearer $masterKey" }
    Wait-ForHttp -Url "http://127.0.0.1:$GatewayPort/health" -Headers $authHeader

    $body = @{
        model = [string]$contract.route
        input = @('alpha', 'beta', 'alpha')
    } | ConvertTo-Json -Depth 8

    $response = Invoke-RestMethod -Uri "http://127.0.0.1:$GatewayPort/v1/embeddings" -Headers $authHeader -Method Post -ContentType 'application/json' -Body $body

    if (-not $response.data -or $response.data.Count -ne 3) {
        throw 'Expected exactly 3 embeddings from batch request.'
    }

    $first = [double[]]$response.data[0].embedding
    $second = [double[]]$response.data[1].embedding
    $third = [double[]]$response.data[2].embedding

    if ($first.Count -ne $expectedDimension) {
        throw "Expected embedding dimension $expectedDimension, got $($first.Count)."
    }

    $firstJson = $first | ConvertTo-Json -Compress
    $thirdJson = $third | ConvertTo-Json -Compress
    $secondJson = $second | ConvertTo-Json -Compress

    if ($firstJson -ne $thirdJson) {
        throw 'Determinism failure: identical inputs produced different embeddings.'
    }

    if ($firstJson -eq $secondJson) {
        throw 'Similarity sanity failure: distinct inputs produced identical embeddings.'
    }

    $selfCos = Get-CosineSimilarity -A $first -B $first
    $crossCos = Get-CosineSimilarity -A $first -B $second

    if ([Math]::Abs($selfCos - 1.0) -gt 0.000001) {
        throw "Expected self cosine similarity ~= 1.0, got $selfCos"
    }

    if ($crossCos -ge 0.9999) {
        throw "Expected non-identical cosine similarity below 0.9999, got $crossCos"
    }

    $norm = [Math]::Sqrt(($first | ForEach-Object { $_ * $_ } | Measure-Object -Sum).Sum)
    if ($expectsNormalized -and [Math]::Abs($norm - 1.0) -gt 0.01) {
        throw "Contract expects normalized vectors, but norm was $norm"
    }
    if (-not $expectsNormalized -and [Math]::Abs($norm - 1.0) -le 0.01) {
        throw "Contract expects non-normalized vectors, but norm was approximately 1.0 ($norm)"
    }

    Write-Host '[OK] Embeddings contract checks passed.' -ForegroundColor Green
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
