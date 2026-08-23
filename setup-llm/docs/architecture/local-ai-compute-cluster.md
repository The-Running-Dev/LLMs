---
title: Local AI Compute Cluster
sidebar_position: 5
description: Phase T3 skeleton for the Local AI Compute Cluster MVP.
---

## Local AI Compute Cluster (T3 Skeleton)

This document records incremental AI-cluster implementation slices for Issue #16.

## Scope of This Slice

Current implemented slices provide:

- `setup-llm/ai-cluster/compose.yaml` with dedicated `headless`, `ui`, `cloud`, and `intel-sycl-linux` profiles.
- Environment and route scaffolding:
  - `setup-llm/ai-cluster/.env.example`
  - `setup-llm/ai-cluster/config/litellm.yaml`
  - `setup-llm/ai-cluster/config/model-manifest.example.yaml`
- Local runtime config template:
  - `setup-llm/ai-cluster/config/local-inference.example.json`
- Lifecycle and validation scripts under `setup-llm/ai-cluster/scripts/`.
- Route and contract tests under `setup-llm/ai-cluster/tests/`.

## Design Constraints Preserved

- Existing GitHub MCP Compose workflow remains under `setup-llm/docker/docker-compose.yml` and is not modified by this slice.
- No model binaries, API keys, or cloud credentials are committed.
- Compose topology is separated into `setup-llm/ai-cluster/` to isolate AI-cluster iteration from workstation setup integrations.

## Validation Command

Run from repository root:

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Test-AiCluster.ps1
```

This currently validates static structure and optionally runs `docker compose config` when Docker is available.

### Local Inference Lifecycle (T4)

Copy the template and fill in executable/model paths:

```powershell
Copy-Item setup-llm/ai-cluster/config/local-inference.example.json setup-llm/ai-cluster/config/local-inference.json
```

Set the backend key in your shell and start providers:

```powershell
$env:LOCAL_INFERENCE_API_KEY = 'replace-me-before-use'
pwsh -File setup-llm/ai-cluster/scripts/Start-LocalInference.ps1
pwsh -File setup-llm/ai-cluster/scripts/Get-LocalInferenceStatus.ps1
pwsh -File setup-llm/ai-cluster/scripts/Stop-LocalInference.ps1
```

The start script validates model paths, optional model hashes, API key presence, and writes PID/log state under `setup-llm/ai-cluster/state` and `setup-llm/ai-cluster/logs`.

### Gateway Contract Test (T5)

Run the gateway contract smoke test:

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Test-GatewayContract.ps1
```

The script provisions a temporary Docker Compose project with deterministic mock OpenAI backends, validates:

- authenticated `/v1/models`
- unauthenticated request rejection
- chat completions (including streaming)
- embeddings responses
- normalized unknown-model failure behavior

and then tears the environment down.

### Embeddings Contract Test (T6)

Run the embeddings contract checks:

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Test-EmbeddingsContract.ps1
```

The script validates the embeddings route contract using `config/embeddings-contract.example.json`:

- batch request handling preserves count and order
- vector dimension matches the contract (`8`)
- deterministic output for identical input
- distinct output for different input
- cosine similarity sanity (`self ~= 1`, cross-input lower)
- normalization behavior matches the contract (`normalized = false`)

### Provider Replacement and Failure Test (T7)

Run provider replacement and failure-path validation:

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Test-ProviderReplacementAndFailure.ps1
```

This script executes scenario-based checks against the same logical `coding` route:

- provider replacement without client changes (`local-coding` -> `local-coding-alt`)
- unreachable backend failure (no silent fallback)
- explicit rate-limit propagation (`429`)
- malformed backend response failure handling

### Operational Controls and Diagnostics (T8)

Run T8 operational controls validation:

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Test-OperationalControls.ps1
```

Run redacted diagnostics output:

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Get-AiClusterDiagnostics.ps1 -AsJson
pwsh -File setup-llm/ai-cluster/scripts/Get-AiClusterDiagnostics.ps1 -ProbeGateway -AsJson
```

T8 controls currently enforce or document:

- health-gated startup for containerized gateway and mock backends
- loopback-only gateway host bind (`127.0.0.1:${GATEWAY_BIND_PORT}:4000`)
- local secret/state/log path ignore rules (`.env`, `.env.*`, `state/`, `logs/`)
- placeholder-secret rejection for runtime `.env` values when present
- host-native inference metrics enabled via `--metrics` while template defaults avoid verbose prompt logging flags
- route/backend/status/latency/token diagnostics without exposing raw keys or prompt payloads

Security and operations notes:

- Firewall/bind-address: gateway and Open WebUI are loopback-bound by default and are not externally reachable unless operators change port bindings.
- Cloud egress: default headless profile uses local routes only; cloud/fallback behavior remains explicit opt-in via route/env configuration.
- Data retention: runtime state and logs are local files under `setup-llm/ai-cluster/state` and `setup-llm/ai-cluster/logs`; these are intentionally excluded from source control.
- Deletion behavior: `docker compose down --volumes --remove-orphans` removes transient containers/volumes for compose-run scenarios; local state/log directories can be removed manually when desired.
- MCP boundary: MCP services remain a separate authenticated tool plane from gateway bearer-key authentication and are not delegated by gateway model routing.

### Vision and Multimodal Routing (T11 / Issue #24)

The MVP now exposes additional capability aliases for provider-neutral multimodal routing:

- `vision`
- `multimodal`

Current capability matrix:

| Alias | Default backend | Notes |
| --- | --- | --- |
| `coding` | local coding backend | Text-first code/chat generation |
| `general` | local coding backend | General text generation |
| `vision` | local coding backend | Multimodal-shaped chat requests are routed here for deterministic MVP validation |
| `multimodal` | local coding backend | Same backend as `vision`; reserved for future provider-specific multimodal swaps |
| `embeddings` | local embeddings backend | Separate vector route |

Mismatch handling:

- Unsupported multimodal capabilities must fail explicitly instead of falling back silently.
- If a future provider advertises a narrower capability set, the gateway config or diagnostics must make the mismatch visible.
- The gateway contract test now includes a multimodal-shaped chat request to prove the route remains stable without client changes.

### Automated Validation and CI (T9)

GitHub Actions workflow:

- `.github/workflows/ai-cluster-ci.yml`

The workflow runs GPU-independent checks on `ubuntu-latest`:

- `Test-AiCluster.ps1`
- `Test-OperationalControls.ps1`
- Pester suite under `setup-llm/ai-cluster/tests`
- deterministic contract runs:
  - `Test-GatewayContract.ps1`
  - `Test-EmbeddingsContract.ps1`
  - `Test-ProviderReplacementAndFailure.ps1`

Hardware-only smoke validation is represented by:

- `setup-llm/ai-cluster/scripts/Test-HardwareSmoke.ps1`

In standard CI it exits with an explicit `[SKIP]` reason. Set `AI_CLUSTER_RUN_HARDWARE_SMOKE=1` (or run with `-Force` locally) to enable it.

### Setup Integration and Operator Workflow (T10)

Opt-in setup and doctor entry points:

- `setup-llm/scripts/setup-ai-cluster.ps1`
- `setup-llm/scripts/doctor-ai-cluster.ps1`

Example usage:

```powershell
pwsh -File setup-llm/scripts/setup-ai-cluster.ps1 -InitializeEnv -InitializeLocalInferenceConfig -RunHeadlessConfigTest
pwsh -File setup-llm/scripts/doctor-ai-cluster.ps1
pwsh -File setup-llm/scripts/doctor-ai-cluster.ps1 -RunContracts
```

Operator guidance page:

- `setup-llm/docs/getting-started/ai-cluster-operations.md`

This covers prerequisites, model acquisition and hash expectations, startup/smoke/shutdown, upgrade and local backup guidance, retention/deletion behavior, Windows host-native SYCL troubleshooting notes, and the optional Linux `/dev/dri` profile caveat.

## Next Steps

- Follow-up issues continue from the MVP baseline, starting with vision/multimodal routing, memory/RAG retention, MCP profile growth, Open WebUI hardening, monitoring, and orchestration.
