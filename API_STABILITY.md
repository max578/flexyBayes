# API stability — flexyBayes

`flexyBayes` is in the **0.3.x** series. Every public export carries a
`lifecycle::badge("experimental")`. The stability guarantees below are
therefore deliberately weaker than they will be at v1.0.

## Stability ladder (lifecycle)

| Stage | Meaning for `flexyBayes` |
|---|---|
| **stable** | Behaviour and signature frozen across the 1.x series; breaking changes ride a major version bump and a deprecation cycle. *No exports are stable yet.* |
| **maturing** | Behaviour and signature unlikely to change in 0.x; minor signature additions are non-breaking. |
| **experimental** | Behaviour and signature may change in any 0.x release. Bug fixes and additions never break, but renamings, default-value changes, and shape changes are allowed with a `lifecycle::deprecate_warn()` cycle of at least one minor release. **All v0.3.x exports.** |
| **deprecated** | Function still callable; emits `lifecycle::deprecate_warn()`. Removal scheduled per `NEWS.md`. |
| **superseded** | Function still callable, no warning, but a newer entry point is preferred. |

## Per-export stability surface (v0.3.x)

The four-verb spine plus its companion diagnostics:

| Export | Stage | Notes |
|---|---|---|
| `flexybayes()` | experimental | ASReml-style entry (`fixed`, `random`, `rcov`). `backend = c("greta", "inla", "auto")`. `prior` argument accepts `fb_prior()`. |
| `fb_brms()` | experimental | brms / lme4-style entry. `backend = c("greta", "inla", "brms", "auto")`; `"brms"` is the Stan passthrough via `brms::brm()`. `"auto"` never routes to Stan (Decision 8 in ADR 0015). |
| `fb_greta()` | experimental | Expert direct-greta entry. Accepts a user-built greta model; `prior` is declaration-only (the user's graph is not re-priored). |
| `fb()` | experimental | Literal alias for `flexybayes()`; documented but not promoted. |
| `triangulate()` | experimental | Pairwise cross-engine posterior comparison. Metric set fixed for 0.3.x (Wasserstein-1, R-hat-on-means, tail drift, SD ratio, mean difference). Additions are non-breaking; metric removals or renamings ride a deprecation cycle. |
| `fb_prior()` | experimental | PC-canonical hybrid prior DSL on the SD scale. Supported targets: `sigma`, `sd(group)`, `b(name)`, `cor(group)`, `smooth(var)`. Supported families: `pc`, `normal`, `student_t`, `half_normal`, `half_cauchy`, `cauchy`, `gamma`, `exponential`, `lkj`, `uniform`. |
| `prior_summary()` | experimental | S3 generic returning the resolved-prior view for a fit. Methods registered for `flexybayes`, `flexybayes_inla`, `flexybayes_brms`, and `flexybayes_direct_greta`. |
| `backend_decision()` | experimental | Returns the captured dispatch trace (`backend`, `path`, `gate_checks`, `reason`). Shape stable across 0.3.x. |
| `canonical_names()` | experimental | S3 generic returning the canonical-name registry view for a fit. Methods registered for all four fit subclasses. |
| `proceed()`, `cat_code()` | experimental | Review-code workflow companions for `review_code = TRUE` fits. |
| `fb_as_draws_simple()` | experimental | S3 generic; methods for all four fit subclasses. Returns a named list of named draw vectors. |
| `tidy.flexybayes()`, `glance.flexybayes()`, `augment.flexybayes()` | experimental | broom-compliant; column names follow broom convention and are stable for the columns currently emitted. New columns are non-breaking. |
| `recover_data.flexybayes()`, `emm_basis.flexybayes()` | experimental | emmeans-compliant; signatures dictated by the emmeans S3 contract. |
| `print.lgm_refusal()` | experimental | Internal S3 method, registered for dispatch only; output format may evolve when ADR 0017 lands (refusal sites consolidated into `lgm_gate()`). |

## Internal-but-S3-visible diagnostics

A small set of internal constructors -- `.fb_dataset()`, `.fb_preflight()`,
`.fb_aggregate_gaussian()` -- are not exported, but their S3 `print` /
`format` methods are registered for dispatch on diagnostic output
(refusal messages, `review_code` summaries, interactive inspection at
the console). Because the methods are registered via the S3 mechanism,
`R CMD check` requires generated `.Rd` entries; those entries are
visible from `?print.fb_preflight` and similar.

Stability promise for these methods through 0.3.x:

- The methods exist and dispatch correctly on instances of the internal
  classes.
- The output format -- column ordering, whitespace, exact wording --
  is **internal-grade** and may change without a deprecation cycle.
- Programmatic use is not supported: parse the structured slot fields
  on the underlying object (`$per_term_estimate`, `$sufficient_stats`,
  `$dictionaries`, etc.) rather than the printed string.

The constructor functions themselves remain internal. Stable export is
gated on at least two downstream workflows (Stage 3A aggregation in
v0.3.2; Stage 3B chunked predict in v0.3.3) reaching the contract
stability bar.

## Default-value contract (v0.3.x)

The current prior contract on the auto-default path — that is, when
neither a user `fb_prior()` nor a legacy `prior_vc_sd` scalar is
supplied:

| Target | Default | Reference |
|---|---|---|
| Residual `sigma` (Gaussian, identity link) | `uniform(0, 5 * sd(y))` | Gelman 2006 |
| Residual `sigma` (log link) | `uniform(0, 5 * sd(log(y + 0.5)))` | Gelman 2006 |
| Residual `sigma` (logit link) | `uniform(0, 5)` | Gelman 2006 |
| `sd(group)` for `simple` / `ide` / `id` random terms | `uniform(0, U)` with `U` set as above by family | Gelman 2006 |
| `sd(group)` for structured-cov terms (`vm`, `ped`, `at`, `us`, `fa`, `ar1`) | legacy `lognormal(0, prior_vc_sd)` (per-form uniform default scheduled for v0.2.5) | flexyBayes legacy |
| Fixed-effect coefficients (intercept, slopes, factor contrasts, `I()` expressions) | `normal(0, prior_fixed_sd)` with `prior_fixed_sd = 100` | Gelman 2006 |

The PC prior remains a first-class explicit option via
`fb_prior(sigma ~ pc(upper = U, prob = p))`, and is the cross-engine
interlingua (Simpson et al. 2017) for translation across greta / INLA /
brms. It is no longer the auto-default; the auto-default is the
bounded uniform on SD.

The legacy scalar bridge (`prior_fixed_sd`, `prior_vc_sd`) preserves
the original `lognormal(0, prior_vc_sd)` semantics verbatim when the
caller passes `prior_vc_sd` explicitly. `prior_summary()` reports
which of the three resolution paths fired (`auto-default`,
`user-supplied`, `legacy-scalar`).

The `prior_fixed_sd` default raised from 10 to 100 between the local
2026-04-27 rename and the v0.2 finalisation, per ADR 0010 — the
previous value was too tight for responses on the natural data scale
(e.g., `sleepstudy$Reaction` with mean ≈ 298 ms) and induced a
substantial intercept bias against the REML reference.

## Deprecation policy

When an experimental export is renamed, restructured, or removed:

1. The old call path emits `lifecycle::deprecate_warn()` for at least
   one minor release (a "warn cycle").
2. The next minor release moves the old call path to
   `lifecycle::deprecate_stop()` ("error cycle"); the function still
   exists but signals a hard error directing callers to the
   replacement.
3. The next minor release after that removes the old export entirely.

For a default-value change, the old default remains available behind
an explicit argument for at least the entire 0.x series.

## Compatibility commitments through 0.3.x

Stable across the 0.3.x patch line:

- The four fit subclasses' externally-visible top-level structure
  (`$glm`, plus the backend-specific slot: `$greta`, `$inla`, or
  `$brms`, plus `$extras`).
- The `fb_prior()` print method's output format.
- The `triangulate()` return shape — `metrics` data frame columns,
  `common` / `only_a` / `only_b` character vectors, `n_common` scalar,
  `source_a` / `source_b` strings.
- The `backend_decision()` return shape — `backend`, `path`,
  `gate_checks`, `reason`.
- The `prior_summary()` return shape — `kind`, `backend`,
  `default_origin`, `fb_prior`, `default_scale`, `default_basis`,
  `declaration_only`.

## What changes when

| Change class | Where it can land |
|---|---|
| New parameter with default value | any patch (0.3.0.9001) |
| New behaviour behind opt-in argument | any patch |
| Bug fix that changes numerical output within tolerance | any patch — flagged in `NEWS.md` |
| New exported function | minor (0.4.0) |
| Renamed export with deprecation cycle | minor |
| Removed export (post-deprecation cycle) | minor |
| Class-structure change | minor |
| Backend swap (e.g., greta → gretaR) at the `flexybayes()` level | minor; gated by capability detection so calls keep working |

## Pinning

Production users who need stability should pin to a specific 0.3.x
patch via `renv::snapshot()` until v1.0 lands.

## Roadmap to v1.0

- v0.2.5 — hardening: fold `emit_inla()` refusals into `lgm_gate()`
  (ADR 0017); smooth-basis retention on the IR for `predict()` with
  `newdata` (ADR 0018); structured-covariance default priors extend
  ADR 0004; numerical-snapshot plot regression tests replacing the
  vdiffr skip.
- v0.3 — Ambition lane: `triangulate_all()` over fitted-model lists;
  tensor smooths (`te` / `ti` / `t2`); BYM2 spatial random effects;
  NIMBLE HMM proof; PESTO → prior bridge (ADR 0008); posteriordb
  ≥40-paired test corpus; gretaR slot activation (external
  precondition).
- v0.4 — survival (parametric AFT + Cox via INLA Poisson);
  multi-engine missing-data ensemble.
- v0.9 — release rehearsal; lift exports from experimental to
  maturing; freeze API for v1.0.
- v1.0 — promote core exports to stable.
