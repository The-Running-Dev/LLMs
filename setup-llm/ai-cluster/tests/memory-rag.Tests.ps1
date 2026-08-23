Describe 'Memory and RAG retention contract' {
    It 'has the memory/RAG contract document' {
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../../docs/architecture/memory-rag-contract.md') -PathType Leaf) | Should -BeTrue
    }

    It 'has the memory/RAG smoke test script' {
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot '../../scripts/Test-MemoryRagContract.ps1') -PathType Leaf) | Should -BeTrue
    }

    It 'documents retrieval, lifecycle, deletion, and safety controls' {
        $contractText = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../docs/architecture/memory-rag-contract.md') -Raw

        $contractText | Should -Match 'Retrieval Boundaries'
        $contractText | Should -Match 'Index Lifecycle'
        $contractText | Should -Match 'Migration Constraints'
        $contractText | Should -Match 'Privacy and Deletion Guarantees'
        $contractText | Should -Match 'Retrieval determinism'
        $contractText | Should -Match 'secret-shaped content'
    }
}
