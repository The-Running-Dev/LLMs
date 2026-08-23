[CmdletBinding()]
param(
    [string]$ComposeFile = (Join-Path $PSScriptRoot '../compose.yaml'),
    [string]$EnvExampleFile = (Join-Path $PSScriptRoot '../.env.example'),
    [string]$EnvFile = (Join-Path $PSScriptRoot '../.env'),
    [string]$GitIgnoreFile = (Join-Path $PSScriptRoot '../.gitignore'),
    [string]$LocalInferenceTemplate = (Join-Path $PSScriptRoot '../config/local-inference.example.json'),
    [string]$StartScript = (Join-Path $PSScriptRoot './Start-LocalInference.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-PathExists {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw ('{0} is missing: {1}' -f $Label, $Path)
    }

    Write-Host ('[OK] ' + $Label + ' / ' + $Path) -ForegroundColor Green
}

function Assert-Match {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Text -notmatch $Pattern) {
        throw "Missing expected control: $Label"
    }

    Write-Host "[OK] $Label" -ForegroundColor Green
}

function Get-EnvironmentMap {
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

function Assert-SecretValue {
    param(
        [Parameter(Mandatory)][hashtable]$EnvMap,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not $EnvMap.ContainsKey($Key)) {
        throw "Missing required env key: $Key"
    }

    $value = [string]$EnvMap[$Key]
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Environment key '$Key' is empty."
    }

    if ($value -match '(?i)replace[_-]?me|changeme|example|your[_-]?key|todo') {
        throw "Environment key '$Key' is still a placeholder value."
    }

    Write-Host "[OK] Environment key '$Key' has a non-placeholder value." -ForegroundColor Green
}

function Assert-PlaceholderValue {
    param(
        [Parameter(Mandatory)][hashtable]$EnvMap,
        [Parameter(Mandatory)][string]$Key
    )

    if (-not $EnvMap.ContainsKey($Key)) {
        throw "Missing required env key in .env.example: $Key"
    }

    $value = [string]$EnvMap[$Key]
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Environment key '$Key' in .env.example is empty."
    }

    if ($value -notmatch '(?i)replace[_-]?me|changeme|example|your[_-]?key|todo') {
        throw "Environment key '$Key' in .env.example should remain a placeholder."
    }

    Write-Host "[OK] Environment key '$Key' in .env.example is a placeholder as expected." -ForegroundColor Green
}

Write-Host 'Validating T8 operational controls...' -ForegroundColor Cyan

Assert-PathExists -Path $ComposeFile -Label 'Compose file'
Assert-PathExists -Path $EnvExampleFile -Label '.env.example'
Assert-PathExists -Path $GitIgnoreFile -Label '.gitignore'
Assert-PathExists -Path $LocalInferenceTemplate -Label 'local inference template'
Assert-PathExists -Path $StartScript -Label 'start script'

$composeText = Get-Content -LiteralPath $ComposeFile -Raw
$gitignoreText = Get-Content -LiteralPath $GitIgnoreFile -Raw
$envExampleMap = Get-EnvironmentMap -Path $EnvExampleFile
$startScriptText = Get-Content -LiteralPath $StartScript -Raw

Assert-Match -Text $composeText -Pattern 'gateway:\s*[\s\S]*ports:\s*[\s\S]*127\.0\.0\.1:\$\{GATEWAY_BIND_PORT:-4000\}:4000' -Label 'gateway bound to loopback host address'
Assert-Match -Text $composeText -Pattern 'open-webui:\s*[\s\S]*ports:\s*[\s\S]*127\.0\.0\.1:3001:8080' -Label 'Open WebUI bound to loopback host address'
Assert-Match -Text $composeText -Pattern 'open-webui:\s*[\s\S]*WEBUI_AUTH:\s*\$\{WEBUI_AUTH:-true\}' -Label 'Open WebUI auth enabled by default'
Assert-Match -Text $composeText -Pattern 'open-webui:\s*[\s\S]*WEBUI_SESSION_COOKIE_SAME_SITE:\s*\$\{WEBUI_SESSION_COOKIE_SAME_SITE:-strict\}' -Label 'Open WebUI session cookies use strict same-site by default'
Assert-Match -Text $composeText -Pattern 'open-webui:\s*[\s\S]*WEBUI_AUTH_COOKIE_SAME_SITE:\s*\$\{WEBUI_AUTH_COOKIE_SAME_SITE:-strict\}' -Label 'Open WebUI auth cookies use strict same-site by default'
Assert-Match -Text $composeText -Pattern 'open-webui:\s*[\s\S]*WEBUI_SECRET_KEY:\s*\$\{WEBUI_SECRET_KEY:\?Set WEBUI_SECRET_KEY in ai-cluster/\.env\}' -Label 'Open WebUI secret key required from environment'
Assert-Match -Text $composeText -Pattern 'open-webui:\s*[\s\S]*DEFAULT_USER_ROLE:\s*\$\{DEFAULT_USER_ROLE:-pending\}' -Label 'Open WebUI default user role is pending'
Assert-Match -Text $composeText -Pattern 'open-webui:\s*[\s\S]*ENABLE_PERSISTENT_CONFIG:\s*\$\{ENABLE_PERSISTENT_CONFIG:-false\}' -Label 'Open WebUI persistent config is disabled by default'
Assert-Match -Text $composeText -Pattern 'depends_on:\s*[\s\S]*coding-backend:\s*[\s\S]*condition:\s*service_healthy' -Label 'gateway depends on healthy coding backend'
Assert-Match -Text $composeText -Pattern 'depends_on:\s*[\s\S]*embeddings-backend:\s*[\s\S]*condition:\s*service_healthy' -Label 'gateway depends on healthy embeddings backend'
Assert-Match -Text $composeText -Pattern 'gateway:\s*[\s\S]*healthcheck:' -Label 'gateway has healthcheck'
Assert-Match -Text $composeText -Pattern 'coding-backend:\s*[\s\S]*healthcheck:' -Label 'coding backend has healthcheck'
Assert-Match -Text $composeText -Pattern 'embeddings-backend:\s*[\s\S]*healthcheck:' -Label 'embeddings backend has healthcheck'

Assert-Match -Text $startScriptText -Pattern "'--metrics'" -Label 'local inference starts with metrics enabled'

Assert-Match -Text $gitignoreText -Pattern '(?m)^\.env\r?$' -Label '.env ignored from source control'
Assert-Match -Text $gitignoreText -Pattern '(?m)^state/\r?$' -Label 'state directory ignored'
Assert-Match -Text $gitignoreText -Pattern '(?m)^logs/\r?$' -Label 'logs directory ignored'

Assert-PlaceholderValue -EnvMap $envExampleMap -Key 'LITELLM_MASTER_KEY'
Assert-PlaceholderValue -EnvMap $envExampleMap -Key 'LOCAL_INFERENCE_API_KEY'
Assert-PlaceholderValue -EnvMap $envExampleMap -Key 'WEBUI_SECRET_KEY'

$templateConfig = Get-Content -LiteralPath $LocalInferenceTemplate -Raw | ConvertFrom-Json
if (-not $templateConfig.providers -or $templateConfig.providers.Count -lt 2) {
    throw 'local-inference.example.json must define at least coding and embeddings providers.'
}

foreach ($provider in $templateConfig.providers) {
    $providerName = [string]$provider.name
    $extraArgs = @($provider.extra_args)

    if (-not $extraArgs -or $extraArgs.Count -eq 0) {
        throw "Provider '$providerName' must define extra_args with safe defaults (for example, --no-webui)."
    }

    if ($extraArgs -contains '--log-verbose') {
        throw "Provider '$providerName' template enables verbose logs. Remove --log-verbose to avoid prompt-body logging risk."
    }

    Write-Host "[OK] Provider '$providerName' template avoids verbose prompt logging defaults." -ForegroundColor Green
}

if (Test-Path -LiteralPath $EnvFile -PathType Leaf) {
    $envMap = Get-EnvironmentMap -Path $EnvFile
    Assert-SecretValue -EnvMap $envMap -Key 'LITELLM_MASTER_KEY'
    Assert-SecretValue -EnvMap $envMap -Key 'LOCAL_INFERENCE_API_KEY'
}
else {
    Write-Host "[INFO] $EnvFile does not exist. Runtime secret-value validation skipped." -ForegroundColor Yellow
}

Write-Host '[OK] T8 operational controls validation passed.' -ForegroundColor Green
