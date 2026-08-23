---
title: Memory and RAG Retention Contract
sidebar_position: 6
description: Retrieval boundaries, lifecycle, deletion, and safety controls for persistent memory and RAG artifacts.
---

## Memory and RAG Retention Contract

This contract defines how durable memory and retrieval artifacts should behave in the workspace when a memory or RAG layer is added.

## Retrieval Boundaries

- Retrieval is a support layer, not a source of truth.
- Durable memory may summarize conventions, preferences, and stable lessons.
- Retrieval must not override committed source files, ADRs, or current runtime output.
- Transient task status belongs in the session/workflow context, not long-lived memory.

## Index Lifecycle

- Create indexes from versioned source or explicitly selected local artifacts.
- Rebuild indexes when the codebase changes materially.
- Invalidate or regenerate indexes after model, embedding, or corpus changes that alter retrieval meaning.
- Treat every index build as disposable and reproducible from the underlying sources.

## Migration Constraints

- Changing embedding models or vector dimensions requires a fresh index or a documented migration path.
- Index migrations must be explicit, versioned, and reversible where practical.
- Do not silently mix incompatible embedding dimensions in the same retrieval store.
- Migration decisions must be recorded in docs or ADRs before rollout.

## Privacy and Deletion Guarantees

- Secrets, API keys, and prompt bodies do not belong in persistent memory or RAG artifacts.
- Local memory/index directories should remain outside version control.
- Deletion must remove both the index artifact and any generated caches or snapshots associated with it.
- A workspace reset should be able to remove local memory/RAG state without affecting the Git repository.

## Suggested Local Artifact Paths

The setup workspace ignores these local-only directories by default:

- `setup-llm/memory/`
- `setup-llm/rag-index/`
- `setup-llm/rag-cache/`

## Smoke Tests

When a memory/RAG layer is introduced, validate the following before use:

1. Retrieval determinism: the same query against the same index returns the same result ordering.
2. Safety controls: secret-shaped content is not persisted or echoed back by default diagnostics.
3. Deletion: removing the local memory/RAG directories removes the retrievable state.
4. Migration: a changed embedding model or vector dimension requires a rebuild, not a silent reuse.

## Operational Guidance

- Prefer checked-in docs, ADRs, and source files over retrieved summaries for authoritative decisions.
- Use durable memory to store stable lessons, not volatile task state.
- Keep RAG usage narrow and explicitly scoped to the repository or project that owns the artifacts.
- If a retrieval system becomes stale or unsafe, disable it before it becomes a hidden dependency.
