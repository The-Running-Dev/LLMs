---
title: ADR 0002 - Ecosystem Specifications and GitHub Plugin Removal
sidebar_position: 2
description: Decision record for the removal of SubZeroDev-Ecosystem-Specifications and plugins/SubZeroDev.Plugins.GitHub (issue #18).
---

# ADR 0002: Ecosystem Specifications and GitHub Plugin Removal

- Status: Accepted
- Date: 2026-08-04
- Issue: #18 Decide and codify migration/removal plan for 135 deleted files
- Owners: Workspace maintainers

## Context

[PR #22](https://github.com/The-Running-Dev/SubZeroDev.Workspace/pull/22) removed two directory
trees in the same change that added the workstation setup task orchestration:

- `SubZeroDev-Ecosystem-Specifications/**` (specification documents for a separate
  ecosystem of products: Automator, Ecosystem, MCP, Platform)
- `plugins/SubZeroDev.Plugins.GitHub/**` (a standalone plugin scaffold)

The PR description explicitly states this cleanup was intentional: *"This PR intentionally
includes broad cleanup/removal of stale spec/plugin content alongside the setup task
updates."* No migration note or dedicated decision record was published at the time,
which is the gap this ADR closes.

## Decision

Treat the removal as **intentional deletion of stale content**, not extraction to a new
location and not an accidental deletion to be restored:

- `SubZeroDev-Ecosystem-Specifications/**` described product surfaces (Automator,
  Platform, MCP strategy) that are out of scope for this workspace and were not being
  maintained here. No replacement source-of-truth is being introduced in this
  repository.
- `plugins/SubZeroDev.Plugins.GitHub/**` was a standalone plugin scaffold with no
  consumer inside this workspace. GitHub MCP integration is provided by the
  `setup-llm` workstation setup scripts instead (`setup-llm/scripts/setup-workstation.ps1`,
  `setup-llm/scripts/workstation/*`), which remain the supported path.

Both trees are considered permanently removed from this repository. If either capability
is revived, it should be done as new, independently proposed work with its own scope and
tests rather than a restoration of the deleted content.

## Follow-through

- Removed `.github/workflows/subzerodev-github-plugin.yml`: the workflow only ran
  conditional steps guarded by `if [ -d "plugins/SubZeroDev.Plugins.GitHub" ]`, so it had
  been a permanent no-op since the plugin directory was deleted.
- No other workflows, scripts, or docs in the repository referenced either removed path.

## Consequences

Positive:

- One authoritative decision is now documented in-repo, closing the ambiguity between
  intentional extraction and accidental deletion.
- No stale CI workflow remains for a directory that no longer exists.

Neutral:

- Any future need for ecosystem specifications or a GitHub plugin scaffold starts fresh,
  scoped to this workspace's current conventions (see ADR 0001 for the AI-cluster
  pattern this workspace now follows).
