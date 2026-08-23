Describe 'Embeddings contract file' {
    It 'defines dimension and normalization behavior' {
        $contractPath = Join-Path $PSScriptRoot '../config/embeddings-contract.example.json'
        $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

        $contract.route | Should -Be 'embeddings'
        $contract.vector.dimension | Should -Be 8
        $contract.vector.normalized | Should -BeFalse
    }
}
