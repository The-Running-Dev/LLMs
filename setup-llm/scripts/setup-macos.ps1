[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Codex', 'ClaudeCode', 'Both')][string]$Client = 'Both',
    [switch]$SkipClaudeMem, [switch]$SkipGitHub, [switch]$SkipPlaywright, [switch]$SkipGraphify,
    [switch]$IncludeContext7, [switch]$IncludeMemoryMcp, [switch]$IncludeDockerMcp,
    [switch]$IncludeFilesystem, [string[]]$FilesystemPath = @(),
    [switch]$IncludeDatabase, [string]$DatabaseName, [string]$DatabaseCommand,
    [string[]]$DatabaseArgument = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'modules/Setup.psm1'
Import-Module $modulePath -Force

if (-not $IsMacOS) { throw 'setup-macos.ps1 can only run on macOS.' }
Assert-CommandAvailable 'brew' 'Install Homebrew from https://brew.sh, then rerun this setup.'

function Install-BrewCommand {
    param([string]$Command, [string]$Formula, [string]$DisplayName)

    Update-SessionPath

    if (Test-CommandAvailable $Command) { Write-Success "$DisplayName is already installed."; return }
    
    if ($PSCmdlet.ShouldProcess($DisplayName, "Install Homebrew formula $Formula")) {
        Invoke-NativeCommand 'brew' @('install', $Formula)
        Update-SessionPath
        Assert-CommandAvailable $Command "$DisplayName was installed, but '$Command' is not on PATH. Start a new shell and rerun."
    }
}

function Install-NpmCommand {
    param([string]$Command, [string]$Package, [string]$DisplayName)
    
    if (Test-CommandAvailable $Command) { Write-Success "$DisplayName is already installed."; return }
    
    if ($PSCmdlet.ShouldProcess($DisplayName, "Install npm package $Package globally")) {
        Invoke-NativeCommand 'npm' @('install', '--global', $Package)
        Update-SessionPath
        Assert-CommandAvailable $Command "$DisplayName was installed, but '$Command' is not on PATH. Start a new shell and rerun."
    }
}

Write-Step 'Installing macOS prerequisites with Homebrew and npm'
if (-not (Test-CommandAvailable 'node')) { Install-BrewCommand 'node' 'node' 'Node.js' }
if (-not (Test-CommandAvailable 'npm') -or -not (Test-CommandAvailable 'npx')) { Install-BrewCommand 'npm' 'node' 'Node.js LTS' }
Install-BrewCommand 'act' 'act' 'act local GitHub Actions runner'
if (-not $SkipGitHub) { Install-BrewCommand 'gh' 'gh' 'GitHub CLI' }
if (-not $SkipGraphify) { Install-BrewCommand 'uv' 'uv' 'Astral uv' }
if ($Client -in @('Codex', 'Both')) { Install-NpmCommand 'codex' '@openai/codex' 'Codex CLI' }
if ($Client -in @('ClaudeCode', 'Both')) { Install-NpmCommand 'claude' '@anthropic-ai/claude-code' 'Claude Code' }

if ($WhatIfPreference) {
    Write-WarningMessage 'Platform prerequisite preview complete. Shared integrations were not run because preview mode does not install missing commands.'
    
    return
}

$parameters = @{} + $PSBoundParameters

& (Join-Path $PSScriptRoot 'setup-workstation.ps1') @parameters
