Describe 'AI cluster compose skeleton' {
    It 'has a compose file' {
        $composePath = Join-Path $PSScriptRoot '../compose.yaml'
        Test-Path -LiteralPath $composePath -PathType Leaf | Should -BeTrue
    }

    It 'renders headless config when docker is available' {
        if ($null -eq (Get-Command docker -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'Docker is not installed in this environment.'
            return
        }

        $composePath = Join-Path $PSScriptRoot '../compose.yaml'
        $composeDirectory = Split-Path -Parent $composePath
        $envExample = Join-Path $composeDirectory '.env.example'
        $envFile = Join-Path $composeDirectory '.env'
        $hadEnvFile = Test-Path -LiteralPath $envFile -PathType Leaf
        $envBackup = Join-Path $composeDirectory '.env.compose-test.backup'

        if ($hadEnvFile) {
            Copy-Item -LiteralPath $envFile -Destination $envBackup -Force
        }
        else {
            Copy-Item -LiteralPath $envExample -Destination $envFile -Force
        }

        Push-Location $composeDirectory
        try {
            docker compose --file $composePath --profile headless config *> $null
            $LASTEXITCODE | Should -Be 0
        }
        finally {
            Pop-Location
            if ($hadEnvFile) {
                if (Test-Path -LiteralPath $envBackup -PathType Leaf) {
                    Move-Item -LiteralPath $envBackup -Destination $envFile -Force
                }
            }
            else {
                if (Test-Path -LiteralPath $envFile -PathType Leaf) {
                    Remove-Item -LiteralPath $envFile -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    It 'preserves a pre-existing environment file during validation' {
        $testScript = Join-Path $PSScriptRoot '../scripts/Test-AiCluster.ps1'
        $composeDirectory = Join-Path $TestDrive 'compose-validation'
        $composePath = Join-Path $composeDirectory 'compose.yaml'
        $envExample = Join-Path $composeDirectory '.env.example'
        $envFile = Join-Path $composeDirectory '.env'
        $fakeBin = Join-Path $TestDrive 'bin'
        $dockerShim = Join-Path $fakeBin 'docker.ps1'
        $originalPath = $env:PATH
        $operatorEnv = 'OPERATOR_SECRET=preserve-me'

        New-Item -ItemType Directory -Path $composeDirectory, $fakeBin -Force | Out-Null
        Set-Content -LiteralPath $composePath -Value 'services: {}'
        Set-Content -LiteralPath $envExample -Value 'EXAMPLE_ONLY=true'
        Set-Content -LiteralPath $envFile -Value $operatorEnv
        Set-Content -LiteralPath $dockerShim -Value 'exit 0'

        try {
            $env:PATH = "$fakeBin$([IO.Path]::PathSeparator)$originalPath"
            & $testScript -ComposeFile $composePath

            $LASTEXITCODE | Should -Be 0
            (Get-Content -LiteralPath $envFile -Raw).Trim() | Should -Be $operatorEnv
        }
        finally {
            $env:PATH = $originalPath
        }
    }
}
