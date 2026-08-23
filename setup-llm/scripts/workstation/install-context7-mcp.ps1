[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Codex', 'ClaudeCode', 'Both')]
    [string]$Client = 'Both'
)

$modulePath = Join-Path $PSScriptRoot '../modules/Setup.psm1'
Import-Module $modulePath -Force

Write-Step 'Registering the optional Context7 MCP server'
Assert-CommandAvailable -Name 'npx' -InstallHint 'Install the current Node.js LTS release first.'

$npxCommand = Get-NpxCommand
$serverArguments = $npxCommand.PrefixArguments + @('-y', '@upstash/context7-mcp@latest')

if ($Client -in @('Codex', 'Both')) {
    Assert-CommandAvailable -Name 'codex' -InstallHint 'Install Codex or rerun with -Client ClaudeCode.'
    if (Test-McpServerRegistered -Client 'codex' -ServerName 'context7') {
        Write-WarningMessage 'Context7 MCP is already registered in Codex; leaving the existing configuration unchanged.'
    }
    elseif ($PSCmdlet.ShouldProcess('Codex', 'Register Context7 MCP server')) {
        Invoke-NativeCommand -FilePath 'codex' -ArgumentList (@('mcp', 'add', 'context7', '--', $npxCommand.FilePath) + $serverArguments)
    }
}

if ($Client -in @('ClaudeCode', 'Both')) {
    Assert-CommandAvailable -Name 'claude' -InstallHint 'Install Claude Code or rerun with -Client Codex.'
    if (Test-McpServerRegistered -Client 'claude' -ServerName 'context7') {
        Write-WarningMessage 'Context7 MCP is already registered in Claude Code; leaving the existing configuration unchanged.'
    }
    elseif ($PSCmdlet.ShouldProcess('Claude Code', 'Register Context7 MCP server')) {
        Invoke-NativeCommand -FilePath 'claude' -ArgumentList (@('mcp', 'add', '--scope', 'user', 'context7', '--', $npxCommand.FilePath) + $serverArguments)
    }
}

Write-Success 'Context7 MCP registration finished.'
