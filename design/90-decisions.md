# Decision log

Append-only. Newest at the top. The rejected alternatives are the point — without them, every future session relitigates the same choice.

## Open
<A staging area, not a home. Things noticed mid-slice that were deliberately not acted on. `/track` turns each into a GitHub issue and removes it from here. An item that is a *decision* rather than a *todo* belongs below as an entry, not in an issue.>

---

### 2026-08-23 — Re-install: sync cores/tools to kit HEAD `9911712`, catch `AGENTS.md` up
Context: a re-install from `SubZeroDev.AgentKit` (kit HEAD `9911712619cd3e6522d015158edf702371a5971c`), reconciling this repository, which was last synced at `syncedCommit` `80a19bdd25d715248ba40fdad93eddd2e2538984` (2026-08-20, PR #36, already merged to `main`). `.claude/kit.json`'s `commit` field was still `6bdd8dcc` — the 2026-08-13 install's own record — never advanced to `80a19bd`, evidently missed by that pass.
Chosen:
- `.claude/commands/{done,install-all,kit-help,kit-sync}.md`, `install-code-review-agent.md` (new) — taken outright via `tools/Sync-Kit.ps1`, no reconciliation; cores are the kit's.
- `tools/{Read-DesignState,Test-CIWorkflow,Test-DesignState,Update-DesignProjection}.Tests.ps1`, `tools/Invoke-CodexCommand.ps1` (new) — same, taken outright.
- `AGENTS.md` — hand-reconciled four spots stale since the 2026-08-13 merge: added the `/install-code-review-agent` routing row; widened the *External writes* carve-out to name `/install`/`/kit-sync` opening PRs (and `/install-all`'s deliberate exclusion); added the new *Marked regions* section; updated the agent-block bullet to reference it instead of restating the marker form inline. None competed with the target's own `Project identity` section or any target-authored rule — this was the kit's rule content advancing past what the target had merged, not a value conflict.
- `.github/ISSUE_TEMPLATE/bug.md` — left untouched. The kit's wording changed, but the target already has its own template; `INSTALL.md` phase 1 stops on divergence here rather than reconciling.
- `.claude/kit.json` — `commit` advances to `9911712619cd3e6522d015158edf702371a5971c`, `installed` to `2026-08-23`, `syncedCommit` left as `Sync-Kit.ps1` wrote it.
Rejected:
- Leaving `AGENTS.md`'s four gaps unmerged — the alternative was to defer them to a later install, which is exactly the drift the 2026-08-13 entry's own missed `commit` bump shows compounds silently.
- Overwriting `.github/ISSUE_TEMPLATE/bug.md` with the kit's newer wording — rejected per `INSTALL.md`'s explicit rule: a target with its own template has its own triage process, and silent replacement changes how every future issue is filed.
Reversibility: cheap — each file change here is independently revertible; the `AGENTS.md` edits are additive except the one routing-row relocation, which is cosmetic (table order only).

### 2026-08-13 — Install `design/`, the `codex/PROFILES.md` seed, and the `Measure-Session.ps1` hooks
Context: an interactive `/install` from SubZeroDev.AgentKit (kit commit `6bdd8dcc347bb3c09a746bb27a204e7fbb205d49`) reconciling this repository, which already carried the kit's command cores, `agent.md`, and `AGENTS.md`/`CLAUDE.md` from an earlier unattended `/install-all` run (kit commit `9b8313cd67cbfbf38c95d105b7f35fffe341532d`, 2026-08-04) that left several named forks unresolved because an unattended pass cannot decide them.
Chosen:
- `design/` — install the `templates/design/` seed at the repository root. Neither occupied nor shadowed by an existing `plans/`/`adr/`/`decisions/`/`rfc/` directory, and `AGENTS.md`'s precedence list was already referencing files that did not exist.
- `codex/PROFILES.md` — install it now, ahead of direct evidence (no `.codex/` directory or profile reference in this repository), on explicit request.
- `.claude/settings.json` — create it containing only `hooks.SessionEnd` and `hooks.UserPromptSubmit`, both calling `tools/Measure-Session.ps1` (`-Hook` / `-Watch`). `pwsh` confirmed on `PATH`; no prior hook on either event to collide with; no other `settings.json` key touched.
- `AGENTS.md` — reconcile the stale 2026-08-04 content up to kit HEAD (Vendor model aliases, Third-party text, The design freeze, work-start/session-boundary banners, and the rewritten `Tracking work`/`Git and delivery` delegation language), preserving the target's `Project identity` section verbatim. Its `Why it is installed this way` section is superseded by this entry and removed, since `design/` is now this repository's canonical decision log.
Rejected:
- Leaving `design/` out again — the alternative was to keep the precedence list aspirational indefinitely, which is what the 2026-08-04 run's own unresolved-fork note flagged as needing a decision.
- Skipping `codex/PROFILES.md` pending evidence — the alternative was to wait for a `.codex/` directory or profile reference to appear before installing, deferring a cheap, reversible file for no operational reason once explicitly requested.
- Leaving the hooks unwritten — the alternative was to keep deferring `Measure-Session.ps1`'s SessionEnd/UserPromptSubmit wiring indefinitely; nothing blocked it once `pwsh` was confirmed present and both hook slots were confirmed empty.
- Keeping `AGENTS.md`'s decision history inline under `Why it is installed this way` — the alternative duplicates this file once `design/` exists, which `AGENTS.md`'s own *Single ownership* rule forbids.
Reversibility: cheap — `design/`, `codex/PROFILES.md`, and the hooks in `.claude/settings.json` are each independently deletable without touching the rest of the install.

### 2026-08-04 — First install via unattended `/install-all`, three forks left unresolved
Context: `SubZeroDev.AgentKit` installed unattended (`/install-all`) at kit commit `9b8313cd67cbfbf38c95d105b7f35fffe341532d`, into a repository with neither `AGENTS.md` nor `CLAUDE.md` and no prior kit install.
Chosen:
- `AGENTS.md`/`CLAUDE.md` direction — the kit's default arrangement: `AGENTS.md` holds the contract, `CLAUDE.md` becomes a pointer. Install-time additions limited to a `Project identity` section sourced from `README.md`; the rest of `AGENTS.md` is the kit's contract verbatim.
- `agent.md` — install the kit's full seed unpruned; pruning requires proposing deletions and waiting for sign-off, which an unattended run cannot do.
- `.claude/commands/`, `.github/ISSUE_TEMPLATE/`, `tools/Measure-Session.ps1` — install as-is; no name collisions, no path rewrite needed since `design/` was not relocated.
Rejected (left open, not decided):
- `design/` — not created; an unattended run cannot resolve this named fork on its own authority. Resolved above, 2026-08-13.
- `codex/PROFILES.md` — skipped per `INSTALL.md`'s default (no `.codex/` evidence in this repository's own agent workflow, as distinct from the projects it scaffolds *for* Codex). Reversed above, 2026-08-13.
- `SessionEnd`/`UserPromptSubmit` hooks — not written; `INSTALL.md` requires proposing the exact JSON and waiting, unconditionally, which an unattended run does not do regardless of `pwsh` availability. Resolved above, 2026-08-13.
Reversibility: cheap.

---
