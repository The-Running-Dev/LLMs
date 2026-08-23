[CmdletBinding()]
param(
    [string]$ContractPath = (Join-Path $PSScriptRoot '../docs/architecture/autonomous-orchestration-contract.md')
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
        throw "Missing expected autonomous orchestration control: $Label"
    }

    Write-Host "[OK] $Label" -ForegroundColor Green
}

if (-not (Test-Path -LiteralPath $ContractPath -PathType Leaf)) {
    throw "Missing autonomous orchestration contract document: $ContractPath"
}

$contractText = Get-Content -LiteralPath $ContractPath -Raw

Assert-Match -Text $contractText -Pattern 'Operator-only' -Label 'operator-only stage documented'
Assert-Match -Text $contractText -Pattern 'Assisted' -Label 'assisted stage documented'
Assert-Match -Text $contractText -Pattern 'Guarded execution' -Label 'guarded execution stage documented'
Assert-Match -Text $contractText -Pattern 'Controlled automation' -Label 'controlled automation stage documented'
Assert-Match -Text $contractText -Pattern 'Approval Gates' -Label 'approval gates documented'
Assert-Match -Text $contractText -Pattern 'CI and MCP Boundaries' -Label 'CI and MCP boundaries documented'
Assert-Match -Text $contractText -Pattern 'Abort and Rollback' -Label 'abort and rollback semantics documented'
Assert-Match -Text $contractText -Pattern 'Observability and Data Handling' -Label 'redacted observability documented'
Assert-Match -Text $contractText -Pattern 'No autonomous executor is enabled' -Label 'default autonomy remains disabled'

Write-Host '[OK] Autonomous orchestration contract validation passed.' -ForegroundColor Green
