---
title: AI Cluster Operations
sidebar_position: 4
description: Operator setup, smoke testing, lifecycle, and troubleshooting for the Local AI Compute Cluster MVP.
---

## Scope and Defaults

The Local AI Compute Cluster is opt-in. Default workstation setup does not download model artifacts and does not auto-enable the AI cluster.

Use these entry points:

```powershell
pwsh -File setup-llm/scripts/setup-ai-cluster.ps1 -InitializeEnv -InitializeLocalInferenceConfig
pwsh -File setup-llm/scripts/doctor-ai-cluster.ps1
```

## Prerequisites

- Docker Desktop (Windows/macOS) or Docker Engine (Linux)
- PowerShell
- Host-native `llama-server` binaries and model files for local SYCL workflows
- Runtime keys in `setup-llm/ai-cluster/.env`

## Model Acquisition and Integrity

Model acquisition is manual and explicit.

1. Select model artifact sources and licenses.
2. Record model identity and hash in `setup-llm/ai-cluster/config/model-manifest.example.yaml` (or local derived manifest).
3. Configure local paths in `setup-llm/ai-cluster/config/local-inference.json` (copied from the example file).
4. Verify hashes before startup via `Start-LocalInference.ps1`.

Do not commit model binaries, local absolute model paths, or secrets.

## Configuration

Required local files:

- `setup-llm/ai-cluster/.env`
- `setup-llm/ai-cluster/config/local-inference.json`

Bootstrap from templates:

```powershell
Copy-Item setup-llm/ai-cluster/.env.example setup-llm/ai-cluster/.env
Copy-Item setup-llm/ai-cluster/config/local-inference.example.json setup-llm/ai-cluster/config/local-inference.json
```

## Startup and Smoke Test

1. Start host-native providers.

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Start-LocalInference.ps1
```

1. Validate local provider status.

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Get-LocalInferenceStatus.ps1
```

1. Run gateway/contract checks (GPU-independent deterministic backend tests).

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Test-GatewayContract.ps1
pwsh -File setup-llm/ai-cluster/scripts/Test-EmbeddingsContract.ps1
pwsh -File setup-llm/ai-cluster/scripts/Test-ProviderReplacementAndFailure.ps1
```

1. Run doctor summary.

```powershell
pwsh -File setup-llm/scripts/doctor-ai-cluster.ps1 -RunContracts
```

## Shutdown

Stop host-native providers:

```powershell
pwsh -File setup-llm/ai-cluster/scripts/Stop-LocalInference.ps1
```

Contract scripts automatically perform `docker compose down --volumes --remove-orphans` for temporary projects.

## Upgrade and Backup

- Upgrade cluster scripts/configuration from source control first.
- Re-check local `.env` and `local-inference.json` for new keys/flags.
- Keep a local backup copy of:
  - `setup-llm/ai-cluster/.env`
  - `setup-llm/ai-cluster/config/local-inference.json`
  - any custom local manifests outside source control

## Retention and Deletion

- Runtime state/log paths: `setup-llm/ai-cluster/state` and `setup-llm/ai-cluster/logs`
- Compose validation/contract runs are ephemeral and cleaned up automatically.
- To fully reset local state:

```powershell
Remove-Item setup-llm/ai-cluster/state -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item setup-llm/ai-cluster/logs -Recurse -Force -ErrorAction SilentlyContinue
```

## Troubleshooting

- SYCL discovery failure: confirm Intel runtime/drivers and `llama-server` build compatibility.
- Out-of-device-memory: reduce model size, reduce context, or reduce GPU layers.
- Partial offload instability: adjust `default_gpu_layers` and context settings in local inference config.
- Gateway connectivity failure: run `Test-GatewayContract.ps1` and `Get-AiClusterDiagnostics.ps1 -ProbeGateway -AsJson`.
- Model hash mismatch: update local model artifact or expected hash in local config/manifest.
- Windows vs Linux profile caveat: host-native Windows SYCL is the verified path in this milestone; Linux `/dev/dri` container profile remains optional and environment-dependent.

## Security Boundary Notes

- Gateway bearer-key auth is separate from MCP authentication.
- MCP tool plane remains independently authenticated and least-privileged.
- Default profile avoids silent fallback to billable providers.
- Open WebUI runs with auth enabled, strict cookies, a required secret key, and persistent config disabled by default.
- The downgrade path for local-only experimentation is to set `WEBUI_AUTH=false` and restart the service; keep the port bound to `127.0.0.1` either way.

## Follow-up Backlog Seeds

Recommended follow-up issue topics after this milestone:

- Vision/multimodal routing and contract extension
- Memory/RAG retention and retrieval boundary definition
- Additional MCP services with least-privilege profiles
- Open WebUI hardening and auth posture
- Monitoring stack expansion (metrics aggregation and dashboards)
- Autonomous orchestration workflow progression
