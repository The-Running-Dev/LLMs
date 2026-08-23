Describe 'Autonomous orchestration contract' {
    It 'has the autonomous orchestration contract document' {
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../../docs/architecture/autonomous-orchestration-contract.md') -PathType Leaf) | Should -BeTrue
    }

    It 'has the autonomous orchestration contract validator' {
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../../scripts/Test-AutonomousOrchestrationContract.ps1') -PathType Leaf) | Should -BeTrue
    }

    It 'defines staged autonomy, approvals, and safe recovery controls' {
        $contractText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../docs/architecture/autonomous-orchestration-contract.md') -Raw

        $contractText | Should -Match 'Operator-only'
        $contractText | Should -Match 'Guarded execution'
        $contractText | Should -Match 'Approval Gates'
        $contractText | Should -Match 'CI and MCP Boundaries'
        $contractText | Should -Match 'Abort and Rollback'
        $contractText | Should -Match 'Observability and Data Handling'
        $contractText | Should -Match 'No autonomous executor is enabled'
    }

    It 'adds the validator to the AI cluster doctor contract suite' {
        $doctorText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../scripts/doctor-ai-cluster.ps1') -Raw

        $doctorText | Should -Match 'Test-AutonomousOrchestrationContract'
    }

    It 'treats a completed PowerShell validator as successful without using a native exit code' {
        $doctorText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../scripts/doctor-ai-cluster.ps1') -Raw
        $contractBlock = [regex]::Match($doctorText, '(?s)if \(\$RunContracts\) \{.*?\n\}\nelse \{').Value

        $contractBlock | Should -Match '\$testAutonomousOrchestration'
        $contractBlock | Should -Match '& \$scriptPath\s+Add-Check.*?Status ''ok'''
        $contractBlock | Should -Not -Match '\$LASTEXITCODE'
    }
}
