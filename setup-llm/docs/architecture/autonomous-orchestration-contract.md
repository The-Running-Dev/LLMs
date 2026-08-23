---
title: Autonomous Orchestration Contract
sidebar_position: 7
description: Staged autonomy, approval, safety, and observability rules for AI-cluster workflows.
---

## Autonomous Orchestration Contract

This contract governs future orchestration capabilities built on the AI-cluster MVP. It defines safety boundaries before an executor is introduced. No autonomous executor is enabled by this contract.

## Staged Rollout

1. **Operator-only**: operators invoke setup, doctor, diagnostics, and contract scripts directly. This is the default and only enabled stage.
2. **Assisted**: an orchestrator may inspect state and propose a plan, but it cannot invoke tools or change files. An operator approves or rejects the plan outside the orchestrator.
3. **Guarded execution**: an operator explicitly approves one immutable plan and its declared scope. Each run uses a unique run ID, is limited to an allowlisted tool set, and creates changes only on a branch through a pull request.
4. **Controlled automation**: recurring or event-driven runs remain opt-in, retain the guarded-execution constraints, and require a named owner, an expiry, and a rollback procedure.

A higher stage must never be inferred from a model capability, a CI event, or the presence of credentials. Promotion requires an ADR or equivalent approved change that documents the owner, scope, approval policy, and rollback plan.

## Approval Gates

Before a guarded or controlled run, all of the following are required:

- A human-approved immutable plan containing the run ID, target repository, branch, allowed tools, expected side effects, and expiry.
- Passing relevant AI-cluster contract checks and repository CI checks.
- A healthy required MCP profile; optional profiles remain unavailable unless explicitly approved in the plan.
- Explicit confirmation for any network egress, credential use, destructive action, merge, deployment, or external write.

The orchestrator must not self-approve, merge pull requests, alter branch protection, broaden MCP permissions, or substitute a failed approval with a fallback provider.

## CI and MCP Boundaries

CI provides validation evidence, not approval. A passing workflow cannot authorize a run by itself. Orchestrated changes must use the repository's normal branch and pull-request workflow, with the same checks required of human-authored changes.

MCP remains a separately authenticated tool plane. The orchestrator receives only the least-privilege MCP profiles named in the approved plan. It must not read secrets, use filesystem or shell tools outside the approved workspace scope, or grant itself new MCP servers or permissions.

## Abort and Rollback

An abort immediately stops scheduling new tool calls and marks the run as aborted. It does not claim to undo external side effects that cannot be verified.

Every plan must declare one of these outcomes for each side effect:

- **No rollback required**: read-only work or an unsubmitted proposal.
- **Compensating action**: an idempotent, verified rollback command with an owner.
- **Manual recovery**: a documented recovery step and responsible operator.

A failed precondition, failed CI check, missing approval, policy violation, timeout, or unexpected tool result must abort the run. Recovery actions need the same approval level as the original side effect and must be recorded with the original run ID.

## Observability and Data Handling

For every assisted or higher-stage run, record a redacted event containing:

- run ID, stage, timestamp, actor, and named owner;
- approved-plan identifier, scope, expiry, and approval result;
- requested and granted MCP profiles;
- CI/contract check outcomes and relevant tool status;
- side-effect references (branch, pull request, deployment, or external ticket IDs);
- terminal state: completed, aborted, failed, or awaiting approval; and
- abort or recovery reason when applicable.

Do not record prompts, response bodies, API keys, tokens, secrets, or unrestricted filesystem content. Retention and deletion of these records must follow the existing local diagnostics and memory/RAG safety controls.

## Validation Requirements

Before enabling a stage beyond operator-only, validate:

1. An unapproved plan cannot invoke a tool or create a side effect.
2. A failing CI or required MCP health check aborts before execution.
3. A policy violation, timeout, and unexpected tool result each produce an aborted terminal event.
4. A compensating action is idempotent and requires the recorded approval level.
5. Redacted observability events include the run state and omit secret-shaped values.
