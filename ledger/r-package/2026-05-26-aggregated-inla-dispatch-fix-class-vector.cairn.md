---
id: 2026-05-26-aggregated-inla-dispatch-fix-class-vector
schema_version: 1.3
date: 2026-05-26
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "Aggregated INLA fits carry `flexybayes_inla` class label for correct S3 dispatch"
tags: [adr-0022, dispatch, s3, class-vector, triangulate, fb_as_draws_simple, audit-triage]
triggers:
  - public_api_change
  - methodology_change_downstream
reversal_cost: low
decision_pressure: refactor
provenance: live_ratified
---

## Status

Decided 2026-05-26 during v0.3.8 Phase C flake-triage. The 13th
H99 close (`state_v038_phase_b_close.md`) flagged a
`test-canonical-names.R:153` ERROR as "environmental / flake-like
(reproduces only under `NOT_CRAN=true` in full-suite context)".
Re-triage under `NOT_CRAN=true` **in isolation** reproduced the
failure deterministically -- a real correctness bug, not a flake.
Fix landed as commit `9d0b087` on `hardening-pass-2026-05-26-v038`.
The Gaussian aggregated emit (Stage 3A, ADR 0022) now writes the
fit's S3 class vector with backend identity preserved:

| Backend | Class vector |
|---|---|
| INLA  | `c("flexybayes_aggregated", "flexybayes_inla", "flexybayes")` |
| greta | `c("flexybayes_aggregated", "flexybayes")` |

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Keep status quo (drop `flexybayes_inla` on the aggregated path); fix the broken `fb_as_draws_simple` dispatch by inspecting `fit$inla` inside the greta method. |
| B (CHOSEN) | Conditionally insert `flexybayes_inla` into the class vector on the INLA branch; let S3 dispatch route generics. |
| C | Add `flexybayes_inla` and `flexybayes_greta` everywhere by symmetry; promote both to first-class backend tags. |
| D | Write a `fb_as_draws_simple.flexybayes_aggregated` method that branches on `!is.null(fit$inla)` / `!is.null(fit$greta)`. |

## Rationale for rejection

### Option A

Replaces S3 polymorphism with hand-rolled class-tag inspection
inside one method; the same fork has to be repeated in every
generic the aggregated fit might encounter. Bug-prone (each new
generic risks repeating the omission), and inverts the
flexyBayes-wide pattern of "method per backend class".

### Option C

Rejected at this scope (deferred to v0.4.0 ADR 0030 if the
constructor-noun work needs it). `flexybayes_greta` is not
currently a class anywhere in the package; introducing it now
would require auditing every `inherits(fit, "flexybayes")` site
for `flexybayes_greta` parity and migrating any code that
assumed the implicit greta-as-default semantics. The minimal-
surface fix preserves the existing greta shape and only adds the
missing INLA label where the absence was the bug.

### Option D

Same critique as A: replaces dispatch with branching. Adds a
method that has to know the union of all backends a future
aggregated fit might carry. Loses the S3 extension surface for
downstream packages that want to add their own draws extractor
for a new backend.

## Forward cost

- Aggregated INLA fits have a three-element class vector
  (`flexybayes_aggregated`, `flexybayes_inla`, `flexybayes`).
  Any existing or future `.flexybayes_inla` S3 method now
  applies to aggregated INLA fits unless a more-specific
  `.flexybayes_aggregated` method shadows it. Print + summary
  already have `.flexybayes_aggregated` methods; they retain
  the aggregated-specific surface. `fb_as_draws_simple()` has
  no `.flexybayes_aggregated` method and falls through to the
  INLA extractor (correct).
- Downstream code that branches on backend should prefer
  `backend_decision(fit)$backend` (ADR 0024) over
  `inherits(fit, "flexybayes_inla")` -- the class vector is
  reliable but not authoritative; the dispatch trace is.
- The greta path stays at two elements; introducing
  `flexybayes_greta` is deferred to ADR 0030 (v0.4.0) under the
  constructor-noun (`fb_engine`) lineage.
- Future ADR work on the representation registry (ADR 0030 C4)
  may promote backend to a first-class slot on the fit;
  class-vector dispatch becomes a vestigial mechanism preserved
  for backward compatibility.

## References

### Methodological

- Wickham, H. (2019). *Advanced R*, 2nd ed., §13 (S3). CRC Press.
  S3 class-vector dispatch semantics underlie the fix; this is
  the idiomatic R way to express "is-a both an aggregated fit and
  an INLA fit".

### Empirical

- `flexyBayes/R/emit_gaussian_aggregated.R:725-739` -- the
  three-element conditional class construct.
- `flexyBayes/R/triangulate.R:332-386` --
  `fb_as_draws_simple()` generic + `.flexybayes` and
  `.flexybayes_inla` methods that the dispatch fix routes to.
- `flexyBayes/tests/testthat/test-canonical-names.R:153-173` --
  the triangulate(greta, INLA) test that exposed the bug.
- `flexyBayes/tests/testthat/test-emit-gaussian-aggregated.R:327-368`
  -- the extended class-invariant test + new greta-counterpart.

### Operational

- ADR: `design-notes-priors-brms-lgm.md` ADR 0022 (Stage 3A
  Gaussian exact aggregation). Class-shape decision was implicit;
  this cairn ratifies it explicitly.
- ADR: `design-notes-priors-brms-lgm.md` ADR 0024 (backend
  routing trace). `backend_decision(fit)$backend` is the
  authoritative backend reporter for downstream consumers.
- ADR: `design-notes-priors-brms-lgm.md` ADR 0030 §C4
  (representation registry; v0.4.0 terminal). Constructor-noun
  work may obsolete class-vector backend dispatch.
- Cairn: `2026-05-26-predict-kernel-extraction.cairn.md` (Phase A
  shared kernel; same family of "shape over branching" decisions).
- Commit: `9d0b087` on `hardening-pass-2026-05-26-v038`.
- Memory: `state_v038_phase_b_close.md` -- the source of the
  initial flake-misclassification triaged here.
