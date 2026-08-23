[CmdletBinding(SupportsShouldProcess)]
param()
$modulePath = Join-Path $PSScriptRoot '../modules/Setup.psm1'
Import-Module $modulePath -Force

function Get-ClaudeCodeCommandPath {
    $seenPaths = [System.Collections.Generic.HashSet[string]]::new((Get-PathComparer))

    foreach ($command in Get-Command 'claude' -All -ErrorAction SilentlyContinue) {
        if ($command.CommandType -notin @('Application', 'ExternalScript')) { continue }
        if ((Test-IsWindowsPlatform) -and
            [string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($command.Source))) {
            continue
        }
        if ($seenPaths.Add($command.Source)) { $command.Source }
    }
}

function Get-ClaudeCodeVersionInfo {
    param([Parameter(Mandatory)][string]$CommandPath)

    $output = & $CommandPath --version 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $versionMatch = [regex]::Match($output, '(\d+)\.(\d+)\.(\d+)')

    [pscustomobject]@{
        CommandPath = $CommandPath
        Output = $output.Trim()
        ExitCode = $exitCode
        Version = if ($versionMatch.Success) { [version]$versionMatch.Value } else { $null }
    }
}

function Get-ClaudeCodeVersionCandidate {
    foreach ($commandPath in Get-ClaudeCodeCommandPath) {
        try {
            $candidate = Get-ClaudeCodeVersionInfo -CommandPath $commandPath
            # A launcher that cannot run is skipped; one that runs but reports an
            # unrecognized version is still usable and handled by the caller.
            if ($candidate.ExitCode -eq 0) { $candidate }
        }
        catch {
            Write-WarningMessage "Could not inspect Claude Code candidate '$commandPath': $_"
        }
    }
}

function Test-GlobalNpmCommand {
    param([Parameter(Mandatory)][string]$CommandPath)

    if (-not (Test-CommandAvailable -Name 'npm')) { return $false }

    $npmCommand = Get-NpmCommand
    $npmPrefixArguments = @($npmCommand.PrefixArguments) + @('prefix', '--global')
    $npmPrefix = (& $npmCommand.FilePath @npmPrefixArguments 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($npmPrefix)) { return $false }

    $comparer = Get-PathComparer
    $commandDirectory = [System.IO.Path]::GetFullPath((Split-Path -Parent $CommandPath))

    foreach ($directory in @($npmPrefix, (Join-Path $npmPrefix 'bin'))) {
        if ($comparer.Equals($commandDirectory, [System.IO.Path]::GetFullPath($directory))) { return $true }
    }

    return $false
}

Write-Step 'Checking Claude Code built-in memory'
Update-SessionPath
$versionInfo = Get-ClaudeCodeVersionCandidate | Select-Object -First 1
if ($null -eq $versionInfo) {
    throw "No runnable Claude Code installation was found. Install or update Claude Code using Anthropic's current official installer, then rerun."
}

$minimumVersion = [version]'2.1.59'
Write-Host $versionInfo.Output

if ($null -eq $versionInfo.Version) {
    Write-WarningMessage "Could not parse the Claude Code version. Built-in auto-memory requires version $minimumVersion or later."
}
else {
    if ($versionInfo.Version -lt $minimumVersion) {
        Write-WarningMessage "Claude Code $($versionInfo.Version) is older than the required version $minimumVersion."

        Update-SessionPath
        $newerCandidate = Get-ClaudeCodeVersionCandidate |
            Where-Object { $_.Version -ge $minimumVersion } |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1

        if ($null -ne $newerCandidate -and $newerCandidate.CommandPath -ne $versionInfo.CommandPath) {
            if (-not $PSCmdlet.ShouldProcess($newerCandidate.CommandPath, "Use newer installed Claude Code $($newerCandidate.Version)")) {
                Write-WarningMessage 'The newer Claude Code installation was not selected, so built-in auto-memory cannot be verified.'
                return
            }

            Add-DirectoryToSessionPath -Directory (Split-Path -Parent $newerCandidate.CommandPath)
            $versionInfo = $newerCandidate
            Write-Host $versionInfo.Output
        }
        else {
            # 'install latest' migrates off the npm build, whose Windows post-install
            # child shell can fail to resolve node even when npm itself ran under node.
            $usesGlobalNpm = Test-GlobalNpmCommand -CommandPath $versionInfo.CommandPath
            $updateArguments = if ($usesGlobalNpm) { @('install', 'latest') } else { @('update') }
            $updateDescription = if ($usesGlobalNpm) {
                'Install the latest native Claude Code build from the resolved npm launcher'
            }
            else {
                'Run the Claude Code installer-aware updater'
            }

            if (-not $PSCmdlet.ShouldProcess($versionInfo.CommandPath, $updateDescription)) {
                Write-WarningMessage 'Claude Code was not updated, so built-in auto-memory cannot be verified.'
                return
            }

            Invoke-NativeCommand -FilePath $versionInfo.CommandPath -ArgumentList $updateArguments
            Update-SessionPath

            $versionInfo = Get-ClaudeCodeVersionCandidate |
                Sort-Object -Property Version -Descending |
                Select-Object -First 1
            if ($null -eq $versionInfo) {
                throw 'Claude Code was updated, but no runnable installation could be inspected afterward.'
            }

            Add-DirectoryToSessionPath -Directory (Split-Path -Parent $versionInfo.CommandPath)
            Write-Host $versionInfo.Output

            if ($null -eq $versionInfo.Version) {
                Write-WarningMessage "Could not parse the Claude Code version after updating. Built-in auto-memory requires version $minimumVersion or later."
                return
            }

            if ($versionInfo.Version -lt $minimumVersion) {
                throw "Claude Code still resolves to $($versionInfo.Version) at '$($versionInfo.CommandPath)' after updating. Remove or update the older installation that appears first on PATH."
            }
        }
    }

    Write-Success "Claude Code $($versionInfo.Version) supports built-in auto-memory."
}

Write-Host 'Inside each repository, run /init once to create project instructions.'
Write-Host 'Use /memory to inspect or toggle auto-memory and /context to verify what loaded.'
