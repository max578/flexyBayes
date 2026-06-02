# flexyBayes surrogate contract (C7, v1)

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
   independently; the reference implementation is per-output.

## The registry (how richer surrogates plug in)

`register_surrogate(method, fit_fn)` adds a method. `fit_fn(x, y, ...)` receives
the **standardised** design matrix `x` and the response matrix `y` and returns a
model object with a `predict()` method honouring clause 2. A registered method is
selected by `fit_surrogate(ensemble, method = "<name>")`.

| Producer | method | How it conforms |
|---|---|---|
| **flexyBayes (reference)** | `rff` | Random Fourier features + Bayesian linear regression, one model per output, predictive variance set by MacKay evidence maximisation (calibrated `<o>_sd`). Self-contained -- the always-available default. |
| **kernR** | `cme` / `dist_regression` | `fit_cme()` / `dist_regression()` emulate the full conditional output *distribution* (the deep distribution-preserving surrogate); register a coercer to the `<o>_mean` / `<o>_sd` predict shape. |
| **PESTO** | `gp` / `rff_gp` | `train_gp_surrogate()` / `train_rff_surrogate()` + `predict_*_surrogate()`; register the predict adapter. |

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

## Consumers (downstream; not built here)

The surrogate's `<o>_mean` / `<o>_sd` feed: a surrogate-accelerated inverse step
(PESTO's `pesto_surrogate_ies`), a posterior-predictive check of the emulator
(kernR's `mmd_ppc()` -- did the surrogate distort the distribution?), and
mechanistic-statistical fits (`fb_apsim()`, partner-gated). Each is provisioned
in its own pass.
