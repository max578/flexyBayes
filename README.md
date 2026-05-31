# flexyBayes

Flexible Bayesian Mixed Models with ASReml and brms-Style Syntax

`flexyBayes` is a multi-backend Bayesian mixed-model framework with
cross-engine posterior **triangulation** exposed as a first-class
robustness diagnostic. The package routes one model specification to
greta (MCMC), INLA (integrated nested Laplace approximation), or brms
(Stan passthrough), and tells you — with evidence — when the engines
agree, when they differ, and why a backend was refused.

## Which entry point do I use?

| If you have… | Use | Notes |
|---|---|---|
| ASReml syntax (`fixed` / `random` / `rcov`) | `fb()` / `flexybayes()` | Variance-component / agricultural workflows. |
| brms or lme4 syntax (`y ~ x + (1 \| g)`) | `fb()` / `flexybayes()` | The grammar is detected from the call; `syntax =` forces it. |
| A pre-built greta model | `fb()` | Pass the `greta::model()` object (or its `fb_from_greta()` representation) straight in. |
| To force one engine | `fb_greta()` / `fb_inla()` / `fb_brms()` | Single-engine pins; a conflicting `backend` is refused. |
| Two fits you want to compare across engines | `triangulate()` | Auto-resolves canonical parameter names. |

`fb()` is the short alias for `flexybayes()`; either name is the
universal entry that spans every backend.

## Which backend will I get?

| Verb | `greta` | `inla` | `brms` (Stan) | `auto` |
|---|:-:|:-:|:-:|:-:|
| `fb()` / `flexybayes()` | ✓ | ✓ | ✓ | ✓ (greta or INLA via `lgm_gate()`) |
| `fb_greta()` | ✓ | – | – | – |
| `fb_inla()` | – | ✓ | – | – |
| `fb_brms()` | – | – | ✓ | – |

The universal entry reaches any backend: name one with `backend =`, or
let `backend = "auto"` choose. Each `fb_<engine>()` pin fits exactly one
engine and refuses a conflicting `backend`. `backend = "auto"` runs the
LGM feasibility gate and routes to INLA on acceptance, otherwise to
greta; it never routes to Stan, because brms's first-call Stan compile
(typically 30–60 s) is incompatible with the auto-fast-path promise.
Reach Stan explicitly with `fb_brms()` or `fb(..., backend = "brms")`.

## Installation

```r
# Install greta (default backend)
install.packages("greta")
greta::install_greta_deps()

# INLA (optional, second backend) — not on CRAN
install.packages("INLA",
  repos = c(getOption("repos"),
            INLA = "https://inla.r-inla-download.org/R/stable"))

# brms (optional, Stan passthrough)
install.packages("brms")

# flexyBayes -- install from the local checkpoint tarball
# (installation from the public repository will be available once
# the package is published there).
R CMD INSTALL release_tarballs/flexyBayes_0.5.0.tar.gz

# Once published, install directly from the repository:
# install.packages("remotes")
# remotes::install_github("AAGI-AUS/flexyBayes")
```

`flexyBayes` degrades gracefully when optional engines are missing:
greta-dependent code paths gate via `skip_if_no_greta()`; INLA paths
gate via `requireNamespace("INLA", quietly = TRUE)`; brms paths gate
the same way.

## Quick start

```r
library(flexyBayes)
data(sleepstudy, package = "lme4")

# Fit a mixed model with ASReml-style syntax
fit <- flexybayes(
  fixed  = Reaction ~ Days,
  random = ~ Subject,
  data   = sleepstudy,
  n_samples = 2000, warmup = 2000, chains = 2
)

# Standard R output
summary(fit)
coef(fit)
confint(fit)

# emmeans + marginaleffects
emmeans::emmeans(fit, ~ Days, at = list(Days = c(0, 5)))
marginaleffects::avg_slopes(fit)
```

## Cross-engine triangulation

Fit the same model on two backends and compare:

```r
fit_g <- flexybayes(Reaction ~ Days, random = ~ Subject,
                    data = sleepstudy, backend = "greta")
fit_i <- flexybayes(Reaction ~ Days, random = ~ Subject,
                    data = sleepstudy, backend = "inla")

triangulate(fit_g, fit_i)
#> Common parameters: 3
#> # A tibble: 3 × 6
#>   parameter   mean_diff sd_ratio tail_drift wasserstein_1 rhat_means
#>   <chr>           <dbl>    <dbl>      <dbl>         <dbl>      <dbl>
#> 1 (Intercept)    -0.04     0.997     0.012          0.04      1.002
#> 2 Days            0.001    1.001     0.003          0.001     1.000
#> 3 sigma           0.12     1.004     0.020          0.12      1.001
```

Add a third engine via brms / Stan:

```r
fit_s <- fb_brms(Reaction ~ Days + (1 | Subject),
                 data = sleepstudy, backend = "brms")

triangulate(fit_g, fit_s)
triangulate(fit_i, fit_s)
```

`canonical_names()` does the work of aligning backend-native parameter
names (greta's `sigma_g`, INLA's `Precision for g` on the precision
scale, brms's `sd_g__Intercept`) to a single canonical name with the
correct scale transform — no `name_map` argument needed in standard
cases.

## Companion accessors

| Accessor | Returns |
|---|---|
| `backend_decision(fit)` | The captured dispatch trace: backend, path, `lgm_gate` checks, reason. |
| `prior_summary(fit)` | The resolved prior — auto-default (bounded uniform on SD per Gelman 2006), user-supplied `fb_prior()`, or legacy scalar bridge. |
| `canonical_names(fit)` | The backend-native ↔ canonical-name table with per-row scale transforms. |
| `review_code = TRUE` on `flexybayes()` / `fb_brms()` | Inspect-before-fit workflow; `cat_code(rev)` prints the generated backend code; `proceed(rev)` advances into the fit. Supported on the formula-entry verbs only. `fb_greta()` raises a documented refusal: the user's model is already greta-side, so there is no flexyBayes-generated code string to inspect (model-graph pretty-printer reserved for a future release). |

## Output structure

Every fit carries three (or four) top-level slots:

```r
fit$glm         # GLM-compatible shim — works with summary(), emmeans,
                # marginaleffects, effectsize, broom

fit$greta       # native greta output (when backend = "greta")
fit$inla        # native INLA output (when backend = "inla")
fit$brms        # live brmsfit (when backend = "brms")

fit$extras      # BLUPs, variance components, convergence diagnostics,
                # generated code, parsed IR, run time, captured call
```

## Supported ASReml syntax (reference)

```r
# Fixed effects
yield ~ env                  # fixed factor
yield ~ env + x_cov          # factor + covariate
yield ~ 0 + env              # means model (no intercept)
yield ~ env + I(x^2)         # expression terms

# Random effects
random = ~ geno                       # simple iid
random = ~ block:rep                  # nested
random = ~ vm(geno, Gmat)             # GBLUP (dense V; both backends)
random = ~ vm(geno, chol = L)         # user-supplied Cholesky (greta only; v0.3.7+)
random = ~ vm(geno, precision = Q)    # user-supplied sparse precision (INLA preferred; v0.3.7+)
random = ~ ped(animal, Amat)          # pedigree (animal model)
random = ~ ped(animal, A_inv,
               use_sparse_precision = TRUE)  # sparse pedigree precision (v0.3.7+)
random = ~ at(env):geno               # diagonal GxE
random = ~ us(env):id(geno)           # unstructured GxE
random = ~ fa(env, 2):id(geno)        # factor-analytic GxE
random = ~ ar1(row):id(col)           # spatial AR1
random = ~ spl(x_cov)                 # P-spline

# Residual
rcov = ~ units                # iid residuals (default)
rcov = ~ at(env):units        # heterogeneous by environment

# Families
family = "gaussian" | "binomial" | "poisson" | "negative_binomial" |
         "gamma" | "beta"
```

## Vignettes

Fifteen numbered vignettes ship with the package:

1. Getting started
2. ASReml-shaped formulas
3. Foundational regression
4. Hierarchical models
5. Structured covariance
6. Priors and regularisation
7. METs and genomic selection
8. Downstream analysis
9. Spatio-temporal models
10. Cross-engine triangulation
11. LGM feasibility filter
12. Backend internals
13. LGM feasibility and memory
14. Choosing an engine: the universal entry and the engine pins
15. Architecture: the backend registry and how a new engine joins

Heavy MCMC vignettes use a `.Rmd.orig` precompile pattern; the `.Rmd`
that ships in the package tarball is the pre-evaluated static output.

## Design principles

- **Indexing, not model matrices**: parameters are sized by number of
  levels (`p`), not observations (`N`), giving O(p) memory for random
  effects.
- **Non-centred parameterisation**: all random effects use NCP for
  efficient MCMC sampling.
- **Cholesky decomposition**: known covariance matrices (G, A) are
  decomposed once.
- **Triangulation as first-class output**: the package is built
  around the claim that *evidence of cross-engine agreement* is the
  signature flexyBayes deliverable, not "one more Bayesian mixed-
  model frontend".

## Known limitations

flexyBayes refuses what it cannot yet fit rather than fitting it
silently. The current release does not cover the following; each is a
roadmap deferral, and a request that needs one is met with a
structured refusal naming the gap, not a quiet wrong answer.

- **Spatial structure**: only separable AR1 (`ar1(row):id(col)`) is
  supported. Intrinsic CAR and BYM2 areal models are not implemented.
  You can express a custom spatial precision by passing your own
  matrix to `vm(g, precision = Q)`, but there is no BYM2 helper.
- **Smooth terms**: univariate penalised splines (`s(x)`, `spl(x)`)
  are supported. Multivariate and tensor-product smooths (`te()`,
  `ti()`, `t2()`) are refused and deferred to a later release.
- **Hidden-Markov, multi-state, and survival models**: not supported.
  Survival / time-to-event families are refused at the family gate.
  A NIMBLE backend covering these is on the roadmap with no fixed
  release target.
- **Missing data**: flexyBayes does not impute. Greta and the brms
  (Stan) passthrough require complete cases for the model variables;
  INLA treats an `NA` response as a prediction target. Resolve
  missingness (drop or impute) before fitting, or use the prediction
  path deliberately.

## Requirements

- R ≥ 4.1.0
- greta ≥ 0.4.0 (Python + TensorFlow + TensorFlow Probability)
- INLA (optional, via Additional_repositories)
- brms (optional, for the Stan passthrough)

## Citation

If you use `flexyBayes` in your research, please cite:

```
@software{flexyBayes,
  title  = {flexyBayes: Flexible Bayesian Mixed Models with ASReml
            and brms-Style Syntax},
  author = {Moldovan, Max and Tanaka, Emi and Hui, Francis K.C. and
            Sznajder, Beata},
  year   = {2026},
  url    = {https://github.com/AAGI-AUS/flexyBayes}
}
```

## License

GPL (≥ 3)
