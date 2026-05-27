---
id: 2026-05-26-v038-phase-c-audit-drift-close
schema_version: 1.3
date: 2026-05-26
tier: T2
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "v0.3.8 Phase C `docs:` close: audit drift items + `--only` precompile flag + vignette-zero-drift finding"
tags: [adr-0024, adr-0030, audit-close, phase-c, vignette, precompile, news]
triggers:
  - documentation_restructure
reversal_cost: low
decision_pressure: audit_close
provenance: live_ratified
---

## Status

Phase C of the v0.3.8 plan (`v038-plan-2026-05-25.md` §6) closed
2026-05-26 with commit `ce21128` on
`hardening-pass-2026-05-26-v038`. Package-side audit drift
(`feedback_v0.3.7_to_v0.4.0_2026-05-25.md` §Documentation And
Governance Drift bullets 4 + 5 + 6) closes; workspace-side audit
drift (bullets 1 + 2 + 3) lands as workspace state (the
flexyBayes_dev/ root is not a git repo per project §10).
Selective vignette re-precompile reduces to a no-op for the
prose-changing subset (no vignette static `.Rmd` renders
`Exact.:`); `--only` flag ships as future-use infrastructure.

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Full 12-vignette sweep regardless of finding (re-precompile everything). |
| B (CHOSEN) | Selective per §12.3 ratification; ship the `--only` flag; document the vignette-zero-drift finding. |
| C | Defer all vignette work to v0.4.0; close audit Critical Fix #4 vignette bullet as "no drift to repair". |

## Rationale for rejection

### Option A

Costs hours of MCMC runtime on a no-op finding (none of the
vignettes carry stale `Exact.:` text). The full sweep is also
correctly deferred to the v0.4.0 vignette deck restructure per
§12.3, where renumbering and the new entry-point hierarchy will
trigger a full re-precompile regardless. Doing it twice would
waste compute.

### Option C

Skips the `--only` flag work that the audit explicitly named in
§6.2; leaves no infrastructure for future selective refreshes
when individual vignettes do drift. The `--only` flag is cheap
to add (one CLI-arg parse + one substring filter) and pays for
itself the first time a single vignette needs refreshing.

## Forward cost

- Vignette static `.Rmd` files remain as-rendered against an
  earlier `print()` / `summary()` shape -- the `Exact.:` field
  the v0.3.6 Stage 4 ADR 0024 work added was never rendered
  into any vignette, so the absence is pre-existing, not new.
  The deeper question -- "vignettes are out of date with the
  current package" -- is real and defers to v0.4.0 alongside
  the deck restructure per §12.3.
- The `--only` precompile flag uses substring match against
  vignette basenames. `--only 08` matches
  `flexyBayes-08-downstream-analysis`; `--only triangulation`
  matches `flexyBayes-10-triangulation`. Substring matching is
  more user-friendly than exact basename matching but does
  carry a small risk: if a future vignette is added whose
  basename contains a previously-unique token, the same `--only
  <token>` invocation will silently pick up both. Watch for
  this when adding vignettes whose names overlap existing
  prefixes.
- Workspace-side audit items (AGENTS.md, workspace README.md,
  AMBITION_STAGE.md §8.6, ADR 0024 amendments) are captured in
  the workspace tree and PROJECT_LOG, not in git. This is
  per-project convention (§10); changes to workspace-only state
  do not enter shared history. The audit considers these closed
  on the basis of the workspace state alone.
- Phase D (`test:` skip ledger + benchmark profiles) is the
  remaining v0.3.8 work; release ceremony (no-ff merge to
  `main`, lockstep version bump, tag, tarball checkpoint, dev-
  bump) follows.

## References

### Empirical

- `flexyBayes/NEWS.md` (lines 1-130) -- new v0.3.8 section.
- `flexyBayes/README.md` (install block) -- local-tarball
  install path.
- `flexyBayes/cran-comments.md` (lines 5 + 49) -- v0.3.8 bump.
- `flexyBayes/vignettes/_precompile.R` (lines 1-30, 47-85) --
  `--only` flag.
- Audit: `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` §Documentation
  And Governance Drift, bullets 4 / 5 / 6 (package-side); bullets
  1 / 2 / 3 (workspace-side, closed in workspace state).

### Operational

- ADR: `design-notes-priors-brms-lgm.md` ADR 0024 §Consequences
  amendments (post-v0.3.6 close) updated to reflect the
  v0.3.7 -> v0.3.8 -> follow-on deferral chain for the
  per-term INLA memory estimator and the vignette companion.
- ADR: `design-notes-priors-brms-lgm.md` ADR 0030 Decision 4
  (Representation: / Engine: two-line truth display) -- the
  vignette-zero-drift finding is the empirical answer to "did
  this change propagate to vignettes": it didn't, because the
  previous field was never rendered there either.
- Cairn: `2026-05-25-fb-plan-verb-exported-as-single-planning-surface.cairn.md`
  (ADR 0030 contract C1; the planner verb behind the Phase B
  feat: that the Phase C docs sweep references in NEWS).
- Cairn: `2026-05-25-representation-engine-two-line-truth-display.cairn.md`
  (ADR 0030 Decision 4; the truth-display extension that
  triggered the vignette-drift question in the first place).
- Cairn: `2026-05-26-aggregated-inla-dispatch-fix-class-vector.cairn.md`
  (the `fix:` correction shipped alongside Phase C and
  referenced in the new NEWS Corrections sub-section).
- Plan: `v038-plan-2026-05-25.md` §6 (Phase C scope) + §12.3
  (selective-vignette ratification).
- Commit: `ce21128` on `hardening-pass-2026-05-26-v038`.
