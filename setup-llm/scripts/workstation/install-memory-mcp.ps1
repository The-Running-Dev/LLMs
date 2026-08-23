[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Codex', 'ClaudeCode', 'Both')]
    [string]$Client = 'Both'
)

$modulePath = Join-Path $PSScriptRoot '../modules/Setup.psm1'
Import-Module $modulePath -Force

Write-Step 'Registering the optional shared Memory MCP server'
Write-WarningMessage 'Enable Memory MCP only when shared memory across multiple tools or agents is explicitly required.'
Assert-CommandAvailable -Name 'npx' -InstallHint 'Install the current Node.js LTS release first.'

$npxCommand = Get-NpxCommand
$serverArguments = $npxCommand.PrefixArguments + @('-y', '@modelcontextprotocol/server-memory')

if ($Client -in @('Codex', 'Both')) {
    Assert-CommandAvailable -Name 'codex' -InstallHint 'Install Codex or rerun with -Client ClaudeCode.'
    if (Test-McpServerRegistered -Client 'codex' -ServerName 'memory') {
        Write-WarningMessage 'Memory MCP is already registered in Codex; leaving the existing configuration unchanged.'
    }
    elseif ($PSCmdlet.ShouldProcess('Codex', 'Register Memory MCP server')) {
        Invoke-NativeCommand -FilePath 'codex' -ArgumentList (@('mcp', 'add', 'memory', '--', $npxCommand.FilePath) + $serverArguments)
    }
}

if ($Client -in @('ClaudeCode', 'Both')) {
    Assert-CommandAvailable -Name 'claude' -InstallHint 'Install Claude Code or rerun with -Client Codex.'
    if (Test-McpServerRegistered -Client 'claude' -ServerName 'memory') {
        Write-WarningMessage 'Memory MCP is already registered in Claude Code; leaving the existing configuration unchanged.'
    }
    elseif ($PSCmdlet.ShouldProcess('Claude Code', 'Register Memory MCP server')) {
        Invoke-NativeCommand -FilePath 'claude' -ArgumentList (@('mcp', 'add', '--scope', 'user', 'memory', '--', $npxCommand.FilePath) + $serverArguments)
    }
}

Write-Success 'Memory MCP registration finished.'
