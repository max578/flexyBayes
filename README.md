# flexyBayes

Flexible Bayesian Mixed Models with ASReml and brms-Style Syntax

## Overview

`flexyBayes` lets you specify mixed models using the familiar ASReml formula
interface (`fixed`, `random`, `rcov`) and estimates them via Bayesian MCMC
using [greta](https://greta-stats.org/). Results are returned in three
complementary formats:

- **`$glm`** -- GLM-compatible object that works with `summary()`, `emmeans`,
  `marginaleffects`, `effectsize`, and other standard R packages
- **`$greta`** -- native greta output (`draws`, `model`, `greta_arrays`) for
  use with `bayesplot`, `greta::calculate()`, `posterior::as_draws()`
- **`$extras`** -- BLUPs, variance components, convergence diagnostics,
  generated code, and more

## Installation

```r
# Install greta first
install.packages("greta")
greta::install_greta_deps()

# Install flexyBayes from GitHub
# install.packages("remotes")
remotes::install_github("AAGI-AUS/flexyBayes")
```

## Quick Start

```r
library(flexyBayes)
data(met_example)
dat <- met_example$dat

# Fit a mixed model with ASReml-like syntax
fit <- flexybayes(
  fixed  = yield ~ env,
  random = ~ geno,
  data   = dat,
  n_samples = 1000,
  warmup = 500,
  chains = 4
)

# Standard R output
summary(fit)
coef(fit)
confint(fit)

# emmeans
library(emmeans)
emmeans(fit, ~ env)

# marginaleffects
library(marginaleffects)
avg_slopes(fit)

# Bayesian diagnostics
library(bayesplot)
mcmc_trace(fit$greta$draws)

# View generated greta code
cat(fit$extras$code)
```

## Supported ASReml Syntax

### Fixed Effects

```r
yield ~ 1                    # intercept only
yield ~ env                  # fixed factor
yield ~ env + x_cov          # factor + covariate
yield ~ 0 + env              # means model (no intercept)
yield ~ env + I(x^2)         # expression terms
```

### Random Effects

```r
random = ~ geno                       # simple iid
random = ~ geno + env                 # crossed
random = ~ block:rep                  # nested
random = ~ vm(geno, Gmat)             # GBLUP (genomic)
random = ~ ped(animal, Amat)          # pedigree (animal model)
random = ~ at(env):geno               # diagonal GxE
random = ~ us(env):id(geno)           # unstructured GxE
random = ~ fa(env, 2):id(geno)        # factor-analytic GxE
random = ~ ar1(row):id(col)           # spatial AR1
random = ~ spl(x_cov)                 # P-spline
random = ~ vm(geno, Gmat):id(env)     # genomic GxE
```

### Residual Structure

```r
rcov = ~ units                # iid residuals (default)
rcov = ~ at(env):units        # heterogeneous by environment
rcov = ~ dsum(~ units | env)  # equivalent to above
```

### Families

```r
family = "gaussian"           # identity link (default)
family = "binomial"           # logit link
family = "binomial", link = "probit"  # probit link
family = "poisson"            # log link
family = "negative_binomial"  # log link
family = "gamma"              # log link
family = "beta"               # logit link
```

## Three-Part Output

```r
fit$glm         # c("flexybayes_glm", "glm", "lm")
                # coefficients, fitted.values, residuals, vcov, family, terms
                # Works with: summary(), emmeans(), marginaleffects(), effectsize()

fit$greta       # "flexybayes_greta"
                # model, draws (mcmc.list), greta_arrays, env
                # Works with: bayesplot, greta::calculate(), posterior

fit$extras      # "flexybayes_extras"
                # summary, convergence, variance_comps, blups, predictions,
                # code, param_names, parse_info, call_info, run_time
```

## Design Principles

- **Indexing, not model matrices**: Parameters are sized by number of levels
  (`p`), not observations (`N`), giving O(p) memory for random effects
- **Non-centered parameterisation**: All random effects use NCP for efficient
  MCMC sampling
- **Cholesky decomposition**: Known covariance matrices (G, A) are decomposed
  once for computational efficiency
- **LKJ priors**: Correlation matrices use LKJ(eta=2) priors for
  regularisation

## Vignettes

The package includes 25 vignettes covering all 20 model categories from the
GLMM Model Formulations Reference:

- **Getting Started**: Installation, first model, output navigation
- **Syntax Guide**: Complete ASReml formula reference
- **Downstream Analysis**: emmeans, marginaleffects, effectsize workflows
- **Tutorials 1--20**: One tutorial per model category, each with open-source
  datasets, mathematical notation, interpretation guidance, and
  publication-quality visualisations

## Requirements

- R >= 4.1.0
- greta >= 0.4.0 (requires Python + TensorFlow + TensorFlow Probability)
- Install greta dependencies: `greta::install_greta_deps()`

## Citation

If you use `flexyBayes` in your research, please cite:

```
@software{flexyBayes,
  title = {flexyBayes: Flexible Bayesian Mixed Models with ASReml and brms-Style Syntax},
  author = {Moldovan, Max and Tanaka, Emi and Hui, Francis K.C. and Sznajder, Beata},
  year = {2026},
  url = {https://github.com/AAGI-AUS/flexyBayes}
}
```

## License

GPL (>= 3)
