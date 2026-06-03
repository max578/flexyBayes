# flexyBayes surrogate contract (C7, v1.2)

The interface a **simulator surrogate** (emulator) must honour to be a
first-class flexyBayes surrogate. A surrogate replaces an expensive forward
model with a fast map from parameter sets to outputs -- and, critically, reports
a predictive **distribution** (not a point), so the uncertainty a calibration /
inverse step depends on is preserved. This is contract **C7** in the flexyBayes
Constellation (`CONSTELLATION.md`); it is the methods-intense payoff downstream
of the C5 ensemble-source floor.

The design rule it encodes (same as C1 / C5): flexyBayes owns the **contract +
registry + a self-contained reference implementation**; the richer surrogates
live in their own packages and **register** here -- never reimplemented in
flexyBayes.

Status legend: [R] required, [O] optional.

## What a surrogate consumes

A surrogate is fit from a C5 `fb_ensemble` (`inst/ensemble_source_contract.md`):
the design `X = ensemble$params` (numeric parameter columns) and the responses
`Y = ensemble$outputs` (numeric output columns). Ingest is via
`as_fb_ensemble()`, so any conforming producer (PESTO, raw `apsimx`, file) feeds
a surrogate.

## The fit + predict contract

1. **Fit** [R] -- `fit_surrogate(ensemble, method, outputs, ...)` returns an
   `fb_surrogate` carrying `method`, the fitted model, `param_names`,
   `output_names`, the design standardisation, and `provenance`.
2. **Predict** [R] -- `predict(<fb_surrogate>, newdata)` returns a `data.frame`
   with, for each emulated output `<o>`, a `<o>_mean` AND a `<o>_sd` column, one
   row per row of `newdata`. **Reporting `<o>_sd` is the distribution-preserving
   requirement**: a surrogate that returns only a point estimate does not
   conform. `newdata` must contain the surrogate's `param_names`.
3. **Independence of outputs** [O] -- multiple outputs may be emulated jointly or
   independently. The reference `rff` surrogate is **joint by default**
   (`joint = TRUE`): it preserves the cross-output predictive covariance, not
   only the marginals; `joint = FALSE` fits one independent model per output.
4. **Joint predictive covariance** [O] -- `predict(<fb_surrogate>, newdata,
   cov = TRUE)` returns an `fb_surrogate_prediction` carrying the predictive
   `mean` matrix and a per-row cross-output covariance array `cov`
   (`k x k x nrow(newdata)`). A surrogate that models only marginals (an
   independent `rff`, or a conformer reporting only `<o>_sd`) returns a
   **diagonal** covariance built from the marginal sds, so the call is always
   honest. The diagonal of `cov` always equals `<o>_sd^2` from clause 2.
5. **Low-rank predictive covariance** [O] -- for a large output count, a joint
   `rff` surrogate fit with `cov_rank = q` stores the cross-output noise
   covariance in a rank-`q` factor-analysis form (`U U' + diag(d)`), and
   `predict(<fb_surrogate>, newdata, cov = "lowrank")` returns the compact
   `cov_lowrank = list(u, d, infl)` (per-row covariance `infl[i] * (u u' +
   diag(d))`), `O(k q + n)` storage instead of the dense `O(k^2 n)`. The
   factorisation reproduces the covariance diagonal -- hence `<o>_sd^2` (clause
   2) -- **exactly**, approximating only the off-diagonal covariance. The factor
   is fitted by an eigen-truncation (`cov_method = "eigen"`, default), by
   factor-analysis EM (`cov_method = "fa"`, more faithful when the residual
   diagonal is heteroscedastic), or `"auto"` (picks between them by the
   eigen-residual heteroscedasticity). [fb_cov_slice()] reconstructs a `k x k` slice
   from either form, so a consumer can work slice-by-slice without materialising
   the dense array; a consumer may also use `cov_lowrank` directly (the IES does,
   via Woodbury; the PPC samples it factored) so the `k x k` covariance is never
   formed. The factor is fitted by `cov_method`: `"eigen"`, `"fa"`, or `"auto"`
   (picks between them by the heteroscedasticity of the eigen-residual diagonal).

## The registry (how richer surrogates plug in)

`register_surrogate(method, fit_fn)` adds a method. `fit_fn(x, y, ...)` receives
the **standardised** design matrix `x` and the response matrix `y` and returns a
model object with a `predict()` method honouring clause 2. A registered method is
selected by `fit_surrogate(ensemble, method = "<name>")`.

**Standardised-design contract.** A conformer is trained on the standardised
design `x` and is asked to predict on the same scale: `predict.fb_surrogate()`
standardises `newdata` with the stored centre/scale and passes that (keyed by
`param_names`) to the conformer's `predict()`. Train and predict therefore agree
on scale -- a conformer must not re-standardise.

| Producer | method | How it conforms |
|---|---|---|
| **flexyBayes (reference)** | `rff` | Random Fourier features + Bayesian linear regression, predictive variance set by MacKay evidence maximisation (calibrated `<o>_sd`). Uses **ARD** lengthscales by default (per-input relevance learned from the evidence) and a **joint** multi-output fit (matrix-normal -- inverse-Wishart) preserving the cross-output covariance (clause 4); `ard = FALSE` / `joint = FALSE` recover the isotropic / per-output behaviour. `ard_refit = TRUE` profiles the prior/noise precisions `(a, t)` at each lengthscale (a fuller evidence, opt-in; `"cv"` regularises it on a k-fold held-out split); `cov_rank = q` stores a rank-`q` low-rank covariance (clause 5; `cov_method = "eigen"` / `"fa"` / `"auto"`) for large output counts. Self-contained -- the always-available default. |
| **PESTO** | `gp` | `train_gp_surrogate()` / `predict_gp_surrogate()` already report a per-output predictive `$mean` **and** `$variance`, so the adapter maps them straight onto `<o>_mean` / `<o>_sd = sqrt(variance)`. Registered by `register_pesto_surrogates()`. (PESTO's `rff` surrogate returns only an aggregate `$uncertainty`, not per-output variance, so it is not registered.) |
| **kernR** | `cme` | `fit_cme()` is a kernel linear smoother: it yields the conditional *mean* `y_hat(x*) = w(x*)' y` but **no** predictive variance. The adapter supplies the standard linear-smoother predictive variance `sigma^2 (1 + ||w(x*)||^2)` (with `sigma^2 = RSS / (n - tr(S))` from the in-sample smoother), so `<o>_sd` is honest. The conditional-mean map stays kernR's; only the UQ is added. Registered by `register_kernr_surrogates()`. (`dist_regression()` takes distributional *bag* inputs, not a parameter design, so it is not a C7 surrogate.) |

Both sibling adapters live in flexyBayes (`R/surrogate_conformers.R`), are
`requireNamespace`-gated, and are registered opportunistically from `.onLoad`
when the member is installed -- so `method = "gp"` / `"cme"` simply works when the
sibling is present, and flexyBayes stays standalone otherwise.

## Why a contract, not a reimplementation

- **No duplication.** flexyBayes ships only the reference `rff` surrogate; kernR's
  CME and PESTO's GP are consumed through the registry, not copied (the
  constellation "contracts not internals" rule -- the same reason flexyBayes does
  not execute APSIM).
- **Distribution preservation is a contract clause, not a hope.** Standard
  surrogate-accelerated calibration silently degrades UQ by plugging in point
  predictions; clause 2 makes `<o>_sd` mandatory, so a non-preserving surrogate
  fails to conform.
- **Standalone-functional** (charter invariant 1): the `rff` reference needs no
  sibling member -- flexyBayes emulates + propagates UQ on its own.

## Consumers

The surrogate's `<o>_mean` / `<o>_sd` feed:

- **Surrogate-accelerated inversion** -- `fb_surrogate_ies()`
  (`R/surrogate_ies.R`): an Ensemble Smoother with Multiple Data Assimilation
  (ES-MDA) that calibrates a parameter ensemble against observed data using the
  surrogate in place of the simulator. The predictive uncertainty is folded into
  the data covariance, so emulator error appropriately inflates the assimilation
  noise -- the consumer the distribution-preserving sd exists to serve. When the
  surrogate is joint, the **full** cross-output predictive covariance (clause 4,
  `cov = TRUE`) enters the data covariance, so correlated emulator errors are
  assimilated coherently (`use_surrogate_cov = TRUE`, default); a marginals-only
  surrogate falls back to the diagonal, identical to the per-output path. When
  the surrogate stores a **low-rank** covariance (`cov_rank`, clause 5) the IES
  consumes the factored form natively -- the Kalman update uses the Woodbury
  identity (a rank-sized solve) and the perturbation is sampled factored, so the
  `d x d` data covariance is never formed (the native low-rank consumer for a
  large output count). It consumes any conforming `fb_surrogate` via
  `predict()`; it deliberately does
  **not** route through PESTO's `pesto_surrogate_ies()`, which is monolithic
  (its GP is trained internally in C++ and cannot accept an external surrogate),
  so flexyBayes is standalone-functional for surrogate-accelerated inversion.
- **Emulator-distortion check** -- `fb_surrogate_ppc()` (`R/surrogate_ppc.R`):
  draws from the surrogate's predictive distribution at held-out parameter sets
  and hands the draws to kernR's `mmd_ppc()` against the true simulator outputs
  -- did the surrogate distort the output *distribution*, not just its mean?
  With `joint = TRUE` (default) the draws are sampled from the **full
  cross-output predictive covariance** (clause 4, via a per-row Cholesky), so the
  emulator's cross-output correlation is tested -- the second consumer of the
  joint covariance after the IES. On a correlated-output simulator, marginal
  draws discard that structure and false-reject a faithful surrogate, so the
  joint path is the correct distribution-preserving check (the cont.20
  marginal-vs-joint lesson, applied to the PPC). When the surrogate stores a
  **low-rank** covariance (`cov_rank`, clause 5) the joint draws are sampled from
  the factored form directly (a `q`-dim factor noise + a `k`-dim idiosyncratic
  noise), so the `k x k` slice is never formed -- the native low-rank consumer
  for the PPC. With `project = TRUE` the draws and `observed` are projected onto
  the surrogate's `q` factor directions before the MMD, so the test runs in `q`
  dimensions (cheaper + higher-powered on the correlated structure for a large
  output count; blind to idiosyncratic-direction distortions by construction).
  With `whiten = TRUE` the draws and `observed` are Mahalanobis-whitened by their
  **pooled covariance** before the MMD -- a label-agnostic linear representation
  (it depends only on the pooled cloud, not the draws-vs-observed labels, so the
  permutation test stays valid) that puts the outputs on a common footing and so
  removes the cross-output scale heterogeneity defeating a single median
  bandwidth. The same map is applied to both clouds, so a relative scale, shape,
  or mean difference survives; empirically it lifts power substantially on a
  localised / heterogeneous-scale distortion the raw check misses, with no blind
  spot found across a mean / variance / shape battery. Opt-in (a graduated ridge
  guards a near-singular pooled covariance); composes with `project` and
  `aggregate`. This is the representation lever that the per-kernel statistic
  exposed: a learned deep kernel was investigated and did not beat this cheap
  whitening in the (conservative-null) PPC.
  With `aggregate = TRUE` the test is an aggregated multi-kernel MMD (MMDAgg;
  Schrab et al. 2023) over a bandwidth grid, aggregated by the weighted-quantile
  statistic `min_g p_g / w_g` (`agg_weights` sets the kernel weights) -- no
  bandwidth tuning, robust when the median heuristic is mis-scaled, at a valid
  level -- orchestrating kernR's single-kernel `mmd_test`.
  kernR owns the MMD machinery (the kernel, the statistic, the permutation null);
  flexyBayes generates the predictive sample and, for `aggregate`, the
  cross-bandwidth aggregation.
- **Mechanistic-statistical fits** -- `fb_apsim()` (ADR 0009, partner-gated),
  provisioned in its own pass.
