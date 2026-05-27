---
id: 2026-05-25-predict-kernel-extraction
schema_version: 1.1
date: 2026-05-25
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "Shared per-draw prediction kernel (closes audit Critical Fix #1, ratifies ADR 0030 C2)"
tags: [predict, kernel, smooth, audit-close-2026-05-25, adr-0030, c2, phase-a, v0.3.8]
triggers:
  - public_api_change
  - adr_class_commitment
  - cross_module_refactor
reversal_cost: high
decision_pressure: audit_close
supersedes: []
superseded_by: null
related: []   # ADR 0028 / 0029 / 0030 cairns to be created in the bootstrap pass
---

## Status

Ratified 2026-05-25 in the v0.3.8 Phase A implementation session
following Max's `proceed with Phase A L99` directive on the
`hardening-pass-2026-05-26-v038` branch off `4dd7079` (v0.3.7 release
merge). The branch name carries the originally-anticipated date and
is preserved verbatim as the foreign artefact in flexyBayes_dev (it
is not renamed by ledger -- ledger reflects, does not rewrite).
Anchored in:

- `v038-plan-2026-05-25.md` §4 (Phase A scope, file inventory, test
  target, commit message)
- `design-notes-priors-brms-lgm.md` ADR 0030 contract C2 (the
  prediction-kernel surface the v0.4.0 architectural-final shape
  commits to)
- `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` Critical Fix #1 (the
  audit finding this cairn closes)
- `flexyBayes` commit `caf229c` (the implementation merge)

## Alternatives considered

The pre-v0.3.8 architecture had three semi-redundant prediction code
paths: in-memory smooth-aware in `predict.flexybayes()`,
file-backed smooth-blind in `.predict_to_file()`, and sample-mode
smooth-blind in `.predict_in_memory_sample()`. The crossroads was *how
to fix the file-backed smooth-bypass bug structurally*, not just
symptomatically.

| Option | One-line description |
|---|---|
| A | Targeted inline patch: copy smooth-basis code into the two per-draw paths. |
| B (CHOSEN) | Shared per-draw kernel (`.predict_linear_draws`) routed through by all per-draw consumers; in-memory smooth branch collapses to a wrapper. |
| C | Full unification: also route the no-smooth in-memory branch through the kernel; every `predict()` becomes per-draw Monte Carlo. |
| D | Per-backend predict adapters: subclass-dispatched `predict.flexybayes_greta()` + `predict.flexybayes_inla()`. |

## Rationale for rejection

### Option A -- targeted inline patch

Closes the bug but leaves three duplicate copies of the smooth-basis
logic (`.linear_formula()` + `mgcv::PredictMat()` + per-draw basis-coef
construction). The next per-draw consumer -- eventual `triangulate()`
pre-fit branch (deferred to v0.4.x per ADR 0029) or any future
ADR-0030 verb -- re-inherits the same structural drift risk. The audit
itself named "single prediction kernel" as the right shape; A is the
wrong-shape patch that fixes the symptom without fixing the cause.

### Option C -- full unification

Would break INLA in-memory `predict()`. INLA fits do not currently
carry `$greta$draws` (the per-draw posterior access); the kernel's
first action is to assert that slot exists. Routing the no-smooth
in-memory branch through the kernel produces a clean refusal for every
INLA `predict(newdata)` call -- a regression on the most common
predict path. Independently, switching `se.fit` from analytic
`sqrt(rowSums(mm V mm))` to Monte-Carlo SD on the no-smooth path
introduces ULP-level numerical noise for no upside (the analytic form
is exact under MVN-posterior assumptions). Two regressions for one
abstraction win is not the trade.

### Option D -- per-backend predict adapters

Better architectural shape long-term; wrong-scoped for an audit-close
release. Subclass-dispatched methods require:

- A v0.4.0-scale design pass on the subclass taxonomy (greta + INLA +
  future `stan_brms` per ADR 0028 + future direct-greta + ...).
- Migration of every existing `predict.flexybayes()` consumer.
- Deprecation discipline for the class shape.

Phase A is hardening, not redesign. The right slot for D is v0.4.0
alongside the constructor-noun migration (ADR 0030 cluster C).

## Implemented option (B)

Extracted `.predict_linear_draws(object, newdata, n_draws_cap = 4000L,
sampled_re = NULL, include = c("fixed", "smooth", "random_sampled"))`
as the single per-draw linear-predictor function (R/predict_kernel.R,
~190 lines). Three consumers route through it:

1. `predict.flexybayes()` smooth branch -- `include = c("fixed", "smooth")`
2. `.predict_to_file()` per chunk -- `include = c("fixed", "smooth", "random_sampled")`
3. `.predict_in_memory_sample()` -- `include = c("fixed", "smooth", "random_sampled")`

The no-smooth in-memory branch keeps its `coef()`-based logic
(preserves INLA support, preserves analytic `se.fit`). The chunked
iterator (`.predict_chunked_iterate`) recurses to
`predict.flexybayes()` per chunk and inherits the kernel transitively
-- no explicit refactor needed.

The kernel exposes a typed `include` vocabulary; malformed values
raise `flexybayes_predict_kernel_refusal` with `reason_code =
"predict_kernel_invalid_include"`. `"random_known"` is reserved for
v0.4.0 (forward-pointer refusal embedded in the message) so the API
surface is forward-compatible without committing to the implementation
prematurely.

## Forward cost

- **Kernel is greta-only.** Requires `$greta$draws`. INLA fits hit a
  clean refusal naming the future INLA draws adapter (queued for
  v0.4.x). Cost is borne by file-backed and sample-mode predict on
  INLA, both of which were already greta-only pre-v0.3.8.
- **Numerical (not bit) equivalence across chunkings.** BLAS
  non-associativity means `(mm × t(β))[rng, ]` and
  `(mm[rng, ] × t(β))` can differ at ~1 ULP. The plan's "byte-identical"
  framing was over-stated; tests use `tolerance = 1e-10`. Bit-identity
  holds *within* a single chunk-size run (file-output test asserts that
  separately) -- the reproducibility-audit contract that matters.
- **Smooth-branch `se.fit` changes from `NA` to Monte-Carlo SD.** A UX
  improvement (users get a real number) but a numerical change. Phase C
  truth sweep documents in NEWS.md.
- **`include` vocabulary is part of the v0.4.0 public surface.** Once
  `<fb_plan>$predict_plan` ships at v0.4.0 (Phase B of v0.3.8 +
  v0.4.0 surface migration), adding or removing `include` values is
  breaking. `"random_known"` deferral is documented in the refusal
  message so users probing find the forward-pointer.
- **Three plan deviations documented in the commit message and queued
  for Phase C truth sweep**: `predict_chunked.R` not modified
  (recursion handles it); `test-structured-cov-validation.R` is a
  phantom path (extended `test-known-covariance-inputs.R` instead);
  `cov_validation_policy` surface on `backend_decision()` deferred to
  Phase B alongside `fb_plan()`.

## References

### Methodological

- Wood, S. N. (2017). *Generalized additive models: an introduction
  with R* (2nd ed.). CRC Press. -- `mgcv::PredictMat()` semantics
  for evaluating a fitted smooth on new data; the
  re-evaluation-against-stored-basis pattern the kernel uses.
- Higham, N. J. (2002). *Accuracy and stability of numerical
  algorithms* (2nd ed.). SIAM. §3 on floating-point summation
  non-associativity -- the reason byte-identity across chunked vs
  monolithic matrix multiplications is infeasible at the BLAS layer.
- ADR 0030 in `design-notes-priors-brms-lgm.md` -- the architectural-
  final v0.4.0 contract ratifying the seven truth contracts + four
  constructor nouns + six verbs; this cairn implements contract C2
  (prediction kernel) at the v0.3.8 hardening release.

### Empirical

- `flexyBayes` audit document
  `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` Critical Fix #1 --
  identified the file-backed smooth-bypass at
  `R/methods.R:472-483` and `R/predict_file_output.R:152-204`.
- `flexyBayes` commit `caf229c` on
  `hardening-pass-2026-05-26-v038` -- the implementation merge;
  10 files changed (+1406 / -248), three new test files (39
  expectations across 25 test_that blocks).
- `flexyBayes/tests/testthat/test-predict-kernel.R` -- 21
  expectations across 8 test_that blocks; covers chunk-invariance,
  include-filter, file-vs-in-memory equivalence, malformed include
  refusal.
- Devtools::test() tally on the post-commit branch: PASS 1761 / FAIL
  1 / SKIP 6. The one failure is pre-existing
  `test-fb-brms.R:284` (Stage-4-era backend_decision shape
  expectation not updated when ADR 0024 v0.3.6 extended the trace
  from 4 to 8 fields; flagged for Phase C truth sweep).

### Operational

- `v038-plan-2026-05-25.md` §4 (Phase A scope) + §12.6
  (ratification block) + §13 (runnable command sequence).
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §8.3
  (Cluster C ADR 0030 alternatives-bracketing matrix).
- Project memory `state_planning_v038_open.md` -- carries the
  pre-Phase-A state and the H99 next-step that triggered this work.
- Project memory
  `feedback_external_review_alternatives_bracketing.md` -- the
  four-field schema standard this cairn instantiates.
- Project memory `feedback_audit_close_methodology.md` -- the
  themed-Phase-commit pattern Phase A follows.
- `flexyBayes` commits `4dd7079` (v0.3.7 release merge; the base for
  the hardening-pass branch) and `caf229c` (Phase A merge).
