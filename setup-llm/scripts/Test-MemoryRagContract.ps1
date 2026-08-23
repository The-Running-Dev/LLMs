[CmdletBinding()]
param(
    [string]$ContractPath = (Join-Path $PSScriptRoot '../docs/architecture/memory-rag-contract.md'),
    [string]$SetupGitIgnorePath = (Join-Path $PSScriptRoot '../.gitignore')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Match {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Text -notmatch $Pattern) {
        throw "Missing expected memory/RAG contract control: $Label"
    }

    Write-Host "[OK] $Label" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
    throw "Missing memory/RAG contract document: $ContractPath"
}

if (-not (Test-Path -LiteralPath $SetupGitIgnorePath -PathType Leaf)) {
    throw "Missing setup-level .gitignore: $SetupGitIgnorePath"
}

$contractText = Get-Content -LiteralPath $ContractPath -Raw
$gitignoreText = Get-Content -LiteralPath $SetupGitIgnorePath -Raw

Assert-Match -Text $contractText -Pattern 'Retrieval Boundaries' -Label 'retrieval boundaries documented'
Assert-Match -Text $contractText -Pattern 'Index Lifecycle' -Label 'index lifecycle documented'
Assert-Match -Text $contractText -Pattern 'Migration Constraints' -Label 'migration constraints documented'
Assert-Match -Text $contractText -Pattern 'Privacy and Deletion Guarantees' -Label 'privacy and deletion guarantees documented'
Assert-Match -Text $contractText -Pattern 'Retrieval determinism' -Label 'smoke tests include retrieval determinism'
Assert-Match -Text $contractText -Pattern 'secret-shaped content' -Label 'smoke tests include safety controls'
Assert-Match -Text $contractText -Pattern 'setup-llm/memory/' -Label 'memory artifacts ignored path documented'
Assert-Match -Text $contractText -Pattern 'setup-llm/rag-index/' -Label 'RAG index ignored path documented'
Assert-Match -Text $gitignoreText -Pattern '(?m)^memory/\r?$' -Label 'memory directory ignored'
Assert-Match -Text $gitignoreText -Pattern '(?m)^rag-index/\r?$' -Label 'rag-index directory ignored'
Assert-Match -Text $gitignoreText -Pattern '(?m)^rag-cache/\r?$' -Label 'rag-cache directory ignored'

Write-Host '[OK] Memory/RAG retention contract validation passed.' -ForegroundColor Green
