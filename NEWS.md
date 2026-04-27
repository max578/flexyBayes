# flexyBayes 0.1.0.9000 (development)

## Variance-component prior default — change with one-time deprecation note

The default prior on every named random-effect standard deviation
and the residual standard deviation has changed from
`lognormal(0, 1)` (the legacy flexyBayes default, undocumented and
without a published rationale) to a penalised-complexity (PC) prior
following Simpson, Rue, Riebler, Martins, & Sørbye (2017,
*Statistical Science* 32(1):1–28):

```
sigma ~ pc(upper = U, prob = 0.05)
```

with `U` chosen family-aware:

* Gaussian / identity link: `U = 2.5 * sd(y)`.
* Log link (Poisson, NegBin, Gamma): `U = 2.5 * sd(log(y + 0.5))`.
* Logit link (binomial, beta): `U = 2.5` (logit-scale random
  effects are typically order one on any data scale).

The PC prior places maximum density at `sigma = 0` and decays
exponentially with rate `-log(0.05) / U`, encoding shrinkage to
the simpler model (no random effect) unless the data say otherwise
— the property that the previous lognormal default lacked.

The default fires only when the caller leaves both `prior` and
`prior_vc_sd` at their defaults; passing `prior_vc_sd` explicitly
preserves the legacy `lognormal(0, prior_vc_sd)` path verbatim,
and passing `prior = fb_prior(...)` gives full per-component
control. The change is announced once per session via a `message()`;
silence it with `options(flexyBayes.silence_default_prior_note = TRUE)`.

The `simple` / `ide` / `id` random-effect codegen branch and the
residual emit honour PC fb_prior() specs by emitting
`greta::exponential(rate = -log(prob)/upper)`. Other random-effect
branches (vm, ped, at, us, fa, ar1, spline) keep the legacy
lognormal default in v0.1.x and are extended to honour fb_prior()
in v0.2.

## fb_prior() additions

* `uniform(lower, upper)` is now accepted in the DSL for sd-scale
  targets (`sigma`, `sd(group = ...)`, `smooth(...)`). The INLA
  backend translates `uniform(0, U)` to a PC prior with matched
  upper tail (`pc.prec(U, 0.01)`) and a one-time message flagging
  the approximation; exact bounded-support uniform via INLA's
  expression-prior is on the v0.2 roadmap. The legacy greta scalar
  bridge refuses uniform with a redirect; direct uniform on the
  greta backend lands in v0.2.
* `fb_prior()` documentation now lists the full supported family
  set.

## triangulate()

* New `transform_a` / `transform_b` arguments, named lists of
  one-argument functions keyed by parameter name, applied to draws
  *before* `name_map` renaming. Common use:
  `transform_b = list("Precision for g" = function(x) 1 / sqrt(x))`
  to put INLA's precision draws on the standard-deviation scale so
  they line up with greta's `sigma_g`.

## emit_inla() — bug fix

`priors_to_inla()` output is now actually injected into the INLA
formula (`f(group, model = "iid", hyper = list(prec = ...))`) and
into `control.family$hyper$prec` for the residual sigma. Previously
the helper was computed but never reached the INLA call, so
user-supplied priors were silently ignored.

## .build_glm() — bug fix

`.build_glm()` now uses a fixed-effects-only formula reconstructed
from the parsed IR for `model.frame()` / `model.matrix()` /
`terms()` calls. The previous implementation passed the user's full
brms-style formula through to those functions, which evaluated
`(1|g)` as bitwise-OR and emitted
`Ops.factor(1, g) : '|' not meaningful for factors` warnings for
every `fb()` greta fit. Asreml ingest behaviour is unchanged
(byte-identical fixed-only formula).

## flexybayes() API

* New `prior` argument (defaults to `NULL`) accepts an `fb_prior()`
  object. Forward-compatible with the v0.2 codegen extensions; in
  v0.1.x the supplied prior takes effect via INLA dispatch and via
  the simple/ide/id greta branch.

## References

* Simpson, D., Rue, H., Riebler, A., Martins, T. G., & Sørbye, S. H.
  (2017). Penalising model component complexity: a principled,
  practical approach to constructing priors. *Statistical Science*
  32(1): 1–28.
* Gelman, A. (2006). Prior distributions for variance parameters in
  hierarchical models. *Bayesian Analysis* 1(3): 515–534.
