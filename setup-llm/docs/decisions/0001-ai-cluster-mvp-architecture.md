---
title: ADR 0001 - AI Cluster MVP Architecture
sidebar_position: 1
description: Architecture decision for Local AI Compute Cluster MVP (issue #16).
---

# ADR 0001: AI Cluster MVP Architecture

- Status: Accepted
- Date: 2026-08-03
- Issue: #16 Deliver the Local AI Compute Cluster MVP
- Owners: Workspace maintainers

## Context

The workspace needs a provider-neutral AI endpoint that supports local inference first, optional cloud providers, and stable client integration semantics. The first milestone must work on Windows with Intel Arc B580 and must not force cloud usage or leak secrets into source control.

Current state:

- Setup scripts provision tools and MCP integrations.
- No model gateway is exposed today.
- Existing GitHub MCP workflow must remain operational.

## Decision

Adopt a two-plane architecture for the MVP:

1. Inference plane
- Host-native llama.cpp processes provide local chat/code generation and embeddings.
- Local processes are lifecycle-managed by PowerShell scripts.

2. Gateway plane
- LiteLLM Proxy runs as a pinned containerized service.
- Gateway exposes an OpenAI-compatible API on loopback (`127.0.0.1:4000`) by default.
- Logical routes (`coding`, `general`, `embeddings`) are mapped in configuration, not client code.

Cross-cutting constraints:

- No implicit fallback to billable cloud providers.
- MCP remains a separately authenticated tool plane.
- Secrets are read from local environment/config and never committed.
- Health and diagnostics must be available without exposing prompt bodies or keys.

## Alternatives considered

### A. Direct client to local runtime only (no gateway)
Rejected because route replacement, fallback policy, and provider neutrality become client concerns.

### B. Fully containerized local inference for MVP
Deferred because Windows + Intel Arc GPU container support is not yet the lowest-risk path for this milestone.

### C. Cloud-first gateway defaults
Rejected because the milestone requires local-first behavior and explicit opt-in for billable routes.

## Consequences

Positive:

- Stable API boundary for tools and agents.
- Provider swaps can be made through configuration.
- Security controls can be centralized in gateway and lifecycle scripts.

Trade-offs:

- Hybrid host+container operations increase orchestration complexity.
- Requires clear diagnostics for host process and gateway coordination.

## MVP contract summary

- Endpoint: OpenAI-compatible API at loopback port 4000.
- Required capabilities: `/v1/models`, `/v1/chat/completions` (including streaming), `/v1/embeddings`.
- Required routes: `coding`, `general`, `embeddings`.
- Required policy: no silent cloud fallback.
- Required evidence: reproducible hardware benchmark for selected models and route behavior.

## Follow-up tasks unblocked by this ADR

- T2 hardware inference spike and model manifest.
- T3 project skeleton and compose baseline.
- T4/T5 runtime lifecycle and gateway integration.
- T7 failure semantics and provider switching tests.
