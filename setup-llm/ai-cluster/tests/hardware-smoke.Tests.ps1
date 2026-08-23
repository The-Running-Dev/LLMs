Describe 'Hardware smoke test behavior' {
    It 'has hardware smoke script' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Test-HardwareSmoke.ps1'
        Test-Path -LiteralPath $scriptPath -PathType Leaf | Should -BeTrue
    }

    It 'documents explicit CI skip behavior' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Test-HardwareSmoke.ps1'
        $text = Get-Content -LiteralPath $scriptPath -Raw

        $text | Should -Match 'AI_CLUSTER_RUN_HARDWARE_SMOKE'
        $text | Should -Match '\[SKIP\]'
        $text | Should -Match 'disabled in standard CI'
    }
}
