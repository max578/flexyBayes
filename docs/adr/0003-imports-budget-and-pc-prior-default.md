# 3. Imports budget; PC-prior default; legacy lognormal preserved

Date: 2026-04-27

## Status

Accepted.

## Context

Two decisions of disproportionate weight on the v0.1.x release
campaign are bundled in this ADR because they share a single
governing principle: **defaults are policy, not convenience**.

### Imports budget

Every package added to `Imports:` lengthens cold install time,
broadens the dependency-update surface (Dependabot, CRAN-incoming
checks), and increases the probability that an upstream change
breaks `bayesreml`. The audit baseline (`audit-bayesreml-2026-04-18.md`,
invariant I3) requires "lean hard dependencies".

### Prior defaults

The variance-component prior is the single most consequential
modelling default in a hierarchical Bayesian package. The legacy
`bayesreml` v0.1.0 default — `lognormal(0, 1)` on every random-
effect SD and the residual SD — is undocumented, has no published
rationale, and shrinks variance components in a way that depends
arbitrarily on the data scale. This is exactly the situation
penalised-complexity (PC) priors per Simpson et al. (2017) were
designed for.

A change in default prior is a *behavioural* breaking change. Any
existing downstream code that relies on the default will produce
materially different posteriors after the change. The deprecation
infrastructure has to make this migration visible without forcing a
rewrite of legacy callers.

## Decision

### Imports

`Imports:` = 7 packages: `coda`, `lifecycle`, `stats`, `methods`,
`graphics`, `splines`, `utils`. Cap: **10 hard imports** for the
0.1.x series.

Everything else lives in `Suggests:` and is gated at call sites by
`requireNamespace("pkg", quietly = TRUE)`. This includes the heavy
modelling backends (`greta`, `INLA`, `brms`), the diagnostics
ecosystem (`bayesplot`, `posterior`, `loo`), the interop layer
(`emmeans`, `marginaleffects`, `effectsize`), the genomics utilities
(`agridat`, `sommer`), and the optional viz / matrix tools (`fields`,
`Matrix`, `patchwork`, `ggrepel`, `ggplot2`).

### Prior default

The variance-component prior default switches from `lognormal(0, 1)`
(legacy) to:

```
sigma ~ pc(upper = 2.5 * sd(y), prob = 0.05)
```

family-aware: identity link uses `2.5 * sd(y)`; log link uses
`2.5 * sd(log(y + 0.5))`; logit link uses `2.5` (logit-scale random
effects are typically order one). The PC prior places maximum
density at `sigma = 0` and decays exponentially with rate
`-log(prob) / upper`, encoding shrinkage to the simpler model.

**Soft-deprecation, not breaking.** The new default fires only when
the caller leaves both `prior` and `prior_vc_sd` at their defaults.
Passing `prior_vc_sd` explicitly preserves the legacy
`lognormal(0, prior_vc_sd)` path verbatim, byte-identical to the
v0.1.0 emit. Passing `prior = fb_prior(...)` gives full per-component
control. The change is announced once per session via a
`message()`; silence with
`options(bayesreml.silence_default_prior_note = TRUE)`.

PC default applies in v0.1.x to the simple / ide / id random-effect
branch and to the residual sigma. Other branches (vm, ped, at, us,
fa, ar1, spline) keep the legacy lognormal default and gain
`fb_prior()` honouring in v0.2.

## Alternatives considered

### For Imports

- **Move `coda` to Suggests.** Rejected: `coda::effectiveSize()` and
  `coda::gelman.diag()` are called unconditionally in the convergence
  diagnostics path; making them optional would require duplicating
  their algorithms.
- **Move `lifecycle` to Suggests.** Rejected: `lifecycle::badge()`
  is evaluated at roxygen-document time and the rendered Rd files
  reference lifecycle resources; making it Suggests breaks doc
  rendering when lifecycle is absent.
- **Hard-import `posterior` for unified draws handling.** Rejected:
  posterior pulls a substantial dep tree (`abind`, `distributional`,
  `rlang`, `tensorA`, `pillar`); we use `posterior::as_draws()` only
  inside a `requireNamespace()` guard.

### For prior default

- **Keep legacy `lognormal(0, 1)` as the headline default; document
  but do not change.** Rejected: indefensible as a default in a
  package documented for use in publication-grade work. The
  `lognormal(0, 1)` policy is invisible to most users.
- **Hard-break: PC default with no legacy escape.** Rejected: every
  existing v0.1.0 fit script that left `prior_vc_sd = 1` (the
  shipped default) would silently produce different posteriors.
  Soft-deprecation preserves the legacy path under the explicit
  `prior_vc_sd` argument.
- **PC default applied to all random-effect branches at once.**
  Rejected: structured-covariance branches (vm, ped, at, us, fa,
  ar1, spline) require per-branch translation work that does not
  fit the v0.1.x scope. Phased rollout to v0.2 is the honest call.

## Consequences

- One-time deprecation message lands in every session that exercises
  the default path. Vignettes silence it via the option in setup
  chunks.
- Cross-engine PC compilation: greta backend uses
  `greta::exponential(rate = -log(prob) / upper)`; INLA backend
  uses `pc.prec(upper, prob)` on the precision; brms passthrough
  uses brms's own PC-prior interface.
- Test suite has a snapshot-regression firewall on the legacy emit
  (`test-emit-greta.R::lognormal-default-byte-identity`) ensuring the
  legacy path stays byte-identical.
- The Imports cap is enforced in the AAGI preset audit; any future
  Imports addition needs a documented rationale plus, if cap is
  exceeded, a justification entry in this ADR or a successor.

## Cite-trail

- Simpson, D., Rue, H., Riebler, A., Martins, T. G., & Sørbye, S. H.
  (2017). Penalising model component complexity: a principled,
  practical approach to constructing priors. *Statistical Science*
  32(1): 1–28.
- Gelman, A. (2006). Prior distributions for variance parameters in
  hierarchical models. *Bayesian Analysis* 1(3): 515–534.
- Audit baseline `audit-bayesreml-2026-04-18.md`, invariant I3.
- design notes `design-notes-priors-brms-lgm.md` Sec. Q2.
