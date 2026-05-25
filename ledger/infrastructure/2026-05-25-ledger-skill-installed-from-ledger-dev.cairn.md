---
id: 2026-05-25-ledger-skill-installed-from-ledger-dev
schema_version: 1.1                          # required; current canonical schema
date: 2026-05-25
tier: T2
classification: open
export_status: local_only                    # required; local_only | export_ready | exported
consensus_mode: none
domain: infrastructure
project: flexyBayes
status: accepted                             # required; draft | proposed | accepted | paused | awaiting_resolution | superseded | rejected. See SCHEMA.md §2.1.
title: "/ledger skill installed (SKILL.md + lib/ at the harness skills root)"
tags: [ledger, skill_install, infrastructure, v038_phase_b_session]
triggers:
  - new_internal_helper
  - test_infrastructure
reversal_cost: medium                        # optional; low | medium | high | severe
decision_pressure: null                      # optional; audit_close | deadline | publication | security | refactor | client
review_due: null                             # optional; ISO date for scheduled re-review
review_trigger: null                         # optional; prose trigger ("before v0.4.0 release")
supersedes: []                               # cairn IDs this replaces
superseded_by: null                          # set when this cairn is replaced (and status -> superseded)
related: []                                  # operational links to other cairn IDs
---

## Status

Ratified 2026-05-25 at the start of the v0.3.8 Phase B implementation session. Max's H00 directive was "is /ledger graduated and installed? if yes -- use it, if not -- fix it to working conditions". Investigation surfaced that `~/Projects/CLAUDE_PROJECTS_LOCAL/ledger_dev/lib/` had complete P0--P1 + P6.5 implementation (init / add / validate / reindex / query / archaeology, plus templates and fixtures, all earned-keep gates met) but two missing pieces blocked harness discovery: no top-level `SKILL.md` frontmatter, and `install.sh --apply` had never been run. Both were fixed in-session before any Phase B code landed.

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Skip /ledger entirely and write Phase B decisions to PROJECT_LOG.md only |
| B | Author SKILL.md directly at the harness-side skill root (no workspace source) |
| C (CHOSEN) | Author SKILL.md in `ledger_dev/` workspace + extend install.sh to copy it; then run `install.sh --apply` |
| D | Defer install until after Phase B; capture cairns retroactively via /ledger archaeology |

## Rationale for rejection

### Option A

PROJECT_LOG.md captures *what happened* dated-entry style but does not structure *the alternatives that were rejected and why* in a backward-auditable way. The audit-close decisions Phase B ratifies (refusal-registry scaffold-only, fb_plan brms-shape entry, plan_field=NA_character_ default) all have meaningful unchosen options; losing them to a one-line PROJECT_LOG entry would defeat the cairn-archive purpose. The decision pressure was specifically to capture them as cairns, not narrative entries.

### Option B

Faster (single write) but violates the ledger_dev source-of-truth invariant. The workspace exists precisely so that schema changes, command edits, and installation tooling flow through one place + propagate via install.sh. Direct edits to the installed skill root would silently diverge from `ledger_dev/` and the next `install.sh --apply` would overwrite the manual SKILL.md (or fail to install it if the convention drifts again).

### Option D

The archaeology sub-skill (P6.5) is for reconstructing decisions that were never captured contemporaneously. Phase B decisions are being made *now* -- the archaeological mode would mark them with `provenance: archaeological_reconstruction` and lower confidence, which mischaracterises a live ratification as a post-hoc reconstruction. Reserving archaeology for genuine historical recovery (the 18 drafts already in `.archaeology_drafts/`) preserves the provenance distinction.

## Forward cost

- **install.sh now copies two artefacts** (lib/ + SKILL.md) rather than one. Any future top-level addition (e.g., REFERENCES.md, CHANGELOG.md) requires a third edit to install.sh. Acceptable given how rarely top-level artefacts land.
- **SKILL.md description string is the discovery surface**; if the trigger keyword list grows stale (e.g., new commands like `/ledger export` ship at P3), the description must be updated and `install.sh --apply` re-run. No automated drift detection.
- **The skill loads on every harness invocation in any project** -- the description appears in the available-skills list system-wide. The cost of a wrong description is a missed routing decision, not silent failure.
- **`flexyBayes/ledger/` now contains live cairns** that will be cited from `design-notes-*.md` ADR ledger entries (per the /rpkg-genesis composition), from /paper methods-paper supplements, and eventually by the ADR amendment pass when v0.3.8 closes. Removing /ledger later would break these cross-references.
