# API stability — bayesreml

`bayesreml` is in the **0.1.x** series. Every public export carries a
`lifecycle::badge("experimental")`. The stability guarantees below are
therefore deliberately weaker than they will be at v1.0.

## Stability ladder (lifecycle)

| Stage | Meaning for `bayesreml` |
|---|---|
| **stable** | Behaviour and signature frozen across the 1.x series; breaking changes ride a major version bump and a deprecation cycle. *No exports are stable yet.* |
| **maturing** | Behaviour and signature unlikely to change in 0.x; minor signature additions are non-breaking. |
| **experimental** | Behaviour and signature may change in any 0.x release. Bug fixes and additions never break, but renamings, default-value changes, and shape changes are allowed with a `lifecycle::deprecate_warn()` cycle of at least one minor release. **All v0.1.x exports.** |
| **deprecated** | Function still callable; emits `lifecycle::deprecate_warn()`. Removal scheduled per `NEWS.md`. |
| **superseded** | Function still callable, no warning, but a newer entry point is preferred. |

## Per-export stability surface (v0.1.x)

| Export | Stage | Notes |
|---|---|---|
| `bayesreml()` | experimental | Signature inherited from the original asreml-format API; `prior` argument added in 0.1.0.9000 is forward-compatible with v0.2 codegen extensions. |
| `fb()` | experimental | brms-format ingest. v0.1 dispatches `"greta"` and `"inla"`; `"brms"` and `"auto"` will gain real dispatch in v0.2. |
| `fb_prior()` | experimental | DSL targets and distribution families list grows in v0.2 (bounded uniform on greta direct; structured-covariance honouring). |
| `triangulate()` | experimental | Metric set fixed for 0.1.x (Wasserstein-1, R-hat-on-means, tail drift, SD ratio). Additions are non-breaking; metric removals or renamings ride a deprecation cycle. |
| `fb_as_draws_simple()` | experimental | S3 generic. New methods may be added; signature stable. |
| `tidy.bayesreml()`, `glance.bayesreml()`, `augment.bayesreml()` | experimental | broom-compliant; column names follow broom convention and are stable for the columns currently emitted. New columns are non-breaking. |
| `recover_data.bayesreml()`, `emm_basis.bayesreml()` | experimental | emmeans-compliant; signatures dictated by the emmeans S3 contract. |

## Default-value changes (v0.1.0.9000)

The variance-component prior default changed from `lognormal(0, 1)` to
`pc(upper = 2.5*sd(y), prob = 0.05)` per Simpson 2017. The previous
default is preserved verbatim when the caller passes `prior_vc_sd`
explicitly. The change is announced once per session via a
`message()`; silence with
`options(bayesreml.silence_default_prior_note = TRUE)`. This counts as
a *behavioural* change (default value) and is the canonical example of
a breaking-by-default change permitted in the experimental tier with a
visible session-level notice.

## Deprecation policy

When an experimental export is renamed, restructured, or removed:

1. The old call path emits `lifecycle::deprecate_warn()` for at least
   one minor release (a "warn cycle").
2. The next minor release moves the old call path to
   `lifecycle::deprecate_stop()` ("error cycle"); the function still
   exists but signals a hard error directing callers to the
   replacement.
3. The next minor release after that removes the old export entirely.

For a default-value change (cf. PC prior), the old default remains
available behind an explicit argument for at least the entire 0.x
series.

## Compatibility commitments through 0.1.x

Stable across the 0.1.x patch line:

- The `bayesreml`-class object's externally-visible structure
  (`$glm`, `$greta`, `$extras` top-level slots).
- The `fb_prior()` print method's output format.
- The `triangulate()` return shape — `metrics` data frame columns,
  `common` / `only_a` / `only_b` character vectors, `n_common`
  scalar, `source_a` / `source_b` strings.

## What changes when

| Change class | Where it can land |
|---|---|
| New parameter with default value | any patch (0.1.0.9001) |
| New behaviour behind opt-in argument | any patch |
| Bug fix that changes numerical output within tolerance | any patch — flagged in `NEWS.md` |
| New exported function | minor (0.2.0) |
| Renamed export with deprecation cycle | minor |
| Removed export (post-deprecation cycle) | minor |
| Class-structure change | minor |
| Backend swap (e.g., greta → gretaR) at the `bayesreml()` level | minor; gated by capability detection so calls keep working |

## Pinning

Production users who need stability should pin to a specific 0.1.x
patch via `renv::snapshot()` until v1.0 lands.

## Roadmap to v1.0

- v0.2 — bounded-uniform on greta direct; structured-covariance
  branches honour `fb_prior()`; `log_lik.bayesreml()` for `loo`;
  marginaleffects + effectsize class registration.
- v0.3 — gretaR backend (when public + audit-clean); LaTeX restricted-
  grammar parser; spatial (BYM2 + HSGP).
- v0.4 — NIMBLE backend for HMM/multistate; survival (parametric AFT
  + Cox via INLA Poisson).
- v0.9 — release rehearsal; lift exports from experimental to
  maturing; freeze API for v1.0.
- v1.0 — promote core exports to stable.
