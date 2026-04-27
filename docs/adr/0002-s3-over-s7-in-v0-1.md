# 2. Use S3 over S7 in v0.1

Date: 2026-04-27

## Status

Accepted. Reconsider at v1.0 if the S7 ecosystem matures and key
interop libraries (`broom`, `emmeans`, `marginaleffects`) adopt or
support S7 first-class.

## Context

`flexyBayes` exposes a small set of object classes:

| Class | Source | Role |
|---|---|---|
| `flexybayes` | `flexybayes()`, `fb()` greta path | top-level fit object |
| `flexybayes_glm` | `.build_glm()` | GLM-compatible facade |
| `flexybayes_inla` | `emit_inla()` | INLA-backed fit |
| `fb_terms` | `fb_from_asreml()`, `fb_from_brms()` | intermediate representation |
| `fb_prior` | `fb_prior()` | prior DSL specification |
| `triangulate_result` | `triangulate()` | cross-engine comparison output |
| `lgm_refusal` | `lgm_gate()` | structured-refusal carrier |

R has two object systems available for this work:

- **S3** — single-dispatch generics, informal class membership via
  `class()` attribute, broom-native, emmeans-native,
  marginaleffects-native, lme4-style. Most CRAN packages.
- **S7** — formal class declarations with `new_class()`,
  multiple-dispatch generics, validators, properties. The official
  successor to S4 / R5; growing but not yet ubiquitous.

The interop libraries the package integrates with —
`broom::tidy()` / `glance()` / `augment()`, `emmeans::recover_data()`
/ `emm_basis()`, `marginaleffects` (planned for v0.2),
`effectsize::standardize_parameters()` (planned for v0.2) — all
expose **S3 generics**. Methods written for those generics are
S3 methods regardless of how the underlying object is represented.

## Decision

Use S3 for all flexyBayes classes in v0.1.x. Concretely:

- Class membership via the `class` attribute, set in constructors.
- Method registration via `S3method()` directives in `NAMESPACE`
  (managed by roxygen2's `@export` on each method).
- Validation functions (`is_*()`) where useful, but no formal
  validator infrastructure.
- No multiple-dispatch generics (single-dispatch is sufficient
  because `triangulate()` uses an explicit two-fit signature, not
  multi-dispatch).

## Alternatives considered

- **S7 throughout.** Rejected for v0.1.x because broom / emmeans /
  marginaleffects all dispatch on S3, so we would need S3 methods
  *anyway* on every class. Adopting S7 would double the surface
  (S7 class + S3 method shim per generic), buy little, and add a
  hard `S7` Imports dependency.
- **Hybrid (S7 for new classes, S3 for legacy).** Rejected: the
  cognitive overhead of two object systems in one package outweighs
  the marginal benefit of formality on the new classes.
- **R6.** Rejected: reference semantics are wrong for fit objects
  (callers expect value semantics, not in-place mutation).

## Consequences

**Positive.**

- Light, broom / emmeans / marginaleffects-native; zero glue.
- Low Imports cost — S3 is in base R.
- Familiar to R developers; matches the lme4 / nlme / mgcv
  vocabulary the user base already speaks.

**Negative.**

- No formal type checking. We rely on `inherits()` checks and runtime
  validation in functions that consume the classes.
- Migration to S7 at v1.0 (if that path is chosen) requires moving
  7 classes plus all their method definitions. Lifecycle policy
  (see `API_STABILITY.md`) provides the deprecation cycle that
  makes this tractable: S3 generics stay callable through one
  release with `lifecycle::deprecate_warn()`, and S7 generics ship
  alongside.

**Neutral.**

- Class-structure changes inside the 0.1.x patch line are forbidden
  by `API_STABILITY.md`. Any move to S7 will land at the next
  minor release at minimum.

## Cite-trail

- *R Packages 2e*, ch. "Object systems".
- S7 design notes: <https://rconsortium.github.io/S7/>.
- broom / emmeans S3 contracts: see the respective package vignettes.
