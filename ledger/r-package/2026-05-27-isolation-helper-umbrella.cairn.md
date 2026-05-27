---
id: 2026-05-27-isolation-helper-umbrella
schema_version: 1.3
date: 2026-05-27
tier: T2
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "Single-call test-isolation umbrella local_flexybayes_clean_state() composes emit-state + TF-seed helpers (v0.3.9 Phase C)"
tags: [v039, phase-c, test-isolation, helper-isolation, composition, discipline-rule]
triggers:
  - test_infrastructure_consolidation
reversal_cost: low
decision_pressure: refactor
provenance: live_ratified
---

## Status

Decided 2026-05-27 during v0.3.9 Phase C. Phase A
(`2026-05-27-emit-state-latch-env-migration.cairn.md`) and Phase B
(`2026-05-27-tf-rng-containment-hybrid-sleepstudy.cairn.md`) landed
two independent test-isolation helpers --
`tests/testthat/helper-emit-state.R` and
`tests/testthat/helper-rng.R` -- covering two distinct leak classes
(emit-once latch + TF-side RNG state). Both classes share a root
cause: state that survives the test_that frame, persisting across
files in `tools/tally.R`'s single-process loop. Phase C ties them
together under a single-call umbrella so a future test that
exercises both surfaces (a greta-MCMC fit that also triggers the
default-prior emission, e.g., a sleepstudy-shape model under the
default uniform-on-SD prior) can scope both contracts in one line.

`tests/testthat/helper-isolation.R` exposes
`local_flexybayes_clean_state(seed = NULL, .local_envir =
parent.frame(), deterministic_ops = FALSE)` which calls
`local_clean_emit_state()` unconditionally and `local_tf_seed()`
when a `seed` is provided. The umbrella is a thin composer --
each underlying helper remains the right entry point for tests
that touch only one surface. The file header consolidates the
cross-helper discipline rules:

* Never use bare `options(flexyBayes.* = ...)` in test code.
* Greta-MCMC numerical-agreement tests must call `local_tf_seed()`.
* Tests with deterministic emit-state expectations must call
  `local_clean_emit_state()`.

Full-suite tally at branch HEAD: PASS 1894 / FAIL 0 / SKIP 8
(unchanged from v0.3.9 Phase B' close; Phase C adds infrastructure
without changing assertion shape).

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Keep the two helpers as-is; let each test call them in sequence when needed. |
| B (CHOSEN) | Thin composer umbrella `local_flexybayes_clean_state()` in a new helper-isolation.R file that documents the cross-helper discipline contract. |
| C | Inline both helpers into a single `local_flexybayes_clean_state()` function (delete helper-emit-state.R and helper-rng.R). |

## Rationale for rejection

### Option A

Functionally adequate but loses the single documentation surface.
The cross-helper discipline rules belong in one place; a future
contributor scanning the test directory should see "this is the
isolation contract for the entire test suite" in one file. The
umbrella file's header is that surface.

### Option C

Conflates two independent contracts. The emit-state helper
applies to any test that hits the default-prior path (greta or
INLA, MCMC or codegen-only). The TF-seed helper applies only to
greta-MCMC tests asserting numerical agreement. Inlining would
force every emit-state-sensitive test to also drag in the TF-
seed reset, even when greta is not loaded. Keeping the helpers
separable preserves the orthogonal-axes pattern.

## Forward cost

- Test-author discipline: when a new test exercises both
  surfaces, prefer `local_flexybayes_clean_state(seed = ...)`
  over two sequential helper calls. For single-surface tests,
  call the targeted helper directly. The umbrella file header
  is the discipline-documentation single source of truth.
- Future Phase / v0.3.10 candidate: a `tools/verify_test_hygiene.R`
  assertion that the full-suite run ends with the same
  `flexyBayes.*` options + the same emit-state env shape as it
  started. Catches new tests that introduce leaks before the
  next tally surfaces them as suite-order flakes. Mentioned in
  the Phase A cairn forward cost; Phase C umbrella is the
  natural home for the entry-point doc once the script lands.
- The umbrella adds no new package-side state; all of the
  isolation contract lives in test infrastructure. Removing the
  umbrella reverts to two sequential helper calls with no
  behaviour change.

## References

### Empirical

- `flexyBayes/tests/testthat/helper-isolation.R` -- the new
  umbrella + the cross-helper discipline rules in the file
  header (~50 lines including documentation).
- `flexyBayes/tests/testthat/helper-emit-state.R` -- Phase A
  helper.
- `flexyBayes/tests/testthat/helper-rng.R` -- Phase B helper.

### Operational

- Cairn: `2026-05-27-emit-state-latch-env-migration.cairn.md`
  (Phase A; the `local_clean_emit_state()` half of the umbrella).
- Cairn: `2026-05-27-tf-rng-containment-hybrid-sleepstudy.cairn.md`
  (Phase B; the `local_tf_seed()` half of the umbrella).
- Memory: `feedback_bare_options_in_r_tests.md` -- the cross-
  project rule cited in the umbrella file header.
