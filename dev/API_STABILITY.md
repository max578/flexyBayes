# API stability — flexyBayes

`flexyBayes` is in the **0.3.x** series. Every public export carries a
`lifecycle::badge("experimental")`. The stability guarantees below are
therefore deliberately weaker than they will be at v1.0.

## Stability ladder (lifecycle)

| Stage | Meaning for `flexyBayes` |
|----|----|
| **stable** | Behaviour and signature frozen across the 1.x series; breaking changes ride a major version bump and a deprecation cycle. *No exports are stable yet.* |
| **maturing** | Behaviour and signature unlikely to change in 0.x; minor signature additions are non-breaking. |
| **experimental** | Behaviour and signature may change in any 0.x release. Bug fixes and additions never break, but renamings, default-value changes, and shape changes are allowed with a [`lifecycle::deprecate_warn()`](https://lifecycle.r-lib.org/reference/deprecate_soft.html) cycle of at least one minor release. **All v0.3.x exports.** |
| **deprecated** | Function still callable; emits [`lifecycle::deprecate_warn()`](https://lifecycle.r-lib.org/reference/deprecate_soft.html). Removal scheduled per `NEWS.md`. |
| **superseded** | Function still callable, no warning, but a newer entry point is preferred. |

## Per-export stability surface (v0.3.x)

The four-verb spine plus its companion diagnostics:

| Export | Stage | Notes |
|----|----|----|
| [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md) | experimental | ASReml-style entry (`fixed`, `random`, `rcov`). `backend = c("greta", "inla", "auto")`. `prior` argument accepts [`fb_prior()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_prior.md). |
| [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_brms.md) | experimental | brms / lme4-style entry. `backend = c("greta", "inla", "brms", "auto")`; `"brms"` is the Stan passthrough via `brms::brm()`. `"auto"` never routes to Stan (Decision 8 in ADR 0015). |
| [`fb_greta()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_greta.md) | experimental | Expert direct-greta entry. Accepts a user-built greta model; `prior` is declaration-only (the user’s graph is not re-priored). |
| [`fb()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md) | experimental | Literal alias for [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md); documented but not promoted. |
| [`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md) | experimental | Pairwise cross-engine posterior comparison. Metric set fixed for 0.3.x (Wasserstein-1, R-hat-on-means, tail drift, SD ratio, mean difference). Additions are non-breaking; metric removals or renamings ride a deprecation cycle. |
| [`fb_prior()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_prior.md) | experimental | PC-canonical hybrid prior DSL on the SD scale. Supported targets: `sigma`, `sd(group)`, `b(name)`, `cor(group)`, `smooth(var)`. Supported families: `pc`, `normal`, `student_t`, `half_normal`, `half_cauchy`, `cauchy`, `gamma`, `exponential`, `lkj`, `uniform`. |
| [`prior_summary()`](https://aagi-aus.github.io/flexyBayes/dev/reference/prior_summary.md) | experimental | S3 generic returning the resolved-prior view for a fit. Methods registered for `flexybayes`, `flexybayes_inla`, `flexybayes_brms`, and `flexybayes_direct_greta`. |
| [`backend_decision()`](https://aagi-aus.github.io/flexyBayes/dev/reference/backend_decision.md) | experimental | Returns the captured dispatch trace (`backend`, `path`, `gate_checks`, `reason`). Shape stable across 0.3.x. |
| [`canonical_names()`](https://aagi-aus.github.io/flexyBayes/dev/reference/canonical_names.md) | experimental | S3 generic returning the canonical-name registry view for a fit. Methods registered for all four fit subclasses. |
| [`proceed()`](https://aagi-aus.github.io/flexyBayes/dev/reference/proceed.md), [`cat_code()`](https://aagi-aus.github.io/flexyBayes/dev/reference/cat_code.md) | experimental | Review-code workflow companions for `review_code = TRUE` fits. |
| [`fb_as_draws_simple()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_as_draws_simple.md) | experimental | S3 generic; methods for all four fit subclasses. Returns a named list of named draw vectors. |
| [`tidy.flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/tidy.flexybayes.md), [`glance.flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/glance.flexybayes.md), [`augment.flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/augment.flexybayes.md) | experimental | broom-compliant; column names follow broom convention and are stable for the columns currently emitted. New columns are non-breaking. |
| [`recover_data.flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/recover_data.flexybayes.md), [`emm_basis.flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/emm_basis.flexybayes.md) | experimental | emmeans-compliant; signatures dictated by the emmeans S3 contract. |
| [`print.lgm_refusal()`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.lgm_refusal.md) | experimental | Internal S3 method, registered for dispatch only; output format may evolve when ADR 0017 lands (refusal sites consolidated into `lgm_gate()`). |
| [`predict.flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/predict.flexybayes.md) (Stage 3A / 3B) | experimental | `newdata` interface mirrors [`stats::predict()`](https://rdrr.io/r/stats/predict.html); v0.3.5 added `output_file` / `format = c("auto","csv","rds","fst")` / `interop` arguments + `allow_new_levels = c("population","sample","refuse")`. Interval semantics are *posterior expected-response*, not posterior-predictive (no residual observation noise). Stage 3A `$aggregate` argument is backend-asymmetric: `"auto"` activates the aggregated path on `backend = "inla"`; on `backend = "greta"` requires explicit `TRUE`. |
| Known-covariance carriers on `vm()` / `ped()` (Stage 5A) | experimental | v0.3.7: `chol = L` (greta only), `precision = Q` (greta + INLA via `generic0`), `ped(..., use_sparse_precision = TRUE)`. Mutually exclusive with the dense `V` carrier and with each other. `blocks = list(V1, V2, ...)` reserves its input vocabulary in v0.3.7 and refuses with `route_not_yet_emitted` (lands v0.3.8). `low_rank_factor =` reserves a slot gated behind ADR 0027 (Stage 6 / v0.4.0); refuses with `approximate_route_not_yet_registered`. |

## Internal-but-S3-visible diagnostics

A small set of internal constructors – `.fb_dataset()`,
`.fb_preflight()`, `.fb_aggregate_gaussian()`, `.fb_aggregation_plan()`
– are not exported, but their S3 `print` / `format` methods are
registered for dispatch on diagnostic output (refusal messages,
`review_code` summaries, interactive inspection at the console). Because
the methods are registered via the S3 mechanism, `R CMD check` requires
generated `.Rd` entries; those entries are visible from
[`?print.fb_preflight`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.fb_preflight.md)
and similar.

Stability promise for these methods through 0.3.x:

- The methods exist and dispatch correctly on instances of the internal
  classes.
- The output format – column ordering, whitespace, exact wording – is
  **internal-grade** and may change without a deprecation cycle.
- Programmatic use is not supported: parse the structured slot fields on
  the underlying object (`$per_term_estimate`, `$sufficient_stats`,
  `$dictionaries`, etc.) rather than the printed string.

The constructor functions themselves remain internal. Stable export is
gated on at least two downstream workflows (Stage 3A aggregation in
v0.3.2; Stage 3B chunked predict in v0.3.3) reaching the contract
stability bar.

## Default-value contract (v0.3.x)

The current prior contract on the auto-default path — that is, when
neither a user
[`fb_prior()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_prior.md)
nor a legacy `prior_vc_sd` scalar is supplied:

| Target | Default | Reference |
|----|----|----|
| Residual `sigma` (Gaussian, identity link) | `uniform(0, 5 * sd(y))` | Gelman 2006 |
| Residual `sigma` (log link) | `uniform(0, 5 * sd(log(y + 0.5)))` | Gelman 2006 |
| Residual `sigma` (logit link) | `uniform(0, 5)` | Gelman 2006 |
| `sd(group)` for `simple` / `ide` / `id` random terms | `uniform(0, U)` with `U` set as above by family | Gelman 2006 |
| `sd(group)` for `vm()`, `ped()` structured-cov terms | `uniform(0, U)` with `U` set by family (matches the random-intercept default; routes via `.sigma_decl()`) | Gelman 2006 |
| `sd(group)` for `at()`, `us()`, `fa()`, `ar1()`, `spl()` structured-cov terms | legacy `lognormal(0, prior_vc_sd)` — per-form uniform default deferred to a future minor release | flexyBayes legacy |
| Fixed-effect coefficients (intercept, slopes, factor contrasts, [`I()`](https://rdrr.io/r/base/AsIs.html) expressions) | `normal(0, prior_fixed_sd)` with `prior_fixed_sd = 100` | Gelman 2006 |

The PC prior remains a first-class explicit option via
`fb_prior(sigma ~ pc(upper = U, prob = p))`, and is the cross-engine
interlingua (Simpson et al. 2017) for translation across greta / INLA /
brms. It is no longer the auto-default; the auto-default is the bounded
uniform on SD.

The legacy scalar bridge (`prior_fixed_sd`, `prior_vc_sd`) preserves the
original `lognormal(0, prior_vc_sd)` semantics verbatim when the caller
passes `prior_vc_sd` explicitly.
[`prior_summary()`](https://aagi-aus.github.io/flexyBayes/dev/reference/prior_summary.md)
reports which of the three resolution paths fired (`auto-default`,
`user-supplied`, `legacy-scalar`).

The `prior_fixed_sd` default raised from 10 to 100 between the local
2026-04-27 rename and the v0.2 finalisation, per ADR 0010 — the previous
value was too tight for responses on the natural data scale (e.g.,
`sleepstudy$Reaction` with mean ≈ 298 ms) and induced a substantial
intercept bias against the REML reference.

## Deprecation policy

When an experimental export is renamed, restructured, or removed:

1.  The old call path emits
    [`lifecycle::deprecate_warn()`](https://lifecycle.r-lib.org/reference/deprecate_soft.html)
    for at least one minor release (a “warn cycle”).
2.  The next minor release moves the old call path to
    [`lifecycle::deprecate_stop()`](https://lifecycle.r-lib.org/reference/deprecate_soft.html)
    (“error cycle”); the function still exists but signals a hard error
    directing callers to the replacement.
3.  The next minor release after that removes the old export entirely.

For a default-value change, the old default remains available behind an
explicit argument for at least the entire 0.x series.

## Compatibility commitments through 0.3.x

Stable across the 0.3.x patch line:

- The four fit subclasses’ externally-visible top-level structure
  (`$glm`, plus the backend-specific slot: `$greta`, `$inla`, or
  `$brms`, plus `$extras`).
- The
  [`fb_prior()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_prior.md)
  print method’s output format.
- The
  [`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)
  return shape — `metrics` data frame columns, `common` / `only_a` /
  `only_b` character vectors, `n_common` scalar, `source_a` / `source_b`
  strings.
- The
  [`backend_decision()`](https://aagi-aus.github.io/flexyBayes/dev/reference/backend_decision.md)
  return shape — `backend`, `path`, `gate_checks`, `reason`.
- The
  [`prior_summary()`](https://aagi-aus.github.io/flexyBayes/dev/reference/prior_summary.md)
  return shape — `kind`, `backend`, `default_origin`, `fb_prior`,
  `default_scale`, `default_basis`, `declaration_only`.

## What changes when

| Change class | Where it can land |
|----|----|
| New parameter with default value | any patch (0.3.0.9001) |
| New behaviour behind opt-in argument | any patch |
| Bug fix that changes numerical output within tolerance | any patch — flagged in `NEWS.md` |
| New exported function | minor (0.4.0) |
| Renamed export with deprecation cycle | minor |
| Removed export (post-deprecation cycle) | minor |
| Class-structure change | minor |
| Backend swap (e.g., greta → gretaR) at the [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md) level | minor; gated by capability detection so calls keep working |

## Pinning

Production users who need stability should pin to a specific 0.3.x patch
via `renv::snapshot()` until v1.0 lands.

## Roadmap to v1.0

- v0.2.5 — hardening: fold `emit_inla()` refusals into `lgm_gate()` (ADR
  0017); smooth-basis retention on the IR for
  [`predict()`](https://rdrr.io/r/stats/predict.html) with `newdata`
  (ADR 0018); structured-covariance default priors extend ADR 0004;
  numerical-snapshot plot regression tests replacing the vdiffr skip.
- v0.3 — Ambition lane: `triangulate_all()` over fitted-model lists;
  tensor smooths (`te` / `ti` / `t2`); BYM2 spatial random effects;
  NIMBLE HMM proof; PESTO → prior bridge (ADR 0008); posteriordb
  ≥40-paired test corpus; gretaR slot activation (external
  precondition).
- v0.4 — survival (parametric AFT + Cox via INLA Poisson); multi-engine
  missing-data ensemble.
- v0.9 — release rehearsal; lift exports from experimental to maturing;
  freeze API for v1.0.
- v1.0 — promote core exports to stable.
