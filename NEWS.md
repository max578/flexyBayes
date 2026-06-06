# flexyBayes (development version)

## Lean-core split

* The orchestra-composition layer has been extracted to the companion package
  **flexyBayesOrchestra** (`Imports: flexyBayes`): the surrogate emulators
  (`fit_surrogate()`, `fb_surrogate_ies()`, `fb_surrogate_ppc()`), ensemble
  sources (`fb_ensemble()`, `as_fb_ensemble()`, `read_fb_ensemble()`,
  `verify_fb_ensemble()`, `register_ensemble_source()`), the PESTO
  ensemble-derived priors (`fb_pesto()`, `fb_prior_from_ensemble()`), the
  surrogate conformers (`register_pesto_surrogates()`,
  `register_kernr_surrogates()`, `register_surrogate()`), and the dormant koine
  fourth-opinion slot (`koine_status()`). Install `flexyBayesOrchestra` for
  these; `flexyBayes` alone now ships the mixed-model and cross-engine
  triangulation core.
* Dropped `kernR`, `PESTO`, `S7`, and `gretaR` from `Suggests` and removed the
  `Remotes:` field, so the package installs cleanly from CRAN-style
  repositories with no GitHub- or r-universe-only dependencies. The `greta`
  (CRAN) and `INLA` backends remain; `INLA` is served by its own
  `Additional_repositories`. The `gretaR` R-native engine is still wired as a
  dormant, opt-in backend: install `gretaR` yourself and it is detected at run
  time, but it is no longer a declared dependency of the public core.

## Methodology

* **Identified factor-analytic loadings.** `fa(x, k)` now emits the loadings
  matrix `Lambda` with the standard lower-triangular, positive-diagonal
  identification (Lopes & West 2004): the strict upper triangle is zeroed and the
  diagonal is constrained positive. Previously `Lambda` was a free `normal(0, 1)`
  matrix, which is unidentified up to rotation, sign, and column permutation for
  `k > 1`, so its posterior summaries were not interpretable. Predictions and the
  g-side covariance are unchanged -- the product `F %*% t(Lambda)` is
  rotation-invariant -- so only the loadings interpretation is affected.
* **Factor-analytic rank upper bound.** `fa(x, k)` is now refused at fit time
  when `k` is not strictly below the number of levels of `x` (new refusal
  `fa_rank_exceeds_dim`). A factor-analytic covariance is identifiable only for
  `k < n_outer`: at `k = n_outer` the loadings and specific variances are an
  over-parameterised reparameterisation of the unstructured form, and at
  `k > n_outer` the lower-triangular loadings carry empty columns. The check is
  data-aware (the number of levels is known only once the term is matched against
  the data), complementing the existing data-free `k >= 1` floor
  (`fa_rank_invalid`). The refusal message points to `us(x)` for a full
  unstructured covariance.
* **Removed the `rhat_means` triangulation metric.** `triangulate()` no longer
  reports `rhat_means`. It pooled two *different* engines' posteriors as if they
  were chains of a single sampler, which conflates genuine between-engine
  approximation bias with within-sampler non-convergence -- so it was not a valid
  convergence diagnostic, and it was mislabelled "rank-normalised R-hat" although
  it applied no rank-normalisation. Cross-engine discrepancy is reported by the
  distributional metrics: `wasserstein_1`, `sd_ratio`, `mean_diff`, and the
  quantile differences. (The per-fit, within-engine rank-normalised R-hat used as
  a convergence diagnostic is unaffected.)
* **Honest default-prior provenance.** The default variance-component prior
  (bounded uniform on each SD; `U = 5 * sd(y)` for Gaussian) was attributed
  "following Gelman (2006)". Gelman (2006) in fact recommends a half-t /
  half-Cauchy for variance components with few groups and cautions against a flat
  prior there; the uniform-on-SD default is a weakly-informative choice for
  *moderate* group counts, and the `5 * sd(y)` bound is a flexyBayes heuristic.
  The attribution is corrected throughout (the one-time announcement message,
  `prior_summary()`, the docstrings, the README, and the regression + priors
  vignettes). The default behaviour is unchanged; `fb_prior(half_cauchy(...))`
  remains the documented choice for small `J` (see the priors vignette).

## Documentation

* **Vignettes migrated to the engine-pin API.** Eight vignettes still showed
  the pre-0.5.0 universal `fb_brms(..., backend = "greta" / "inla" / "auto")`
  call surface, which the 0.5.0 engine-pin refactor removed (`fb_brms()` now
  pins to Stan and rejects a conflicting `backend`). Every example is updated to
  the current surface: `fb_greta()` / `fb_inla()` for a fixed engine,
  `flexybayes()` / `fb()` for the universal entry that takes a `backend`
  argument. The brms-style *grammar* is unchanged and still accepted by every
  entry; only the engine selection moved. Stale prose is corrected accordingly
  (the `backend` default is `"auto"`, not `"greta"`; the Stan/brms emit backend
  is live, not "queued"; the native-greta canonical-name map is supplied via
  `fb_from_greta(model, canonical_names = ...)`). Vignettes were re-precompiled.

# flexyBayes 0.7.0

> **Note (current state).** The orchestra-composition features described in this
> section — the ensemble-source data contract, simulator-derived priors, the
> surrogate emulators and predictive checks, and the dormant fourth-opinion slot
> — were subsequently extracted to the companion package **flexyBayesOrchestra**
> (see the lean-core split under "(development version)" above). They are no
> longer part of the `flexyBayes` exported surface; the entries below record the
> 0.7.0 history.

This release reconciles three parallel development streams onto the engine, data,
and surrogate axes: gretaR activated as a fourth inference engine (the engine
axis), the ensemble-source data contract and its first consumers (the data
axis), and the surrogate carried end-to-end from a reference emulator to a
distribution-preserving predictive check (the surrogate axis).

## New features

- **gretaR activated as a fourth inference engine.** `flexybayes(..., backend =
  "gretaR")` fits supported hierarchical models through an out-of-process
  torch-NUTS worker, returning canonical parameter names and a `draws_array` that
  flows into `triangulate()` like any other engine. The integration is governed by
  a versioned backend contract with an **executable
  conformance battery** -- a new engine onboards by adding one descriptor, gated on
  `triangulate()`-agreement within an SBC-calibrated threshold. A **dormant koine
  backend slot** is provisioned (scaffolded and correct, switched on when koine's
  programmatic model builder is confirmed against the contract).
- **`fb_ensemble()` and the `ensemble_source` data contract.**
  A canonical ingest shape for calibrated parameter ensembles, with PESTO (via its
  manifest), raw `apsimx`, and file as conforming producers -- so flexyBayes is
  standalone-functional for methods work without depending on any one producer's
  internals. **`fb_pesto()`** turns a calibrated ensemble into an informative
  `fb_prior` for a downstream fit (moments method; joint and KDE methods refuse
  cleanly behind their gates).
- **`fitted()`, `residuals()`, and `logLik()` methods for INLA fits.** `fitted()`
  and `residuals()` now return values for a `flexybayes_inla` fit (previously
  `NULL`); `logLik()` returns an honest `NA` with the right shape where INLA does
  not expose a likelihood, rather than erroring.
- **`fb_surrogate_ppc(whiten = TRUE)` whitens the outputs before the MMD.** The
  predictive draws and `observed` are Mahalanobis-whitened by their pooled
  covariance -- a label-agnostic representation that puts the outputs on a common
  footing, removing the cross-output scale heterogeneity that makes a single
  median bandwidth too coarse to resolve a distortion in a low-variance direction.
  The map depends only on the pooled cloud (not the draws-vs-observed labels), so
  the permutation test stays valid, and the same map is applied to both clouds, so
  a relative scale, shape, or mean difference is preserved. It lifts power
  substantially on localised / heterogeneous-scale distortions a raw-output check
  misses (with no blind spot found across a mean / variance / shape battery), at a
  valid level. Opt-in (a graduated ridge guards a near-singular pooled
  covariance); composes with `project` and `aggregate`.
- **`fb_surrogate_ppc(aggregate = TRUE)` runs an aggregated multi-kernel MMD.**
  An MMDAgg test (Schrab et al. 2023) over an RBF bandwidth grid around the median
  heuristic, sharing the permutations across bandwidths and aggregating by the
  weighted-quantile statistic `min_g p_g / w_g` -- it removes the bandwidth choice
  and is robust when the median heuristic is mis-scaled, at a valid level. The
  kernel weights are set by `agg_weights` (`"uniform"` default, or `"increasing"`
  / `"decreasing"` / `"centred"`, or a numeric vector): up-weighting the scale a
  distortion is expected to live at recovers power, and `"uniform"` recovers the
  min p-value aggregation. It orchestrates kernR's single-kernel `mmd_test` over
  the grid (the MMD machinery stays kernR's) and composes with `project`. Returns
  an `fb_mmd_agg` object.
- **New vignette: distribution-preserving surrogates (emulate, invert, check).**
  A self-contained walkthrough of the surrogate workflow -- ingest an
  ensemble, fit a surrogate, read its predictive distribution, invert it with
  `fb_surrogate_ies()`, and check it with `fb_surrogate_ppc()` -- runnable on the
  built-in reference surrogate with no other package.
- **`fb_surrogate_ppc(project = TRUE)` runs a factor-space MMD for large output
  counts.** For a surrogate that stores a low-rank covariance (`cov_rank`), the
  predictive-check draws and `observed` are projected onto the surrogate's `q`
  factor directions before the MMD, so the test runs in `q` dimensions, not `k`
  -- cheaper and higher-powered on the correlated cross-output structure (the MMD
  loses power as the dimension grows). It is, by design, blind to distortions
  orthogonal to the factor space (idiosyncratic per-output errors, which the
  marginal and `joint = FALSE` checks cover), so it complements the full-space
  check.
- **`fit_surrogate(cov_method = "auto")` picks the low-rank factor method.**
  In addition to `"eigen"` (default) and `"fa"`, `"auto"` selects between them
  from the heteroscedasticity of the eigen-residual diagonal -- `"fa"` when the
  residual is uneven (where eigen-truncation is biased), `"eigen"` otherwise. The
  resolved method is recorded in the fitted object.
- **`fit_surrogate(ard_refit = "cv")` now uses k-fold cross-validation.** The
  held-out predictive-density objective is summed over a k-fold partition of the
  subsample rather than a single split -- a less noisy objective, so the
  Nelder-Mead lands on sharper lengthscales.
- **`fb_surrogate_ppc()` samples a low-rank covariance factored.** When the
  surrogate stores a low-rank covariance (`cov_rank`), the joint predictive-check
  draws are sampled from the factored form directly -- a `q`-dimensional factor
  noise plus a `k`-dimensional idiosyncratic noise -- so the `k x k` covariance
  slice is never formed (the native low-rank consumer for the PPC, `O(k q)` per
  draw). Draws from the same per-row covariance as the dense path.
- **`fb_surrogate_ies()` consumes a low-rank covariance natively (Woodbury).**
  When the surrogate stores a low-rank covariance (`cov_rank`), the ES-MDA Kalman
  update folds the factored form straight in via the Woodbury identity (a
  rank-sized solve) and samples the observation perturbation factored, so the
  `d x d` data covariance is never formed -- the inversion cost scales with the
  covariance rank, not the output count. Produces the same Kalman gain as the
  dense path (a dense-joint or marginal surrogate keeps the dense path).
- **`fit_surrogate(cov_method = "fa")` learns the low-rank factor by EM.**
  In addition to the default eigen-truncation (`"eigen"`), the rank-`cov_rank`
  factor can be fitted by factor-analysis EM, which recovers the loadings more
  faithfully when the residual diagonal is heteroscedastic (the eigenvectors of
  the full covariance are otherwise contaminated by the uneven diagonal). The
  covariance diagonal stays exact either way.
- **`fit_surrogate(ard_refit = "cv")` regularises the fuller evidence-ARD.**
  The `ard_refit = TRUE` profiling maximises the in-sample evidence and can
  over-shorten lengthscales; `"cv"` instead maximises the held-out predictive
  log-density on a train/validation split, keeping the relevance sharpening
  without the in-sample over-shortening.
- **`fb_surrogate_ppc()` gains a joint draw path.** With
  `joint = TRUE` (default) the predictive-check draws are sampled from the full
  cross-output predictive covariance (`predict(cov = TRUE)` + a per-row
  Cholesky), so the emulator's cross-output correlation is exercised -- the
  second consumer of the joint covariance after `fb_surrogate_ies()`. On a
  correlated-output simulator, marginal draws (`joint = FALSE`) discard that
  structure and false-reject a faithful surrogate, so the joint path is the
  correct distribution-preserving check. A single output, or a marginals-only
  surrogate, behaves exactly as before.
- **`fit_surrogate(method = "rff")` gains `cov_rank` for large output counts.**
  Stores the cross-output noise covariance in a rank-`q` factor-analysis form
  (`U U' + diag`), `O(k q)` instead of `O(k^2)`. The per-output marginal sd and
  the covariance diagonal are reproduced exactly; only the off-diagonal
  covariance is approximated. `predict(<fb_surrogate>, newdata,
  cov = "lowrank")` returns the compact factored predictive
  (`cov_lowrank = list(u, d, infl)`), and the new `fb_cov_slice()` reconstructs
  a `k x k` covariance slice from either the dense or the factored form.
- **`fit_surrogate(method = "rff")` gains `ard_refit` (fuller evidence-ARD).**
  When `TRUE`, the prior/noise precisions `(a, t)` are re-estimated by evidence
  at each candidate lengthscale (the evidence profiled over `(a, t)`), a fuller
  -- and at equal lengthscales never lower -- marginal likelihood. It sharpens
  relevance ranking but can over-shorten lengthscales (a higher evidence does
  not guarantee better held-out recovery for finite-feature models), so it is
  opt-in (`ard_refit = FALSE` default).
- **The reference `rff` surrogate gains ARD lengthscales and a joint
  multi-output fit, both on by default.** `fit_surrogate(method = "rff")`
  now learns per-input (automatic relevance determination) lengthscales by
  maximising the model evidence (`ard = TRUE`), so irrelevant parameters are
  stretched out of the kernel; and it fits a joint matrix-normal --
  inverse-Wishart model across outputs (`joint = TRUE`), preserving the
  cross-output predictive covariance rather than only the marginals. Both
  default behaviours can be turned off (`ard = FALSE`, `joint = FALSE`) to
  recover the isotropic, per-output fit. The per-output `<o>_sd` contract is
  unchanged.
- **`predict(<fb_surrogate>, newdata, cov = TRUE)` returns the joint
  predictive distribution**: an
  `fb_surrogate_prediction` with the predictive mean matrix and a per-row
  cross-output covariance array. A marginals-only surrogate (independent
  `rff`, or a conformer reporting only `<o>_sd`) returns a diagonal
  covariance, so the call is always honest.
- **`fb_surrogate_ies()` consumes the joint predictive covariance.** When the
  surrogate is joint, the full cross-output predictive covariance enters the
  ES-MDA data covariance (`use_surrogate_cov = TRUE`, default), so correlated
  emulator errors are assimilated coherently; a marginals-only surrogate
  falls back to the diagonal path, identical to before.
- **Sibling surrogate backends register as conformers.** PESTO's GP
  surrogate (`method = "gp"`) and kernR's conditional mean embedding
  (`method = "cme"`) are available to `fit_surrogate()` when the member
  package is installed, registered through the existing surrogate
  registry. PESTO's GP already reports a per-output predictive mean and
  variance; kernR's CME is a kernel linear smoother, so the adapter
  supplies the standard linear-smoother predictive variance
  `sigma^2 (1 + ||w||^2)` to honour the distribution-preserving `<o>_sd`
  requirement. Both register opportunistically on load, or explicitly via
  `register_pesto_surrogates()` / `register_kernr_surrogates()`. The
  surrogate methods are consumed through the contract, never copied into
  flexyBayes, and the built-in `rff` reference keeps the package
  standalone.
- **`fb_surrogate_ies()` calibrates a parameter ensemble through a
  surrogate.** An Ensemble Smoother with Multiple Data Assimilation
  (ES-MDA) drives a prior parameter ensemble toward observed data using
  the surrogate in place of the forward model; the predictive `<o>_sd` is
  folded into the data covariance, so emulator uncertainty inflates the
  assimilation noise.
- **`fb_surrogate_ppc()` checks whether a surrogate distorted the output
  distribution.** It draws from the surrogate's predictive distribution
  at held-out parameter sets and runs kernR's `mmd_ppc()` against the true
  simulator outputs there -- a distribution-level check, not a mean-only
  accuracy measure.

## Bug fixes

- **Registered surrogate conformers now predict on the standardised
  design.** `predict.fb_surrogate()` previously passed raw `newdata` to a
  registered conformer's `predict()` while training it on the standardised
  design, so train and predict disagreed on scale. The standardised design
  is now passed consistently.

---

Older release history (0.6.0 and earlier) lives in `NEWS_ARCHIVE.md`.
