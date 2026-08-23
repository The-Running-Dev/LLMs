Describe 'AI cluster setup/doctor entry points' {
    It 'includes opt-in setup and doctor scripts' {
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../../scripts/setup-ai-cluster.ps1') -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../../scripts/doctor-ai-cluster.ps1') -PathType Leaf) | Should -BeTrue
    }

    It 'keeps setup opt-in and non-default for model downloads' {
        $setupText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../scripts/setup-ai-cluster.ps1') -Raw

        $setupText | Should -Match 'opt-in'
        $setupText | Should -Match 'does not download models'
        $setupText | Should -Match 'InitializeEnv'
        $setupText | Should -Match 'InitializeLocalInferenceConfig'
    }

    It 'provides doctor controls for contracts and warning policy' {
        $doctorText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../scripts/doctor-ai-cluster.ps1') -Raw

        $doctorText | Should -Match 'RunContracts'
        $doctorText | Should -Match 'RunHardwareSmoke'
        $doctorText | Should -Match 'FailOnWarnings'
        $doctorText | Should -Match 'AsJson'
    }
}
