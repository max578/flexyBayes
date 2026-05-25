---
id: 2026-05-25-fb-plan-verb-exported-as-single-planning-surface
schema_version: 1.1
date: 2026-05-25
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "fb_plan() exported as the single planning surface (ADR 0030 C1)"
tags: [fb_plan, planning, dispatch, adr_0030, v038_phase_b, public_api]
triggers:
  - public_api_change
  - adr_class_commitment
  - methodology_change_downstream
reversal_cost: high
decision_pressure: audit_close
review_due: null
review_trigger: "before v0.4.0 release"
supersedes: []
superseded_by: null
related: [2026-05-25-representation-engine-two-line-truth-display]
---

## Status

Ratified 2026-05-25 during the v0.3.8 Phase B implementation session, anchored to the 11th H99 close `v038-plan-2026-05-25.md` §5 (audit Critical Fixes #4 + #5 + ADR 0030 C1 / C7 / Decision 4). Branch `hardening-pass-2026-05-26-v038` off the v0.3.7 release tag (`4dd7079`); Phase A had previously landed at `caf229c` (shared prediction kernel + known-matrix alignment + sparse-precision policy). Phase B as implemented: `R/fb_plan.R` (380 lines) shipping the `fb_plan()` exported entry plus `print.fb_plan()`, `summary.fb_plan()`, `as.data.frame.fb_plan()` S3 methods. Both formula verbs (`flexybayes()`, `fb_brms()`) gained `plan = FALSE` arguments routing to `.fb_plan_from_ir()`. Six exported verbs at v0.3.8: flexybayes, fb_brms, fb_greta, fb_plan, triangulate, fb (alias).

## Alternatives considered

| Option | One-line description |
|---|---|
| A | No plan verb; users inspect `backend_decision()` on a completed fit instead |
| B | `plan = TRUE` on formula verbs only -- no standalone `fb_plan()` export |
| C | Two plan verbs -- one mirroring `flexybayes()` (asreml-style), one mirroring `fb_brms()` (brms-style) |
| D (CHOSEN) | Single exported `fb_plan(formula, data, ...)` (brms-style) + courtesy `plan = TRUE` on both formula verbs; both route through internal `.fb_plan_from_ir()` |
| E | Plan verb returns a closure that fits when called -- "deferred fit" rather than "plan" |

## Rationale for rejection

### Option A

The whole point of v0.3.8 Critical Fix #5 is that users should be able to see the dispatch decision *before paying the fit cost*. Routing `auto` to greta on small data takes 30--120 s of MCMC; the user paying that to discover the wrong backend was chosen is exactly the failure mode the audit named. `backend_decision()` on a completed fit answers a different question (forensic, post-fit) than `fb_plan()` (planning, pre-fit). Both should exist.

### Option B

Discoverability and economy. A user who knows what `fb_plan()` does will type `fb_plan(...)`; a user who is uncertain whether to fit will reach for the verb their muscle memory already knows (`flexybayes()`, `fb_brms()`) and discover the `plan = TRUE` flag via help. Shipping only the flag hides the existence of the planning surface from package-list scans (`ls("package:flexyBayes")`); shipping only the verb forces users to learn a new entry point even for one-off planning. Ship both. The courtesy `plan = TRUE` is the *alternative invocation* ADR 0030 C1 explicitly names; the standalone verb is the *canonical* one.

### Option C

Two verbs for one decision violates the four-verb-spine cardinality ADR 0030 ratifies. The asreml ingest path (`fixed = ...`, `random = ...`, `rcov = ...`) and the brms ingest path (`formula = ...`) build the *same* IR via different parsers; once the IR exists, the routing decision is identical. Two plan verbs would invite drift between the two paths' planning surfaces -- one might gain a feature the other never gets. Single verb, single internal constructor (`.fb_plan_from_ir()`), single path through the policy table.

### Option E

The deferred-fit pattern already exists for greta-emit code review (`review_code = TRUE` returns a `<flexybayes_review>` with `proceed()`). Adding a second deferred-fit pattern would create overlap with `review_code` semantics: users would not know whether to inspect the plan + fit (`fb_plan() then flexybayes()`) or the code + proceed (`review_code = TRUE then proceed()`). Keep `fb_plan()` strictly inspection-only -- no proceed semantics, no fit closure -- and let `review_code` retain its code-inspection role.

## Implemented option (D)

`fb_plan(formula, data, backend = "auto", priors = NULL, known_matrices = list(), family = "gaussian", link = NULL, weights = NULL, aggregate = "auto", memory_ceiling_gb = NULL, predict_plan = NULL, ...)`. Returns `<fb_plan>` with 24 slots covering: requested-vs-chosen backend, routing-policy-version, gate outcome, aggregation eligibility + ratio, representation plan per term, rejected routes per backend, known-matrix summary, `cov_validation_policy`, predict-shape plan (when requested), memory estimate, full `<fb_preflight>` reference, and human-readable `representation_label` / `engine_label` for the truth-display surface. `flexybayes(plan = TRUE)` short-circuits after IR build (post-default-prior-expansion) via `.fb_plan_from_ir()`; `fb_brms(plan = TRUE)` mirrors. Twelve test_that blocks in `tests/testthat/test-fb-plan.R` cover the surface plus the backward-compat path for legacy `backend_decision()` callers.

## Forward cost

- **Sixth verb (`validate_approximation`) at v0.3.9+** is now load-bearing on the verb-count invariant; the four-verb spine has become a six-verb spine and the spine cardinality test enforces it. Any future API change that *adds* a verb is a T3 cairn; *removing* `fb_plan` would be a T4 cairn (irreversible without major bump).
- **`<fb_plan>` shape is now a public contract**. The 24 slots + their semantics are documented in the help page; field renames are deprecation-cycle changes. The stable column ordering on `as.data.frame.fb_plan()` (the `.FB_PLAN_DF_COLS` constant) is part of that contract.
- **`.fb_plan_from_ir()` becomes the single source of truth for pre-fit routing decisions**. Any new dispatch dimension (e.g., a v0.4.0 noun-constructor axis, an INLA-side preflight memory estimator) must update both `.dispatch_backend()` *and* `.fb_plan_from_ir()` or the plan + fit will diverge. The test (g) shape-check is the canary.
- **`fb_plan(plan = TRUE)` route triggers default-prior emission** when `prior_vc_sd` is missing -- the same as `flexybayes()`. This caused a test interaction with `test-smooth.R` in the full-suite run (one-shot flag `_default_prior_note_emitted` consumed). Trade is acceptable -- the plan should reflect the prior shape the fit would receive -- but explicit `suppressMessages()` should be used in test code that mixes the planning + fit paths.
- **`cov_validation_policy` is now reportable on the plan** but only enumerates three values (`n/a` / `structural_only` / `full_pd`) tied to the `flexyBayes.trust_pd` option (Phase A). Future Phase C / v0.4.0 may add `trusted` (user assertion override) or `incremental` (PD probe on first use only); these would require schema-version bumps on the plan object.

## References

### Methodological

- Plummer, M. (2017). *Penalising model component complexity: A principled, practical approach to constructing priors*. Statistical Science 32(1):1--28. (Background on the principled-prior + structural-refusal posture that motivates an explicit planning surface.)
- Carpenter, B. et al. (2017). *Stan: A probabilistic programming language*. Journal of Statistical Software 76(1):1--32. (Reference for the "compile-then-fit" pattern Stan uses; `fb_plan()` is the flexyBayes analogue of `stan_model()` inspection without the C++ compile step.)

### Empirical

- `R/fb_plan.R:74--105` -- `fb_plan()` exported entry signature + body.
- `R/fb_plan.R:120--240` -- `.fb_plan_from_ir()` internal constructor; preflight / gate / routing / aggregation plumbing.
- `R/flexybayes.R:179--180` -- `plan = FALSE` argument addition.
- `R/flexybayes.R:296--309` -- `plan = TRUE` short-circuit.
- `R/fb_brms.R:185--186` -- `plan = FALSE` argument addition.
- `R/fb_brms.R:323--334` -- `plan = TRUE` short-circuit.
- `tests/testthat/test-fb-plan.R` -- 12 test_that blocks; 26 expectations.
- Audit: `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` Critical Fix #5 -- "users should be able to inspect the dispatch decision before paying fit cost".

### Operational

- ADR: `design-notes-priors-brms-lgm.md` §ADR 0030 (architectural-final distribution; six-verb spine at v0.3.9 includes fb_plan as the planning verb).
- Plan: `v038-plan-2026-05-25.md` §5 (Phase B objective; the runnable construction sequence for fb_plan + truth-display + refusal-registry-scaffold).
- Cross-ref: `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §8 Decision Point §12.2 (the print-form sketch this implementation realises).
- Cairn: `2026-05-25-representation-engine-two-line-truth-display.cairn.md` -- the print-side companion (truth-display surface).
- Cairn: `2026-05-25-adr-0030-architectural-final-v040.cairn.md` -- parent architectural commitment.
- Branch: `hardening-pass-2026-05-26-v038` (off `4dd7079` v0.3.7 release; Phase A landed at `caf229c`).
