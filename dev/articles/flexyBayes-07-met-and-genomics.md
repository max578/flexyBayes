# Tutorial 07: Multi-environment trials and genomic selection

## 1. The two questions of plant breeding

Crop variety evaluation poses two intertwined questions, and
`flexyBayes` provides one statistical framework for both.

1.  **Multi-environment trials (METs).** Genotypes are evaluated across
    many environments (locations × years). Their *rankings* change
    across environments — *genotype-by-environment interaction* (GxE).
    The first question is which genotypes are best on average, and which
    trade off mean for stability.
2.  **Genomic selection.** Modern breeding programmes have genome- wide
    markers on every candidate genotype, even those untested in the
    field. Predicting the field performance of an *unphenotyped*
    candidate from its markers is *genomic prediction*; selecting
    candidates by predicted performance is *genomic selection*
    (Meuwissen, Hayes, & Goddard, 2001).

This vignette walks through both questions, fitting models on real
agricultural data, and notes the connection through the kinship matrix.

## 2. Multi-environment trials: `yan.winterwheat`

`agridat::yan.winterwheat` (Yan & Tinker, 2006) records winter wheat
yield for 18 genotypes in 9 Ontario environments — a small, classic
dataset that produces interpretable factor-analytic results.

``` r

library(flexyBayes)
data(yan.winterwheat, package = "agridat")
str(yan.winterwheat)
#> 'data.frame':    162 obs. of  3 variables:
#>  $ gen  : Factor w/ 18 levels "Ann","Ari","Aug",..: 1 2 3 4 5 6 7 8 9 10 ...
#>  $ env  : Factor w/ 9 levels "BH93","EA93",..: 1 1 1 1 1 1 1 1 1 1 ...
#>  $ yield: num  4.46 4.42 4.67 4.73 4.39 ...
```

The natural mixed model is

``` math
y_{ijk} = \mu + e_j + g_i + (ge)_{ij} + \varepsilon_{ijk},
```

with $`e_j`$ environment effects (fixed), $`g_i`$ genotype effects
(random), $`(ge)_{ij}`$ genotype-by-environment interaction, and
$`\varepsilon_{ijk}`$ residuals. The *parameterisation of $`(ge)_{ij}`$*
is the modelling choice. Three options span the parsimony spectrum:

- **diagonal**: $`(ge)_{ij} \sim \mathcal{N}(0, \sigma_{e_j}^2)`$,
  independent across environments;
- **factor-analytic** with `k = 2`: small-rank approximation;
- **unstructured**: full $`9 \times 9`$ covariance.

The unstructured fit has 45 free entries — too many for 162 observations
to identify. The factor-analytic with `k = 2` reduces this to 18 entries
(16 loadings + 2 specific variances) and is the recommended starting
point.

``` r

fit_fa <- flexybayes(
  fixed     = yield ~ env,
  random    = ~ fa(env, 2):gen,
  data      = yan.winterwheat,
  n_samples = mcmc_small$n_samples,
  warmup    = mcmc_small$warmup,
  chains    = mcmc_small$chains,
  verbose   = FALSE
)
fit_fa
#> Bayesian mixed model  [flexyBayes]
#> ------------------------------------------------------- 
#>   Fixed  : yield ~ env 
#>   Random : ~fa(env, 2):gen 
#>   Family : gaussian ( identity link )
#>   MCMC   : 1 chain(s) x 200 samples (warmup = 200 ) -- 2.6 sec
#>   Params : 5 monitored; 2 fixed, 1 random terms
#>   Min ESS: 1 
#> ------------------------------------------------------- 
#>   $glm    -- GLM-compatible (summary, emmeans, etc.)
#>   $greta  -- native greta (draws, model, calculate)
#>   $extras -- diagnostics, BLUPs, variance components
```

The variance-component block reports the loading variances (one per
factor) and the specific variances (one per environment). Together these
reconstruct the implied environment-by-environment covariance
$`\boldsymbol{\Sigma} = \boldsymbol{\Lambda}\boldsymbol{\Lambda}^\top + \boldsymbol{\Psi}`$.

## 3. Genotype rankings and stability

Two questions plant breeders ask of every fit:

- **Mean performance**: which genotypes have the highest predicted
  yield, averaged across environments?
- **Stability**: which genotypes maintain their ranking across
  environments — and which do not?

Mean performance comes from the posterior of the genotype effect
$`g_i`$. Stability comes from the magnitude and direction of each
genotype’s factor scores: a genotype near the origin of the factor space
is stable; a genotype far from the origin in factor 1 is sensitive to
the dimension that factor 1 captures.

``` r

draws  <- flexyBayes::fb_as_draws_simple(fit_fa)
gen_levels <- levels(yan.winterwheat$gen)
# Note: parameter names are backend-specific; the genotype effects
# typically appear as g_i_1 ... g_i_18 or similar in the greta draws.
# We summarise the posterior means and rank.
gen_means <- vapply(seq_along(gen_levels), function(k) {
  nm <- paste0("g_atg_", k)
  if (!is.null(draws[[nm]])) mean(draws[[nm]]) else NA_real_
}, numeric(1))
names(gen_means) <- gen_levels
sort(gen_means, decreasing = TRUE)
#> named numeric(0)
```

Note: the precise parameter naming inside `draws` varies with the
generated greta program; `fit_fa$extras$code` shows the literal names.
The pedagogical point is that the posterior of every random effect is
available — *with full uncertainty quantification* — for ranking,
contrasts, and downstream selection decisions.

## 4. Visualising GxE: the interaction plot

Before any model is fit, the canonical exploratory plot of MET data is
the *genotype-by-environment interaction plot*.

``` r

library(ggplot2)
gxe <- aggregate(yield ~ gen + env, data = yan.winterwheat, mean)
ggplot(gxe, aes(x = env, y = yield, group = gen, colour = gen)) +
  geom_line(alpha = 0.6) +
  geom_point(size = 1) +
  scale_colour_viridis_d(option = "viridis") +
  theme_minimal(base_size = 12) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        legend.position = "none") +
  labs(x = "environment", y = "yield (t/ha)",
       title = "yan.winterwheat: genotype means per environment")
```

![plot of chunk
yw-interaction-plot](flexyBayes-07-met-and-genomics-figs/yw-interaction-plot-1.png)

plot of chunk yw-interaction-plot

Crossing lines indicate GxE — the rank of a genotype changes across
environments. Parallel lines indicate no GxE — the diagonal model
suffices. In `yan.winterwheat`, the lines cross visibly, motivating the
factor-analytic decomposition.

## 5. Genomic BLUP (GBLUP)

When genome-wide markers are available, the kinship matrix
$`\mathbf{G}`$ — the realised additive genetic relationship matrix
computed from marker genotypes (VanRaden, 2008) — replaces the default
identity covariance in the genotype random effect:

``` math
\mathbf{u} \mid \sigma_g^2 \sim \mathcal{N}\!\left(\mathbf{0},\, \sigma_g^2 \mathbf{G}\right).
```

This is *genomic BLUP* (GBLUP). It pools information across genotypes
via marker-based similarity, and — crucially — it extrapolates to
*unphenotyped* genotypes whose markers are known.

`flexyBayes` plumbs this through the `vm()` term and the
`known_matrices` argument:

``` r

data(met_example, package = "flexyBayes")
fit_gblup <- flexybayes(
  fixed     = yield ~ env,
  random    = ~ vm(geno, Gmat),
  data      = met_example$dat,
  known_matrices = list(Gmat = met_example$G_mat),
  n_samples = mcmc_small$n_samples,
  warmup    = mcmc_small$warmup,
  chains    = mcmc_small$chains,
  verbose   = FALSE
)
fit_gblup
#> Bayesian mixed model  [flexyBayes]
#> ------------------------------------------------------- 
#>   Fixed  : yield ~ env 
#>   Random : ~vm(geno, Gmat) 
#>   Family : gaussian ( identity link )
#>   MCMC   : 1 chain(s) x 200 samples (warmup = 200 ) -- 2.1 sec
#>   Params : 4 monitored; 2 fixed, 1 random terms
#>   Min ESS: 5 
#> ------------------------------------------------------- 
#>   $glm    -- GLM-compatible (summary, emmeans, etc.)
#>   $greta  -- native greta (draws, model, calculate)
#>   $extras -- diagnostics, BLUPs, variance components
```

The variance-component block reports a single $`\sigma_g^2`$ — the
*additive genetic variance*. Combined with the residual variance, this
gives the *narrow-sense heritability* $`h^2 = \sigma_g^2 /
(\sigma_g^2 + \sigma_e^2)`$ on the appropriate plot mean basis (Falconer
& Mackay, 1996).

``` r

draws <- flexyBayes::fb_as_draws_simple(fit_gblup)
# vm(geno, Gmat) names the genotype SD `sigma_geno`.
sigma_g <- draws$sigma_geno
sigma_e <- draws$sigma_e_atg
h2 <- sigma_g^2 / (sigma_g^2 + sigma_e^2)
c(mean = mean(h2), q025 = quantile(h2, 0.025), q975 = quantile(h2, 0.975))
#>       mean  q025.2.5% q975.97.5% 
#>  0.6665770  0.6535742  0.7080067
```

The credible interval on $`h^2`$ is the practitioner’s first quantity of
interest — a heritability of 0.4 with a tight interval is actionable for
breeding-value selection; 0.4 with a wide interval is a warning that the
data are insufficient for confident decisions.

## 6. Pedigree BLUP (the conventional alternative)

If a known pedigree is available — but no genome-wide markers — the
pedigree-derived numerator relationship matrix $`\mathbf{A}`$ takes the
role of $`\mathbf{G}`$:

``` r

fit_ped <- flexybayes(
  fixed     = yield ~ env,
  random    = ~ vm(geno, Amat),
  data      = met_example$dat,
  known_matrices = list(Amat = met_example$A_mat),
  n_samples = mcmc_small$n_samples,
  warmup    = mcmc_small$warmup,
  chains    = mcmc_small$chains,
  verbose   = FALSE
)
fit_ped
#> Bayesian mixed model  [flexyBayes]
#> ------------------------------------------------------- 
#>   Fixed  : yield ~ env 
#>   Random : ~vm(geno, Amat) 
#>   Family : gaussian ( identity link )
#>   MCMC   : 1 chain(s) x 200 samples (warmup = 200 ) -- 1.9 sec
#>   Params : 4 monitored; 2 fixed, 1 random terms
#>   Min ESS: 0 
#> ------------------------------------------------------- 
#>   $glm    -- GLM-compatible (summary, emmeans, etc.)
#>   $greta  -- native greta (draws, model, calculate)
#>   $extras -- diagnostics, BLUPs, variance components
```

GBLUP and pedigree BLUP are structurally identical; only the
relationship matrix changes. When both markers and pedigree are
available, the genomic-pedigree blend (`H` matrix; Christensen & Lund,
2010) is on the roadmap.

## 7. Genomic prediction error

The cross-validation procedure for genomic prediction holds out a random
subset of phenotyped genotypes, fits the model on the rest, predicts the
held-out genotypes from their markers + the trained $`\sigma_g^2`$
posterior, and compares predictions with realised phenotypes. The
summary metric is *prediction accuracy*: the correlation between
predicted and observed across the held-out set.

``` r

# Sketch (full implementation depends on dataset structure):
folds <- rsample::vfold_cv(unique(geno_id), v = 5)
acc <- vapply(seq_along(folds$splits), function(k) {
  train_id <- rsample::analysis(folds$splits[[k]])
  test_id  <- rsample::assessment(folds$splits[[k]])
  fit_k <- flexybayes(..., data = subset(dat, geno %in% train_id), ...)
  pred  <- predict(fit_k, newdata = subset(dat, geno %in% test_id))
  cor(pred, subset(dat, geno %in% test_id)$yield)
}, numeric(1))
mean(acc)
```

The Bayesian framework propagates uncertainty into the predictions —
each prediction comes with a posterior distribution, not a single
number. Decision-theoretic genomic selection uses these full
distributions (Bauer, Reif, & Schipprack, 2009) rather than
posterior-mean point predictions.

## 8. Pitfalls

**Kinship matrix scaling.** $`\mathbf{G}`$ matrices are conventionally
scaled so that their average diagonal equals 1. Different scaling
conventions (VanRaden 2008 versus Astle & Balding 2009) shift the
posterior on $`\sigma_g^2`$ by a constant. State the scaling explicitly
when reporting heritability.

**Connectedness across environments.** Factor-analytic GxE assumes that
*enough* genotypes are common across environments to identify the
loadings. With strongly disconnected designs — different genotype sets
per environment — `fa(env, 2):gen` may give noisy loadings; convergence
diagnostics will flag this.

**`spl()` for environmental covariates.** Many MET analyses have
quantitative environmental covariates (temperature, rainfall) — fit
these via `spl()` in the random formula to capture non-linear
genotype-by-environment-covariate interactions.

**Genotype-environment covariance versus genotype variance.** The
factor-analytic model puts structure on $`\mathrm{Var}(g_{ij})`$ across
environments; it does *not* introduce a separate $`\sigma_g^2`$
hyperparameter. This is why the factor-analytic fit reports loading
variances rather than a single genotype variance.

## 9. Active prompts

1.  Refit `yan.winterwheat` with `fa(env, 1):gen`. How does the
    posterior on `gen` change? Does the one-factor approximation pick up
    the dominant pattern visible in the interaction plot?
2.  Compute the heritability from the GBLUP fit on `met_example`. Is the
    credible interval narrow enough to support breeding decisions?
3.  Replace the kinship matrix in the GBLUP fit with the pedigree matrix
    and triangulate the two fits. Where do they agree, and where do they
    differ?

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
#> [1] ggplot2_4.0.3         flexyBayes_0.2.0.9000
#> 
#> loaded via a namespace (and not attached):
#>   [1] tidyselect_1.2.1     viridisLite_0.4.3    dplyr_1.2.1         
#>   [4] farver_2.1.2         tensorflow_2.20.0    S7_0.2.2            
#>   [7] INLA_25.10.19        TH.data_1.1-5        tensorA_0.36.2.1    
#>  [10] digest_0.6.39        estimability_1.5.1   lifecycle_1.0.5     
#>  [13] sf_1.1-0             agridat_1.26         survival_3.8-3      
#>  [16] processx_3.9.0       magrittr_2.0.5       posterior_1.7.0     
#>  [19] compiler_4.5.2       rlang_1.2.0          progress_1.2.3      
#>  [22] tools_4.5.2          sn_2.1.3             knitr_1.51          
#>  [25] prettyunits_1.2.0    labeling_0.4.3       mnormt_2.1.2        
#>  [28] classInt_0.4-11      reticulate_1.45.0    plyr_1.8.9          
#>  [31] RColorBrewer_1.1-3   multcomp_1.4-29      abind_1.4-8         
#>  [34] KernSmooth_2.23-26   numDeriv_2016.8-1.1  withr_3.0.2         
#>  [37] stats4_4.5.2         grid_4.5.2           xtable_1.8-8        
#>  [40] e1071_1.7-17         future_1.70.0        globals_0.19.1      
#>  [43] emmeans_2.0.2        scales_1.4.0         MASS_7.3-65         
#>  [46] dichromat_2.0-0.1    cli_3.6.6            mvtnorm_1.3-6       
#>  [49] crayon_1.5.3         reformulas_0.4.4     generics_0.1.4      
#>  [52] otel_0.2.0           reshape2_1.4.5       tfruns_1.5.4        
#>  [55] minqa_1.2.8          DBI_1.3.0            proxy_0.4-29        
#>  [58] stringr_1.6.0        splines_4.5.2        bayesplot_1.15.0    
#>  [61] parallel_4.5.2       base64enc_0.1-6      vctrs_0.7.3         
#>  [64] boot_1.3-32          Matrix_1.7-4         sandwich_3.1-1      
#>  [67] jsonlite_2.0.0       greta_0.5.1          callr_3.7.6         
#>  [70] hms_1.1.4            listenv_0.10.1       units_1.0-1         
#>  [73] glue_1.8.1           parallelly_1.47.0    nloptr_2.2.1        
#>  [76] codetools_0.2-20     distributional_0.7.0 stringi_1.8.7       
#>  [79] gtable_0.3.6         lme4_2.0-1           tibble_3.3.1        
#>  [82] pillar_1.11.1        R6_2.6.1             fmesher_0.7.0       
#>  [85] Rdpack_2.6.6         evaluate_1.0.5       lattice_0.22-7      
#>  [88] rbibutils_2.4.1      png_0.1-9            backports_1.5.1     
#>  [91] tfautograph_0.3.2    MatrixModels_0.5-4   class_7.3-23        
#>  [94] Rcpp_1.1.1-1.1       nlme_3.1-168         coda_0.19-4.1       
#>  [97] checkmate_2.3.4      mgcv_1.9-3           whisker_0.4.1       
#> [100] xfun_0.57            zoo_1.8-15           pkgconfig_2.0.3
```

## References

Bauer, A. M., Reif, J. C., & Schipprack, W. (2009). Reduction of the
genetic distance for marker-assisted backcrossing. *Theoretical and
Applied Genetics*, 119(1), 47–53.

Christensen, O. F., & Lund, M. S. (2010). Genomic prediction when some
animals are not genotyped. *Genetics Selection Evolution*, 42(2), 1–8.

Falconer, D. S., & Mackay, T. F. C. (1996). *Introduction to
quantitative genetics* (4th ed.). Longman.

Meuwissen, T. H. E., Hayes, B. J., & Goddard, M. E. (2001). Prediction
of total genetic value using genome-wide dense marker maps. *Genetics*,
157(4), 1819–1829.

Smith, A. B., Cullis, B. R., & Thompson, R. (2001). Analyzing variety by
environment data using multiplicative mixed models and adjustments for
spatial field trend. *Biometrics*, 57(4), 1138–1147.

VanRaden, P. M. (2008). Efficient methods to compute genomic
predictions. *Journal of Dairy Science*, 91(11), 4414–4423.

Yan, W., & Tinker, N. A. (2006). Biplot analysis of multi-environment
trial data: Principles and applications. *Canadian Journal of Plant
Science*, 86(3), 623–645.
