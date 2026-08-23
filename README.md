# SubZeroDev Workspace

This repository contains reusable PowerShell tooling for preparing AI-assisted development workstations and scaffolding new projects for Codex and Claude Code.

## Documentation

The complete setup documentation is published at **[workspace.subzerodev.com](https://workspace.subzerodev.com/)**. The links below open the version stored in this repository, so they also work while reviewing a branch before it is deployed.

### Getting Started

- [Quick Start](setup-llm/docs/getting-started/quickstart.md) — create and open a new AI-assisted project with the shortest supported workflow.
- [Start a New Project](setup-llm/docs/getting-started/new-project.md) — follow the complete Claude Desktop, Claude Code, and Codex workflow.
- [Setup Overview](setup-llm/docs/index.md) — understand the combined setup, authentication, integrations, and platform prerequisites. On the published site, this page is available at [the documentation root](https://workspace.subzerodev.com/docs/).
- [AI Cluster Operations](setup-llm/docs/getting-started/ai-cluster-operations.md) — run opt-in setup, doctor checks, startup/smoke/shutdown, and troubleshooting for the Local AI Compute Cluster.

### Architecture and Setup Design

- [Modular Architecture](setup-llm/docs/architecture/modular-architecture.md) — understand the workstation and project setup modules.
- [Setup Flowcharts](setup-llm/docs/architecture/setup-flowcharts.md) — review the installation and project-creation flows visually.
- [Setup Specification](setup-llm/docs/architecture/setup-specification.md) — review inputs, outputs, validation, and required project files.
- [Local AI Compute Cluster](setup-llm/docs/architecture/local-ai-compute-cluster.md) — review the Issue #16 T3 AI-cluster skeleton, compose profiles, and validation flow.
- [Memory and RAG Retention Contract](setup-llm/docs/architecture/memory-rag-contract.md) — review retrieval boundaries, index lifecycle, deletion guarantees, and smoke-test expectations for durable memory layers.
- [Workspace Blueprint](setup-llm/docs/architecture/workspace-blueprint.md) — review the recommended AI development workspace and rollout plan.

### Reference

- [Language Starters](setup-llm/docs/reference/language-starters.md) — use or extend the language-specific project starters.
- [Reflection Mode](setup-llm/docs/reference/reflection-mode.md) — use the guided inquiry prompt for deliberate analysis.

The root README is the canonical documentation index. The remaining documentation source lives in [`setup-llm/docs/`](setup-llm/docs/). Run `setup-llm/scripts/docs-local.ps1` to synchronize both into the pinned Docusaurus template and serve them locally with live reload enabled.

To test the same documentation build job used by GitHub Actions, start Docker and run `setup-llm/scripts/docs-workflow-local.ps1`. The script uses [`act`](https://nektosact.com/) to execute the workflow's pull-request build job locally; it does not deploy to GitHub Pages.

## Container Usage

The published container includes PowerShell, the setup scripts, and the prebuilt documentation. No host PowerShell installation is required.

```bash
# Serve the documentation at http://localhost:8080
docker run --rm -p 8080:8080 ghcr.io/the-running-dev/subzerodev-workspace:latest

# Run the setup inside the container
docker run --rm -it ghcr.io/the-running-dev/subzerodev-workspace:latest setup -Client Codex -SkipGitHub

# Open an interactive PowerShell session
docker run --rm -it ghcr.io/the-running-dev/subzerodev-workspace:latest pwsh
```

Container setup changes the container environment. Mount `/root/.config` and `/workspace` when configuration or generated projects must persist. See the [container quick start](setup-llm/docs/getting-started/container.md) for volume and Docker-socket examples.

## Repository Layout

| Path                                                                       | Purpose                                                                            |
| -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| [`setup-llm/`](setup-llm/)                                                 | Cross-platform workstation provisioning, MCP registration, and project scaffolding |
| [`setup-llm/docs/`](setup-llm/docs/)                                       | Getting-started guides, architecture, reference material, and setup specifications |
| [`docs-template/`](docs-template/)                                         | Pinned Docusaurus template submodule used to build the documentation site          |
| `SubZeroDev.Workspace.code-workspace`                                      | VS Code workspace definition                                                       |

## Quick Start

The setup scripts support Windows, macOS, and Ubuntu/Debian. PowerShell automatically detects the current operating system and selects the appropriate package-installation flow.

```powershell
./setup-llm/scripts/setup.ps1 -Client Both -WhatIf
./setup-llm/scripts/setup.ps1 -Client Both -SkipClaudeMem
```

The preview command shows prerequisite actions without installing them. The second command performs workstation setup while omitting the optional third-party `claude-mem` integration.

## Local AI Cluster (Opt-in)

The Local AI Compute Cluster is not part of default workstation setup and does not auto-download model artifacts.

Initialize local templates and run baseline validation:

```powershell
./setup-llm/scripts/setup-ai-cluster.ps1 -InitializeEnv -InitializeLocalInferenceConfig -RunHeadlessConfigTest
```

Run an operator doctor summary:

```powershell
./setup-llm/scripts/doctor-ai-cluster.ps1
./setup-llm/scripts/doctor-ai-cluster.ps1 -RunContracts
```

Use the VS Code tasks `AI Cluster Setup (Opt-in)` and `AI Cluster Doctor` for task-driven operation.

## Workstation Setup

### Supported Platforms

| Platform      | Prerequisite installer                | Package tooling    |
| ------------- | ------------------------------------- | ------------------ |
| Windows       | `setup-llm/scripts/setup-windows.ps1` | Winget             |
| macOS         | `setup-llm/scripts/setup-macos.ps1`   | Homebrew and npm   |
| Ubuntu/Debian | `setup-llm/scripts/setup-ubuntu.ps1`  | apt, pipx, and npm |

Use `setup-llm/scripts/setup.ps1` for normal operation. It detects the OS and dispatches to the matching platform script. `setup-llm/scripts/setup-workstation.ps1` contains the shared Graphify, memory, and MCP configuration used after platform prerequisites are available.

### Prerequisites

- PowerShell 7 on macOS and Linux; Windows PowerShell 5.1 or PowerShell 7 on Windows
- Winget on Windows, Homebrew on macOS, or `apt-get` plus `sudo` on Ubuntu/Debian
- Docker Desktop or Docker Engine when GitHub MCP is enabled
- A narrowly scoped GitHub personal access token for GitHub MCP

Run the scripts as your normal user. Review package installations and third-party integrations before enabling them.

### Run the Setup

From the repository root, preview platform prerequisite actions:

```powershell
./setup-llm/scripts/setup.ps1 -Client Both -WhatIf
```

Recommended first run without third-party session memory:

```powershell
./setup-llm/scripts/setup.ps1 -Client Both -SkipClaudeMem
```

The default setup installs or configures Node.js, the selected assistant CLIs, GitHub CLI, `act`, Astral `uv`, Graphify, Claude Code memory support, optional `claude-mem`, GitHub MCP, and Playwright MCP.

For a VS Code task-driven flow, run **Tasks: Run Task** and select **Workstation Setup + Memory/Context7/GitHub/Docker MCP**. This task runs the standard workstation setup and then registers Context7 and Docker MCP servers for both Codex and Claude Code.

Select one or both supported clients:

```powershell
./setup-llm/scripts/setup.ps1 -Client Codex
./setup-llm/scripts/setup.ps1 -Client ClaudeCode
./setup-llm/scripts/setup.ps1 -Client Both
```

Skip optional components when they are not required:

```powershell
./setup-llm/scripts/setup.ps1 `
  -Client Both `
  -IncludeMemoryMcp `
  -SkipGraphify `
  -SkipClaudeMem `
  -SkipGitHub `
  -SkipPlaywright
```

Use `-IncludeMemoryMcp` only when you need shared memory across multiple tools or agents through MCP. Leave it off for normal single-tool workflows.

### Restrict Filesystem MCP

Filesystem MCP is disabled by default because the assistants already have native file access. When it is required, grant only the smallest practical directory:

```powershell
./setup-llm/scripts/setup.ps1 `
  -Client Both `
  -IncludeFilesystem `
  -FilesystemPath '/path/to/project'
```

### Configure a Database Integration

No generic database MCP package is installed. Select and security-review a maintained server first, then provide its installed command explicitly:

```powershell
./setup-llm/scripts/setup.ps1 `
  -Client Codex `
  -SkipClaudeMem `
  -IncludeDatabase `
  -DatabaseName 'my-readonly-db' `
  -DatabaseCommand 'the-reviewed-server-command' `
  -DatabaseArgument @('server-specific-argument')
```

Use a read-only development database account. Keep connection strings and passwords out of script arguments, command history, and source control.

### Configure GitHub MCP

Copy the environment template and insert a narrowly scoped token locally:

```powershell
Copy-Item setup-llm/docker/.env.example setup-llm/docker/.env
```

Keep these defensive defaults unless broader access is intentional:

```dotenv
GITHUB_PERSONAL_ACCESS_TOKEN=github_pat_replace_me
GITHUB_READ_ONLY=1
GITHUB_TOOLSETS=context,repos,issues,pull_requests,actions
```

`setup-llm/docker/.env` is git-ignored. Start Docker Desktop on Windows/macOS or Docker Engine on Linux before running GitHub setup. To retry only GitHub MCP after supplying the token:

```powershell
./setup-llm/scripts/setup.ps1 `
  -Client Both `
  -SkipGraphify `
  -SkipClaudeMem `
  -SkipPlaywright
```

`GITHUB_READ_ONLY=1` removes mutation tools exposed by enabled toolsets. `GITHUB_TOOLSETS` is a comma-separated allow-list: `context` exposes authenticated-user context, `repos` repository content, `issues` issue data, `pull_requests` review data, and `actions` workflow information. Avoid `all` unless broad access is intentional, and keep the token itself read-only and narrowly scoped as a second layer of protection.

### Individual Installers

The shared setup orchestrator calls focused installers:

- `setup-llm/scripts/setup-windows.ps1`
- `setup-llm/scripts/setup-macos.ps1`
- `setup-llm/scripts/setup-ubuntu.ps1`
- `setup-llm/scripts/setup-workstation.ps1`
- `setup-llm/scripts/workstation/install-graphify.ps1`
- `setup-llm/scripts/workstation/install-claude-memory.ps1`
- `setup-llm/scripts/workstation/install-claude-mem.ps1`
- `setup-llm/scripts/workstation/install-github-mcp.ps1`
- `setup-llm/scripts/workstation/install-filesystem-mcp.ps1`
- `setup-llm/scripts/workstation/install-playwright-mcp.ps1`
- `setup-llm/scripts/workstation/install-memory-mcp.ps1`
- `setup-llm/scripts/workstation/install-database-mcp.ps1`

Most component scripts preserve existing registrations. The GitHub installer intentionally replaces the existing `github` registration so it points to the Compose-managed service.

The root workspace task file is available at `.vscode/tasks.json` and includes:

- `Workstation Setup (Preview)`
- `Workstation Setup`
- `Workstation Setup (No claude-mem)`
- `Workstation Setup + Memory/Context7/GitHub/Docker MCP`

## Create a Project

After workstation setup, scaffold a new project with:

```powershell
./setup-llm/scripts/setup-project.ps1 `
  -ProjectPath '/path/to/MyProject' `
  -ProjectName 'MyProject' `
  -Language 'node'
```

Supported command profiles include Node.js, Python, C#, Rust, Java, and Go. Node.js and Python currently include generated language starters.

Useful generator switches include:

- `-Client Both|Code|Codex`
- `-SkipGit`
- `-SkipLanguageStarter`
- `-SkipValidation`
- `-AutoCommit`
- `-WhatIf`

## Troubleshooting

- **Docker CLI exists but the engine is stopped:** start Docker Desktop or the Docker service, wait until `docker info` succeeds, and rerun.
- **GitHub token error:** verify `setup-llm/docker/.env` exists and its token is not the placeholder.
- **New command is not found:** start a new PowerShell session so package-manager PATH changes load.
- **MCP server is not visible:** restart Codex and Claude Code after registration.
- **Fresh-machine preview stops before integrations:** this is expected; `-WhatIf` does not install commands needed to inspect MCP state.

## Build and Serve the Documentation

Initialize the pinned Docusaurus template after cloning:

```powershell
git submodule update --init --recursive
./setup-llm/scripts/setup-docs.ps1
```

The synchronization script copies the canonical root README to the Docusaurus `/docs/` index, copies the remaining documentation, and applies the project-owned sidebar and Docusaurus configuration. Do not edit the generated `docs-template` working tree.

Build the synchronized site locally:

```powershell
Set-Location docs-template
npx -y pnpm@9.0.0 install --frozen-lockfile
npx -y pnpm@9.0.0 run build:prod
```

The build output is written to `docs-template/artifacts`. GitHub Actions validates documentation and the OCI container on pull requests, deploys GitHub Pages from `main`, and publishes the container to GHCR from `main`.

For live reload, run:

```powershell
./setup-llm/scripts/docs-local.ps1
```

The default address is `http://localhost:3000/`. Use `-Port`, `-HostName`, or `-NoOpen` to change the server behavior, and `-SkipInstall` only when template dependencies are already installed. Stop an older background instance before restarting so the server can claim its port.

To validate the GitHub documentation build locally with Docker and `act`, run:

```powershell
./setup-llm/scripts/docs-workflow-local.ps1
```

The first run downloads the runner image and can take several minutes. On Apple Silicon the wrapper requests `linux/amd64`. Use `-ReuseRunnerImage` after the runner image and actions are cached. `act` closely approximates GitHub-hosted runners but does not implement every GitHub Actions feature.

## Security

- Review scripts before running them.
- Keep tokens and credentials out of source control.
- GitHub MCP is configured through the git-ignored `setup-llm/docker/.env` file and defaults to read-only access.
- Grant Filesystem MCP access only to narrowly scoped directories.
- Use development or sanitized databases with read-only accounts for database MCP integrations.
