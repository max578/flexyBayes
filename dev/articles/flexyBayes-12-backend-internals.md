# Tutorial 12: Backend internals: greta, INLA, and the intermediate representation

## 1. Why look under the hood?

Every
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md),
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_brms.md),
or
[`fb_greta()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_greta.md)
call produces a fitted object plus, in its `$extras` slot, the literal
program the package generated for the chosen backend (where applicable).
Reading that program is the fastest way to understand:

- which random-effect parameterisation the package chose;
- how the prior translates between greta and INLA;
- where the cross-engine equivalence lives;
- how to extend the package with a new backend.

This vignette is a reference for power users, contributors, and anyone
debugging an unexpected backend choice or refusal.

## 2. The dispatch flow at a glance

    user call
      → fb_from_brms()  or  fb_from_asreml()
           (both produce a single internal class: fb_terms)
      → lgm_gate(fb_terms)
           │
           ├ pass    → emit_greta()  or  emit_inla()
           └ refuse  → lgm_refusal (printed to user; user re-routes)
      → fitted-model object (class flexybayes or flexybayes_inla)

The `fb_terms` class is the *intermediate representation* (IR) of the
package. Everything downstream — `lgm_gate`, the emit shims, the
posterior unification — operates on `fb_terms`, not on the user’s
formulas. This separation is what allows two ingest paths (asreml-format
and brms-format) to share a single dispatch infrastructure.

## 3. The `fb_terms` IR

The IR is an S3-classed list with twelve fields; for the purpose of
debugging, four are essential.

``` r

library(flexyBayes)
data(sleepstudy, package = "lme4")
fb_t <- flexyBayes:::fb_from_brms(
  Reaction ~ Days + (1 | Subject),
  data = sleepstudy
)
class(fb_t)
#> [1] "fb_terms" "list"
names(fb_t)
#>  [1] "response"       "family"         "link"           "intercept"     
#>  [5] "fixed_terms"    "random_terms"   "rcov_terms"     "addition_terms"
#>  [9] "priors"         "data_summary"   "capabilities"   "source"        
#> [13] "greta_meta"
```

The `print` method gives a one-page digest:

``` r

fb_t
#> <fb_terms> flexyBayes intermediate representation
#>   source:    brms
#>   response:  Reaction
#>   family:    gaussian (identity link)
#>   intercept: TRUE
#>   terms:
#>     fixed:    1
#>     random:   1
#>     rcov:     0
#>     addition: 0
#>   priors:    <user-supplied>
#>   capabilities: <not yet evaluated by lgm_gate>
```

The four fields you read most often:

- `$response` — the response variable name (string).
- `$family` — the response family (string or `family` object).
- `$fixed_terms`, `$random_terms`, `$rcov_terms` — lists of term
  descriptors. Each descriptor names its `type` (e.g., `"factor"`,
  `"continuous"`, `"simple"`, `"fa_gxe"`), the variables it touches, and
  any term-specific parameters.
- `$capabilities` — a character vector populated by `lgm_gate()` during
  dispatch. The presence of `"lgm_compatible"` means the model passed
  all six structural checks.

## 4. The two ingest paths

[`fb_from_asreml()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_from_asreml.md)
walks the fixed/random/rcov formulas of an asreml-format call:

``` r

data(met_example, package = "flexyBayes")
fb_a <- flexyBayes:::fb_from_asreml(
  fixed = yield ~ env,
  random = ~ fa(env, 2):geno,
  rcov = NULL,
  data = met_example$dat
)
fb_a$random_terms[[1]]$type
#> [1] "fa_gxe"
fb_a$random_terms[[1]]$k         # number of factor-analytic loadings
#> [1] 2
```

[`fb_from_brms()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_from_brms.md)
walks a single brms-style formula via `brms::brmsterms()` when `brms` is
loaded; otherwise it parses a v0.1 minimum subset directly:

``` r

fb_b <- flexyBayes:::fb_from_brms(
  Reaction ~ Days + (1 | Subject),
  data = sleepstudy
)
fb_b$source                       # "brms"
#> [1] "brms"
fb_b$random_terms[[1]]$type       # "simple"
#> [1] "simple"
```

The `$source` field carries `"asreml"` or `"brms"` and surfaces in
[`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)
reports so cross-engine comparisons disclose the ingest path of each
fit.

## 5. The emit shims

`emit_greta()` and `emit_inla()` are the package’s two backend shims.
Both consume an `fb_terms` IR and return a fitted-model object.

`emit_greta()` calls into the existing
`parse_formula → codegen → build_glm` pipeline (the legacy flexyBayes
engine, retained verbatim for compatibility). Its job is to *unwrap* the
IR back into the shape the legacy code expects, run the fit, and wrap
the result.

`emit_inla()` is new in v0.1: it builds an INLA formula with
`f(group, model = "iid", hyper = ...)` for each random effect, plumbs
`priors_to_inla()` into the hyperparameter slot, calls
[`INLA::inla()`](https://rdrr.io/pkg/INLA/man/inla.html), and then runs
*check 7* — the post-fit numerical- confirm gate.

The literal greta program is available after a fit:

``` r

fit <- fb_brms(
  Reaction ~ Days + (1 | Subject), data = sleepstudy,
  backend      = "greta",
  n_samples    = 200, warmup = 200, chains = 1,
  verbose      = FALSE,
  mcmc_verbose = FALSE
)
cat(fit$extras$code, sep = "\n")
#> # -- Fixed effects -------------------------------------------
#> mu_atg <- normal(0, 100)
#> beta_Days <- normal(0, 100)
#> # -- Random effects ------------------------------------------
#> sigma_Subject <- greta::uniform(0, 281.6438)
#> Subject_raw <- normal(0, 1, dim = n_Subject)
#> u_Subject <- Subject_raw * sigma_Subject
#> # -- Residual ------------------------------------------------
#> sigma_e_atg <- greta::uniform(0, 281.6438)
#> # -- Linear predictor ----------------------------------------
#> mu_i_atg <- mu_atg + beta_Days * as_data(Days) + u_Subject[Subject_id]
#> # -- Likelihood ----------------------------------------------
#> y_atg_obs <- as_data(y_atg)
#> distribution(y_atg_obs) <- normal(mu_i_atg, sigma_e_atg)
#> # -- Model and MCMC -----------------------------------------
#> atg_model <- greta::model(mu_atg, beta_Days, sigma_Subject, sigma_e_atg)
#> atg_draws <- greta::mcmc(atg_model, n_samples = 200, warmup = 200, chains = 1, verbose = FALSE)
```

The output is a literal greta program:
[`greta::normal()`](https://rdrr.io/pkg/greta/man/distributions.html),
[`greta::uniform()`](https://rdrr.io/pkg/greta/man/distributions.html),
the model definition, and the `greta::mcmc()` call. Reading it once
removes much of the magic.

For INLA, the formula passed to
[`INLA::inla()`](https://rdrr.io/pkg/INLA/man/inla.html) is in
`fit_inla$inla$.args$formula`:

``` r

fit_inla <- fb_brms(
  Reaction ~ Days + (1 | Subject), data = sleepstudy,
  backend = "inla",
  verbose = FALSE
)
fit_inla$inla$.args$formula
#> Reaction ~ 1 + Days + f(Subject, model = "iid", hyper = list(prec = list(prior = "pc.prec", 
#>     param = c(281.643785626176, 0.01))))
#> NULL
```

## 6. `lgm_gate()` as the dispatch arbiter

`lgm_gate()` is the structural-first feasibility filter that decides
whether INLA can fit the IR. The *LGM feasibility* vignette catalogues
each check and the override path; this section examines the call from
the package side.

``` r

res <- flexyBayes:::lgm_gate(fb_b)
class(res)
#> [1] "fb_terms" "list"
res$capabilities
#> [1] "lgm_compatible"      "gretaR_slot_dormant"
```

The return value is one of three:

- the IR with `"lgm_compatible"` appended to `$capabilities` — proceed
  to `emit_inla()`;
- the IR with `"lgm_force_overridden"` appended — proceed to
  `emit_inla()` despite a refusal, on user authorisation;
- a structured `lgm_refusal` object — `print` and stop.

Inside `flexybayes(..., backend = "auto")` (and likewise
`fb_brms(..., backend = "auto")`), the dispatch logic is literally:

``` r

if (inherits(res, "fb_terms"))
  return(emit_inla(res, data = data, ...))      # gate accepted
if (inherits(res, "lgm_refusal"))
  return(emit_greta(res$fb, data = data, ...))  # gate refused
```

On the refusal branch, dispatch falls back to greta and emits a one-time
silenceable note carrying the primary failure rule
(`options(flexyBayes.silence_auto_fallback_note = TRUE)`). When INLA is
not installed, auto dispatch routes to greta with a separate silenceable
note (`options(flexyBayes.silence_auto_inla_missing_note = TRUE)`).

The full trace is available on every fit through \[backend_decision()\]:

``` r

fit_auto <- fb_brms(
  Reaction ~ Days + (1 | Subject), data = sleepstudy,
  backend      = "auto",
  n_samples    = 200, warmup = 200, chains = 1,
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

The returned list reports `backend` (which backend ran), `path`
(`"direct"`, `"auto_inla_accepted"`, `"auto_inla_refused"`, etc.),
`gate_checks` (the list of structural checks that ran), and `reason`
(free text).

## 7. The capabilities slot

`fb_terms$capabilities` is a character vector that flows through the
dispatch infrastructure as a structured trail of evidence. It carries:

- `"lgm_compatible"` (passed all six structural checks);
- soft warnings (`"lgm_warning:hyperparam_budget:soft"`);
- override audit (`"lgm_force_bypassed:family_allowlist"`,
  `"lgm_force_reason:..."`);
- ingest provenance (the `$source` field, separate but always read with
  the capabilities).

Every
[`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)
print scans for these markers and surfaces them prominently so
cross-engine comparisons disclose the dispatch context.

## 8. Direct-greta entry: `fb_greta()`

[`fb_greta()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_greta.md)
is the expert / power-user entry. Use it when the model is already
expressed in native greta primitives
([`as_data()`](https://rdrr.io/pkg/greta/man/as_data.html),
[`normal()`](https://rdrr.io/pkg/greta/man/distributions.html),
[`uniform()`](https://rdrr.io/pkg/greta/man/distributions.html),
`distribution()<-`,
[`model()`](https://rdrr.io/pkg/greta/man/model.html)) and you want the
flexyBayes post-fit surface —
[`summary()`](https://rdrr.io/r/base/summary.html),
[`coef()`](https://rdrr.io/r/stats/coef.html),
[`vcov()`](https://rdrr.io/r/stats/vcov.html),
[`prior_summary()`](https://aagi-aus.github.io/flexyBayes/dev/reference/prior_summary.md),
[`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)
— without rewriting the model in asreml or brms-style formula grammar.

``` r

library(greta)
data(sleepstudy, package = "lme4")

y      <- as_data(sleepstudy$Reaction)
x_days <- as_data(sleepstudy$Days)

b0    <- normal(0, 100)
b1    <- normal(0, 100)
sigma <- uniform(0, 5 * sd(sleepstudy$Reaction))

mu <- b0 + b1 * x_days
distribution(y) <- normal(mu, sigma)

m <- model(b0, b1, sigma)

fit_dg <- fb_greta(
  m,
  data            = sleepstudy,
  canonical_names = c(b0 = "(Intercept)", b1 = "Days",
                      sigma = "sigma"),
  n_samples       = 200,
  warmup          = 200,
  chains          = 1,
  verbose         = FALSE,
  mcmc_verbose    = FALSE
)
coef(fit_dg)
#> (Intercept)        Days       sigma 
#>   244.75433    10.73406    47.60219
```

The `canonical_names` argument maps each greta target-array name to the
canonical brms-style name `flexyBayes` uses elsewhere (`(Intercept)`,
`Days`, `sigma`, `sd_<group>`, …). The mapping unlocks
[`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)
against any other `flexyBayes` fit of the same model without a
user-supplied `name_map`. When `canonical_names` is omitted the package
falls back to the verbatim greta names with a one-time structured note.

[`fb_greta()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_greta.md)
deliberately *never* re-priors the user’s model: the greta program is
the source of truth. Pass an
[`fb_prior()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_prior.md)
object only as a *declaration* (for downstream
[`prior_summary()`](https://aagi-aus.github.io/flexyBayes/dev/reference/prior_summary.md)
/
[`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)
reporting); a semantic mismatch between the declared prior and the model
graph raises a structural refusal.

Two flags are deferred on the
[`fb_greta()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_greta.md)
path: `return_code = TRUE` (the user’s model is already greta-side, so
there is no flexyBayes-generated code string to return) and
`review_code = TRUE` (the model-graph pretty-printer for the
deferred-execution token is queued for a subsequent release). The
formula-entry verbs
([`flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md)
/
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_brms.md))
continue to support both flags.

## 9. The gretaR slot

The package carries a slot for a *gretaR backend* alongside greta and
INLA. The slot is registered in the canonical-name registry, in
`lgm_gate()`, and in the shared dispatch helper, but it is not
advertised on any user-facing `backend` argument until activated.
Activation lands in a subsequent release when the gretaR package is
publicly available and has cleared the package’s audit gate.

``` r

gretaR_status()
#> $activated
#> [1] FALSE
#> 
#> $gretaR_installed
#> [1] TRUE
#> 
#> $audit_clean
#> [1] NA
#> 
#> $dormancy_reason
#> [1] "slot_provisioned_not_activated"
#> 
#> $activation_procedure
#> [1] "Install the gretaR package when it goes public on CRAN."        
#> [2] "Verify the local gretaR build against the audit checklist."     
#> [3] "Run options(flexyBayes.gretaR_activated = TRUE) in the session."
```

Until activation, every LGM-compatible IR carries the informational
capability flag `gretaR_slot_dormant`, and any code path that would have
dispatched to gretaR (reachable only from internal callers and tests
today) raises a structured `gretaR_dormant_refusal` error naming the
dormancy reason and the activation procedure. Activation is a
four-touch-point flip: widen the `match.arg` sets on the user-facing
entries, swap the canonical-name mapper stub for the production mapper,
replace the dispatch-helper branch body with the real emit step, and
update the lgm_gate capability flag value.

## 10. Adding a new emit backend

The package architecture is wrap-don’t-rewrite — the legacy greta
pipeline is preserved verbatim, and new backends sit alongside it.
Adding a third backend (Stan via brms passthrough; PyMC via reticulate;
…) follows a five-step recipe:

1.  **Implement an `emit_<backend>()` function** that takes an
    `fb_terms` IR plus the user-facing arguments and returns a
    fitted-model object.
2.  **Register the new backend** in the `match.arg(backend, …)` list on
    [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md)
    and
    [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_brms.md).
3.  **Decide the gating policy** — does the new backend require
    `lgm_compatible`? Add the check at the entry of `emit_<backend>`.
4.  **Implement an `fb_as_draws_simple` method** for the fitted-model
    class, returning a named list of draw vectors. This unlocks
    [`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)
    immediately.
5.  **Register a canonical-name mapper** via the internal
    `register_canonical_mapper()` helper so
    [`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)
    can reconcile parameter names against the existing greta and INLA
    mappers without user-supplied `name_map`.
6.  **Write tests + a vignette** demonstrating the new path. The
    *cross-engine triangulation* vignette pattern is the template.

Three further backends are scaffolded or planned: a Stan passthrough via
brms (`fb_brms(..., backend = "brms")` — the emitter is queued and the
canonical-name mapper is identity through brms), gretaR (slot
provisioned and dormant at the current release; see §9 above), and
NIMBLE (for hidden Markov, multistate, and partial-LGM models that INLA
refuses and that benefit from NIMBLE’s specialised samplers).

## 11. Posterior unification

The `posterior::draws_array` interface is the package’s single point of
contact with the wider Bayesian R ecosystem. Every fitted-model class
implements
[`fb_as_draws_simple()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_as_draws_simple.md),
which returns a named list of draw vectors keyed by parameter name.

``` r

draws_g <- flexyBayes::fb_as_draws_simple(fit)
names(draws_g)
#> [1] "mu_atg"        "beta_Days"     "sigma_Subject" "sigma_e_atg"
length(draws_g$mu_atg)            # number of draws
#> [1] 200
```

The naming is backend-specific (greta uses `mu_atg`, `beta_x`,
`sigma_g`, `sigma_e_atg`; INLA uses `(Intercept):1`, `Days:1`,
`Precision for Subject`, `Precision for the Gaussian observations`).
[`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)’s
`name_map` argument is what reconciles them across engines.

The escape hatch — for analyses outside the standard summaries — is to
call
[`fb_as_draws_simple()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_as_draws_simple.md)
directly and work with the draws.

## 12. Pitfalls

**`flexyBayes:::` is internal API.** The `:::` accessor reaches into the
package’s non-exported functions. They are stable across patch releases
but not across major releases. If you build on `flexyBayes:::` for
production code, pin your package version.

**The IR is not a long-term commitment.** The current release fixes the
twelve fields documented above. Subsequent releases may add fields (for
example `$dpars` for distributional regression). Read the package
`NEWS.md` between upgrades.

**Reading `$extras$code` does not survive a save/load round-trip on all
platforms.** The greta program references TensorFlow objects in the
original session. Re-fitting after a `saveRDS` / `readRDS` is generally
fine; running stored greta code directly is not.

**`emit_inla()` populates `$num_check`.** This is the post-fit
numerical-confirm gate (check 7 of `lgm_gate`). A failed numerical check
halts the call — your fit object is not silently corrupted.

## 13. Active prompts

1.  Print `fit$extras$code` for a Gaussian random-intercept model and a
    factor-analytic GxE model. What changes? What stays the same?
2.  Inspect `fb_terms$capabilities` for a passing fit and a
    force-overridden fit. Which markers distinguish them?
3.  Implement a stub `emit_brms()` that calls `brms::brm()` with the
    IR’s fixed and random formulas reconstructed. What state would it
    need to populate to support
    [`fb_as_draws_simple()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_as_draws_simple.md)?

## 14. Session information

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
#> [1] greta_0.5.1           bayesplot_1.15.0      emmeans_2.0.2        
#> [4] ggplot2_4.0.3         flexyBayes_0.2.0.9000
#> 
#> loaded via a namespace (and not attached):
#>   [1] Rdpack_2.6.6           DBI_1.3.0              mnormt_2.1.2          
#>   [4] tfautograph_0.3.2      sandwich_3.1-1         rlang_1.2.0           
#>   [7] magrittr_2.0.5         multcomp_1.4-29        otel_0.2.0            
#>  [10] ggridges_0.5.7         matrixStats_1.5.0      e1071_1.7-17          
#>  [13] compiler_4.5.2         mgcv_1.9-3             loo_2.9.0             
#>  [16] png_0.1-9              callr_3.7.6            vctrs_0.7.3           
#>  [19] reshape2_1.4.5         stringr_1.6.0          pkgconfig_2.0.3       
#>  [22] crayon_1.5.3           backports_1.5.1        labeling_0.4.3        
#>  [25] effectsize_1.0.2       nloptr_2.2.1           MatrixModels_0.5-4    
#>  [28] INLA_25.10.19          xfun_0.57              jsonlite_2.0.0        
#>  [31] progress_1.2.3         parallel_4.5.2         prettyunits_1.2.0     
#>  [34] tensorflow_2.20.0      R6_2.6.1               stringi_1.8.7         
#>  [37] RColorBrewer_1.1-3     reticulate_1.45.0      parallelly_1.47.0     
#>  [40] boot_1.3-32            numDeriv_2016.8-1.1    estimability_1.5.1    
#>  [43] Rcpp_1.1.1-1.1         knitr_1.51             zoo_1.8-15            
#>  [46] parameters_0.28.3      base64enc_0.1-6        Matrix_1.7-4          
#>  [49] splines_4.5.2          tidyselect_1.2.1       dichromat_2.0-0.1     
#>  [52] abind_1.4-8            agridat_1.26           codetools_0.2-20      
#>  [55] processx_3.9.0         listenv_0.10.1         lattice_0.22-7        
#>  [58] tibble_3.3.1           plyr_1.8.9             bayestestR_0.17.0     
#>  [61] withr_3.0.2            S7_0.2.2               posterior_1.7.0       
#>  [64] coda_0.19-4.1          evaluate_1.0.5         marginaleffects_0.32.0
#>  [67] future_1.70.0          survival_3.8-3         sf_1.1-0              
#>  [70] units_1.0-1            proxy_0.4-29           pillar_1.11.1         
#>  [73] tensorA_0.36.2.1       whisker_0.4.1          KernSmooth_2.23-26    
#>  [76] checkmate_2.3.4        stats4_4.5.2           insight_1.4.6         
#>  [79] reformulas_0.4.4       sn_2.1.3               distributional_0.7.0  
#>  [82] generics_0.1.4         hms_1.1.4              scales_1.4.0          
#>  [85] minqa_1.2.8            globals_0.19.1         xtable_1.8-8          
#>  [88] class_7.3-23           glue_1.8.1             tools_4.5.2           
#>  [91] data.table_1.18.2.1    lme4_2.0-1             mvtnorm_1.3-6         
#>  [94] grid_4.5.2             rbibutils_2.4.1        datawizard_1.3.0      
#>  [97] nlme_3.1-168           cli_3.6.6              tfruns_1.5.4          
#> [100] viridisLite_0.4.3      fmesher_0.7.0          dplyr_1.2.1           
#> [103] gtable_0.3.6           digest_0.6.39          classInt_0.4-11       
#> [106] TH.data_1.1-5          farver_2.1.2           lifecycle_1.0.5       
#> [109] MASS_7.3-65
```

## References

Bürkner, P.-C. (2017). brms: An R package for Bayesian multilevel models
using Stan. *Journal of Statistical Software*, 80(1), 1–28.

Golding, N. (2019). greta: simple and scalable statistical modelling in
R. *Journal of Open Source Software*, 4(40), 1601.

Rue, H., Martino, S., & Chopin, N. (2009). Approximate Bayesian
inference for latent Gaussian models by using integrated nested Laplace
approximations. *Journal of the Royal Statistical Society: Series B*,
71(2), 319–392.
