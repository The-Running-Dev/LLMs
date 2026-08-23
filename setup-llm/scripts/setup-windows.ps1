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

if (-not (Test-IsWindowsPlatform)) { throw 'setup-windows.ps1 can only run on Windows.' }

function Install-WingetCommand {
    param([string]$Command, [string]$PackageId, [string]$DisplayName)
    Update-SessionPath
    if (Test-CommandAvailable -Name $Command) { Write-Success "$DisplayName is already installed."; return }
    Assert-CommandAvailable -Name 'winget' -InstallHint "Install $DisplayName manually, then rerun the setup."
    if ($PSCmdlet.ShouldProcess($DisplayName, "Install Winget package $PackageId")) {
        Invoke-NativeCommand -FilePath 'winget' -ArgumentList @('install', '--id', $PackageId, '--exact', '--accept-package-agreements', '--accept-source-agreements')
        Update-SessionPath
        Assert-CommandAvailable -Name $Command -InstallHint "$DisplayName was installed, but '$Command' is not on PATH. Restart PowerShell and rerun."
    }
}

Write-Step 'Installing Windows prerequisites with Winget'
if (-not (Test-CommandAvailable 'node')) { Install-WingetCommand 'node' 'OpenJS.NodeJS.LTS' 'Node.js LTS' }
if (-not (Test-CommandAvailable 'npm') -or -not (Test-CommandAvailable 'npx')) { Install-WingetCommand 'npm' 'OpenJS.NodeJS.LTS' 'Node.js LTS' }
Install-WingetCommand 'act' 'nektos.act' 'act local GitHub Actions runner'
if ($Client -in @('Codex', 'Both')) { Install-WingetCommand 'codex' 'OpenAI.Codex' 'Codex CLI' }
if ($Client -in @('ClaudeCode', 'Both')) { Install-WingetCommand 'claude' 'Anthropic.ClaudeCode' 'Claude Code' }
if (-not $SkipGitHub) { Install-WingetCommand 'gh' 'GitHub.cli' 'GitHub CLI' }
if (-not $SkipGraphify) { Install-WingetCommand 'uv' 'astral-sh.uv' 'Astral uv' }

if ($WhatIfPreference) {
    Write-WarningMessage 'Platform prerequisite preview complete. Shared integrations were not run because preview mode does not install missing commands.'
    return
}

$parameters = @{} + $PSBoundParameters
& (Join-Path $PSScriptRoot 'setup-workstation.ps1') @parameters
