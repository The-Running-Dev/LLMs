[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Codex', 'ClaudeCode', 'Both')]
    [string]$Client = 'Both',

    [switch]$SkipClaudeMem,
    [switch]$SkipGitHub,
    [switch]$SkipPlaywright,
    [switch]$SkipGraphify,
    [switch]$IncludeContext7,
    [switch]$IncludeMemoryMcp,
    [switch]$IncludeDockerMcp,

    [switch]$IncludeFilesystem,
    [string[]]$FilesystemPath = @(),

    [switch]$IncludeDatabase,
    [string]$DatabaseName,
    [string]$DatabaseCommand,
    [string[]]$DatabaseArgument = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$componentRoot = Join-Path $PSScriptRoot 'workstation'

function Invoke-SetupScript {
    param(
        [Parameter(Mandatory)][string]$ScriptName,
        [Parameter()][hashtable]$Parameters = @{}
    )
    
    $scriptPath = Join-Path $componentRoot $ScriptName

    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "Setup component is missing: $scriptPath"
    }

    Write-Host "`nRunning $ScriptName" -ForegroundColor Magenta

    & $scriptPath @Parameters
}

if (-not $SkipGraphify) {
    Invoke-SetupScript -ScriptName 'install-graphify.ps1' -Parameters @{ WhatIf = $WhatIfPreference }
}

if ($Client -in @('ClaudeCode', 'Both')) {
    Invoke-SetupScript -ScriptName 'install-claude-memory.ps1' -Parameters @{ WhatIf = $WhatIfPreference }

    if (-not $SkipClaudeMem) {
        Invoke-SetupScript -ScriptName 'install-claude-mem.ps1' -Parameters @{ WhatIf = $WhatIfPreference }
    }
}

if (-not $SkipGitHub) {
    Invoke-SetupScript -ScriptName 'install-github-mcp.ps1' -Parameters @{ Client = $Client; WhatIf = $WhatIfPreference }
}

if (-not $SkipPlaywright) {
    Invoke-SetupScript -ScriptName 'install-playwright-mcp.ps1' -Parameters @{ Client = $Client; WhatIf = $WhatIfPreference }
}

if ($IncludeContext7) {
    Invoke-SetupScript -ScriptName 'install-context7-mcp.ps1' -Parameters @{ Client = $Client; WhatIf = $WhatIfPreference }
}

if ($IncludeMemoryMcp) {
    Invoke-SetupScript -ScriptName 'install-memory-mcp.ps1' -Parameters @{ Client = $Client; WhatIf = $WhatIfPreference }
}

if ($IncludeDockerMcp) {
    Invoke-SetupScript -ScriptName 'install-docker-mcp.ps1' -Parameters @{ Client = $Client; WhatIf = $WhatIfPreference }
}

if ($IncludeFilesystem) {
    if ($FilesystemPath.Count -eq 0) { throw '-IncludeFilesystem requires at least one -FilesystemPath.' }
    
    Invoke-SetupScript -ScriptName 'install-filesystem-mcp.ps1' -Parameters @{
        AllowedPath = $FilesystemPath; Client = $Client; WhatIf = $WhatIfPreference
    }
}

if ($IncludeDatabase) {
    if ([string]::IsNullOrWhiteSpace($DatabaseName) -or [string]::IsNullOrWhiteSpace($DatabaseCommand)) {
        throw '-IncludeDatabase requires -DatabaseName and -DatabaseCommand.'
    }
    
    Invoke-SetupScript -ScriptName 'install-database-mcp.ps1' -Parameters @{
        Name = $DatabaseName; Command = $DatabaseCommand; ServerArgument = $DatabaseArgument
        Client = $Client; WhatIf = $WhatIfPreference
    }
}

Write-Host "`nLLM workspace setup completed." -ForegroundColor Green
Write-Host 'Restart the configured clients and verify their MCP connections.'
Write-Host 'GitHub remains read-only and loads its token from setup-llm/docker/.env through Docker Compose.'
