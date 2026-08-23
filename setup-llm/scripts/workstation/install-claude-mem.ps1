[CmdletBinding(SupportsShouldProcess)]
param()
$modulePath = Join-Path $PSScriptRoot '../modules/Setup.psm1'
Import-Module $modulePath -Force

Write-Step 'Installing optional third-party claude-mem'
Assert-CommandAvailable -Name 'node' -InstallHint 'Install the current Node.js LTS release first.'
Assert-CommandAvailable -Name 'npm' -InstallHint 'Install npm with the current Node.js LTS release first.'
Assert-CommandAvailable -Name 'claude' -InstallHint 'Install Claude Code first.'
$npmCommand = Get-NpmCommand

Write-WarningMessage 'claude-mem captures and stores coding-session activity. Review its privacy, storage, sync, and exclusion settings before private-repository use.'

function Invoke-ClaudeMemCommand {
    param(
        [Parameter(Mandatory)][string]$NodePath,
        [Parameter(Mandatory)][string]$Entrypoint,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    $commandOutput = [System.Collections.Generic.List[string]]::new()
    # claude-mem only prompts when stdin is a TTY, so piping stdin keeps it non-interactive.
    '' | & $NodePath $Entrypoint @ArgumentList 2>&1 | ForEach-Object {
        $line = [string]$_
        Write-Host $line
        $commandOutput.Add($line)
    }
    $outputText = $commandOutput -join [Environment]::NewLine

    # claude-mem exits 0 on several failures, so its output has to be inspected.
    # These patterns follow upstream wording and need review on version bumps.
    if ($LASTEXITCODE -ne 0 -or
        $outputText -match '(?i)installation cancelled|failed to start worker|"status"\s*:\s*"error"|health is unreachable') {
        throw "claude-mem $($ArgumentList -join ' ') failed: $($outputText.Trim())"
    }
}

function Get-AvailableWorkerPort {
    foreach ($port in 37700..37799) {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
        try {
            $listener.Start()
            $listener.Stop()
            return $port
        }
        catch { continue }
    }

    throw 'No free TCP port was available in the claude-mem worker range (37700-37799).'
}

function Set-ClaudeMemWorkerPort {
    param([Parameter(Mandatory)][int]$Port)

    $settingsPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.claude-mem/settings.json'
    $settings = if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    }
    else {
        [pscustomobject]@{}
    }

    $settings | Add-Member -NotePropertyName 'CLAUDE_MEM_WORKER_PORT' -NotePropertyValue "$Port" -Force

    $settingsDirectory = Split-Path -Parent $settingsPath
    if (-not (Test-Path -LiteralPath $settingsDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $settingsDirectory -Force
    }

    $settings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsPath -Encoding UTF8
}

if ($PSCmdlet.ShouldProcess('claude-mem', 'Install the official npm package globally')) {
    # npx/npm exec can intermittently omit the temporary package bin directory
    # on Windows. A global install creates a stable command shim that can also
    # be resolved by absolute path in the current PowerShell session.
    $npmInstallArguments = @($npmCommand.PrefixArguments) + @('install', '--global', 'claude-mem@latest')
    Invoke-NativeCommand -FilePath $npmCommand.FilePath -ArgumentList $npmInstallArguments
    Update-SessionPath
}

if (-not $WhatIfPreference) {
    $npmPrefixArguments = @($npmCommand.PrefixArguments) + @('prefix', '--global')
    $npmPrefix = (& $npmCommand.FilePath @npmPrefixArguments 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($npmPrefix)) {
        throw 'Could not determine the global npm prefix.'
    }

    # npm's generated Windows .cmd shim can double-quote `node` and fail with
    # '"node" is not recognized'. Invoke the package entry point through the
    # resolved Node executable instead. Account for npm's Windows and Unix
    # global package layouts.
    $nodeCommand = (Get-Command 'node' -ErrorAction Stop).Source
    $entrypointCandidates = @(
        (Join-Path $npmPrefix 'node_modules/claude-mem/dist/npx-cli/index.js'),
        (Join-Path $npmPrefix 'lib/node_modules/claude-mem/dist/npx-cli/index.js')
    )
    $claudeMemEntrypoint = $entrypointCandidates |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $claudeMemEntrypoint) {
        throw "claude-mem was installed, but its JavaScript entry point could not be found under: $npmPrefix"
    }

    # 'repair' only restores the plugin runtime, so it cannot replace 'install',
    # which is idempotent and is what registers the hooks.
    $installArguments = @('install', '--ide', 'claude-code', '--runtime', 'worker')

    if ($PSCmdlet.ShouldProcess('claude-mem', 'Install hooks and worker runtime')) {
        Invoke-ClaudeMemCommand -NodePath $nodeCommand -Entrypoint $claudeMemEntrypoint -ArgumentList $installArguments
    }

    if ($PSCmdlet.ShouldProcess('claude-mem worker', 'Start the local memory worker')) {
        try {
            Invoke-ClaudeMemCommand -NodePath $nodeCommand -Entrypoint $claudeMemEntrypoint -ArgumentList @('start')
        }
        catch {
            # A stale listener can hold the configured port even when no process owns it.
            $fallbackPort = Get-AvailableWorkerPort
            Write-WarningMessage "The claude-mem worker did not start ($_). Retrying on free port $fallbackPort."
            Set-ClaudeMemWorkerPort -Port $fallbackPort
            Invoke-ClaudeMemCommand -NodePath $nodeCommand -Entrypoint $claudeMemEntrypoint -ArgumentList @('start')
        }
    }
}
else {
    $null = $PSCmdlet.ShouldProcess('claude-mem', 'Install hooks and worker')
    $null = $PSCmdlet.ShouldProcess('claude-mem worker', 'Start the local memory worker')
}

if ($WhatIfPreference) {
    Write-Success 'claude-mem installation preview completed.'
}
else {
    Write-Success 'claude-mem installation finished and its worker was started. Restart Claude Code before testing it.'
}
