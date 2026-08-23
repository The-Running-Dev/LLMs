[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Codex', 'ClaudeCode', 'Both')]
    [string]$Client = 'Both'
)

$modulePath = Join-Path $PSScriptRoot '../modules/Setup.psm1'
Import-Module $modulePath -Force

function Test-DockerEngineRunning {
    try {
        & docker info *> $null
        return $LASTEXITCODE -eq 0
    }
    catch {
        return $false
    }
}

Write-Step 'Registering the optional Docker MCP server'
Assert-CommandAvailable -Name 'docker' -InstallHint 'Install Docker Desktop or Docker Engine first.'

if (-not (Test-DockerEngineRunning)) {
    Write-WarningMessage 'Docker engine is not currently reachable; the Docker MCP profile will register only after the engine is running.'
}

$dockerArguments = @('mcp', 'gateway', 'run')

if ($Client -in @('Codex', 'Both')) {
    Assert-CommandAvailable -Name 'codex' -InstallHint 'Install Codex or rerun with -Client ClaudeCode.'
    if (Test-McpServerRegistered -Client 'codex' -ServerName 'docker') {
        Write-WarningMessage 'Docker MCP is already registered in Codex; leaving the existing configuration unchanged.'
    }
    elseif ($PSCmdlet.ShouldProcess('Codex', 'Register Docker MCP server')) {
        Invoke-NativeCommand -FilePath 'codex' -ArgumentList (@('mcp', 'add', 'docker', '--', 'docker') + $dockerArguments)
    }
}

if ($Client -in @('ClaudeCode', 'Both')) {
    Assert-CommandAvailable -Name 'claude' -InstallHint 'Install Claude Code or rerun with -Client Codex.'
    if (Test-McpServerRegistered -Client 'claude' -ServerName 'docker') {
        Write-WarningMessage 'Docker MCP is already registered in Claude Code; leaving the existing configuration unchanged.'
    }
    elseif ($PSCmdlet.ShouldProcess('Claude Code', 'Register Docker MCP server')) {
        Invoke-NativeCommand -FilePath 'claude' -ArgumentList (@('mcp', 'add', '--scope', 'user', 'docker', '--', 'docker') + $dockerArguments)
    }
}

Write-Success 'Docker MCP registration finished.'
