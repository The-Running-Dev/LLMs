Describe 'Workspace MCP profile contract' {
    It 'includes setup flags for optional Context7 and Docker MCP profiles' {
        $setupText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../scripts/setup-workstation.ps1') -Raw
        $setupText | Should -Match 'IncludeContext7'
        $setupText | Should -Match 'IncludeDockerMcp'
    }

    It 'has installer scripts for the optional MCP profiles' {
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../../scripts/workstation/install-context7-mcp.ps1') -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../../scripts/workstation/install-docker-mcp.ps1') -PathType Leaf) | Should -BeTrue
    }

    It 'documents the least-privilege MCP boundary and profile health checks' {
        $doctorText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../scripts/doctor-workstation.ps1') -Raw
        $specText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../docs/architecture/setup-specification.md') -Raw

        $doctorText | Should -Match 'context7'
        $doctorText | Should -Match 'docker'
        $specText | Should -Match 'Context7 MCP'
        $specText | Should -Match 'Docker MCP'
        $specText | Should -Match 'MCP tool plane'
    }
    It 'allows optional profiles to be absent without failing in JSON mode' {
        $doctorScript = Join-Path $PSScriptRoot '../../scripts/doctor-workstation.ps1'
        $fakeBin = Join-Path $TestDrive 'bin'
        $codexShim = Join-Path $fakeBin 'codex.ps1'
        $dockerShim = Join-Path $fakeBin 'docker.ps1'
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source

        New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
        $codexOutput = @'
Write-Output 'github'
Write-Output 'playwright'
Write-Output 'filesystem'
'@
        Set-Content -LiteralPath $codexShim -Value $codexOutput
        Set-Content -LiteralPath $dockerShim -Value 'exit 0'

        $command = "`$env:PATH = '$($fakeBin.Replace("'", "''"))' + [IO.Path]::PathSeparator + `$env:PATH; & '$($doctorScript.Replace("'", "''"))' -Client Codex -AsJson"
        $output = & $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command $command
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 0
        $parsed = ($output -join [Environment]::NewLine) | ConvertFrom-Json
        @($parsed).Count | Should -Be 5
        @($parsed | Where-Object { $_.status -eq 'missing' }).Count | Should -Be 2
    }

    It 'returns a failing exit code for unhealthy profiles in JSON mode' {
        $doctorScript = Join-Path $PSScriptRoot '../../scripts/doctor-workstation.ps1'
        $fakeBin = Join-Path $TestDrive 'bin'
        $codexShim = Join-Path $fakeBin 'codex.ps1'
        $pwsh = (Get-Command pwsh -ErrorAction Stop).Source

        New-Item -ItemType Directory -Path $fakeBin -Force | Out-Null
        Set-Content -LiteralPath $codexShim -Value "'No MCP servers registered.'"

        $command = "`$env:PATH = '$($fakeBin.Replace("'", "''"))' + [IO.Path]::PathSeparator + `$env:PATH; & '$($doctorScript.Replace("'", "''"))' -Client Codex -AsJson"
        $output = & $pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass -Command $command
        $exitCode = $LASTEXITCODE

        $exitCode | Should -Be 1
        $parsed = ($output -join [Environment]::NewLine) | ConvertFrom-Json
        @($parsed).Count | Should -Be 5
        @($parsed | Where-Object { $_.status -eq 'missing' }).Count | Should -Be 5
    }
}
