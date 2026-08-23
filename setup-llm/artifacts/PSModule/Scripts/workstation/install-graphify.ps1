[CmdletBinding(SupportsShouldProcess)]
param()
$modulePath = Join-Path $PSScriptRoot '../modules/Setup.psm1'
Import-Module $modulePath -Force

Write-Step 'Installing Graphify'

if (-not (Test-CommandAvailable -Name 'uv')) {
    Update-SessionPath
}

# In preview mode uv has intentionally not been installed, so commands that
# depend on it cannot be inspected or executed yet. Still include the remaining
# Graphify actions in the WhatIf output, then finish the preview successfully.
if ($WhatIfPreference -and -not (Test-CommandAvailable -Name 'uv')) {
    $null = $PSCmdlet.ShouldProcess('graphifyy', 'Install or upgrade uv tool')
    $null = $PSCmdlet.ShouldProcess('Detected coding assistants', 'Register the Graphify skill')
    Write-Success 'Preview complete. A real run will install uv before Graphify.'
    return
}

Assert-CommandAvailable -Name 'uv' -InstallHint 'Run the platform setup script to install uv, or install it from https://docs.astral.sh/uv/getting-started/installation/.'

if ($PSCmdlet.ShouldProcess('graphifyy', 'Install or upgrade uv tool')) {
    # uv tool install replaces an existing tool, while --upgrade refreshes its
    # package resolution. This covers both states without a separate list probe.
    Invoke-NativeCommand -FilePath 'uv' -ArgumentList @('tool', 'install', '--upgrade', 'graphifyy')
}


# When uv is already available but Graphify is not, WhatIf must not require the
# executable that the preview deliberately declined to install.
if ($WhatIfPreference -and -not (Test-CommandAvailable -Name 'graphify')) {
    $null = $PSCmdlet.ShouldProcess('Detected coding assistants', 'Register the Graphify skill')
    Write-Success 'Preview complete. A real run will install Graphify before registering its skill.'
    return
}

if (-not (Test-CommandAvailable -Name 'graphify')) {
    $uvToolBin = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local/bin'
    if (Test-Path -LiteralPath $uvToolBin) { $env:PATH = "$uvToolBin$([System.IO.Path]::PathSeparator)$env:PATH" }
}

Assert-CommandAvailable -Name 'graphify' -InstallHint 'Restart PowerShell so the uv tool directory is added to PATH.'
if ($PSCmdlet.ShouldProcess('Detected coding assistants', 'Register the Graphify skill')) {
    Invoke-NativeCommand -FilePath 'graphify' -ArgumentList @('install')
}

Write-Success 'Graphify is installed. In a repository, run /graphify . from a supported coding assistant.'
