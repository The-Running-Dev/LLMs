---
title: Modular Architecture
sidebar_position: 2
description: Package boundaries and responsibilities for the setup toolkit.
---

# Modular Project Setup Architecture

**Complete guide to the new project setup system**

The setup scripts have been refactored into a modular, extensible system following the patterns established in this workspace. This document explains how the pieces fit together and how to extend them.

## Architecture Overview

```
setup-project.ps1 (Orchestrator)
        ↓
Setup.psm1 (Core Module)
        ↓
├── New-ProjectStructure()
├── New-Gitignore()
├── New-ReadmeFile()
├── New-ArchitectureFile()
├── New-ClaudeInstructions()
├── New-AgentsInstructions()
├── Initialize-ProjectGit()
├── Invoke-LanguageStarter()      ← Delegates to language-specific scripts
├── Test-ProjectBuildable()
├── Test-ProjectTestable()
└── New-ProjectInitialCommit()

Utility functions exported by Setup.psm1
├── Write-Step()
├── Write-Success()
├── Write-WarningMessage()
├── Assert-CommandAvailable()
├── Test-CommandAvailable()
└── Invoke-NativeCommand()

Language Starters
├── setup-starter-node.ps1       (Generates package.json, tsconfig.json, etc.)
├── setup-starter-python.ps1     (Generates requirements.txt, setup.py, etc.)
├── setup-starter-csharp.ps1     (Extensible - create as needed)
├── setup-starter-rust.ps1       (Extensible - create as needed)
└── ... more languages ...
```

## File Organization

```text
setup-llm/
├── ai-cluster/                     # Local AI cluster compose/config/scripts/tests
│   ├── compose.yaml                # AI gateway + provider topology by profile
│   ├── config/                     # LiteLLM routing and model-manifest templates
│   ├── scripts/                    # Start/stop/test/measure workflow entry points
│   └── tests/                      # Pester validation and contract placeholders
├── scripts/
│   ├── setup.ps1                   # OS-detecting entry point
│   ├── setup-windows.ps1           # Winget prerequisites
│   ├── setup-macos.ps1             # Homebrew/npm prerequisites
│   ├── setup-ubuntu.ps1            # apt/pipx/npm prerequisites
│   ├── setup-workstation.ps1       # Shared integration orchestration
│   ├── setup-project.ps1           # Project generator entry point
│   ├── modules/
│   │   └── Setup.psm1              # Shared utility + project creation module
│   ├── workstation/                # Component installers
│   └── starters/                   # Language-specific generators
├── docker/                         # GitHub MCP Compose and secret files
├── config/                         # Schema and example configuration
└── docs/                           # Docusaurus-ready documentation
```

## How It Works

### Workstation Orchestration

`setup.ps1` detects Windows, macOS, or Linux and delegates to its platform script. Each platform script installs missing prerequisites and invokes `setup-workstation.ps1`. The shared orchestrator runs the OS-independent component installers. MCP commands use `cmd /c npx` on Windows and invoke `npx` directly on macOS and Linux.

### Project Orchestration (`setup-project.ps1`)

The main script:
1. Imports `Setup.psm1`
2. Uses exported utility and core project functions
3. Validates input parameters
4. Gets Git configuration
5. Calls module functions in sequence
6. Handles errors and reports progress

**Key features:**
- Uses `[CmdletBinding(SupportsShouldProcess)]` for `-WhatIf` support
- Follows existing script patterns (parameter validation, error handling)
- Uses shared utility functions exported by `Setup.psm1` for consistent output
- Supports multiple switch options: `-SkipGit`, `-SkipValidation`, `-AutoCommit`

### Phase 2: Core Functions (Setup.psm1)

The module contains focused functions, each doing one thing well:

**Structure functions:**
- `New-ProjectStructure()` — Creates directory tree
- `New-ProjectFile()` — Creates a file with content

**File generators:**
- `New-Gitignore()` — Language-specific .gitignore
- `New-EnvExample()` — .env.example template
- `New-ReadmeFile()` — README.md with language commands
- `New-ArchitectureFile()` — docs/architecture.md template
- `New-AdtTemplate()` — ADR template
- `New-ClaudeInstructions()` — CLAUDE.md generator
- `New-AgentsInstructions()` — AGENTS.md generator

**Git functions:**
- `Initialize-ProjectGit()` — git init + config

**Language support:**
- `Invoke-LanguageStarter()` — Delegates to language-specific scripts

**Validation functions:**
- `Test-ProjectBuildable()` — Runs build command
- `Test-ProjectTestable()` — Runs test command

**Commit functions:**
- `New-ProjectInitialCommit()` — Creates initial commit

**Key patterns:**
- Each function has `[Parameter()]` attributes with validation
- Functions use relative paths (ProjectPath as base)
- Error handling via `-ErrorAction`
- Progress reporting via `Write-Success()` and `Write-WarningMessage()`

### Phase 3: Language Customization (setup-starter-*.ps1)

Language-specific scripts generate starter files:

**Node.js example:**
```powershell
.\scripts\starters\setup-starter-node.ps1 -ProjectPath 'D:\Projects\MyApp' -ProjectName 'MyApp'
```

Generates:
- `package.json`
- `tsconfig.json`
- `.eslintrc.json`
- `jest.config.js`
- `.prettierrc.json`
- `src/index.js`
- `tests/index.test.js`

**Creating a new starter:**
1. Copy `setup-starter-node.ps1` template
2. Replace language-specific content
3. Name it `setup-starter-<language>.ps1`
4. Test by running `setup-project.ps1 -Language '<language>'`

## Usage Examples

### Basic Project Creation

```powershell
cd D:\Projects\SubZeroDev.Workspace\setup-llm

.\scripts\setup-project.ps1 `
  -ProjectPath 'D:\Dropbox\Projects\MyApp' `
  -ProjectName 'MyApp' `
  -Language 'node'
```

**Result:**
- Directory structure created
- Common files generated (README, CLAUDE.md, AGENTS.md, docs/)
- Node.js starters created (package.json, tsconfig.json, etc.)
- Git initialized
- User is guided to next steps

### With Auto-Commit

```powershell
.\scripts\setup-project.ps1 `
  -ProjectPath 'D:\Dropbox\Projects\MyBackend' `
  -ProjectName 'Backend' `
  -Language 'csharp' `
  -AutoCommit
```

**Result:**
- Same as above, PLUS
- Build and tests validated
- Initial commit automatically created

### Skipping Steps

```powershell
.\scripts\setup-project.ps1 `
  -ProjectPath 'D:\Dropbox\Projects\ExistingProject' `
  -ProjectName 'ExistingProject' `
  -Language 'python' `
  -SkipGit `
  -SkipLanguageStarter `
  -SkipValidation
```

**Result:**
- Only creates common files and client instructions
- No Git operations, language starters, or validation

### Test (`WhatIf` Mode)

```powershell
.\scripts\setup-project.ps1 `
  -ProjectPath 'D:\Dropbox\Projects\TestProject' `
  -ProjectName 'TestProject' `
  -Language 'node' `
  -WhatIf
```

**Result:**
- Shows what would be done without making changes

## Extending the System

### Add Support for a New Language

1. **Create the starter script**
   ```powershell
   Copy-Item scripts\starters\setup-starter-node.ps1 scripts\starters\setup-starter-rust.ps1
   ```

2. **Edit for Rust**
   - Replace Node-specific files with Rust files
   - Update `Cargo.toml` instead of `package.json`
   - Create `src/main.rs` instead of `src/index.js`
   - Keep the script structure and comment style

3. **Update language commands** in `setup-project.ps1`
   ```powershell
   rust = @{
       install  = 'cargo fetch'
       build    = 'cargo build --release'
       test     = 'cargo test'
       lint     = 'cargo clippy'
       run      = 'cargo run --release'
   }
   ```

4. **Test**
   ```powershell
   .\scripts\setup-project.ps1 -ProjectPath 'D:\Test\Rust' -ProjectName 'RustApp' -Language 'rust'
   ```

5. **Document** in [Language starters](../reference/language-starters.md)

### Add a New Generation Function to ProjectSetup Module

1. **Open Setup.psm1**

2. **Add your function**
   ```powershell
   function New-CustomFile {
       param(
           [Parameter(Mandatory)][string]$ProjectPath,
           [Parameter(Mandatory)][string]$CustomParam
       )
       
       $content = @"
           Your file content
       "@
       
       New-ProjectFile -ProjectPath $ProjectPath -RelativePath 'custom.txt' -Content $content
   }
   ```

3. **Export it** in the `Export-ModuleMember` list

4. **Call it** from `setup-project.ps1`
   ```powershell
   New-CustomFile -ProjectPath $ProjectPath -CustomParam 'value'
   ```

### Add a New Validation Check

1. **Add the function** to Setup.psm1
2. **Call it** in setup-project.ps1 before/after build/test validation
3. **Report results** using `Write-Success()` or `Write-WarningMessage()`

## Compatibility with Existing Scripts

The new system maintains compatibility with existing scripts:

- **Setup.psm1** — Shared utility and project functions used by all scripts
- **install-*.ps1** — Workstation setup scripts still work
- **setup.ps1** — Detects the host OS and delegates Phase 1 to a platform entry point

You can now use setup-project.ps1 for Phase 2 and Phase 3 project creation.

## Troubleshooting

### Module Import Fails

**Error:** `Setup module not found`

**Solution:**
```powershell
# Ensure you're in the setup directory
cd D:\Projects\SubZeroDev.Workspace\setup-llm

# Check file exists
Test-Path .\scripts\modules\Setup.psm1

# Try again
.\scripts\setup-project.ps1 ...
```

### Language Starter Not Found

**Warning:** `Language starter script not found`

**Solution:**
- Create `setup-starter-<language>.ps1` using the template
- Or skip with `-SkipLanguageStarter`
- See [Language starters](../reference/language-starters.md) for details

### Git Config Not Found

**Error:** `Cannot determine Git user.name`

**Solution:**
```powershell
# Set Git config
git config --global user.name 'Your Name'
git config --global user.email 'your@email.com'

# Or provide explicitly
.\scripts\setup-project.ps1 ... -GitUserName 'Your Name' -GitUserEmail 'your@email.com'
```

### Build/Test Validation Fails

**Warning:** `Build validation skipped or failed`

**Likely cause:** Language tools not installed yet

**Solution:**
```powershell
# Install dependencies first
npm install  # for Node
pip install -r requirements.txt  # for Python

# Then run with validation
.\scripts\setup-project.ps1 ... -AutoCommit

# Or skip validation for now
.\scripts\setup-project.ps1 ... -SkipValidation
```

## Performance

The system is designed to be fast:

- Minimal external command calls
- Lazy evaluation of language commands
- Optional validation and commit steps
- Parallel-capable directory creation

**Typical creation time:** 1-3 seconds (without validation)
**With validation:** 5-15 seconds (depends on language tooling)

## References

- [Setup specification](./setup-specification.md) — Requirements and workflows
- [Setup flowcharts](./setup-flowcharts.md) — Visual process diagrams
- [Language starters](../reference/language-starters.md) — Creating language-specific setup
- `scripts/modules/Setup.psm1` — Shared utilities and core module documentation
- `setup-project.ps1` — Script with inline documentation
