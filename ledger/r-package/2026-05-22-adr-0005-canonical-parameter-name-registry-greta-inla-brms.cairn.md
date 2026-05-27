---
id: 2026-05-22-adr-0005-canonical-parameter-name-registry-greta-inla-brms
schema_version: 1.3
date: 2026-05-22
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "ADR 0005 -- canonical parameter-name registry (greta + INLA + brms-passthrough)"
tags: [archaeology, adr-0005, archaeology-confidence-explicit, canonical-names, triangulate, brms-style]
triggers:
  - adr_class_commitment
  - public_api_change
provenance: archaeological_reconstruction
archaeology_source: design-notes-priors-brms-lgm.md
archaeology_extracted_at: 2026-05-26
archaeology_confidence: explicit
review_status: reviewed
reviewed_by: max.moldovan@gmail.com
reviewed_at: 2026-05-26
supersedes: []
superseded_by: null
related: []
reversal_cost: high
decision_pressure: null
---

## Status

Ratified 2026-05-22 per ADR 0005 in `design-notes-priors-brms-lgm.md`
(lines 1028--1196). The ADR's `**Date.**` field is the authoritative
ratification date; the Status sentence anchors the ADR to plan-final
sec.6 user-facing principle 5 (*"`triangulate_all()` never requires
the user to hand-map common parameter names for standard models"*)
and sec.11.2 row 0005, and composes with ADR 0006 (the
`backend_decision()` trace records gate capabilities; this ADR adds
the per-fit canonical-name map). Status keyword: `accepted`.
Reconstructed post-hoc via `/ledger archaeology` on 2026-05-26;
confidence `explicit` (Date field + Status keyword unambiguous in
source). No target version in source -- v0.2 implementation lives in
`R/canonical_names.R`; v0.3 extends to multi-term random naming;
Ambition-lane backends (NIMBLE, brms-via-Stan-as-peer) inherit the
registry via `register_canonical_mapper()`.

## Alternatives considered

Lifted from source §iv "Sensitivity bracketing" (four variants
explicitly bracketed):

| Option | One-line description |
|---|---|
| A | Internal-flexyBayes canonical convention (e.g., `fb_<term>`, `fb_sd_<group>`) -- invent a fourth name space. |
| B (CHOSEN) | Brms-style as canonical + per-backend registry of mappers + `canonical_names()` S3 generic. |
| C | Static cross-engine table baked into `triangulate()` (no S3 generic, no registry). |
| D | Canonical = INLA convention (e.g., `Precision for <group>`, precision-side parameterisation). |

## Rationale for rejection

### Option A

Yields a fourth-naming-convention burden on top of the three the user
community already knows (brms, posterior, bayesplot). Compatibility
with `bayesplot::mcmc_*()` and `posterior::draws_array` downstream
tools would require an additional rename layer everywhere -- pushing
naming friction into every plotting and summarisation call site. Loses
the "no surprise" property the package commits to.

### Option C

Cannot be extended for the Ambition-lane backends (NIMBLE,
brms-via-Stan as a triangulate peer) without rewriting
`triangulate()` itself. The S3-generic + registry pattern *is* the
extensibility surface. A baked-in table would have to grow each time
a new backend lands, with no mechanism for third-party authors to
register their own mappers (the v0.3+ export of
`register_canonical_mapper()` becomes impossible).

### Option D

INLA's precision-side parameterisation is the *opposite* of the
SD-scale convention flexyBayes commits to (ADR 0004 + 0010). Using it
as canonical would require every `triangulate()` output to display
precisions instead of SDs, conflicting with the prior-default +
plotting + user-expectation conventions. Adopting it would mean every
greta-native, brms-native, and posterior-package downstream user sees
parameters they have never named that way.

## Forward cost

Lifted and condensed from source ### Consequences:

- New file `R/canonical_names.R` (~250 lines): the `canonical_names()`
  S3 generic + three methods + the `.canonical_mappers` internal
  registry + the `register_canonical_mapper()` helper + per-backend
  mapper implementations (greta + INLA) + helper utilities for
  indexed-parameter parsing (e.g., `b_env_2[1]` -> `("env2", element 1)`).
- One new exported S3 generic (`canonical_names`) + three methods
  (`canonical_names.flexybayes`, `canonical_names.flexybayes_inla`,
  `canonical_names.flexybayes_direct_greta`).
- One new internal helper (`register_canonical_mapper`) -- internal in
  v0.2; exported in v0.3 when third-party backend authors might use it.
- `triangulate.R` extension (~30 lines): default-resolution logic that
  consults `canonical_names(fit)` when `name_map = NULL`. No signature
  change. Existing call sites unaffected.
- `R/fb_greta.R` reads `$extras$model_info$canonical_map` populated per
  ADR 0012 sec.1; `R/flexybayes.R` populates `$extras$canonical_map` at
  fit-completion so `canonical_names(fit)` is O(1) downstream.
- Test coverage adds `test-canonical-names.R` covering: greta + INLA
  canonical-name maps, precision-to-SD transform, no-name_map
  `triangulate()` resolution, registry round-trip via
  `register_canonical_mapper()`, fb_greta user-supplied
  `canonical_names` precedence.
- Vignette coverage: vignette 09 (Triangulation) gains a chunk
  demonstrating no-`name_map` calls; existing user-supplied chunk
  preserved as the explicit-override example.
- Strict precondition for the Ambition-lane `triangulate_all()`
  verb -- the N-engine variant cannot ship without this registry.
- Out-of-scope (explicitly deferred): multi-term random-effect naming
  (`sd_<group>__<term>` form; v0.3); NIMBLE mapper (Ambition lane);
  brms-via-Stan as a triangulate peer (Ambition lane); tensor-product
  smooth naming (`te()` / `ti()` / `t2()`; Ambition lane);
  user-facing `register_canonical_mapper()` export (v0.3+).

## References

### Methodological

- Bürkner, P.-C. (2017). brms: An R Package for Bayesian Multilevel
  Models Using Stan. *Journal of Statistical Software*, 80(1), 1--28.
  doi:10.18637/jss.v080.i01. -- Establishes the brms naming convention
  (`b_<term>`, `sd_<group>`, `sigma`) adopted as canonical.
- Vehtari, A., et al. *posterior*: Tools for Working with Posterior
  Distributions. CRAN. -- Standardises the `posterior::draws_array`
  shape with named parameters; canonical view aligns with that shape.
- Gabry, J., et al. *bayesplot*: Plotting for Bayesian Models. CRAN.
  -- The `bayesplot::mcmc_*()` plotting functions key off brms-style
  parameter names; canonical adoption preserves zero-rename composition.

### Empirical

- `design-notes-priors-brms-lgm.md` lines 1028--1196 -- the source ADR
  slice this cairn was reconstructed from (load-bearing empirical
  citation for this archaeological cairn).
- `R/canonical_names.R` -- the implementation surface (~250 lines
  anticipated; ships in v0.2 with greta + INLA mappers).
- `tests/testthat/test-canonical-names.R` -- the test corpus (six
  assertion clusters per source ### Consequences).
- `vignettes/09-triangulation.Rmd` -- the user-facing demonstration
  chunk added by this ADR.

### Operational

- ADR: `design-notes-priors-brms-lgm.md` §ADR 0005 -- the source ADR
  this cairn reconstructs.
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0004 (uniform default;
  SD-scale prior convention) -- composes with this ADR; reason Option
  D was rejected.
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0006 (`backend_decision()`
  trace) -- composes with this ADR; the `$extras` slots are
  orthogonal (canonical_names reads the canonical_map; backend_decision
  reads the dispatch trace).
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0010 (`prior_fixed_sd`
  default) -- SD-scale convention this ADR's Option D would have
  conflicted with.
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0012 (`fb_greta()`
  direct-greta entry) -- populates `$extras$model_info$canonical_map`
  consumed by `canonical_names.flexybayes_direct_greta`.
