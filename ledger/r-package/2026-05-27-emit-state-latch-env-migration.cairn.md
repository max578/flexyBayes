---
id: 2026-05-27-emit-state-latch-env-migration
schema_version: 1.3
date: 2026-05-27
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "Emit-once message latch migrates from options() to package-internal env; bare-options leaks in tests repaired"
tags: [v039, phase-a, emit-state, test-isolation, withr, flake-test-infrastructure, suite-order]
triggers:
  - test_infrastructure_change
  - internal_state_encapsulation
reversal_cost: low
decision_pressure: refactor
provenance: live_ratified
---

## Status

Decided 2026-05-27 during v0.3.9 Phase A (test-isolation pass). Lands
on branch `test-isolation-2026-05-27-v039` off `3d963dc` (the v0.3.8
dev-bump on `main`). The pre-v0.3.9 emit-once latches lived in the
`options()` namespace:

- `options(flexyBayes._default_prior_note_emitted = ...)`
- `options(flexyBayes._uniform_inla_approx_emitted = ...)`

Any caller, anywhere in the loaded R session, could read or write
those names. The v0.3.8 close-note (`state_v038_released.md`) named
the consequence: a v0.3.8 Phase D triage entry classified
`test-smooth.R:88` as `[flake-test-infrastructure]` because some
intervening test in full-suite ordering consumed the once-flag before
the affected test's reset took effect. Phase D documented the flake;
v0.3.9 Phase A cures it.

The migration moves both once-flags into a package-private
environment created at top-level of `R/emit_state.R`:

```r
.flexybayes_emit_state <- new.env(parent = emptyenv())
```

Accessor functions `.emit_state_get(key)` / `.emit_state_set(key,
value)` / `.init_emit_state()` / `.reset_emit_state_for_test()` are
the only paths in and out. The env is initialised in `.onLoad()`
(`R/zzz.R`). The two emit-once helpers (`.default_prior_note_once()`,
`.uniform_to_inla_warn_once()`) in `R/fb_prior.R` consult the env-
keyed latch in place of the options() lookup; the public-API silence
toggles `options(flexyBayes.silence_*)` remain unchanged and continue
to short-circuit emission at function entry.

A test helper `tests/testthat/helper-emit-state.R` exposes
`local_clean_emit_state()` (withr-scoped snapshot + reset + restore),
`reset_emit_state()` (one-shot reset), and `set_emit_state(key,
value)` (explicit toggle). A regression suite
`tests/testthat/test-emit-state-isolation.R` (15 expectations across
7 `test_that` blocks) pins the contract end-to-end: env initialises
FALSE/FALSE, accessors return FALSE for unknown keys, options()
writes do not affect the env-keyed latch, back-to-back default-prior
emission re-fires under the scope wrapper, and the public silence
toggle short-circuits without flipping the latch.

A separate but co-essential repair lands in the same Phase A commit:
six bare `options(flexyBayes.silence_default_prior_note = TRUE)`
calls without restoration -- one in
`tests/testthat/test-inla-verification-simple-slope-uncor.R:135` and
five in `tests/testthat/test-random-slopes-uncor.R` -- were migrated
to `withr::local_options(...)` so the silence flag does not leak
across files in `tools/tally.R`'s single-process loop. Empirical
bisection during Phase A traced the v0.3.8 `test-smooth.R:88` flake
*through* the v0.3.9 env migration to this leak as the upstream
cause: `flexyBayes.silence_default_prior_note = TRUE` was carried
forward from the inla-verification suite into test-smooth.R, where
it short-circuited `.default_prior_note_once()` at the silence check
before the latch check could fire. The env migration alone would not
have closed the flake at this site; the bare-options repair alone
would not have closed the *class* of bug. Both are required.

`test-smooth.R:88` is re-enabled with a structural-witness pattern
(`expect_false(latch); flexybayes(...); expect_true(latch)`) rather
than the prior `expect_message(...)`. The latch-transition contract
is more robust against future callinghandler-stack churn than the
message-stream contract; textual-emission coverage is preserved by
the new `test-emit-state-isolation.R` regression suite and the
existing `test-emit-greta.R:99` block.

Full-suite tally at branch HEAD: **PASS 1889 / FAIL 0 / SKIP 7**
(was 1871/0/8 at v0.3.8). The `[flake-test-infrastructure]` class in
`flexyBayes/inst/skip-ledger.md` drops to zero residual entries for
the emit-state mechanism.

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Status quo: leave the once-flags in `options()`, accept the suite-order flake at `test-smooth.R:88`, keep the skip permanent. |
| B (CHOSEN) | Migrate the once-flags to a package-private env (`R/emit_state.R`), expose a test-only reset helper, and migrate bare-options leaks across test sites to `withr::local_options()`. |
| C | Migrate the test sites only (replace `options(flexyBayes._..._emitted = ...)` resets with `withr::local_options(...)`); leave the package-side latch on `options()`. |
| D | Migrate the message contract itself to a typed rlang condition (`rlang::inform(class = "flexybayes_default_prior_note")`); keep the latch on `options()` but assert emission via `expect_condition(class = ...)`. |

## Rationale for rejection

### Option A

Permanently abandons unique smooth-specific coverage at
`test-smooth.R:88` (the only assertion in the repo that the default
uniform prior reaches the residual sigma in a model whose only
random structure is a smooth). The skip-ledger creep also weakens
the package's "zero-flake" posture going into v0.4.0. The flake's
root cause is structural -- two distinct mechanisms in the test
infrastructure -- and is fixable at known low cost.

### Option C

Closes the immediate suite-order symptom at the failing site but
leaves the underlying coupling intact: the once-flag remains
readable and writable via `options()`, so *any* future test caller
that wrongly assumes the option name is a public flag could
silently consume it. The bug class returns under any new caller
that bypasses the helper. Withr-only fixes are *necessary* (Phase A
applies them across the six leak sites) but not *sufficient* --
they must compose with the env-keyed encapsulation.

### Option D

Functionally equivalent to Option B at the user-visible surface
(a typed condition still inherits from `"message"` and is still
catchable by `expect_message(regexp = ...)`); the contract-tightening
benefit (a class-keyed assertion via `expect_condition`) is real
but belongs in the v0.4.0 ADR 0030 §C7 refusal-taxonomy migration,
where ~30 existing refusal sites get registered against the locked
`.refusal_registry`. Folding it into v0.3.9 Phase A would conflate
two independent migrations (state encapsulation + condition-class
contract) and risk under-specifying the typed-message schema. The
env-keyed latch is the prerequisite for the typed-message
migration: once state is invisible to `options()`, the typed
message can be added at v0.4.0 without re-litigating where the
once-flag lives.

## Forward cost

- **Internal discipline rule**: new tests must use the
  `local_clean_emit_state()` helper (or `reset_emit_state()` /
  `set_emit_state()`) rather than the pre-v0.3.9 pattern of
  `options(flexyBayes._..._emitted = ...)`. The discipline is
  documented in the helper file header
  (`tests/testthat/helper-emit-state.R`). Migration is complete in
  v0.3.9 Phase A; no follow-on package code carries the old
  pattern.
- **Bare-options() discipline rule**: new tests must wrap any
  `options(flexyBayes.* = ...)` call in `withr::local_options(...)`
  (or `on.exit(options(old), add = TRUE)` with explicit capture)
  so the option is restored on test scope exit. The
  `tools/tally.R` single-process loop is the regression surface;
  parallel runners under `Config/testthat/parallel: true` isolate
  per-file but `tally.R` does not. The helper file header
  carries the rule. A future Phase C / v0.3.10 candidate adds a
  `tools/verify_test_hygiene.R` assertion that the full-suite run
  ends with the same `flexyBayes.*` options as it started.
- **Public-API surface unchanged**: `options(flexyBayes.silence_*)`
  toggles continue to suppress emission; their semantics are
  documented in the silence option call sites. The
  `flexyBayes._..._emitted` option names (leading-underscore,
  never documented) are no longer consulted by package code; if
  any external caller was relying on them as a public latch (no
  evidence this is the case), they would experience a no-op
  silently. Acceptable: those names were never part of the
  declared API.
- **Latch persistence semantics preserved**: the once-emission
  behaviour at user-session granularity is identical to pre-v0.3.9
  -- the message emits exactly once per loaded session unless the
  test-only reset is called. The contract is now harder to break
  by accident.
- **Forward bridge to v0.4.0 ADR 0030 §C7**: the env-keyed
  encapsulation is the prerequisite for migrating the message body
  to a typed `rlang::inform(class = "flexybayes_default_prior_note")`
  contract under the v0.4.0 refusal-registry. The v0.3.9 work
  raises the abstraction level by one rung; v0.4.0 closes the
  contract.

## Risks if NOT applied

Documented for completeness; both risks are now eliminated by
v0.3.9 Phase A but recur if either half of the fix regresses.

- **Coverage gap regression**: removing the env-keyed latch reverts
  the once-flag to `options()` -- any future test that internally
  calls flexybayes/fb_plan with a default prior can silently
  consume the latch and break unrelated `expect_message` tests
  downstream. The v0.3.8 cairn
  `2026-05-25-fb-plan-verb-exported-as-single-planning-surface.cairn.md:68`
  documented the *exact* mechanism that caused the v0.3.8 flake:
  `fb_plan(plan = TRUE)` triggered default-prior emission and
  consumed the option-keyed flag. The env migration removes the
  coupling surface entirely.
- **Suite-order leak resurgence**: removing the bare-options repair
  reverts the leak: tests that flip
  `flexyBayes.silence_default_prior_note = TRUE` without `withr`
  scope leak the silence flag into downstream files via
  `tools/tally.R`'s single-process loop, short-circuiting
  emission in unrelated assertions. The repair is one-line per
  site; the long-term guard is the discipline rule plus the
  proposed `verify_test_hygiene.R` script (deferred Phase C / v0.3.10
  candidate).

## References

### Methodological

- Wickham, H. (2019). *Advanced R*, 2nd ed., §7 (Environments) and
  §10.3 (Encapsulation). CRC Press. The package-private env idiom
  for once-flags follows standard R encapsulation practice; the
  test helper's snapshot-and-restore wrapper composes with withr's
  defer mechanism documented in §6 (function operators).
- Henry, L. (2023). `withr::local_options()` reference. The
  `.local_envir = parent.frame()` semantic is the contract that
  `withr::local_options()` inside a `test_that()` body restores on
  block exit; the bare `options()` calls migrated in Phase A
  lacked any restoration mechanism and were the upstream leak.

### Empirical

- `flexyBayes/R/emit_state.R` -- the new package-private env +
  accessor surface (38 lines).
- `flexyBayes/R/zzz.R:.onLoad()` -- the `.init_emit_state()` call
  added between the greta S3-method registration and the
  refusal-registry lock.
- `flexyBayes/R/fb_prior.R:451-476` -- the migrated
  `.default_prior_note_once()` and `.uniform_to_inla_warn_once()`
  helpers.
- `flexyBayes/tests/testthat/helper-emit-state.R` -- the test
  isolation helpers + the bare-options discipline rule.
- `flexyBayes/tests/testthat/test-emit-state-isolation.R` -- the
  15-expectation regression suite.
- `flexyBayes/tests/testthat/test-smooth.R:88` -- the re-enabled
  flake site, now exercising the structural-witness contract.
- `flexyBayes/tests/testthat/test-inla-verification-simple-slope-uncor.R:135`
  -- one of the six bare-options leak sites repaired.
- `flexyBayes/tests/testthat/test-random-slopes-uncor.R` -- five
  bare-options leak sites repaired via `replace_all`.
- `flexyBayes/tests/testthat/test-emit-greta.R:102,123` and
  `flexyBayes/tests/testthat/test-fb-prior.R:194` -- the migrated
  test sites using the new helper instead of `options()` reset.

### Operational

- Cairn: `2026-05-25-fb-plan-verb-exported-as-single-planning-surface.cairn.md`
  -- documented the exact `fb_plan(plan = TRUE)` mechanism that
  consumed the option-keyed once-flag; the v0.3.9 migration
  closes the underlying coupling.
- Cairn: `2026-05-27-v038-phase-d-skip-ledger-and-benchmark-profiles.cairn.md`
  -- the v0.3.8 Phase D triage that documented the
  `[flake-test-infrastructure]` site at `test-smooth.R:88`; this
  cairn ratifies the cure for the documented flake.
- ADR: `design-notes-priors-brms-lgm.md` ADR 0004 (uniform-default
  variance-component prior). The default-prior-note that motivates
  the once-flag.
- ADR: `design-notes-priors-brms-lgm.md` ADR 0030 §C7 (refusal
  taxonomy; v0.4.0 terminal). The env-keyed encapsulation here is
  the prerequisite for the v0.4.0 typed-message contract.
- Memory: `state_v038_released.md` -- the v0.3.8 release-close
  state that named the three deferred stochastic flakes
  (test-smooth.R + test-validation-lmer.R + test-emit-gaussian-aggregated.R);
  v0.3.9 Phase A closes the first.
- Plan: `v038-plan-2026-05-25.md` is the v0.3.8 plan; v0.3.9 has no
  formal plan file because Phase A scope was approved live in the
  same session as branch cut. A retrospective `v039-plan-2026-05-27.md`
  is *not* warranted -- the four-Phase shape mirrors v0.3.8 and the
  per-Phase H99 cadence is the operating record.
