---
id: 2026-05-27-v038-phase-d-skip-ledger-and-benchmark-profiles
schema_version: 1.3
date: 2026-05-27
tier: T2
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "v0.3.8 Phase D close: skip-ledger generator + four benchmark profiles + structured flake triage"
tags: [adr-0030, audit-close, phase-d, skip-ledger, benchmark-profiles, flake-triage, test-infrastructure]
triggers:
  - test_infrastructure
reversal_cost: low
decision_pressure: audit_close
provenance: live_ratified
---

## Status

Phase D of the v0.3.8 plan (`v038-plan-2026-05-25.md` §7) closed
2026-05-27 on `hardening-pass-2026-05-26-v038` (off Phase C
`672861b`).  Closes audit
`feedback_v0.3.7_to_v0.4.0_2026-05-25.md` §Test And Benchmark
Advice end-to-end.  Three deliverables ship together:

1. `flexyBayes/tools/skip_ledger.R` -- parses every
   `tests/testthat/test-*.R` via `parse()` + `utils::getParseData()`,
   classifies each skip site against a seven-class taxonomy (the
   five audit classes plus two in-portfolio extensions ratified
   below for documented flakes), writes `inst/skip-ledger.md`.
2. Four named benchmark profiles under `flexyBayes/tools/profiles/`:
   `smoke.R` (< 30 s pure-R subset), `release.R` (5 -- 10 min
   tally + skip-ledger refresh + `R CMD check --as-cran
   --no-manual`), `stress.R` (`FLEXYBAYES_RUN_STRESS=true`),
   `huge_n_probe.R` (`FLEXYBAYES_RUN_HUGE_N=true`; skeleton at
   v0.3.8, full `N = 5e6` MCMC at v0.4.0 per ADR 0027).
3. Two documented flakes (`test-smooth.R:88`,
   `test-validation-lmer.R:31`) triaged through structured
   `testthat::skip()` calls carrying `[flake-test-infrastructure]`
   and `[flake-stochastic-rng]` reason tokens; the skip ledger
   recognises both tokens and routes them into the two new
   taxonomy classes.  Cumulative effect on the tally: FAIL 2 -> 0,
   SKIP 6 -> 8, PASS lift from the +21 expectations in the new
   `test-tooling-skip-ledger.R`.

`tools/tally.R` (workspace root) sources `skip_ledger.R` as its
closing step so the ledger refreshes on every full-suite run.
`flexyBayes/.Rbuildignore` requires no modification: line 36
`^tools$` already excludes the whole `tools/` directory (including
the new `profiles/` subdir and `skip_ledger.R`) from the tarball.
The plan's spec'd specific patterns are redundant; the more
specific rules would have been defence-in-depth at the cost of
unused regex.

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Five-class taxonomy verbatim from the audit; flakes get squeezed into "deliberately deferred feature". |
| B (CHOSEN) | Seven-class taxonomy: audit's five plus two in-portfolio extensions (`test_infrastructure_flake`, `stochastic_rng_dependent`); flakes triaged through reason-token prefixes. |
| C | Fix both flakes in v0.3.8 (test isolation pass for `test-smooth.R`; TF graph reset for `test-validation-lmer.R`) rather than skip-and-defer. |

## Rationale for rejection

### Option A

The audit's five classes are about *current* skip calls
(toolchain / time-budget / stress / backend / deferred-feature),
which protect against environment shortfall.  The two flake FAILs
are a different *kind* of skip -- code-side bugs that pass in
isolation and fail under specific suite orderings.  Folding them
into "deliberately deferred feature" hides the failure mode under
a class that is meant to flag missing functionality, not flaky
tests.  A reviewer reading the ledger would draw the wrong
inference about test quality.  The two new classes are honest about
what they describe.

### Option C

The right answer for v0.3.9 (per ADR 0030 C7 refusal-registry
window).  Fixing now would couple Phase D's test-infrastructure
work to test-isolation refactoring and TF-graph-reset machinery,
both of which deserve their own bounded design pass.  The
structured-skip alternative captures the *contract* of the future
fix (the `[flake-*]` token names the class of bug) without
landing the fix prematurely.  Forward cost is one v0.3.9 line item
per flake, both already in the v038-plan deferral tail.

## Forward cost

- The two flake skips lose two test executions per full-suite run
  (~5 s total).  The contract assertions themselves (intercept
  agreement with lme4 within REML SE; smooth-sigma uniform-prior
  message under ADR 0004) are unverified until v0.3.9 isolation
  + RNG-containment work lands.  Risk: a regression that breaks
  the underlying contract would not be caught by the test suite
  during the v0.3.8 -> v0.3.9 window.  Mitigation: the
  `stress.R` profile remains as a quarterly check, and the
  v0.3.9 release plan §1 already names "skip-ledger flake
  closure" as a release gate.
- The `huge_n_probe.R` skeleton at v0.3.8 only probes preflight +
  aggregation kernel shape -- it does not run the full MCMC.  This
  means a regression in the *fit* path at `N = 5e6` is not
  detected until v0.4.0.  Per ADR 0027 trust-release gate, this
  is the intended posture for v0.3.x: scaling-to-huge-N is a
  v0.4.0 promise, not a v0.3.x promise.
- `release.R` shells out to `pkgbuild::build()` +
  `rcmdcheck::rcmdcheck()`, which adds two Suggests-grade
  dependencies (`pkgbuild`, `rcmdcheck`) to the release-ceremony
  toolchain.  These are not added to DESCRIPTION because the
  profile is workspace tooling excluded by `.Rbuildignore`
  `^tools$`.  Reviewers running the release profile must have
  both packages installed; the script raises a structured error
  if not.
- The skip-ledger reason-text keyword routing uses a small
  hand-curated optional-backends list (`greta`, `INLA`, `brms`,
  ...).  A future backend whose name does not appear in the list
  would route to `external_toolchain_unavailable` rather than
  `unavailable_optional_backend` for the bare
  `skip_if_not_installed("<new_backend>")` form.  Mitigation: the
  list is at `.skip_ledger_optional_backends` and is two lines to
  extend; the project-local `skip_if_no_<pkg>()` helper pattern
  routes correctly via call-name regardless of the list.

## References

### Empirical

- `flexyBayes/tools/skip_ledger.R` (~210 lines) -- the generator.
- `flexyBayes/tools/profiles/{smoke,release,stress,huge_n_probe}.R`.
- `flexyBayes/tests/testthat/test-tooling-skip-ledger.R` (~21
  expectations across 6 `test_that` blocks).
- `flexyBayes/inst/skip-ledger.md` (auto-generated; first
  snapshot 2026-05-27: 312 skip sites across 32 test files; class
  breakdown logged in PROJECT_LOG dated entry).
- `flexyBayes/tests/testthat/test-smooth.R:88-100` -- structured
  skip with `[flake-test-infrastructure]` token + multi-line
  preface documenting the suite-order race.
- `flexyBayes/tests/testthat/test-validation-lmer.R:41-48` --
  structured skip with `[flake-stochastic-rng]` token + multi-line
  preface documenting the TF-RNG state leak.
- `tools/tally.R` (workspace root) -- new closing block sources
  `flexyBayes/tools/skip_ledger.R` and refreshes
  `inst/skip-ledger.md`.
- Audit: `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` §Test And
  Benchmark Advice (5 reason classes + 4 benchmark profile
  names).

### Operational

- Plan: `v038-plan-2026-05-25.md` §7 (Phase D scope) + §7.4
  (commit message template) + §8 (release ceremony, NEXT).
- ADR: `design-notes-priors-brms-lgm.md` ADR 0027 trust-release
  gate -- `huge_n_probe.R` skeleton-at-v0.3.8 / full-at-v0.4.0
  posture follows the ADR contract.
- ADR: `design-notes-priors-brms-lgm.md` ADR 0030 C7 (refusal-
  registry window) -- the deferred flake fixes are named
  scope-bounded follow-on items, not silent debt.
- Discipline: `~/.claude/projects/.../memory/feedback_ledger_parallel_discipline.md`
  -- cairn authored at decision time (mid-session, before
  release ceremony), not batched at H99 close.
- Cairn: `2026-05-26-v038-phase-c-audit-drift-close.cairn.md`
  (Phase C close; Phase D is the immediate successor).
- Cairn: `2026-05-26-aggregated-inla-dispatch-fix-class-vector.cairn.md`
  (the dispatch fix shipped alongside Phase C; informs Phase D's
  treatment of the 13th-H99-mis-triaged flake category).
