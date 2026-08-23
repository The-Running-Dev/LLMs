Describe 'Operational controls and diagnostics scripts' {
    It 'has the T8 operational validator script' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Test-OperationalControls.ps1'
        Test-Path -LiteralPath $scriptPath -PathType Leaf | Should -BeTrue
    }

    It 'has the T8 diagnostics script' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Get-AiClusterDiagnostics.ps1'
        Test-Path -LiteralPath $scriptPath -PathType Leaf | Should -BeTrue
    }

    It 'captures route/backend/status/latency/token coverage in diagnostics script' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Get-AiClusterDiagnostics.ps1'
        $text = Get-Content -LiteralPath $scriptPath -Raw

        $text | Should -Match 'coding_route_probe'
        $text | Should -Match 'backend'
        $text | Should -Match 'latency_ms'
        $text | Should -Match 'token_usage'
    }

    It 'includes placeholder-secret validation in operational controls script' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Test-OperationalControls.ps1'
        $text = Get-Content -LiteralPath $scriptPath -Raw

        $text | Should -Match 'placeholder'
        $text | Should -Match 'LITELLM_MASTER_KEY'
        $text | Should -Match 'LOCAL_INFERENCE_API_KEY'
        $text | Should -Match 'WEBUI_SECRET_KEY'
    }
}
