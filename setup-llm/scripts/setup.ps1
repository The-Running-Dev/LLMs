[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Codex', 'ClaudeCode', 'Both')][string]$Client = 'Both',
    [switch]$SkipClaudeMem,
    [switch]$SkipGitHub,
    [switch]$SkipPlaywright,
    [switch]$SkipGraphify,
    [switch]$IncludeMemoryMcp,
    [switch]$IncludeFilesystem,
    [string[]]$FilesystemPath = @(),
    [switch]$IncludeDatabase,
    [string]$DatabaseName,
    [string]$DatabaseCommand,
    [string[]]$DatabaseArgument = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$platformScript = if ($PSVersionTable.PSVersion.Major -le 5 -or $IsWindows) {
    'setup-windows.ps1'
} elseif ($IsMacOS) {
    'setup-macos.ps1'
} elseif ($IsLinux) {
    'setup-ubuntu.ps1'
} else {
    throw 'Unsupported operating system. Run a platform setup script explicitly or install the prerequisites manually.'
}

$parameters = @{} + $PSBoundParameters
$parameters['WhatIf'] = $WhatIfPreference

& (Join-Path $PSScriptRoot $platformScript) @parameters
