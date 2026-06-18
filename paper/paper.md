---
title: 'flexyBayes: flexible Bayesian mixed models with ASReml- and brms-style syntax and cross-engine triangulation'
tags:
  - R
  - Bayesian inference
  - mixed models
  - Markov chain Monte Carlo
  - integrated nested Laplace approximation
  - agricultural statistics
authors:
  - name: Max Moldovan
    orcid: 0000-0001-9680-8474
    corresponding: true
    affiliation: "1, 2"
  - name: Emi Tanaka
    orcid: 0000-0002-1455-259X
    affiliation: 3
  - name: Francis K. C. Hui
    orcid: 0000-0003-0765-3533
    affiliation: 3
  - name: Anabel Forte Deltell
    affiliation: 4
affiliations:
  - name: Australian Agricultural Genomics Institute (AAGI-AUS), Australia
    index: 1
  - name: Adelaide University, Australia
    index: 2
  - name: Australian National University, Australia
    index: 3
  - name: AFFILIATION TO CONFIRM (Anabel Forte Deltell)
    index: 4
date: 6 June 2026
bibliography: paper.bib
---

# Summary

`flexyBayes` is an R package for fitting Bayesian mixed models from a single
model specification that can be expressed in either ASReml-style `fixed` /
`random` / `rcov` syntax or `brms`/`lme4`-style bar-grouped formulas. One
specification is routed, unchanged, to any of three inference engines -- greta
for Hamiltonian Monte Carlo [@greta], INLA for integrated nested Laplace
approximation [@inla], or `brms` for a Stan passthrough [@brms] -- and results
are returned in objects compatible with the standard R modelling ecosystem
(`summary()`, `emmeans`, `marginaleffects`, `effectsize`, `broom`). The
package's distinguishing feature is **cross-engine triangulation**: the same
model fitted under two engines can be compared parameter by parameter, with
backend-native names automatically aligned to a common scale, so that
disagreement between approximate and exact inference becomes an explicit,
reportable diagnostic rather than a hidden assumption. `flexyBayes` supports
Gaussian, binomial, Poisson, negative-binomial, gamma, and beta families;
structured covariance models (`us`, `fa`, `ar1`); genomic relationship
matrices (GBLUP); pedigree-based animal models; separable spatial models; and
penalised splines.

# Statement of need

Analysts of multi-environment field trials and genomic-selection data typically
work in the ASReml formula language, which expresses variance structures
(unstructured, factor-analytic, autoregressive, relationship-matrix) compactly
and is the lingua franca of quantitative agricultural genetics [@asreml].
Moving such an analysis into a Bayesian setting normally requires rewriting the
model in an engine-specific dialect (Stan, INLA's `f()` terms, or a hand-built
greta graph) and committing to a single inference algorithm. Each engine makes
different approximations -- INLA is fast but approximate, HMC is asymptotically
exact but expensive -- and a practitioner rarely has an inexpensive way to tell
whether a chosen engine's answer is trustworthy for the model and data at hand.

`flexyBayes` addresses three gaps. First, it accepts the ASReml grammar
agricultural users already know (and the `brms`/`lme4` grammar familiar from the
wider mixed-model community), translating either to backend-specific code so the
user never re-specifies the model to change engine. Second, it treats
*evidence of cross-engine agreement* as a first-class output: `triangulate()`
reports per-parameter mean differences, posterior-SD ratios, tail-quantile
differences, and the 1-D Wasserstein distance between two engines' marginals,
turning "is this approximation safe here?" into a measured quantity. Third, it
scales to the sizes encountered in plant breeding by parameterising random
effects by their number of levels rather than by the number of observations,
giving memory linear in the number of coefficients.

The package complements `brms` [@brms] and the greta and INLA ecosystems
[@greta; @inla] -- it is a grammar-and-orchestration layer over them, not a new
sampler -- and complements `lme4` [@lme4] by providing a Bayesian path from the
same broad family of model specifications. Default variance-component priors are
weakly-informative bounded-uniform distributions on the standard-deviation scale
for moderate group counts, with penalised-complexity [@simpson2017] and
half-Cauchy alternatives available; the small-group guidance follows
@gelman2006. Within-engine convergence is assessed with rank-normalised
$\widehat{R}$ and effective sample size [@vehtari2021].

# Acknowledgements

We thank colleagues at the Australian Agricultural Genomics Institute and
Adelaide University for testing and feedback during development.

# References
