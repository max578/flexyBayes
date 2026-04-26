#' Bayesian Mixed Models with ASReml Syntax
#'
#' Specify mixed models using ASReml formula syntax and estimate them via
#' Bayesian MCMC using greta. Returns a three-part result: a GLM-compatible
#' object for use with standard R packages (emmeans, marginaleffects, etc.),
#' native greta output for Bayesian diagnostics, and extras for secondary
#' analyses.
#'
#' @param fixed Two-sided formula: `response ~ fixed_effects`.
#' @param random One-sided formula: `~ random_terms` using ASReml syntax.
#'   Supports `vm()`, `at()`, `us()`, `fa()`, `ar1()`, `spl()`, `ped()`,
#'   `dsum()`, `id()`, and nested colon terms.
#' @param rcov One-sided formula: `~ residual_structure`. Default `~ units`
#'   (iid residuals). Use `~ at(env):units` for heterogeneous variance.
#' @param data A data.frame containing all variables referenced in the formulas.
#' @param family Character: `"gaussian"`, `"binomial"`, `"poisson"`,
#'   `"negative_binomial"`, `"gamma"`, or `"beta"`.
#' @param link Character or NULL: override the default link function
#'   (e.g., `"probit"` for binomial).
#' @param known_matrices Named list of matrices referred to in the random
#'   formula (e.g., `list(Gmat = G_mat, Amat = A_mat)`).
#' @param weights Optional numeric weight vector (length N); sets
#'   Var = sigma^2 / w.
#' @param n_samples Integer: number of posterior samples per chain.
#' @param warmup Integer: number of warmup (burn-in) iterations per chain.
#' @param chains Integer: number of MCMC chains.
#' @param prior_fixed_sd Numeric: SD for fixed-effect normal priors.
#' @param prior_vc_sd Numeric: hyperparameter for lognormal variance-component
#'   priors.
#' @param verbose Logical: print generated greta code to console.
#' @param mcmc_verbose Logical: show MCMC progress bar from greta.
#' @param return_code Logical: if TRUE, return the generated code string
#'   without fitting the model.
#'
#' @return An object of class `"bayesreml"` — a list with three components:
#' \describe{
#'   \item{`$glm`}{A GLM-compatible object (class `c("bayesreml_glm", "glm",
#'     "lm")`) with posterior mean coefficients, vcov, residuals, fitted values,
#'     etc. Works with `summary()`, `emmeans()`, `marginaleffects()`,
#'     `effectsize()`.}
#'   \item{`$greta`}{Native greta output: `model`, `draws` (mcmc.list),
#'     `greta_arrays`, and `env`. Use with `bayesplot`, `greta::calculate()`,
#'     `posterior::as_draws()`.}
#'   \item{`$extras`}{Additional outputs: posterior `summary`, `convergence`
#'     diagnostics, `variance_comps`, `blups`, `predictions`, generated `code`,
#'     `param_names`, `parse_info`, `call_info`, `run_time`, `model_info`.}
#' }
#'
#' If `return_code = TRUE`, returns a character string of greta code instead.
#'
#' @examples
#' \dontrun{
#' # Simple random intercept model
#' fit <- bayesreml(
#'   fixed  = yield ~ env,
#'   random = ~ geno,
#'   data   = met_example,
#'   n_samples = 1000, warmup = 500, chains = 4
#' )
#'
#' # Inspect results
#' summary(fit)
#' coef(fit)
#' confint(fit)
#'
#' # Use with emmeans
#' library(emmeans)
#' emmeans(fit, ~ env)
#'
#' # Use with marginaleffects
#' library(marginaleffects)
#' avg_slopes(fit)
#'
#' # Bayesian diagnostics
#' library(bayesplot)
#' mcmc_trace(fit$greta$draws)
#'
#' # View generated greta code
#' cat(fit$extras$code)
#' }
#'
#' @importFrom stats terms model.frame model.matrix model.response
#'   formula family gaussian binomial poisson Gamma
#'   fitted residuals predict confint coef vcov logLik
#'   nobs update anova na.omit var cov quantile median
#'   qnorm pnorm dnorm setNames df.residual deviance
#'   .getXlevels dbinom density dpois lowess
#'   printCoefmat qqline qqnorm
#' @importFrom graphics abline axis hist legend lines par segments
#' @importFrom methods is
#' @importFrom coda effectiveSize gelman.diag
#' @importFrom splines bs
#' @export
bayesreml <- function(
    fixed,
    random           = NULL,
    rcov             = NULL,
    data,
    family           = "gaussian",
    link             = NULL,
    known_matrices   = list(),
    weights          = NULL,
    n_samples        = 1000,
    warmup           = 500,
    chains           = 4,
    prior_fixed_sd   = 10,
    prior_vc_sd      = 1,
    verbose          = TRUE,
    mcmc_verbose     = TRUE,
    return_code      = FALSE
) {
  if (!requireNamespace("greta", quietly = TRUE))
    stop("Package 'greta' is required. Install with:\n",
         "  install.packages('greta')\n",
         "  greta::install_greta_deps()")

  the_call  <- match.call()
  data_name <- deparse(substitute(data))

  # Build the flexyBayes intermediate representation (IR) via the
  # asreml-format ingest path. See R/fb.R.
  fb <- fb_from_asreml(
    fixed          = fixed,
    random         = random,
    rcov           = rcov,
    data           = data,
    family         = family,
    link           = link,
    weights        = weights,
    known_matrices = known_matrices,
    prior_fixed_sd = prior_fixed_sd,
    prior_vc_sd    = prior_vc_sd
  )

  # Drive the greta backend through the emit shim. Behaviour is
  # byte-identical to the pre-0.C inline pipeline; see
  # tests/testthat/test-emit-greta.R for the snapshot regression
  # firewall and tests/testthat/test-fb-from-asreml.R for the
  # ingest-side transparency check.
  emit_greta(
    fb             = fb,
    data           = data,
    known_matrices = known_matrices,
    weights        = weights,
    n_samples      = n_samples,
    warmup         = warmup,
    chains         = chains,
    prior_fixed_sd = prior_fixed_sd,
    prior_vc_sd    = prior_vc_sd,
    verbose        = verbose,
    mcmc_verbose   = mcmc_verbose,
    return_code    = return_code,
    the_call       = the_call,
    fixed          = fixed,
    random         = random,
    rcov           = rcov,
    family         = family,
    link           = link,
    data_name      = data_name
  )
}
