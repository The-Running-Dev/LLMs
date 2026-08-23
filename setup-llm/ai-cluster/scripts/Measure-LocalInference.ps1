[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '../state/benchmark-skeleton.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $outputDirectory -Force
}

$benchmarkTemplate = [ordered]@{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString('o')
    host = $env:COMPUTERNAME
    providers = @(
        [ordered]@{
            name = 'coding'
            ttft_ms = $null
            prompt_tokens_per_sec = $null
            generation_tokens_per_sec = $null
            vram_peak_mb = $null
            ram_peak_mb = $null
        },
        [ordered]@{
            name = 'embeddings'
            tokens_per_sec = $null
            dimension = $null
            vram_peak_mb = $null
            ram_peak_mb = $null
        }
    )
}

if ($PSCmdlet.ShouldProcess($OutputPath, 'Write benchmark skeleton file')) {
    $benchmarkTemplate | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Host "Benchmark template written to $OutputPath" -ForegroundColor Green
}
