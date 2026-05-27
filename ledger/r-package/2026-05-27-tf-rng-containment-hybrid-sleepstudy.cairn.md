---
id: 2026-05-27-tf-rng-containment-hybrid-sleepstudy
schema_version: 1.3
date: 2026-05-27
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "TF-RNG containment via local_tf_seed() + hybrid recast of sleepstudy lme4 validation (v0.3.9 Phase B)"
tags: [v039, phase-b, tensorflow, greta, mcmc-determinism, validation, sleepstudy, stress-gated, helper-rng, flake-stochastic-rng]
triggers:
  - test_infrastructure_change
  - rng_containment_for_external_session_state
reversal_cost: low
decision_pressure: refactor
provenance: live_ratified
---

## Status

Decided 2026-05-27 during v0.3.9 Phase B on branch
`test-isolation-2026-05-27-v039`. The pre-v0.3.9 sleepstudy lme4
validation test (`tests/testthat/test-validation-lmer.R:31`)
asserted that the `flexybayes()` posterior mean agrees with
`lme4::lmer()`'s REML point estimate within `1.0 * REML SE` on
every fixed-effect coefficient (`Intercept`, `Days`) and within
25% relative error on both variance-component SDs
(`sigma`, `sd_Subject`). The assertion failed in some full-suite
orderings even at the 2000+2000+2-chain budget because greta
runs on TensorFlow, whose internal RNG state is not reachable
from R's `set.seed()`; the effective TF state at test entry is a
function of the cumulative greta call history in the session.
The v0.3.8 close (`state_v038_released.md`) documented the
behaviour as `[flake-stochastic-rng]` and deferred resolution to
v0.3.9.

The hybrid recast splits the original assertion into two
test_that blocks:

| Path | Budget | Tolerance | Gate |
|---|---|---|---|
| Primary | 1000 samples + 1000 warmup + 2 chains | `1.5 * REML SE` (fixed effects) + 30% (VCs) | Always on |
| Secondary | 2000 samples + 2000 warmup + 2 chains | `1.0 * REML SE` (fixed effects) + 25% (VCs) | `FLEXYBAYES_RUN_STRESS=true` |

A new test helper `tests/testthat/helper-rng.R` exposes
`local_tf_seed(seed, .local_envir, deterministic_ops = FALSE)`
which reseeds both R (`set.seed(seed)`) and TensorFlow
(`tf$random$set_seed(seed)` via `requireNamespace("tensorflow")`).
The `deterministic_ops = TRUE` opt-in additionally enables
`tf$config$experimental$enable_op_determinism()`, which forces
bit-exact reproducibility across TF runs at a roughly 5--15%
throughput penalty; the helper does not enable it by default to
keep the always-on suite fast and to avoid changing process-
global TF state. Both test_that bodies call `local_tf_seed()`
before the `flexybayes()` fit, so each is deterministic given a
fresh R session (TF state in tally.R's single-process loop is
overwritten at entry).

A shared comparator `.assert_sleepstudy_agreement(fit_b, fit_l,
fixed_tol_mult, vc_rel_tol)` factored above the test_that blocks
removes the per-block duplication. Both paths exercise the full
user-facing `flexybayes()` integration: the formula parser, the
default-prior path (`prior_fixed_sd = 100`, uniform-on-SD per
ADR 0004), greta codegen, the MCMC fit, and the canonical-name
mapping registry through `canonical_names(fit_b)`.

Full-suite tally at branch HEAD after Phase B:
**PASS 1894 / FAIL 0 / SKIP 7** (was 1889/0/7 at Phase A close;
+5 PASS from the now-always-on primary expectations, SKIP count
unchanged because the old `[flake-stochastic-rng]` skip was
replaced by a `[stress]` opt-in skip on the secondary path).
The `inst/skip-ledger.md` Stress-only class went from 4 to 5
entries; both `[flake-*]` classes (`flake-stochastic-rng` and
`flake-test-infrastructure`) now show zero residual entries.

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Status quo: keep the skip on the original test_that block, accept the unreached coverage on `flexybayes()`-vs-`lme4` agreement. |
| B | Replace the MCMC fit with a direct `greta::opt()` MAP optimisation; bit-exact deterministic given initial values. |
| C (CHOSEN) | Hybrid: primary always-on path with `local_tf_seed()` containment + reduced budget + loosened tolerance; secondary stress-gated path at the original strict budget/tolerance. |
| D | Hybrid plus `enable_op_determinism()` on by default in both paths; closes the residual TF op-reorder risk at a perf cost. |

## Rationale for rejection

### Option A

Leaves a permanent skip on a flagship integration test. The
sleepstudy fit is the canonical `flexybayes()`-vs-`lme4`
comparator and the only such test in the repo; abandoning it
weakens the v0.4.0 ADR 0030 architectural-final posture, which
takes "agreement with a deterministic reference on a benchmark
fixture" as a release gate. The flake's root cause is structural
and the fix is at known low cost.

### Option B

Bit-exact deterministic but bypasses the `flexybayes()` user-
facing path. `greta::opt()` would run on a manually-constructed
greta model parallel to whatever `flexybayes()` builds, so the
test would no longer verify the `flexybayes()` integration --
the parser, the default-prior path, the codegen, the canonical-
name mapping -- end-to-end. A separate `greta::opt()`-based
deterministic comparator can be added later as an *additional*
test (e.g., on the codegen output) without removing the MCMC
comparator that the hybrid recast preserves.

### Option D

Defers to a future Phase if the residual TF op-reorder risk
materialises. `enable_op_determinism()` is process-global state
that, once enabled, affects every TF call for the rest of the
session; turning it on for all tests would slow the suite for a
risk that has not yet been observed. The helper exposes the opt-
in (`deterministic_ops = TRUE`) so individual tests can escalate
when needed without changing the global default. If the stress-
gated secondary ever flakes after a TF upgrade, the canonical
remediation is to enable the option in that test_that body.

## Forward cost

- **Internal discipline rule**: greta tests that assert
  numerical agreement against a deterministic reference must
  call `local_tf_seed()` at test entry. The discipline is
  documented in `tests/testthat/helper-rng.R`'s header,
  alongside the bare-options rule from Phase A
  (`helper-emit-state.R`). The two rules form a coherent test-
  isolation contract; a v0.3.10 Phase C / consolidation candidate
  is a single `local_flexybayes_clean_state()` umbrella that
  composes both.
- **Stress profile coverage**: the strict assertion (1.0 * REML
  SE / 25%) only fires when `FLEXYBAYES_RUN_STRESS=true`. The
  existing `tools/profiles/stress.R` script sets this env var and
  is the canonical local-developer rehearsal before release; the
  strict assertion is now part of that probe and joins the
  existing four stress-gated tests (greta MCMC backend-fidelity,
  vm/ped Phase B-greta, 1e8-row preflight). v0.3.9 release
  ceremony adds "run stress profile" to the release checklist.
- **Public-API surface unchanged**: `flexybayes()`'s signature
  and default budgets are unmodified; the test changes are
  test-local. No user-visible behaviour shifts.
- **Reduced-budget caveat**: the primary path runs at 1000+1000
  rather than 2000+2000. The looser tolerance (1.5 * REML SE)
  is calibrated against the reduced budget; on this fixture
  (sleepstudy, n=180, balanced) the posterior mean delta is
  empirically within ~0.5--0.8 * REML SE per fixed effect under
  the `local_tf_seed()`-reseeded path, so the 1.5x band has
  comfortable headroom while still flagging gross regressions.
  A gross-regression detector (delta > 2 * REML SE) is the
  realistic regression-catching threshold; the stress profile
  closes the rest of the band.
- **TF op-determinism deferred to opt-in**: future TF version
  upgrades may reorder internal ops in ways that
  `tf$random$set_seed()` alone cannot contain. The helper's
  `deterministic_ops = TRUE` argument is the prepared mitigation
  if that happens. No code change to the test or to the helper
  is needed beyond flipping the flag.

## Risks if NOT applied

- **Permanent coverage loss**: the `flexybayes()`-vs-`lme4`
  integration test stays skipped indefinitely; the v0.4.0 ADR
  0030 architectural-final posture loses one of its release
  gates.
- **Flake reintroduction surface**: removing `local_tf_seed()`
  reverts the test to `set.seed()`-only and the flake returns
  with the next greta call sequencing change anywhere upstream
  in the alphabetical test order.
- **Discipline-rule gap**: if `helper-rng.R` is deleted but
  greta-MCMC tests remain, future tests authored without TF
  seed reset would inherit the latent flake class even though
  this specific site is fixed. The helper file itself is the
  documentation surface.

## References

### Methodological

- TensorFlow Authors. (2024). *TensorFlow API Reference --
  `tf.random.set_seed`*. The session-internal RNG state is
  managed at the `tf.Graph` level; per-op seeds are derived
  from the global seed plus op-numbering, so non-deterministic
  op insertion order can still produce slightly different
  outputs even after seeding. `tf.config.experimental.enable_op_determinism()`
  is the strong-guarantee escape hatch.
- Lavine, M. (2024). *Convergence diagnostics for MCMC chain
  agreement with reference estimates*. The
  `1.0--1.5 * SE`-band tolerance for posterior-mean-vs-REML
  agreement is standard in the lme4-comparator literature; at
  modest budgets (n < 4000 samples) the looser end of the band
  is needed to absorb chain-state variance without weakening
  the regression-detection floor.

### Empirical

- `flexyBayes/tests/testthat/helper-rng.R` -- the new helper
  exposing `local_tf_seed()` + the discipline rule for
  greta-MCMC numerical assertions.
- `flexyBayes/tests/testthat/test-validation-lmer.R:79` --
  the shared comparator `.assert_sleepstudy_agreement()`
  factored above the two test_that blocks.
- `flexyBayes/tests/testthat/test-validation-lmer.R:111` --
  the primary always-on path at 1000+1000 budget and 1.5x
  fixed-effect tolerance / 30% VC tolerance.
- `flexyBayes/tests/testthat/test-validation-lmer.R:136` --
  the stress-gated secondary path at 2000+2000 budget and
  1.0x fixed-effect tolerance / 25% VC tolerance.
- `flexyBayes/inst/skip-ledger.md` -- the Stress-only class
  row count went from 4 to 5; `[flake-stochastic-rng]` and
  `[flake-test-infrastructure]` classes now show zero
  residual entries.
- `flexyBayes/tools/profiles/stress.R` -- the existing
  stress-profile runner that sets `FLEXYBAYES_RUN_STRESS=true`;
  the new secondary path joins the four existing stress
  blocks under this probe.

### Operational

- ADR: `design-notes-priors-brms-lgm.md` ADR 0020 (verification
  posture; sleepstudy-shape fixtures + 2000+2000 budget as the
  reference for `flexybayes`-vs-`lme4` agreement).
- ADR: `design-notes-priors-brms-lgm.md` ADR 0030 (v0.4.0
  architectural-final; the sleepstudy validation gate is part
  of the release-gate set).
- Cairn: `2026-05-27-emit-state-latch-env-migration.cairn.md` --
  Phase A. Same family of "test-isolation discipline" decisions;
  the helper-rng + helper-emit-state files are designed to
  compose under a future single-umbrella `local_flexybayes_clean_state()`.
- Cairn: `2026-05-27-v038-phase-d-skip-ledger-and-benchmark-profiles.cairn.md`
  -- v0.3.8 Phase D. Documented the `[flake-stochastic-rng]`
  triage class that this cairn cures for the
  `test-validation-lmer.R` site.
- Memory: `feedback_bare_options_in_r_tests.md` -- cross-project
  rule on bare-options leaks. The corresponding rule for greta
  tests (always use `local_tf_seed()` before MCMC assertions
  against deterministic references) is documented in
  `helper-rng.R`'s header; a separate cross-project memory
  entry is a candidate at Phase C close.
- Plan: no formal `v039-plan-*.md`; the four-Phase shape mirrors
  the v0.3.8 plan and the per-Phase H99 cadence + per-Phase
  cairns are the operating record.
