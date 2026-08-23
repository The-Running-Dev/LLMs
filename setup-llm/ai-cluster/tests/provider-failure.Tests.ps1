Describe 'Provider replacement and failure test surface' {
    It 'has the T7 script' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Test-ProviderReplacementAndFailure.ps1'
        Test-Path -LiteralPath $scriptPath -PathType Leaf | Should -BeTrue
    }

    It 'contains expected scenarios' {
        $scriptPath = Join-Path $PSScriptRoot '../scripts/Test-ProviderReplacementAndFailure.ps1'
        $text = Get-Content -LiteralPath $scriptPath -Raw

        $text | Should -Match "provider-default"
        $text | Should -Match "provider-alternate"
        $text | Should -Match "failure-unreachable"
        $text | Should -Match "failure-rate-limit"
        $text | Should -Match "failure-malformed"
    }
}
