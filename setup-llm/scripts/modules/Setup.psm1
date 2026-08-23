#Requires -Version 5.1
<#
.SYNOPSIS
Setup module - Provides functions for creating and configuring new AI-assisted projects.

.DESCRIPTION
Modular PowerShell module for project creation, following docs/architecture/setup-specification.md.
Handles project structure, file generation, language starters, and validation.

.NOTES
This module is designed to work with setup-project.ps1 orchestrator script.
Contains shared utility and project setup functions in one module.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Test-CommandAvailable {
    param([Parameter(Mandatory)][string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-IsWindowsPlatform {
    # $IsWindows does not exist on PowerShell 5.1, so the version test must stay first.
    return $PSVersionTable.PSVersion.Major -le 5 -or $IsWindows
}

function Get-PathComparer {
    if (Test-IsWindowsPlatform) { return [System.StringComparer]::OrdinalIgnoreCase }
    return [System.StringComparer]::Ordinal
}

function Update-SessionPath {
    $separator = [System.IO.Path]::PathSeparator
    $persistentPaths = if (Test-IsWindowsPlatform) {
        @(
            [Environment]::GetEnvironmentVariable('Path', 'Machine')
            [Environment]::GetEnvironmentVariable('Path', 'User')
        )
    }
    else {
        @(
            (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.local/bin')
            '/opt/homebrew/bin'
            '/usr/local/bin'
            '/home/linuxbrew/.linuxbrew/bin'
        )
    }

    $seenPaths = [System.Collections.Generic.HashSet[string]]::new((Get-PathComparer))

    $mergedPaths = foreach ($source in @($persistentPaths) + @($env:PATH)) {
        foreach ($pathEntry in $source -split [regex]::Escape($separator)) {
            # Untrimmed entries would otherwise defeat deduplication and regrow PATH.
            $trimmedEntry = $pathEntry.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmedEntry) -and $seenPaths.Add($trimmedEntry)) {
                $trimmedEntry
            }
        }
    }

    $env:PATH = $mergedPaths -join $separator
}

function Add-DirectoryToSessionPath {
    param([Parameter(Mandatory)][string]$Directory)

    $separator = [System.IO.Path]::PathSeparator
    $comparer = Get-PathComparer
    $targetDirectory = $Directory.Trim()

    $remainingEntries = $env:PATH -split [regex]::Escape($separator) |
        ForEach-Object { $_.Trim() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and -not $comparer.Equals($_, $targetDirectory) }

    $env:PATH = (@($targetDirectory) + @($remainingEntries)) -join $separator
}

function Get-NpxCommand {
    if (Test-IsWindowsPlatform) {
        return @{ FilePath = 'cmd'; PrefixArguments = @('/c', 'npx') }
    }
    return @{ FilePath = 'npx'; PrefixArguments = @() }
}

function Get-NpmCommand {
    if (Test-IsWindowsPlatform) {
        $npmCommand = Get-Command 'npm.cmd' -ErrorAction Stop
        return @{ FilePath = $npmCommand.Source; PrefixArguments = @() }
    }
    return @{ FilePath = 'npm'; PrefixArguments = @() }
}

function Assert-CommandAvailable {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$InstallHint
    )
    if (-not (Test-CommandAvailable -Name $Name)) {
        throw "'$Name' was not found. $InstallHint"
    }
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter()][string[]]$ArgumentList = @()
    )
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $FilePath $($ArgumentList -join ' ')"
    }
}

function Test-McpServerRegistered {
    param(
        [Parameter(Mandatory)][ValidateSet('codex', 'claude')][string]$Client,
        [Parameter(Mandatory)][string]$ServerName
    )
    if (-not (Test-CommandAvailable -Name $Client)) { return $false }
    $output = & $Client mcp list 2>&1 | Out-String
    return $output -match "(?im)\b$([regex]::Escape($ServerName))\b"
}

function Resolve-OrCreatePath {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('Directory', 'File')][string]$PathKind
    )

    $expandedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    $pathExists = Test-Path -LiteralPath $expandedPath
    if (-not $pathExists) {
        if ($PathKind -eq 'Directory') {
            New-Item -ItemType Directory -Path $expandedPath -Force | Out-Null
        }
        else {
            $parentPath = Split-Path -Parent $expandedPath
            if ($parentPath -and -not (Test-Path -LiteralPath $parentPath -PathType Container)) {
                New-Item -ItemType Directory -Path $parentPath -Force | Out-Null
            }
            New-Item -ItemType File -Path $expandedPath -Force | Out-Null
        }

        $pathExists = Test-Path -LiteralPath $expandedPath
        if (-not $pathExists -and $WhatIfPreference) {
            return $expandedPath
        }
    }

    switch ($PathKind) {
        'Directory' {
            if (-not (Test-Path -LiteralPath $expandedPath -PathType Container)) {
                throw "Expected a directory path but found a non-directory item: $expandedPath"
            }
        }
        'File' {
            if (-not (Test-Path -LiteralPath $expandedPath -PathType Leaf)) {
                throw "Expected a file path but found a non-file item: $expandedPath"
            }
        }
    }

    (Resolve-Path -LiteralPath $expandedPath -ErrorAction Stop).Path
}


Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# Project Structure Functions
# ============================================================================

function New-ProjectStructure {
    <#
    .SYNOPSIS
    Creates the required project directory structure.
    
    .PARAMETER ProjectPath
    Absolute path where the project will be created.
    
    .PARAMETER Directories
    Array of directories to create (relative to ProjectPath).
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter()][string[]]$Directories = @('src', 'tests', 'docs/decisions', '.github')
    )

    foreach ($dir in $Directories) {
        $fullPath = Join-Path $ProjectPath $dir
        $null = New-Item -ItemType Directory -Path $fullPath -Force -ErrorAction SilentlyContinue
    }
}

function New-ProjectFile {
    <#
    .SYNOPSIS
    Creates a file in the project with the given content.
    
    .PARAMETER ProjectPath
    Base project path.
    
    .PARAMETER RelativePath
    Path relative to ProjectPath (e.g., 'README.md', 'src/index.js').
    
    .PARAMETER Content
    File content as string.
    
    .PARAMETER Force
    Overwrite existing file if $true.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$RelativePath,
        [Parameter(Mandatory)][string]$Content,
        [Parameter()][switch]$Force
    )

    $fullPath = Join-Path $ProjectPath $RelativePath
    $directory = Split-Path -Parent $fullPath
    
    if (-not (Test-Path $directory)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }

    if ((Test-Path $fullPath) -and -not $Force) {
        Write-WarningMessage "File already exists: $RelativePath (skipped)"
        return
    }

    Set-Content -Path $fullPath -Value $Content -Force
}

# ============================================================================
# File Generation Functions
# ============================================================================

function New-Gitignore {
    <#
    .SYNOPSIS
    Generates a project-appropriate .gitignore file.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter()][string]$Language = 'generic'
    )

    $content = @'
# Environment & secrets
.env
.env.local
.env.*.local
*.key
*.pem
secrets/

# IDE & build outputs
.vscode/
.idea/
.DS_Store
Thumbs.db

# Dependencies
node_modules/
__pycache__/
venv/
.venv/
*.egg-info/
dist/
build/

# Build outputs
bin/
obj/
.next/
out/
.pytest_cache/
coverage/
.nyc_output/

# Logs
*.log
npm-debug.log*
yarn-debug.log*

# Runtime
tmp/
cache/
.cache/
'@

    # Add language-specific entries
    switch ($Language) {
        'python' {
            $content += "`n# Python specific`nvenv/`n*.pyc`n.pytest_cache/`ndist/`nbuild/"
        }
        'node' {
            $content += "`n# Node specific`nnode_modules/`n.npm/`n.next/`nout/"
        }
        'csharp' {
            $content += "`n# C# specific`nbin/`nobj/`n*.user`n.vs/"
        }
        'java' {
            $content += "`n# Java specific`ntarget/`n.gradle/`nbuild/"
        }
        'rust' {
            $content += "`n# Rust specific`ntarget/`nCargo.lock"
        }
    }

    New-ProjectFile -ProjectPath $ProjectPath -RelativePath '.gitignore' -Content $content -Force
}

function New-EnvExample {
    <#
    .SYNOPSIS
    Generates .env.example template for configuration.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath
    )

    $content = @'
# Environment variables template
# Copy this file to .env and configure for local development
# Never commit .env to version control - it contains secrets

# Deployment environment
NODE_ENV=development
DEBUG=false

# Database (if applicable)
DATABASE_URL=postgresql://user:password@localhost:5432/myproject
DATABASE_POOL_SIZE=10

# API Configuration
API_KEY=your_api_key_here
API_SECRET=your_api_secret_here
API_BASE_URL=http://localhost:3000

# Logging
LOG_LEVEL=info

# Add project-specific variables below
'@

    New-ProjectFile -ProjectPath $ProjectPath -RelativePath '.env.example' -Content $content -Force
}

function New-ReadmeFile {
    <#
    .SYNOPSIS
    Generates README.md with language-appropriate build/test/run commands.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][hashtable]$Commands
    )

    $installCmd = $Commands['install']
    $buildCmd = $Commands['build']
    $testCmd = $Commands['test']
    $lintCmd = $Commands['lint']
    $runCmd = $Commands['run']

    $content = @"
# $ProjectName

Brief description of what this project does and its main purpose.

## Prerequisites

- [List required tools, frameworks, and versions]
- See [setup documentation](docs/setup.md) for detailed installation instructions

## Local Setup

1. **Clone the repository**
   \`\`\`bash
   git clone <repository-url>
   cd $ProjectName
   \`\`\`

2. **Install dependencies**
   \`\`\`bash
   $installCmd
   \`\`\`

3. **Configure environment**
   \`\`\`bash
   cp .env.example .env
   # Edit .env and add your configuration
   \`\`\`

4. **Additional setup** (if needed)
   - Database migrations
   - Service initialization
   - etc.

## Build

\`\`\`bash
$buildCmd
\`\`\`

## Test

\`\`\`bash
$testCmd
\`\`\`

## Lint

\`\`\`bash
$lintCmd
\`\`\`

## Run Locally

\`\`\`bash
$runCmd
\`\`\`

## Architecture

This project consists of:
- **src/** — Main source code
- **tests/** — Test suite
- **docs/** — Architecture and decision records

See [docs/architecture.md](docs/architecture.md) for detailed system design.

## Development Workflow

1. Create a feature branch
2. Make focused, atomic commits
3. Write or update tests for new functionality
4. Ensure all tests pass locally
5. Submit a pull request

See [AGENTS.md](AGENTS.md) and [CLAUDE.md](CLAUDE.md) for AI assistant guidelines.

## Contributing

Please read [AGENTS.md](AGENTS.md) for development conventions and workflow.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) for common issues and solutions.

## License

[Add license information]
"@

    New-ProjectFile -ProjectPath $ProjectPath -RelativePath 'README.md' -Content $content -Force
}

function New-ArchitectureFile {
    <#
    .SYNOPSIS
    Generates docs/architecture.md template.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ProjectName
    )

    $content = @"
# $ProjectName Architecture

**Last Updated:** $(Get-Date -Format 'yyyy-MM-dd')

## Overview

[Provide a high-level overview of the system's purpose and main responsibilities]

## System Architecture Diagram

\`\`\`
[Add ASCII diagram or describe the component relationships]
\`\`\`

## Core Components

### Component 1: [Name]
- **Purpose:** [What does it do?]
- **Responsibilities:** [Key duties]
- **Dependencies:** [What does it depend on?]
- **Technology:** [Tech stack]

### Component 2: [Name]
- **Purpose:** [What does it do?]
- **Responsibilities:** [Key duties]
- **Dependencies:** [What does it depend on?]
- **Technology:** [Tech stack]

[Add more components as needed]

## Data Flow

[Describe how data flows through the system]

Example:
1. User inputs data via API
2. Service validates and processes
3. Data persisted to database
4. Events published for downstream services

## External Integrations

- [Service 1]: [Purpose and API details]
- [Service 2]: [Purpose and API details]

## Deployment Architecture

[Describe how the system is deployed in production]

## Technology Stack

- **Language:** [e.g., Node.js, Python]
- **Framework:** [e.g., Express, FastAPI]
- **Database:** [e.g., PostgreSQL]
- **Caching:** [if applicable]
- **Message Queue:** [if applicable]
- **Hosting:** [e.g., Docker, Kubernetes, serverless]

## Scaling Considerations

[Describe how the system scales for increased load]

## Security Considerations

[Key security measures and threat model]

## Design Decisions

See [decisions/](decisions/) for Architecture Decision Records (ADRs) documenting major design choices.

## Future Improvements

- [Planned enhancement 1]
- [Planned enhancement 2]
"@

    New-ProjectFile -ProjectPath $ProjectPath -RelativePath 'docs/architecture.md' -Content $content -Force
}

function New-AdtTemplate {
    <#
    .SYNOPSIS
    Generates the ADR template file.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath
    )

    $date = Get-Date -Format 'yyyy-MM-dd'
    $content = @"
# ADR-0001: Project Setup and Initial Decisions

**Status:** Accepted  
**Date:** $date  
**Author:** [Your Name]  

## Context

What is the issue that we're seeing that is motivating this decision or change?

[Describe the background and context that led to this decision]

## Decision

What is the change that we're proposing and/or doing?

[Clearly state what decision was made]

## Rationale

Why is this decision the best choice given the context?

- [Reason 1]
- [Reason 2]
- [Reason 3]

## Consequences

What becomes easier or more difficult to do because of this change?

### Positive
- [Benefit 1]
- [Benefit 2]

### Negative
- [Trade-off 1]
- [Trade-off 2]

### Neutral
- [Neutral consequence]

## Alternatives Considered

- **Alternative 1:** [Description and why rejected]
- **Alternative 2:** [Description and why rejected]

## Related ADRs

- [Link to related ADR if any]

## References

- [Reference 1]
- [Reference 2]
"@

    New-ProjectFile -ProjectPath $ProjectPath -RelativePath 'docs/decisions/0001-initial-project-setup.md' -Content $content -Force
}

function New-ClaudeInstructions {
    <#
    .SYNOPSIS
    Generates CLAUDE.md for Claude Code.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][hashtable]$Commands
    )

    $installCmd = $Commands['install']
    $buildCmd = $Commands['build']
    $testCmd = $Commands['test']
    $lintCmd = $Commands['lint']
    $runCmd = $Commands['run']

    $content = @"
# Claude Code Project Instructions

**Project:** $ProjectName  
**Last Updated:** $(Get-Date -Format 'yyyy-MM-dd')

## Commands

Essential commands for development:

- **Install:** \`$installCmd\`
- **Build:** \`$buildCmd\`
- **Test:** \`$testCmd\`
- **Lint/Format:** \`$lintCmd\`
- **Run locally:** \`$runCmd\`

## Architecture Principles

- Keep domain logic independent from infrastructure
- Put external integrations behind well-defined interfaces
- Avoid circular dependencies between modules
- Record consequential architecture decisions in [docs/decisions/](docs/decisions/)

## Project Structure

\`\`\`
$ProjectName/
├── src/           # Source code
├── tests/         # Test suite
├── docs/          # Documentation
│   ├── architecture.md
│   └── decisions/  # Architecture Decision Records
└── README.md      # Project overview
\`\`\`

## Workflow Guidelines

1. **Before making changes:**
   - Read relevant tests to understand expected behavior
   - Check [docs/architecture.md](docs/architecture.md) for component relationships

2. **During implementation:**
   - Make the smallest coherent change
   - Keep commits focused and descriptive
   - Run affected checks before committing

3. **Before committing:**
   - Ensure tests pass
   - Verify no secrets or credentials in diff
   - Update documentation if behavior changed

## MCP Tools & Integrations

Available tools:
- **Filesystem MCP:** Access and modify project files
- **GitHub MCP:** Query GitHub issues, PRs, actions, and manage repositories
- **Playwright MCP:** Test browser behavior when needed (for web projects)

## Memory & Knowledge Management

- Use \`/memory\` to access persistent project knowledge
- Store important conventions and lessons learned
- Link memory to versioned docs - memory supplements but doesn't replace documentation
- Keep architecture rationale in docs/decisions/ (not just memory)

## First-Time Setup

\`\`\`
/init         # Generate initial instructions (review before committing)
/context      # Verify all instructions loaded correctly
/memory       # Inspect available memory and conventions
/graphify .   # Index repository when it has sufficient source code
\`\`\`

## Suggested Initial Prompt

Read README.md, CLAUDE.md, and docs/architecture.md without editing.

Tell me:
1. How to build, test, and run this project
2. The main components and their relationships
3. Any missing or unclear documentation
4. The safest and smallest next implementation task
"@

    New-ProjectFile -ProjectPath $ProjectPath -RelativePath 'CLAUDE.md' -Content $content -Force
}

function New-AgentsInstructions {
    <#
    .SYNOPSIS
    Generates AGENTS.md for Codex.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ProjectName,
        [Parameter(Mandatory)][hashtable]$Commands
    )

    $installCmd = $Commands['install']
    $buildCmd = $Commands['build']
    $testCmd = $Commands['test']
    $lintCmd = $Commands['lint']
    $runCmd = $Commands['run']

    $content = @"
# Project Working Agreement

**Project:** $ProjectName  
**Last Updated:** $(Get-Date -Format 'yyyy-MM-dd')

## Essential Commands

- **Install:** \`$installCmd\`
- **Build:** \`$buildCmd\`
- **Test:** \`$testCmd\`
- **Lint/Format:** \`$lintCmd\`
- **Run locally:** \`$runCmd\`

## Architecture & Design

- Keep domain logic independent from infrastructure
- Put external integrations behind well-defined interfaces
- Avoid circular dependencies between modules
- Record all consequential architecture decisions in [docs/decisions/](docs/decisions/)

### Project Structure
\`\`\`
$ProjectName/
├── src/           # Source code
├── tests/         # Test suite
├── docs/          # Documentation
│   ├── architecture.md
│   └── decisions/  # Architecture Decision Records (ADRs)
└── README.md
\`\`\`

## Development Workflow

1. **Before making changes:**
   - Read relevant tests to understand expected behavior
   - Review [docs/architecture.md](docs/architecture.md) for design context

2. **During implementation:**
   - Make the smallest coherent change possible
   - Keep commits focused and well-described
   - Run the checks affected by your change

3. **Commit safety:**
   - Never commit secrets, generated credentials, or local .env files
   - Ensure all tests pass locally
   - Verify no unwanted files in the diff

## MCP Tools Available

- **github:** Query and manage GitHub issues, PRs, and repositories (use explicitly when needed)
- **filesystem:** Access project files within configured allowed roots
- **playwright:** Browser automation for integration testing (web projects only)

## First-Time Orientation

Use \`/mcp\` or \`/mcp verbose\` to confirm all local MCP tools have loaded.

Ask me to:
1. Read AGENTS.md and README.md
2. Inspect the repository structure without editing
3. Explain the architecture and exact build/test/run commands
4. Show current Git status
5. Identify the smallest useful next task
6. Flag any contradictions or missing documentation

## Suggested Initial Prompt

Read AGENTS.md and README.md.

Inspect the repository and test configuration without editing.

Explain:
1. The architecture and main components
2. Exact build, test, and run commands
3. Current Git status
4. The smallest useful next implementation task

Flag any contradictions or missing instructions before proposing changes.
"@

    New-ProjectFile -ProjectPath $ProjectPath -RelativePath 'AGENTS.md' -Content $content -Force
}

# ============================================================================
# Git Initialization
# ============================================================================

function Initialize-ProjectGit {
    <#
    .SYNOPSIS
    Initializes Git repository and configures user.
    
    .PARAMETER ProjectPath
    Project root directory.
    
    .PARAMETER UserName
    Git user.name for commits.
    
    .PARAMETER UserEmail
    Git user.email for commits.
    
    .PARAMETER SkipInit
    If $true, skip git init (repository already exists).
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter()][string]$UserName,
        [Parameter()][string]$UserEmail,
        [Parameter()][switch]$SkipInit
    )

    $currentDir = Get-Location
    try {
        Set-Location $ProjectPath

        if (-not $SkipInit) {
            Invoke-NativeCommand -FilePath 'git' -ArgumentList 'init'
        }

        # Set user config if provided
        if ($UserName) {
            Invoke-NativeCommand -FilePath 'git' -ArgumentList 'config', 'user.name', $UserName
        }
        if ($UserEmail) {
            Invoke-NativeCommand -FilePath 'git' -ArgumentList 'config', 'user.email', $UserEmail
        }

        # Create .gitkeep files
        $null = New-Item -Path 'src/.gitkeep' -Force -ErrorAction SilentlyContinue
        $null = New-Item -Path 'tests/.gitkeep' -Force -ErrorAction SilentlyContinue
    }
    finally {
        Set-Location $currentDir
    }
}

# ============================================================================
# Language Starter Generators (delegated to separate scripts)
# ============================================================================

function Invoke-LanguageStarter {
    <#
    .SYNOPSIS
    Invokes language-specific starter generation script.
    
    .PARAMETER Language
    Programming language (node, python, csharp, rust, java, go).
    
    .PARAMETER ProjectPath
    Project root directory.
    
    .PARAMETER ProjectName
    Project display name.
    #>
    param(
        [Parameter(Mandatory)][string]$Language,
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$ProjectName
    )

    $starterScript = Join-Path $PSScriptRoot "../starters/setup-starter-$Language.ps1"
    
    if (-not (Test-Path $starterScript)) {
        Write-WarningMessage "Language starter script not found: $starterScript"
        Write-WarningMessage "Skipping language-specific setup. Create starter files manually."
        return
    }

    & $starterScript -ProjectPath $ProjectPath -ProjectName $ProjectName
}

# ============================================================================
# Build & Test Validation
# ============================================================================

function Test-ProjectBuildable {
    <#
    .SYNOPSIS
    Attempts to build the project and reports success/failure.
    
    .PARAMETER ProjectPath
    Project root directory.
    
    .PARAMETER BuildCommand
    Build command to execute.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$BuildCommand
    )

    $currentDir = Get-Location
    try {
        Set-Location $ProjectPath
        Write-Step "Running: $BuildCommand"
        Invoke-Expression $BuildCommand
        return $true
    }
    catch {
        Write-WarningMessage "Build failed: $_"
        return $false
    }
    finally {
        Set-Location $currentDir
    }
}

function Test-ProjectTestable {
    <#
    .SYNOPSIS
    Runs the project test suite.
    
    .PARAMETER ProjectPath
    Project root directory.
    
    .PARAMETER TestCommand
    Test command to execute.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter(Mandatory)][string]$TestCommand
    )

    $currentDir = Get-Location
    try {
        Set-Location $ProjectPath
        Write-Step "Running: $TestCommand"
        Invoke-Expression $TestCommand
        return $true
    }
    catch {
        Write-WarningMessage "Tests failed: $_"
        return $false
    }
    finally {
        Set-Location $currentDir
    }
}

# ============================================================================
# Git Commit
# ============================================================================

function New-ProjectInitialCommit {
    <#
    .SYNOPSIS
    Creates the initial project commit.
    
    .PARAMETER ProjectPath
    Project root directory.
    
    .PARAMETER Message
    Commit message (default: "Initial project scaffold").
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectPath,
        [Parameter()][string]$Message = "Initial project scaffold"
    )

    $currentDir = Get-Location
    try {
        Set-Location $ProjectPath
        
        Write-Step "Staging files"
        Invoke-NativeCommand -FilePath 'git' -ArgumentList 'add', '.'
        
        Write-Step "Creating initial commit: $Message"
        Invoke-NativeCommand -FilePath 'git' -ArgumentList 'commit', '-m', $Message
        
        Write-Success "Initial commit created"
    }
    finally {
        Set-Location $currentDir
    }
}

# ============================================================================
# Exports
# ============================================================================

Export-ModuleMember -Function @(
    # Shared utilities (formerly Common.ps1)
    'Write-Step'
    'Write-Success'
    'Write-WarningMessage'
    'Test-CommandAvailable'
    'Test-IsWindowsPlatform'
    'Get-PathComparer'
    'Update-SessionPath'
    'Add-DirectoryToSessionPath'
    'Get-NpmCommand'
    'Get-NpxCommand'
    'Assert-CommandAvailable'
    'Invoke-NativeCommand'
    'Test-McpServerRegistered'
    'Resolve-OrCreatePath'

    # Project structure
    'New-ProjectStructure'
    'New-ProjectFile'
    
    # File generation
    'New-Gitignore'
    'New-EnvExample'
    'New-ReadmeFile'
    'New-ArchitectureFile'
    'New-AdtTemplate'
    'New-ClaudeInstructions'
    'New-AgentsInstructions'
    
    # Git initialization
    'Initialize-ProjectGit'
    
    # Language starters
    'Invoke-LanguageStarter'
    
    # Build & test
    'Test-ProjectBuildable'
    'Test-ProjectTestable'
    
    # Commit
    'New-ProjectInitialCommit'
)
