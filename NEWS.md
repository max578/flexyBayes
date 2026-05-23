# flexyBayes 0.2.6.9000

## Feature -- uncorrelated random slopes (x || g) (ADR 0020)

`fb_brms(y ~ x + (x || g), ...)` now parses and emits the
uncorrelated random-effect form -- in lme4 / brms semantics each
level of `g` carries an independent intercept deviation AND an
independent slope deviation, both drawn from their own univariate-
normal priors (no correlation parameter shared between intercept
and slope). The explicit `(1 + x || g)` shape is equivalent;
`(0 + x || g)` suppresses the intercept block, yielding a slope-
only random effect. The correlated form `(x | g)` continues to
refuse with a v0.3 deferral message pointing to ADR 0025
(Stage 5A known-covariance inputs), which will admit the user-
supplied Cholesky factor that makes the correlated form
tractable; the refusal raises a typed condition
(`flexybayes_correlated_slope_unsupported`) carrying
`grouping_factor`, `slope_variable`, `deferral_target`, and
`workaround` slots so downstream tooling can pattern-match.

Canonical-name family `sd_<x>_<g>` registered on the greta + brms
backends -- the brms-side `sd_<g>__<x>` parameter (brms's
double-underscore Stan convention) maps to the canonical
`sd_<x>_<g>`. INLA mapping is gated by a three-arbitrator
verification test (INLA vs greta vs lme4) on a simple fixture
following the §3.4 verification policy in
`plan-indexing-bigdata-merged-2026-05-23-v2.md`; until the
verification artefact records pass, the INLA backend refuses
`(x || g)` with a v0.3 deferral message naming `backend = "greta"`
as the workaround. Triangulation between greta and brms on
`(x || g)` fits agrees on slope-variance posteriors within
`W_1 <= 0.20 * tau_true` (the loosened envelope per merged-v2
§5.6 risk 3 -- slope-variance posteriors are intrinsically less
identified than intercept-variance ones at modest J).

# flexyBayes 0.2.5.9000

## Correctness fix -- predict(newdata) on smooths (ADR 0018)

`predict.flexybayes(..., newdata = ...)` on fits containing one or
more `s()` smooth terms now uses retained `mgcv` `Smooth` objects via
`mgcv::PredictMat()`, restoring correctness on `newdata` containing
`x` values inside or near the training range. Previously the basis
was implicitly re-derived from `newdata` via `stats::model.matrix()`,
producing correct-by-coincidence values inside the training range
and silently wrong values near or beyond. The fix retains the
`mgcv::smoothCon()` output on the IR (internal slot
`random_terms[[i]]$smooth_obj`) and threads it via
`extras$parse_info$smooths`. `fb_brms(backend = "brms")` and
`fb_greta()` are exempt -- both already correct.

A correctness refusal fires on legacy fits saved before this fix:
re-fit on the current version to enable `predict(newdata)`.

## Code-size fix -- smooth emit literal-matrix storage

The `greta` emit path for `s()` smooths no longer inlines the n-row
basis matrix as a literal in the generated code. The basis is bound
into the model environment as `B_s_<varname>` and the emitted code
references `as_data(B_s_<varname>)` instead.
`nchar(return_code(fit))` for `s(x)` at `n = 10000` dropped from
~10 MB to under 10 kB.

## Gate truth = emit truth (ADR 0017)

`lgm_gate(fb) == accept` is now a sufficient condition for the
INLA emit path to succeed structurally. Three new gate rules
(`fixed_term_type_inla`, `random_term_type_inla`,
`rcov_term_type_inla`) fold the prior emit-time refusal sites into
`lgm_gate()` so users see refusals before the INLA machinery is
invoked. `backend = "auto"` no longer carries a separate emit-time
fall-back path; dispatch trace's auto-non-LGM path is uniformly
`"auto_lgm_refuse"`.

## Visual-regression test tier upgraded (AMBITION_STAGE §1.1)

The `vdiffr` SVG-snapshot tests in `test-plot-vdiffr.R` (which had
been skipped unconditionally due to MCMC-float-drift fragility) are
replaced with numerical snapshots on the plotted data structure.
Equivalent coverage for "did the plot get built correctly" without
the SVG-diff fragility.

## Structured-cov default priors -- vm() + ped() now uniform-on-SD

`.default_uniform_prior()` (extending ADR 0004) now fires on `vm()`
and `ped()` random-term inputs, closing the documented inconsistency
where `simple`/`ide`/`id` RE SDs defaulted to uniform-on-SD while
`vm`/`ped` fell back to legacy lognormal. The other structured forms
(`at`, `us`, `fa`, `ar1`) remain on the legacy default for now.

# flexyBayes 0.2.0 (development)

## Four-verb API

`flexyBayes` exposes four user-facing entry points covering the
formula-grammar × backend-ambition cross-product:

| Verb | Grammar | Backend choices | Use when |
|---|---|---|---|
| `flexybayes()` | ASReml (`fixed` / `random` / `rcov`) | `greta`, `inla`, `auto` | ASReml syntax; agricultural / variance-component workflows. |
| `fb_brms()` | brms / lme4 (`y ~ x + (1 | g)`) | `greta`, `inla`, `brms`, `auto` | brms or lme4 syntax; Stan passthrough on `backend = "brms"`. |
| `fb_greta()` | direct greta model graph | `greta` | Expert escape hatch; supplies a pre-built greta model. |
| `triangulate()` | n/a | n/a | Pairwise cross-engine posterior comparison. |

`fb()` remains as a literal alias for `flexybayes()`.

## Dispatch trace

Every fit records a structured `backend_decision()` describing which
backend ran and why:

```r
fit <- flexybayes(yield ~ env, random = ~ geno, data = trial)
backend_decision(fit)
#> $backend     "greta"
#> $path        "auto_inla_refuse"
#> $gate_checks <list of lgm_gate rules + pass/fail>
#> $reason      "lgm_gate refused at check `hyperparam_budget`."
```

`backend = "auto"` runs `lgm_gate()` and routes to INLA on acceptance,
otherwise to greta. `auto` never routes to Stan — brms's first-call
Stan compile (typically 30–60 s) is incompatible with the auto-fast-
path promise; Stan is opt-in only via explicit `backend = "brms"` on
`fb_brms()`.

## Stan passthrough on `fb_brms(backend = "brms")`

`fb_brms()` builds the flexyBayes intermediate representation (IR),
translates the prior, hands off to `brms::brm()`, and wraps the
returned `brmsfit` in a `c("flexybayes_brms", "flexybayes")` subclass.
The live `brmsfit` is exposed on the `$brms` slot so brms's own
posterior tooling (`loo()`, `posterior_predict()`, `bayes_factor()`)
remains directly available.

```r
fit_s <- fb_brms(Reaction ~ Days + (1 | Subject),
                 data = sleepstudy, backend = "brms")
fit_g <- fb_brms(Reaction ~ Days + (1 | Subject),
                 data = sleepstudy, backend = "greta")
triangulate(fit_s, fit_g)
```

`review_code = TRUE` on the Stan path returns Stan source via
`brms::make_stancode()` — compile-free inspection before any Stan
compilation fires.

## Cross-engine triangulation

`triangulate(fit_a, fit_b)` computes mean difference, SD ratio, tail
drift, Wasserstein-1, and R-hat-on-means on every parameter the two
fits have in common. Canonical-name resolution (see below) means the
caller usually does not need to pass a `name_map`.

```r
fit_g <- flexybayes(yield ~ env, random = ~ geno, data = trial,
                    backend = "greta")
fit_i <- flexybayes(yield ~ env, random = ~ geno, data = trial,
                    backend = "inla")
triangulate(fit_g, fit_i)
#> Common parameters: 5
#> # A tibble: 5 × 6
#>   parameter        mean_diff sd_ratio tail_drift wasserstein_1 rhat_means
#>   <chr>                <dbl>    <dbl>      <dbl>         <dbl>      <dbl>
#> 1 (Intercept)        -0.041   0.997      0.012         0.041     1.002
#> ...
```

## `canonical_names()` registry

Each backend names parameters differently (greta's `sigma_g`, INLA's
`Precision for g` on the precision scale, brms's `sd_g__Intercept`,
etc.). `canonical_names()` resolves backend-native names to a single
canonical name and applies the appropriate scale transform — most
visibly, INLA's precision draws are flipped to the SD scale before
comparison.

```r
canonical_names(fit_i)
#>   native                canonical    transform
#>   "(Intercept)"         "(Intercept)" identity
#>   "Precision for g"     "sd_g"        1/sqrt(.)
#>   "Precision for the Gaussian observations" "sigma" 1/sqrt(.)
```

`triangulate()` uses the registry to align parameters before
computing metrics.

## `prior_summary()` accessor

A new exported S3 generic surfaces the resolved priors used to fit
the model. The summary distinguishes three resolution paths:

- **auto-default** — bounded uniform on SD per Gelman (2006); fires
  when neither a user `fb_prior()` nor a legacy `prior_vc_sd` scalar
  is supplied.
- **user-supplied** — the `fb_prior()` object the caller passed via
  the `prior` argument.
- **legacy-scalar** — the `prior_fixed_sd` / `prior_vc_sd` bridge,
  preserved verbatim when `prior_vc_sd` is passed explicitly.

```r
fit <- flexybayes(Reaction ~ Days, random = ~ Subject,
                  data = sleepstudy)
prior_summary(fit)
#> <prior_summary>  backend = greta
#>   Source: auto-default bounded uniform on SD (Gelman 2006)
#>     Upper bound U = 282.7
#>     Scale basis    = 5 * sd(Reaction)
```

On `fb_greta()` fits the summary is flagged `declaration_only = TRUE`
because flexyBayes does not re-prior the user-built greta graph; the
prior records what the user declared the model encodes.

## `review_code = TRUE` workflow

A new optional argument on `flexybayes()`, `fb_brms()`, and
`fb_greta()` lets users inspect the generated backend code before any
sampling fires, then advance into the fit when ready:

```r
rev <- flexybayes(yield ~ env, random = ~ geno, data = trial,
                  review_code = TRUE)
rev                  # two-line summary: backend + IR dimensions
cat_code(rev)        # emit the generated greta (or Stan) code
fit <- proceed(rev)  # fit; a second proceed(rev) returns the cache
```

The returned `<flexybayes_review>` object carries the generated code,
the parsed IR, the resolved prior, the captured call, and a snapshot
of `.Random.seed`. The seed snapshot is restored on `proceed()` entry
so a direct call and a review-then-proceed pair reproduce the same
R-RNG state.

`review_code = TRUE` and `return_code = TRUE` (the older
code-string-only option) are mutually exclusive. Default is `FALSE`;
session-level override via
`options(flexyBayes.review_code_default = TRUE)`.

## Prior contract

Auto-default (no `prior` and no `prior_vc_sd` supplied):

| Target | Default | Notes |
|---|---|---|
| Residual `sigma` (Gaussian / identity link) | `uniform(0, 5 * sd(y))` | Gelman 2006 |
| Residual `sigma` (log link) | `uniform(0, 5 * sd(log(y + 0.5)))` | Gelman 2006 |
| Residual `sigma` (logit link) | `uniform(0, 5)` | Gelman 2006 |
| `sd(group)` for `simple` / `ide` / `id` terms | matched to residual by family | Gelman 2006 |
| Fixed-effect coefficients | `normal(0, prior_fixed_sd)`, `prior_fixed_sd = 100` | Gelman 2006 |

Structured-covariance random terms (`vm`, `ped`, `at`, `us`, `fa`,
`ar1`) currently fall back to the legacy `lognormal(0, prior_vc_sd)`
default; per-form uniform defaults are scheduled for v0.2.5.

The PC prior remains a first-class explicit option via
`fb_prior(sigma ~ pc(upper = U, prob = p))` and is the cross-engine
interlingua (Simpson et al. 2017) for translation across greta / INLA
/ brms.

The `prior_fixed_sd` default was raised from 10 to 100 in this cycle;
the previous value was too tight for responses on the natural data
scale (e.g., `sleepstudy$Reaction` with mean ≈ 298 ms) and induced a
substantial intercept bias against the REML reference.

`fb_prior()` accepts the targets `sigma`, `sd(group)`, `b(name)`,
`cor(group)`, `smooth(var)`, and the families `pc`, `normal`,
`student_t`, `half_normal`, `half_cauchy`, `cauchy`, `gamma`,
`exponential`, `lkj`, `uniform`.

## LGM feasibility filter

`lgm_gate(fb)` runs a structural feasibility check on the parsed IR
before INLA dispatch. The filter returns either an acceptance or an
`lgm_refusal` object carrying every rule that failed, the diagnostic,
the suggested re-route (`backend = "brms"` via `fb_brms()` for the
Stan passthrough; greta for the broader flexyBayes formula path), and
a two-key-armed override path.

The structural refusals currently live in two places (the gate plus
`emit_inla()`); folding the emit-time refusals into the gate is the
ADR 0017 v0.2.5 work.

## `gretaR` slot

A dormant scaffold for the `gretaR` backend is registered:
`gretaR_status()` reports `activated = FALSE` and explains the
activation procedure. The four touch-points (`match.arg` extension,
canonical-name mapper, dispatch branch, status helper) are in place
so v0.3 activation reduces to a single short patch plus the
`emit_gretaR.R` body — once the gretaR package goes public and
audit-clean.

## Vignettes

Twelve numbered vignettes ship with the package:

1. Getting started · 2. ASReml-shaped formulas · 3. Foundational
regression · 4. Hierarchical models · 5. Structured covariance ·
6. Priors and regularisation · 7. METs and genomic selection ·
8. Downstream analysis · 9. Spatio-temporal models · 10. Cross-
engine triangulation · 11. LGM feasibility filter · 12. Backend
internals.

Heavy MCMC vignettes use a `.Rmd.orig` precompile pattern
(`vignettes/_precompile.R`); the `.Rmd` that ships in the package
tarball is the pre-evaluated static output.

## References

- Gelman, A. (2006). Prior distributions for variance parameters in
  hierarchical models. *Bayesian Analysis* 1(3): 515–534.
- Simpson, D., Rue, H., Riebler, A., Martins, T. G., & Sørbye, S. H.
  (2017). Penalising model component complexity: a principled,
  practical approach to constructing priors. *Statistical Science*
  32(1): 1–28.
- Rue, H., Martino, S., & Chopin, N. (2009). Approximate Bayesian
  inference for latent Gaussian models by using integrated nested
  Laplace approximations. *JRSS: Series B* 71(2): 319–392.
