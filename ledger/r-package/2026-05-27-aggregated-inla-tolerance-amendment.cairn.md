---
id: 2026-05-27-aggregated-inla-tolerance-amendment
schema_version: 1.3
date: 2026-05-27
tier: T2
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "Aggregated INLA bit-exact identity test tolerance loosened to 5e-3 always-on; 1e-3 spike-floor kept stress-gated (v0.3.9 Phase B')"
tags: [v039, phase-b-prime, aggregated-inla, blas-non-associativity, tolerance-amendment, stress-gated, adr-0022]
triggers:
  - test_tolerance_amendment
  - blas_drift_acknowledgement
reversal_cost: low
decision_pressure: refactor
provenance: live_ratified
---

## Status

Decided 2026-05-27 during v0.3.9 Phase B'. The test
`test-emit-gaussian-aggregated.R` `INLA per-row + aggregated agree
on beta within 1e-3 under matched defaults` (line 284 pre-v0.3.9
Phase B') was flagged in the v0.3.8 Phase D triage
(`state_v038_released.md`) as a stochastic-flake site: deterministic
in isolation but observed at delta `3.4e-3` in a Phase D full-suite
run. The pre-v0.3.9 1e-3 threshold was theoretical -- the
`R/emit_gaussian_aggregated.R:30-41` spike documentation reports
differences `<= 1e-4` on a 1000-row example, and isolated runs of
this fixture deliver roughly `5e-4`. Full-suite ordering inherits
BLAS reduction-order drift and accumulated INLA-side session state
from prior fits, which lifts the observed delta into the `~3.4e-3`
band.

The amendment splits the assertion into two test_that blocks
sharing the same fixture:

| Path | Tolerance | Gate |
|---|---|---|
| Primary | `5e-3` (10x spike, 1.5x observed worst) | Always on |
| Secondary | `1e-3` (the original spike-anchored band) | `FLEXYBAYES_RUN_STRESS=true` |

The primary tolerance was chosen to provide a 5x guard against
gross algebraic regression while absorbing the empirical worst-
case BLAS + session-state drift at this fixture size. The
secondary preserves the spike-floor as a release-rehearsal probe
under the stress profile (joins the existing five stress-only
blocks).

Full-suite tally at branch HEAD after Phase B':
**PASS 1894 / FAIL 0 / SKIP 8** (was 1894/0/7 at Phase B close;
SKIP count grew by 1 from the new stress-gated block). All three
v0.3.8-deferred stochastic flakes now have zero residual entries
in `inst/skip-ledger.md` under both `[flake-*]` classes; the new
Stress-only class entries are all opt-in by design.

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Status quo: keep the 1e-3 always-on assertion, accept the v0.3.8 flake observation, re-flag for triage at v0.3.10. |
| B (CHOSEN) | Loosen always-on to 5e-3 + add a stress-gated 1e-3 companion. |
| C | Investigate INLA-side session state (num.threads, smtp, BLAS thread pool) to remove the source of the drift. |
| D | Loosen unconditionally to 1e-2 (10x observed worst, no stress companion). |

## Rationale for rejection

### Option A

Already triaged as a flake at v0.3.8 close; deferring without
amendment is the same posture and would re-fire the
`[flake-stochastic-rng]` skip class in v0.3.9 inst/skip-ledger.md.
The v0.3.9 Phase A and Phase B cairns aim at a zero-residual flake-
class invariant for the release; Option A would carry the lone
INLA-side flake across that boundary without progress.

### Option C

Open-ended investigation into INLA's internal numerical engine.
INLA's parallel reductions depend on BLAS thread count and op
order; both are environment-coupled and the upstream R-INLA
package does not expose hooks for fixing them at the test
boundary. Mitigation would require either pinning
`OMP_NUM_THREADS=1` process-wide before R starts (out of scope
for the test runner) or adopting `inla(control.compute$smtp = ...)`
configuration that may itself drift across INLA versions.
Deferred indefinitely until the cost of the loosened-tolerance
posture is shown to mask a real regression.

### Option D

Functionally equivalent to Option B for the always-on path but
loses the spike-floor coverage in any mode. The stress-gated
companion preserves the algebraic-identity claim in the release-
rehearsal probe at negligible maintenance cost.

## Forward cost

- Test-coverage discipline: the always-on band of `5e-3`
  detects gross algebraic regressions (delta > 5e-3 indicates a
  structural break in the matched-prior identity, not BLAS
  noise). The strict `1e-3` floor lives in the stress profile.
- The empirical worst-case observation (3.4e-3) is fixture-
  specific; if a new fixture is added that pushes worst-case
  higher, the always-on tolerance should be re-calibrated per
  the same shape (10x spike-floor; 1.5x observed worst-case at
  the fixture).
- A future Phase C / v0.3.10 candidate is a `process-isolated
  INLA harness` that runs aggregated-INLA assertions in a fresh
  R subprocess to fully insulate from session-state drift. This
  would let the always-on band collapse back toward the
  spike-floor and is the natural successor if the loosened
  posture ever masks a regression in practice.
- ADR 0022 (Stage 3A Gaussian exact aggregation) status header
  is unaffected; the amendment is test-tolerance-only and does
  not change the algebraic identity claim documented in
  `R/emit_gaussian_aggregated.R:30-41`. A note for the v0.3.9
  Phase D documentation sweep: the aggregated-gaussian section
  of NEWS.md should mention the Phase B' amendment alongside
  the v0.3.5 BLAS non-associativity precedent.

## References

### Methodological

- The `1e-4` spike claim at `R/emit_gaussian_aggregated.R:30-41`
  rests on a closed-form decomposition of the INLA `loggamma`
  precision-prior into a per-row + Delta correction (the spike
  proof in `spikes_stage3a/spike_inla.R`). The decomposition is
  algebraically exact; the residual delta is the numerical-
  engine noise floor.
- BLAS non-associativity: floating-point sum order changes the
  bit-pattern of inner products. At the matrix sizes used in
  INLA's Laplace approximation, the per-row vs aggregated paths
  compose different inner-product accumulation orders; the
  resulting bit-pattern divergence is ULP-scale per element but
  accumulates over the precision-matrix factorisation.

### Empirical

- `flexyBayes/tests/testthat/test-emit-gaussian-aggregated.R:284-302`
  -- the always-on primary path at 5e-3 tolerance with cite to
  this cairn.
- `flexyBayes/tests/testthat/test-emit-gaussian-aggregated.R:304-322`
  -- the stress-gated secondary path at 1e-3 tolerance,
  joining the existing stress-only blocks under
  `tools/profiles/stress.R`.
- `flexyBayes/R/emit_gaussian_aggregated.R:30-41` -- the spike
  documentation pinning the theoretical band at `1e-4`.

### Operational

- ADR: `design-notes-priors-brms-lgm.md` ADR 0022 (Stage 3A
  Gaussian exact aggregation; algebraic identity claim).
- ADR: `design-notes-priors-brms-lgm.md` ADR 0023 §amendment
  v0.3.5 (BLAS non-associativity interpretation of
  `testthat::expect_equal` default tolerance; the parallel
  precedent for "loosen tolerance with documented rationale"
  at this layer).
- ADR: `design-notes-priors-brms-lgm.md` ADR 0025 (known-
  covariance input formats; the v0.3.7 close amended subtest
  (d) tolerance for similar reasons).
- Cairn: `2026-05-27-emit-state-latch-env-migration.cairn.md`
  (v0.3.9 Phase A).
- Cairn: `2026-05-27-tf-rng-containment-hybrid-sleepstudy.cairn.md`
  (v0.3.9 Phase B); the stress-gated hybrid pattern was
  adopted here.
- Memory: `state_v038_released.md` -- the v0.3.8 release-close
  state that documented the `3.4e-3` observation and deferred
  to v0.3.9.
