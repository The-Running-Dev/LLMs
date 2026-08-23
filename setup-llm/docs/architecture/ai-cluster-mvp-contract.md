---
title: AI Cluster MVP Implementation Contract
sidebar_position: 5
description: T1 implementation contract and delivery baseline for issue #16.
---

## AI Cluster MVP Implementation Contract

This contract translates issue #16 into implementation constraints for T1-T10.

## Scope for MVP

In scope:

- OpenAI-compatible gateway for chat and embeddings.
- Host-native local inference lifecycle on Windows.
- Configurable provider routing through logical model aliases.
- Security/health/diagnostic controls suitable for local operations.
- GPU-independent CI checks for contract behavior.

Out of scope (MVP):

- Autonomous orchestration beyond explicit operator commands.
- Production HA deployment concerns.
- Broad multi-tenant controls.

## Logical routing contract

Required aliases:

- `coding`
- `general`
- `vision`
- `multimodal`
- `embeddings`

Contract rules:

- Clients must use aliases, not backend-specific identifiers.
- Alias remapping must not require client-code changes.
- Fallback to cloud providers must be explicit and observable.
- `vision` and `multimodal` are capability aliases, not a promise of a distinct backend implementation.
- Unsupported multimodal capability must fail explicitly or be remapped in configuration, never silently downgraded.

## Error and fallback semantics

- Unavailable backend: return explicit error with stable error shape.
- Timeout: return timeout-class error, never silent reroute.
- Auth/config errors: fail fast with actionable diagnostics.
- Optional fallback, if enabled, must emit route/fallback metadata.

## Configuration ownership

Proposed configuration surfaces:

- `setup-llm/ai-cluster/.env.example`
- `setup-llm/ai-cluster/compose.yaml`
- `setup-llm/ai-cluster/config/litellm.yaml`
- `setup-llm/ai-cluster/config/models.local.yaml`
- `setup-llm/ai-cluster/config/routes.yaml`

Ownership model:

- Versioned defaults in repository.
- Secrets and machine-specific overrides outside source control.
- Runtime state (PID/log/cache/model dirs) in ignored local paths.

## Security baseline

- Bind gateway to loopback by default.
- Keep MCP credentials and API credentials separated.
- Redact secrets from logs and diagnostics.
- Do not persist prompt bodies in default diagnostics.

## Observability baseline

Required checks:

- Host runtime health (coding + embeddings backends).
- Gateway health and route readiness.
- Route-level request outcome (status, latency, token totals where available).

## Testability baseline

CI must validate without GPU:

- `docker compose config` succeeds.
- Route contract tests pass using deterministic mock backends.
- Error semantics and no-silent-fallback behavior are verified.

Hardware-only validation (non-CI):

- Intel Arc B580 benchmark report for selected models.
- Evidence of selected backend/device and offload configuration.

## Delivery checkpoints

1. T1 complete when ADR + this contract are accepted.
2. T3 complete when baseline compose + config validates without secrets.
3. T5/T6 complete when gateway and embeddings route pass smoke tests.
4. T7 complete when provider switch works with no client changes.
5. T9 complete when GPU-independent CI contract tests are green.

## Initial repository skeleton plan (T3 target)

```text
setup-llm/ai-cluster/
  compose.yaml
  .env.example
  config/
    litellm.yaml
    models.local.yaml
    routes.yaml
  scripts/
    start-local.ps1
    stop-local.ps1
    health.ps1
    doctor.ps1
  tests/
    contract/
    smoke/
  docs/
    operator-guide.md
```

This skeleton is intentionally minimal and is created in T3 after model/runtime choices are finalized in T2.
