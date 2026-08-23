[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Codex', 'ClaudeCode', 'Both')]
    [string]$Client = 'Both'
)
$modulePath = Join-Path $PSScriptRoot '../modules/Setup.psm1'
Import-Module $modulePath -Force

function Test-DockerEngineRunning {
    $serverVersion = & docker info --format '{{.ServerVersion}}' 2>$null
    return $LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($serverVersion | Out-String))
}

function Wait-DockerEngine {
    param([int]$TimeoutSeconds = 60)

    if (Test-DockerEngineRunning) { return }

    if (-not (Test-IsWindowsPlatform)) {
        throw 'The Docker CLI is installed, but its engine is not running. Start Docker Desktop (macOS) or the Docker service (Linux), then rerun the setup.'
    }

    $dockerDesktopPath = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe')
        (Join-Path $env:LOCALAPPDATA 'Docker\Docker Desktop.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if (-not $dockerDesktopPath) {
        throw 'The Docker CLI is installed, but Docker Desktop was not found. Start a Docker engine and rerun the setup.'
    }

    if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
        Write-WarningMessage 'The Docker engine is not running. Starting Docker Desktop...'
        Start-Process -FilePath $dockerDesktopPath -WindowStyle Hidden
    }
    else {
        Write-WarningMessage 'Docker Desktop is open, but its engine is not ready. Waiting for it to start...'
    }

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        if (Test-DockerEngineRunning) {
            Write-Success 'Docker engine is running.'
            return
        }
    } while ([DateTime]::UtcNow -lt $deadline)

    throw "Docker Desktop did not become ready within $TimeoutSeconds seconds. Open Docker Desktop, resolve any startup prompt or error, and rerun the setup."
}

function Test-DotEnvValueSet {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        if ($line -match "^\s*$([regex]::Escape($Name))\s*=\s*(.*)\s*$") {
            $value = $Matches[1].Trim()
            if ($value.Length -ge 2 -and (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))
            )) {
                $value = $value.Substring(1, $value.Length - 2).Trim()
            }
            return -not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch 'replace_me|your_token'
        }
    }
    return $false
}

function Remove-ClaudeMcpServerFromScope {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('local', 'user', 'project')][string]$Scope
    )

    $output = & claude mcp remove $Name --scope $Scope 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { return }
    if ($output -match '(?i)not found|does not exist|no .*MCP server.*found') { return }
    throw "Failed to remove Claude MCP server '$Name' from the $Scope scope: $($output.Trim())"
}

Write-Step "Installing GitHub's official MCP server"
Assert-CommandAvailable -Name 'docker' -InstallHint 'Install Docker Desktop and make sure it is running.'

$dockerRoot = Resolve-OrCreatePath -Path (Join-Path $PSScriptRoot '../../docker') -PathKind Directory
$composeFile = Join-Path $dockerRoot 'docker-compose.yml'
$envFile = Join-Path $dockerRoot '.env'
if (-not (Test-Path -LiteralPath $composeFile -PathType Leaf)) {
    throw "Docker Compose file is missing: $composeFile"
}
if (-not (Test-Path -LiteralPath $envFile -PathType Leaf)) {
    throw "Secrets file is missing: $envFile. Copy .env.example to .env and add a GitHub token."
}
if (-not (Test-DotEnvValueSet -Path $envFile -Name 'GITHUB_PERSONAL_ACCESS_TOKEN')) {
    throw "GITHUB_PERSONAL_ACCESS_TOKEN is empty or still contains a placeholder in $envFile. Add a narrowly scoped GitHub token and rerun the setup."
}
Write-Success "GitHub token configuration was found in the git-ignored .env file."

$composeArguments = @('compose', '--file', $composeFile, '--env-file', $envFile)

if ($PSCmdlet.ShouldProcess('github-mcp', 'Pull service image with Docker Compose')) {
    Wait-DockerEngine
    Invoke-NativeCommand -FilePath 'docker' -ArgumentList ($composeArguments + @('pull', 'github-mcp'))
}

$dockerArguments = @(
    'compose', '--file', $composeFile, '--env-file', $envFile,
    'run', '--rm', '-T', 'github-mcp'
)

if ($Client -in @('Codex', 'Both')) {
    Assert-CommandAvailable -Name 'codex' -InstallHint 'Install Codex or rerun with -Client ClaudeCode.'
    if ($PSCmdlet.ShouldProcess('Codex', 'Replace the GitHub MCP registration with Docker Compose')) {
        if (Test-McpServerRegistered -Client 'codex' -ServerName 'github') {
            Invoke-NativeCommand -FilePath 'codex' -ArgumentList @('mcp', 'remove', 'github')
        }
        Invoke-NativeCommand -FilePath 'codex' -ArgumentList (@('mcp', 'add', 'github', '--', 'docker') + $dockerArguments)
    }
}

if ($Client -in @('ClaudeCode', 'Both')) {
    Assert-CommandAvailable -Name 'claude' -InstallHint 'Install Claude Code or rerun with -Client Codex.'
    if ($PSCmdlet.ShouldProcess('Claude Code', 'Replace the GitHub MCP registration with Docker Compose')) {
        if (Test-McpServerRegistered -Client 'claude' -ServerName 'github') {
            foreach ($scope in @('local', 'user', 'project')) {
                Remove-ClaudeMcpServerFromScope -Name 'github' -Scope $scope
            }
        }
        Invoke-NativeCommand -FilePath 'claude' -ArgumentList (@('mcp', 'add', '--scope', 'user', 'github', '--', 'docker') + $dockerArguments)
    }
}

Write-Success "GitHub MCP reads its token from the git-ignored file: $envFile"
Write-Success 'GitHub MCP was installed in read-only mode with a limited toolset.'
