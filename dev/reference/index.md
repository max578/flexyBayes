# Package index

## Verbs

The universal entry, the single-engine pins, the feasibility planner,
cross-engine triangulation, and approximation validation.

- [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md)
  [`fb()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md)
  : Bayesian Mixed Models with ASReml Syntax
- [`flexybayes_stream()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes_stream.md)
  : Fit a mixed model to an out-of-core dataset by streaming aggregation
- [`fb_greta()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_greta.md)
  : Fit a flexyBayes model via the greta engine
- [`fb_inla()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_inla.md)
  : Fit a flexyBayes model via the INLA engine
- [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_brms.md)
  : Fit a flexyBayes model via the brms (Stan) engine
- [`fb_plan()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_plan.md)
  : Plan a flexyBayes fit without firing the backend
- [`triangulate()`](https://aagi-aus.github.io/flexyBayes/dev/reference/triangulate.md)
  : Cross-engine posterior triangulation
- [`validate_approximation()`](https://aagi-aus.github.io/flexyBayes/dev/reference/validate_approximation.md)
  : Validate an approximate model fit against its bias bound
- [`proceed()`](https://aagi-aus.github.io/flexyBayes/dev/reference/proceed.md)
  : Advance a deferred-execution object into its fit

## Ingest adapters

Turn a model specification into a backend-agnostic representation.

- [`fb_from_asreml()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_from_asreml.md)
  : Ingest an ASReml-format model specification into the flexyBayes IR
- [`fb_from_brms()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_from_brms.md)
  : Ingest a brms-format formula into the flexyBayes IR
- [`fb_from_greta()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_from_greta.md)
  : Ingest a user-built greta model into the flexyBayes IR

## Constructor nouns

The four classed input constructors: priors, covariance carriers,
approximation schemes, and engine selections.

- [`fb_prior()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_prior.md)
  : Specify priors via the PC-canonical hybrid DSL

- [`fb_cov()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_cov.md)
  : Construct a structured-covariance carrier

- [`fb_approx()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_approx.md)
  : Construct an approximation-scheme specification

- [`fb_engine()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_engine.md)
  : Construct an inference-engine specification

- [`is_fb_cov()`](https://aagi-aus.github.io/flexyBayes/dev/reference/is_fb_cov.md)
  :

  Test whether an object is an `fb_cov` carrier

- [`is_fb_approx()`](https://aagi-aus.github.io/flexyBayes/dev/reference/is_fb_approx.md)
  :

  Test whether an object is an `fb_approx` specification

- [`is_fb_engine()`](https://aagi-aus.github.io/flexyBayes/dev/reference/is_fb_engine.md)
  :

  Test whether an object is an `fb_engine` specification

## Accessors and discovery

Routing trace, refusal vocabulary, canonical names, prior summary,
status.

- [`backend_decision()`](https://aagi-aus.github.io/flexyBayes/dev/reference/backend_decision.md)
  : Backend dispatch trace for a flexyBayes fit
- [`canonical_names()`](https://aagi-aus.github.io/flexyBayes/dev/reference/canonical_names.md)
  : Canonical parameter-name view for a flexyBayes fit
- [`fb_refusals()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_refusals.md)
  : List flexyBayes refusal reasons
- [`prior_summary()`](https://aagi-aus.github.io/flexyBayes/dev/reference/prior_summary.md)
  : Resolved-prior summary for a flexyBayes fit
- [`gretaR_status()`](https://aagi-aus.github.io/flexyBayes/dev/reference/gretaR_status.md)
  : Introspect the gretaR backend slot
- [`cat_code()`](https://aagi-aus.github.io/flexyBayes/dev/reference/cat_code.md)
  : Emit the generated backend code for a deferred review object

## Cross-package interop

Tidiers, emmeans, marginaleffects, and draws conversion.

- [`tidy.flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/tidy.flexybayes.md)
  : Tidy a flexybayes model
- [`glance.flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/glance.flexybayes.md)
  : Glance at a flexybayes model
- [`augment.flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/augment.flexybayes.md)
  : Augment a flexybayes model
- [`emm_basis(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/emm_basis.flexybayes.md)
  [`emm_basis(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/emm_basis.flexybayes.md)
  : emmeans support: estimation basis (greta backend)
- [`recover_data(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/recover_data.flexybayes.md)
  [`recover_data(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/recover_data.flexybayes.md)
  : emmeans support: recover model data (greta backend)
- [`get_coef(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/get_coef.flexybayes.md)
  [`get_coef(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/get_coef.flexybayes.md)
  : marginaleffects support: fixed-effect coefficients (greta backend)
- [`get_vcov(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/get_vcov.flexybayes.md)
  [`get_vcov(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/get_vcov.flexybayes.md)
  : marginaleffects support: covariance (greta backend)
- [`get_predict(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/get_predict.flexybayes.md)
  [`get_predict(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/get_predict.flexybayes.md)
  : marginaleffects support: population-level predictions (greta
  backend)
- [`get_data(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/get_data.flexybayes.md)
  [`get_data(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/get_data.flexybayes.md)
  : Model data accessor (greta backend)
- [`set_coef(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/set_coef.flexybayes.md)
  [`set_coef(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/set_coef.flexybayes.md)
  : marginaleffects support: set coefficients (greta backend)
- [`fb_as_draws_simple()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_as_draws_simple.md)
  : Extract per-parameter posterior draws from a model fit

## Methods

S3 methods on the fit objects. Most are reached through their generic
(for example [`coef()`](https://rdrr.io/r/stats/coef.html),
[`predict()`](https://rdrr.io/r/stats/predict.html)); they are listed
here for completeness.

- [`summary(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/summary.flexybayes.md)
  : Summarise a flexybayes object

- [`summary(`*`<flexybayes_aggregated>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/summary.flexybayes_aggregated.md)
  : Summarise a flexybayes_aggregated object

- [`summary(`*`<flexybayes_glm>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/summary.flexybayes_glm.md)
  : Summary for flexybayes GLM-compatible object

- [`summary(`*`<fb_plan>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/summary.fb_plan.md)
  :

  Summarise an `<fb_plan>` — verbose form

- [`print(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.flexybayes.md)
  : Print a flexybayes object

- [`print(`*`<flexybayes_aggregated>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.flexybayes_aggregated.md)
  : Print a flexybayes_aggregated object

- [`print(`*`<flexybayes_brms>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.flexybayes_brms.md)
  : Print method for the brms-passthrough flexybayes subclass

- [`print(`*`<flexybayes_direct_greta>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.flexybayes_direct_greta.md)
  : Print a flexybayes object built via fb_greta() (direct greta entry)

- [`print(`*`<fb_approx>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.fb_approx.md)
  :

  Print an `fb_approx` specification

- [`print(`*`<fb_cov>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.fb_cov.md)
  :

  Print an `fb_cov` carrier

- [`print(`*`<fb_engine>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.fb_engine.md)
  :

  Print an `fb_engine` specification

- [`print(`*`<fb_plan>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/print.fb_plan.md)
  :

  Print an `<fb_plan>` — flight-checklist form

- [`coef(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/coef.flexybayes.md)
  : Extract fixed effect coefficients

- [`coef(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/coef.flexybayes_inla.md)
  : Fixed-effect coefficients of a per-row INLA fit

- [`coef(`*`<flexybayes_direct_greta>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/coef.flexybayes_direct_greta.md)
  : Extract canonical-named posterior means from an fb_greta() fit

- [`confint(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/confint.flexybayes.md)
  : Credible intervals for fixed effects

- [`confint(`*`<flexybayes_brms>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/confint.flexybayes_brms.md)
  : Credible intervals on the brms path

- [`confint(`*`<flexybayes_glm>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/confint.flexybayes_glm.md)
  : Credible intervals for flexybayes_glm

- [`vcov(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/vcov.flexybayes.md)
  : Extract variance-covariance matrix of fixed effects

- [`vcov(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/vcov.flexybayes_inla.md)
  : Posterior covariance of a per-row INLA fit's fixed effects

- [`predict(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/predict.flexybayes.md)
  : Predict from a flexybayes model

- [`predict(`*`<flexybayes_brms>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/predict.flexybayes_brms.md)
  : Predict from a brms-passthrough flexybayes fit

- [`predict(`*`<flexybayes_direct_greta>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/predict.flexybayes_direct_greta.md)
  : Predict from a flexybayes_direct_greta fit

- [`predict(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/predict.flexybayes_inla.md)
  : Population-level predictions from a per-row INLA fit

- [`fitted(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/fitted.flexybayes.md)
  : Extract fitted values

- [`residuals(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/residuals.flexybayes.md)
  : Extract residuals

- [`plot(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/plot.flexybayes.md)
  [`plot(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/plot.flexybayes.md)
  [`plot(`*`<flexybayes_brms>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/plot.flexybayes.md)
  [`plot(`*`<flexybayes_aggregated>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/plot.flexybayes.md)
  [`plot(`*`<flexybayes_direct_greta>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/plot.flexybayes.md)
  [`plot(`*`<flexybayes_glm>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/plot.flexybayes.md)
  : Plot diagnostics for a flexybayes model

- [`anova(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/anova.flexybayes.md)
  : Compare flexybayes models

- [`logLik(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/logLik.flexybayes.md)
  : Log-likelihood (approximate)

- [`logLik(`*`<flexybayes_brms>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/logLik.flexybayes_brms.md)
  : Log-likelihood on the brms path

- [`nobs(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/nobs.flexybayes.md)
  : Number of observations

- [`family(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/family.flexybayes.md)
  : Extract model family

- [`family(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/family.flexybayes_inla.md)
  : Response family of a per-row INLA fit

- [`formula(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/formula.flexybayes.md)
  : Extract model formula

- [`formula(`*`<flexybayes_inla>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/formula.flexybayes_inla.md)
  : Fixed-effect model formula of a per-row INLA fit

- [`model.matrix(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/model.matrix.flexybayes.md)
  : Extract model matrix

- [`update(`*`<flexybayes>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/update.flexybayes.md)
  : Update a flexybayes model

- [`as.data.frame(`*`<fb_plan>`*`)`](https://aagi-aus.github.io/flexyBayes/dev/reference/as.data.frame.fb_plan.md)
  :

  Coerce an `<fb_plan>` to data.frame — one row, stable columns

## Datasets

- [`met_example`](https://aagi-aus.github.io/flexyBayes/dev/reference/met_example.md)
  : Example Multi-Environment Trial (MET) Dataset

## Package

- [`flexyBayes`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexyBayes-package.md)
  [`flexyBayes-package`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexyBayes-package.md)
  : flexyBayes: Bayesian Mixed Models with ASReml Syntax, Powered by
  Greta and INLA
