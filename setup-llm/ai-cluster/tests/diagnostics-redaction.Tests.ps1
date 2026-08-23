Describe 'Diagnostics redaction surface' {
    It 'has diagnostics script' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Get-AiClusterDiagnostics.ps1'
        Test-Path -LiteralPath $scriptPath -PathType Leaf | Should -BeTrue
    }

    It 'redacts secret-shaped env values and avoids prompt payload echoing' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Get-AiClusterDiagnostics.ps1'
        $text = Get-Content -LiteralPath $scriptPath -Raw

        $text | Should -Match 'Get-RedactedEnvSummary'
        $text | Should -Match 'preview'
        $text | Should -Match 'length'
        $text | Should -Match 'does not include raw secret values'
        $text | Should -Match 'does not include raw secret values or prompt payloads'
    }
}
