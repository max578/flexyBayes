---
id: 2026-05-25-refusal-registry-scaffold-only-v038-no-migration
schema_version: 1.1
date: 2026-05-25
tier: T2
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "Refusal registry shipped as empty scaffold; ~30-site migration deferred to v0.4.0 (ADR 0030 C7)"
tags: [refusal, registry, scaffold, adr_0030, v038_phase_b, staged_release]
triggers:
  - new_internal_helper
reversal_cost: low
decision_pressure: audit_close
review_due: null
review_trigger: "before v0.4.0 release"
supersedes: []
superseded_by: null
related: [2026-05-25-fb-plan-verb-exported-as-single-planning-surface]
---

## Status

Ratified 2026-05-25 in the v0.3.8 Phase B session per `v038-plan-2026-05-25.md` §5.2 explicit guidance: *"The deliberate choice here is to ship the container without the migration risk of touching ~30 existing refusal sites in one release."* Implements ADR 0030 contract C7 (refusal vocabulary registry) in the scaffold-only posture. Lands in `R/refusal_taxonomy.R` (155 lines): the `.refusal_registry` environment + four helpers (`.register_refusal`, `.lookup_refusal`, `.lock_refusal_registry`, plus the lock wired into `.onLoad()` after the existing emmeans / broom / greta method registrations). Zero `.register_refusal()` call sites at v0.3.8 -- the registry is empty + locked at namespace-load. The user-facing `fb_refusals()` accessor + the migration of the existing refusal sites in `dispatch.R` / `lgm_gate.R` / `structured_cov.R` / `emit_inla.R` is queued for v0.4.0.

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Full registry migration in v0.3.8 -- convert all ~30 sites + ship `fb_refusals()` accessor in one release |
| B (CHOSEN) | Scaffold-only at v0.3.8 (container + helper); migration + accessor at v0.4.0 |
| C | Two-phase migration -- convert just the routing-policy sites (10) at v0.3.8; rest at v0.4.0 |
| D | Skip the registry entirely -- the inline structured-condition pattern is sufficient |

## Rationale for rejection

### Option A

Migration risk in a single release is the load-bearing concern. The ~30 existing refusal sites span four files and four ADRs (0021 preflight, 0024 routing, 0025 known-cov, 0027 approximate-route refusal pattern), each with its own message-template idiom and reason-code naming convention. Touching all of them at once would mix the message-template registration changes (mechanical) with the message-text harmonisation (judgement-heavy) in one diff. If something goes wrong with the harmonisation, rollback is per-site. Phase B is already shipping `fb_plan()` + the truth-display surface; bundling a 30-site refusal migration on top would exceed the L99 budget for one release.

### Option C

Two-phase is the seductive middle ground but creates a worse audit posture than (B). At the end of v0.3.8, half the sites would emit registry-aware structured conditions and half would emit the legacy inline pattern; users querying `fb_refusals()` would see a partial vocabulary. That partial state is harder to reason about than "empty at v0.3.8, complete at v0.4.0". Staged_release pattern dictates: A or B or D; not a fractional migration.

### Option D

`fb_refusals()` is on the v0.4.0 noun-constructor roadmap (ADR 0030 §architectural-final distribution). Shipping the registry container makes that v0.4.0 work mechanical -- the migration becomes "add 30 `.register_refusal()` calls before the lock fires". Skipping the container forces v0.4.0 to ship both the container AND the migration in one release, which is exactly what (A) refused. (D) trades a small v0.3.8 cost for a large v0.4.0 cost; (B) takes the small cost now.

## Implemented option (B)

`R/refusal_taxonomy.R` ships four functions: `.refusal_registry` (environment with `emptyenv()` parent, allocated at namespace-load), `.register_refusal(reason_code, description, message_template, registered_in_adr, plan_field, since_version)` (validates 6 args, refuses duplicate reason_codes, refuses post-lock writes), `.lookup_refusal(reason_code)` (NULL-tolerant accessor, NULL for any code at v0.3.8), and `.lock_refusal_registry()` (called at end of `.onLoad()`; locks the environment with `bindings = TRUE` so user-side `assign()` also raises). Five test_that blocks in `tests/testthat/test-refusal-registry-scaffold.R` cover the existence + lock state, argument validation, duplicate-detection branch (verified by reading the function body), user-side assign refusal, and the empty-at-v0.3.8 invariant.

## Forward cost

- **v0.4.0 must populate the registry before the lock fires.** The migration sequence is: add ~30 `.register_refusal()` calls in a new `R/refusal_register_all.R` (or inline in `R/refusal_taxonomy.R`), wire the calls in `.onLoad()` *before* `.lock_refusal_registry()`, then add `fb_refusals()` as the exported user-facing accessor. The empty-at-v0.3.8 test in `test-refusal-registry-scaffold.R` will flip to expect-the-full-vocabulary at v0.4.0; the v0.4.0 release ceremony updates that test.
- **The `plan_field` argument is now part of the registration contract**. Future refusals that surface on `<fb_plan>` must declare which plan slot they appear on (e.g., `plan_field = "rejected_routes"`). Refusals that are pure-runtime (e.g., `.gretaR_dormant_refusal()`) get `plan_field = NA_character_`. This is the integration point between the refusal vocabulary + the planning surface from the sibling `fb_plan` cairn.
- **Reason codes become append-only.** The duplicate-detection branch makes the v0.4.0 migration order irrelevant for correctness but means any rename of a reason code is a deprecation cycle, not a free edit. The existing reason codes in `routing_policy_table()` (`explicit_greta`, `auto_inla_accept`, etc.) become the v0.4.0 vocabulary anchors.
- **The registry is per-namespace-load**, not per-session. Reloading via `devtools::load_all()` re-runs `.onLoad()` and re-locks; tests that need a fresh / unlocked registry must construct their own environment (the v0.3.8 tests do this implicitly by exercising the helper's validation logic before any assign).
