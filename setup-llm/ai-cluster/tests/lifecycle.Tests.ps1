Describe 'Local inference lifecycle and idempotency surface' {
    It 'includes lifecycle scripts' {
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../scripts/Start-LocalInference.ps1') -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../scripts/Stop-LocalInference.ps1') -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../scripts/Get-LocalInferenceStatus.ps1') -PathType Leaf) | Should -BeTrue
    }

    It 'exposes idempotent restart/keep-state controls' {
        $startText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../scripts/Start-LocalInference.ps1') -Raw
        $stopText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../scripts/Stop-LocalInference.ps1') -Raw

        $startText | Should -Match 'ForceRestart'
        $startText | Should -Match 'already running'
        $stopText | Should -Match 'KeepStateFile'
        $stopText | Should -Match 'stale state'
    }

    It 'parses local inference template with required provider fields' {
        $templatePath = Join-Path $PSScriptRoot '../config/local-inference.example.json'
        $cfg = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json

        $cfg.providers.Count | Should -BeGreaterThan 1

        foreach ($provider in $cfg.providers) {
            ([string]::IsNullOrWhiteSpace([string]$provider.name)) | Should -BeFalse
            ([string]::IsNullOrWhiteSpace([string]$provider.executable_path)) | Should -BeFalse
            ([string]::IsNullOrWhiteSpace([string]$provider.model_path)) | Should -BeFalse
            ($provider.port -gt 0) | Should -BeTrue
            ($provider.extra_args.Count -ge 1) | Should -BeTrue
        }
    }
}
