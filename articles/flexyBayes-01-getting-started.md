# Tutorial 01: Getting started with flexyBayes

## 1. Why Bayesian mixed models?

Restricted maximum likelihood (REML) — the workhorse behind `lme4`,
`nlme`, and ASReml — returns a single point estimate of each variance
component plus a Wald-style standard error. Two situations make this
summary uncomfortable.

- **Small group counts.** When the number of clusters is modest (fewer
  than roughly thirty), the sampling distribution of the
  variance-component estimator has a long right tail. The Wald interval
  is informative only near the centre, where the posterior is
  approximately quadratic.
- **Boundary problems.** A maximum-likelihood variance estimate can land
  on zero. That is *uninformative*: the data may not have ruled out a
  small-but-nonzero variance, but the boundary collapses both the
  estimate and the uncertainty.

A Bayesian fit replaces the point estimate with the *full posterior
distribution*. You see directly how much mass the data place near zero,
and you can propagate that uncertainty into derived quantities —
predictions, contrasts, best linear unbiased predictors (BLUPs) —
without leaning on quadratic approximations.

`flexyBayes` is built around one principle: switching from REML to
Bayesian inference should not change the formula you write. If you can
express the model in ASReml-style syntax,
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
fits it. If you prefer brms-style notation,
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
fits the same model. Both routes go through a shared internal
representation, and the same fitted object supports
[`summary()`](https://rdrr.io/r/base/summary.html),
[`predict()`](https://rdrr.io/r/stats/predict.html),
`emmeans::emmeans()`, `marginaleffects::predictions()`, and the
`bayesplot::*` family.

## 2. Installation

`flexyBayes` requires R 4.1.0 or later. Inference happens through one of
two engines.

- **greta** (default). A TensorFlow-backed Hamiltonian Monte Carlo (HMC)
  sampler. Covers every term type in the asreml-format domain- specific
  language (DSL).
- **INLA** — integrated nested Laplace approximation (Rue et al., 2009).
  A deterministic Laplace approximation over the latent Gaussian model
  (LGM) class. Substantially faster than HMC, but with a narrower scope.

Install both:

``` r

# greta and its TensorFlow backend
install.packages("greta")
greta::install_greta_deps()      # one-time Python/TF setup

# INLA — not on CRAN; from the INLA team's repository
install.packages(
  "INLA",
  repos = c(getOption("repos"),
            INLA = "https://inla.r-inla-download.org/R/stable")
)

# flexyBayes itself
install.packages("flexyBayes")
# or, while on GitHub:
# remotes::install_github("AAGI-AUS/flexyBayes")
```

A handful of companion packages enrich the post-fit experience and are
introduced in subsequent vignettes:

``` r

install.packages(c("emmeans", "marginaleffects", "bayesplot",
                   "posterior", "loo", "effectsize", "agridat"))
```

If INLA cannot be installed on your platform, the package degrades
gracefully. The greta backend remains available; INLA-only paths emit
clear messages and you simply do without
[`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md)
for now.

## 3. The four-verb API

`flexyBayes` exposes four user-facing entry points. Pick the verb that
matches how the model is expressed; the choice of entry never implicitly
changes the choice of backend.

| Verb | When to use |
|----|----|
| [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md) | Principal entry. Asreml-style formulas (`fixed = ..., random = ~ g, rcov = ~ ...`). Full term-type surface (`fa`, `us`, `at`, `ar1`, `vm`, `ped`, `spl`, `pol`). |
| [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md) | brms-style formulas (`response ~ x + (1 \| g)`). Fixed effects; single or crossed random intercepts; Gaussian, binomial, and Poisson likelihoods. |
| [`fb_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_greta.md) | A user-built `greta_model` — the expert / power-user entry for models already written in native greta primitives. |
| [`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md) | Cross-engine posterior comparison. Takes two fits from different backends and reports per-parameter agreement metrics. |

[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
and
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
share a `backend` argument with three settings: `"greta"` (the default —
HMC), `"inla"` (explicit LGM fast path; refuses non-LGM models with a
structured message), and `"auto"` (gate-driven routing: INLA on accept,
greta on refuse, with a silenceable note carrying the reason). The
dispatch trace is available post-fit via
[`backend_decision()`](https://aagi-aus.github.io/flexyBayes/reference/backend_decision.md).
The *backend internals* vignette walks through the dispatch flow
end-to-end.

## 4. Your first model

We use `lme4::sleepstudy` (Belenky et al., 2003): reaction times for
eighteen subjects across ten days of restricted sleep. The natural mixed
model has a fixed linear time trend and a random subject intercept.

``` r

library(flexyBayes)
data(sleepstudy, package = "lme4")
str(sleepstudy)
#> 'data.frame':    180 obs. of  3 variables:
#>  $ Reaction: num  250 259 251 321 357 ...
#>  $ Days    : num  0 1 2 3 4 5 6 7 8 9 ...
#>  $ Subject : Factor w/ 18 levels "308","309","310",..: 1 1 1 1 1 1 1 1 1 1 ...
```

We start with the brms-style entry,
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md).
The formula reads exactly as in `lme4::lmer()` or `brms::brm()`:
`Reaction ~ Days + (1 | Subject)`.

``` r

fit_greta <- fb_brms(
  Reaction ~ Days + (1 | Subject),
  data         = sleepstudy,
  backend      = "greta",
  n_samples    = 500,
  warmup       = 500,
  chains       = 2,
  verbose      = FALSE,
  mcmc_verbose = FALSE
)
fit_greta
#> Bayesian mixed model  [flexyBayes]
#> ------------------------------------------------------- 
#>   Fixed  : Reaction ~ Days 
#>   Random : ~Subject 
#>   Family : gaussian ( identity link )
#>   MCMC   : 2 chain(s) x 500 samples (warmup = 500 ) -- 6.8 sec
#>   Params : 4 monitored; 2 fixed, 1 random terms
#>   Max Rhat: 2.817  [!] 
#>   Min ESS: 10 
#> ------------------------------------------------------- 
#>   $glm    -- GLM-compatible (summary, emmeans, etc.)
#>   $greta  -- native greta (draws, model, calculate)
#>   $extras -- diagnostics, BLUPs, variance components
```

#### A note on random *intercepts* versus random *slopes*

The same data also supports `Reaction ~ Days + (Days | Subject)` — a
per-subject slope on top of the intercept.
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
accepts random intercepts only (single or crossed); random slopes raise
a structured refusal naming the offending construct:

``` r

fb_brms(Reaction ~ Days + (Days | Subject), data = sleepstudy,
        backend = "greta")
#> Error: random slopes (Days | Subject) are not in the supported
#>   brms-style corpus. Express the random structure in asreml-style
#>   form via flexybayes(fixed = Reaction ~ Days,
#>                       random = ~ Subject + Subject:Days, ...).
```

The asreml-style entry
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
covers a wider term surface (factor-analytic, unstructured,
autoregressive, pedigree, smooths) and is documented in the
*asreml-shaped formulas* vignette; the *hierarchical models* vignette
covers the random-slope case via the asreml route. For the remainder of
this introduction we keep the random intercept.

## 5. What is inside a fit?

`fit_greta` is an object of class `flexybayes`. The default print method
is concise; [`summary()`](https://rdrr.io/r/base/summary.html) gives the
full posterior digest:

``` r

summary(fit_greta)
#> Bayesian mixed model summary  [flexyBayes]
#> ============================================================ 
#>   Fixed  : Reaction ~ Days 
#>   Random : ~Subject 
#>   Family : gaussian / identity 
#>   N = 180 , chains = 2 , samples = 500 
#> 
#> -- Fixed effects (posterior)  --------------------------------- 
#>             Estimate Post.SD     2.5%    97.5%
#> (Intercept) 253.4231 11.8276 227.6631 276.6649
#> Days         10.5691  0.8116   8.9657  12.1516
#> 
#> -- Variance components  -------------------------------------- 
#>       Component Estimate     SD    2.5%   97.5%
#> 1 sigma_Subject  43.3434 8.5259 27.6680 61.1253
#> 2   sigma_e_atg  31.3205 1.7396 28.2306 34.9309
#> 
#> -- Convergence  --------------------------------------------- 
#>   Rhat range: 1.001 - 2.817 
#>   ESS  range: 10 - 914 
#>   Run time  : 6.8 sec
```

The output is laid out in three blocks.

1.  **Fixed effects.** Posterior mean, posterior standard deviation
    (SD), and equal-tailed 95 % credible interval for each design-
    matrix column. Here `(Intercept)` is the baseline reaction time and
    `Days` is the per-day slope.
2.  **Variance components.** The Subject-level SD and the residual SD,
    both on the response scale.
3.  **Sampler diagnostics.** Effective sample size (ESS) and the
    rank-normalised $`\widehat{R}`$ (Vehtari et al., 2021). A
    trustworthy fit has ESS ≥ 400 and $`\widehat{R} \le 1.01`$ on every
    parameter.

A density plot of the posteriors is one line:

``` r

plot(fit_greta)
```

![plot of chunk
sleepstudy-plot](flexyBayes-01-getting-started-figs/sleepstudy-plot-1.png)

plot of chunk sleepstudy-plot

#### Variance-component priors

When you call
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
or
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
without specifying a prior, `flexyBayes` announces the default it uses
on every random-effect SD and the residual SD: a **bounded uniform on
the SD scale**, $`\sigma \sim \mathrm{Uniform}(0, U)`$, with a
family-aware upper bound (Gelman, 2006). The announcement names $`U`$,
the scale basis, and the override knobs, and fires once per session.
Passing `prior_vc_sd = m` opts back into the legacy
$`\sigma \sim \mathrm{Lognormal}(0, m)`$ default; passing a structured
`prior = fb_prior(...)` overrides both. The *priors and regularisation*
vignette articulates the choice in detail and shows how to set priors
deliberately.

Fixed-effect coefficients carry a separate weakly-informative default:
$`\beta \sim \mathcal{N}(0, 100)`$, applied uniformly to the intercept,
contrast levels, continuous slopes, factor-by-continuous interactions,
and [`I()`](https://rdrr.io/r/base/AsIs.html)-expression terms. The
scale (`sd = 100`) covers responses with central tendency up to several
hundred on the natural scale without crushing the posterior toward zero,
while still regularising at small per-coefficient sample sizes (Gelman
et al., 2008). Override via `prior_fixed_sd = ...` or, for individual
coefficients, via `b("name") ~ normal(...)` in
[`fb_prior()`](https://aagi-aus.github.io/flexyBayes/reference/fb_prior.md).

## 6. The same model on a second engine

`fit_greta` is a Markov chain Monte Carlo (MCMC) fit; INLA runs a
fundamentally different algorithm — a Laplace approximation over a small
set of hyperparameters — and finishes almost instantly:

``` r

fit_inla <- fb_brms(
  Reaction ~ Days + (1 | Subject),
  data    = sleepstudy,
  backend = "inla",
  verbose = FALSE
)
summary(fit_inla)
#> Bayesian fit summary  [flexybayes_inla / INLA backend]
#> ------------------------------------------------------------ 
#> Fixed effects:
#>                 mean     sd 0.025quant 0.5quant 0.975quant     mode kld
#> (Intercept) 251.4773 6.6118   238.5005 251.4770   264.4561 251.4770   0
#> Days         10.4512 1.2382     8.0206  10.4513    12.8814  10.4513   0
#> 
#> Hyperparameters:
#>                                                 mean         sd   0.025quant
#> Precision for the Gaussian observations 4.000000e-04          0 4.000000e-04
#> Precision for Subject                   1.658427e+10 2257931055 1.345796e+10
#>                                            0.5quant   0.975quant         mode
#> Precision for the Gaussian observations 4.00000e-04 5.000000e-04 4.000000e-04
#> Precision for Subject                   1.61847e+10 2.211318e+10 1.486987e+10
#> 
#> Random effects:
#>   groups: Subject
#> ------------------------------------------------------------
```

Both engines have approximated the same posterior. *How well do they
agree?* That is the question
[`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md)
answers. The canonical parameter-name registry reconciles greta’s
internal names (`mu_atg`, `beta_Days`, `sigma_Subject`, `sigma_e_atg`)
and INLA’s internal names (`(Intercept)`, `Days`,
`Precision for Subject`, `Precision for the Gaussian observations`)
automatically — no `name_map` is needed for the common cases.

``` r

# INLA's posterior sampler can be flaky under restricted-process
# environments (e.g., CRAN's vignette re-render). Wrap so a failure
# is informative rather than fatal.
tri <- tryCatch(
  triangulate(fit_greta, fit_inla),
  error = function(e) {
    message("triangulate() unavailable in this session: ",
            conditionMessage(e))
    NULL
  }
)
if (!is.null(tri)) tri
#> <triangulate_result>
#>   source_a: greta
#>   source_b: inla
#>   n_common: 4
#>   only_a:   0 parameters
#>   only_b:   198 parameters (Predictor:1, Predictor:2, Predictor:3, Predictor:4, Predictor:5, ...)
#> 
#> Metrics (per common parameter):
#>         param   mean_a       mean_b     mean_diff    sd_a        sd_b
#> 1 (Intercept) 253.4231 2.512323e+02  2.190900e+00 11.8276 6.51940e+00
#> 2        Days  10.5691 1.053870e+01  3.030000e-02  0.8116 1.21360e+00
#> 3  sd_Subject  43.3434 1.734126e+10 -1.734126e+10  8.5259 5.99785e+09
#> 4       sigma  31.3205 4.000000e-04  3.132010e+01  1.7396 0.00000e+00
#>     sd_ratio     q025_diff     q975_diff wasserstein_1 rhat_means
#> 1     1.8142 -1.075040e+01  1.299940e+01   4.51720e+00     1.0131
#> 2     0.6688  7.471000e-01 -8.129000e-01   3.13100e-01     1.0002
#> 3     0.0000 -1.202472e+10 -2.843011e+10   1.73427e+10     3.0593
#> 4 37772.2922  2.823030e+01  3.493040e+01   3.13142e+01    18.0317
```

The output is a per-parameter readout. The two columns to focus on first
are `wasserstein_1` — a scale-respecting distance between the two
posterior marginals — and `rhat_means`, a rank-normalised
$`\widehat{R}`$ applied across the two engines’ posterior means. Values
near unity indicate agreement.

For a well-behaved Gaussian random-intercept model the two engines
should agree to at least the second decimal on the fixed effects and
within a few percent on the variance components. Disagreement of more
than 0.1 SD on any parameter is a *finding*, not a bug — the
*cross-engine triangulation* vignette walks through the eight common
patterns and the protocol for diagnosing each.

#### Letting the package choose the backend

`backend = "auto"` runs the model through `lgm_gate()` and routes to
INLA on accept, greta on refuse:

``` r

fit_auto <- fb_brms(
  Reaction ~ Days + (1 | Subject),
  data         = sleepstudy,
  backend      = "auto",
  n_samples    = 200,
  warmup       = 200,
  chains       = 1,
  verbose      = FALSE,
  mcmc_verbose = FALSE
)
backend_decision(fit_auto)
#> $backend
#> [1] "inla"
#> 
#> $path
#> [1] "auto_accept"
#> 
#> $gate_checks
#> [1] "lgm_compatible"      "gretaR_slot_dormant"
#> 
#> $reason
#> [1] "lgm_gate() accepted; INLA dispatch."
```

[`backend_decision()`](https://aagi-aus.github.io/flexyBayes/reference/backend_decision.md)
returns the dispatch trace: which backend ran, which gate checks were
evaluated, and the reason. On a Gaussian random-intercept model the gate
accepts and (when INLA is installed) the auto path lands on INLA;
otherwise it falls back to greta with a silenceable note.

## 7. Where to next?

The remaining vignettes are organised by topic, not by engine. A
suggested reading order:

| Vignette | What it covers |
|----|----|
| Foundational regression | one- and two-way fixed effects; smooths via [`mgcv::s()`](https://rdrr.io/pkg/mgcv/man/s.html); comparison with [`lm()`](https://rdrr.io/r/stats/lm.html) |
| Hierarchical models | random intercepts, nested and crossed effects, Poisson and binomial generalised linear mixed models (GLMMs); backend dispatch in practice |
| asreml-shaped formulas | the full term-type catalogue: `factor`, `fa`, `us`, `at`, `ar1`, `vm`, `ped`, … |
| Priors and regularisation | the [`fb_prior()`](https://aagi-aus.github.io/flexyBayes/reference/fb_prior.md) DSL, the uniform-on-SD default, the fixed-effect default, prior-predictive checks |
| Cross-engine triangulation | the signature feature: when engines disagree, what it means, what to do |
| LGM feasibility | what `lgm_gate()` accepts, what it refuses, and how to override |
| Downstream analysis | `emmeans`, `marginaleffects`, `bayesplot`, `loo` |
| Backend internals | the IR, `emit_greta`, `emit_inla`, capability gating, the gretaR slot |
| Structured covariance | `us`, `fa`, `at`, design variance components |
| Spatio-temporal | AR1, geostatistical, temporal correlation |
| Multi-environment trials and genomics | MET, genotype-by-environment interaction (GxE), GBLUP (genomic BLUP) |

## 8. Pitfalls

**Never `R CMD INSTALL` while `flexyBayes` is loaded.** R’s lazy-load
database can be corrupted when a package is overwritten under a live
session. Restart R first.

**Convergence is not correctness.** A passing $`\widehat{R}`$ tells you
that the chains explored the same posterior; it does not tell you
whether that posterior is the right one for the problem. Posterior-
predictive checks (Gelman, Meng, & Stern, 1996) and the cross-engine
triangulation vignette address that distinction.

**The uniform default is not always what you want.** The default scales
the prior to the observed response. If you have strong external
information about a variance component (for example a known
measurement-error magnitude), set it explicitly via
[`fb_prior()`](https://aagi-aus.github.io/flexyBayes/reference/fb_prior.md).
If you are reproducing a published analysis that used a different prior,
use that prior.

**INLA’s scope is narrower than greta’s.** Random slopes, structured
covariance models, finite mixtures, and a few non-Gaussian families fall
outside the LGM class. `flexyBayes` detects these structurally via
`lgm_gate()` and either routes to greta or refuses with a structured
message that names the rule violated.

## 9. Active prompts

Try the following while the package is loaded:

1.  Re-fit `fit_greta` with `chains = 4` and `n_samples = 1000`. How do
    the ESS and $`\widehat{R}`$ values change? Does the posterior mean
    of `Days` shift?
2.  Inspect `fit_greta$extras$code`: this is the literal greta program
    that `flexyBayes` generated. Compare it with the program generated
    by the asreml-style call
    `flexybayes(fixed = Reaction ~ Days, random = ~ Subject, data = sleepstudy, ...)`.
3.  Pass `prior_vc_sd = 1` to
    [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
    and refit. The default-prior announcement disappears (you have opted
    into the legacy lognormal). Does the posterior on `sigma_Subject`
    change appreciably?

## 10. Session information

``` r

sessionInfo()
#> R version 4.5.2 (2025-10-31)
#> Platform: aarch64-apple-darwin20
#> Running under: macOS Tahoe 26.4.1
#> 
#> Matrix products: default
#> BLAS:   /System/Library/Frameworks/Accelerate.framework/Versions/A/Frameworks/vecLib.framework/Versions/A/libBLAS.dylib 
#> LAPACK: /Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/lib/libRlapack.dylib;  LAPACK version 3.12.1
#> 
#> locale:
#> [1] C.UTF-8/C.UTF-8/C.UTF-8/C/C.UTF-8/C.UTF-8
#> 
#> time zone: Australia/Adelaide
#> tzcode source: internal
#> 
#> attached base packages:
#> [1] stats     graphics  grDevices utils     datasets  methods   base     
#> 
#> other attached packages:
#> [1] flexyBayes_0.2.0.9000
#> 
#> loaded via a namespace (and not attached):
#>  [1] tidyselect_1.2.1     dplyr_1.2.1          farver_2.1.2        
#>  [4] tensorflow_2.20.0    S7_0.2.2             INLA_25.10.19       
#>  [7] TH.data_1.1-5        tensorA_0.36.2.1     digest_0.6.39       
#> [10] estimability_1.5.1   lifecycle_1.0.5      sf_1.1-0            
#> [13] survival_3.8-3       processx_3.9.0       magrittr_2.0.5      
#> [16] posterior_1.7.0      compiler_4.5.2       rlang_1.2.0         
#> [19] progress_1.2.3       tools_4.5.2          sn_2.1.3            
#> [22] knitr_1.51           prettyunits_1.2.0    labeling_0.4.3      
#> [25] mnormt_2.1.2         classInt_0.4-11      reticulate_1.45.0   
#> [28] plyr_1.8.9           RColorBrewer_1.1-3   multcomp_1.4-29     
#> [31] abind_1.4-8          KernSmooth_2.23-26   numDeriv_2016.8-1.1 
#> [34] withr_3.0.2          stats4_4.5.2         grid_4.5.2          
#> [37] xtable_1.8-8         e1071_1.7-17         future_1.70.0       
#> [40] ggplot2_4.0.3        globals_0.19.1       emmeans_2.0.2       
#> [43] scales_1.4.0         MASS_7.3-65          dichromat_2.0-0.1   
#> [46] cli_3.6.6            mvtnorm_1.3-6        crayon_1.5.3        
#> [49] generics_0.1.4       otel_0.2.0           reshape2_1.4.5      
#> [52] tfruns_1.5.4         DBI_1.3.0            proxy_0.4-29        
#> [55] stringr_1.6.0        splines_4.5.2        bayesplot_1.15.0    
#> [58] parallel_4.5.2       base64enc_0.1-6      vctrs_0.7.3         
#> [61] Matrix_1.7-4         sandwich_3.1-1       jsonlite_2.0.0      
#> [64] greta_0.5.1          callr_3.7.6          hms_1.1.4           
#> [67] listenv_0.10.1       units_1.0-1          glue_1.8.1          
#> [70] parallelly_1.47.0    codetools_0.2-20     distributional_0.7.0
#> [73] stringi_1.8.7        gtable_0.3.6         tibble_3.3.1        
#> [76] pillar_1.11.1        R6_2.6.1             fmesher_0.7.0       
#> [79] evaluate_1.0.5       lattice_0.22-7       png_0.1-9           
#> [82] backports_1.5.1      tfautograph_0.3.2    MatrixModels_0.5-4  
#> [85] class_7.3-23         Rcpp_1.1.1-1.1       coda_0.19-4.1       
#> [88] checkmate_2.3.4      whisker_0.4.1        xfun_0.57           
#> [91] zoo_1.8-15           pkgconfig_2.0.3
```

## References

Belenky, G., Wesensten, N. J., Thorne, D. R., Thomas, M. L., Sing, H.
C., Redmond, D. P., Russo, M. B., & Balkin, T. J. (2003). Patterns of
performance degradation and restoration during sleep restriction and
subsequent recovery: A sleep dose-response study. *Journal of Sleep
Research*, 12(1), 1–12.

Bates, D., Mächler, M., Bolker, B., & Walker, S. (2015). Fitting linear
mixed-effects models using lme4. *Journal of Statistical Software*,
67(1), 1–48.

Gelman, A. (2006). Prior distributions for variance parameters in
hierarchical models. *Bayesian Analysis*, 1(3), 515–534.

Gelman, A., Jakulin, A., Pittau, M. G., & Su, Y.-S. (2008). A weakly
informative default prior distribution for logistic and other regression
models. *Annals of Applied Statistics*, 2(4), 1360–1383.

Gelman, A., Meng, X.-L., & Stern, H. (1996). Posterior predictive
assessment of model fitness via realized discrepancies. *Statistica
Sinica*, 6(4), 733–760.

Rue, H., Martino, S., & Chopin, N. (2009). Approximate Bayesian
inference for latent Gaussian models by using integrated nested Laplace
approximations. *Journal of the Royal Statistical Society: Series B*,
71(2), 319–392.

Vehtari, A., Gelman, A., Simpson, D., Carpenter, B., & Bürkner, P.-C.
(2021). Rank-normalization, folding, and localization: An improved
$`\widehat{R}`$ for assessing convergence of MCMC. *Bayesian Analysis*,
16(2), 667–718.
