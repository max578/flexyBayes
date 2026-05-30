# Standard model interface for per-row INLA fits.
#
# A per-row INLA fit carries class `c("flexybayes_inla", "list")` and
# deliberately does NOT inherit "flexybayes" (its internal shape differs
# from the greta fit -- it has no `$glm` shim). That left it without the
# coef() / vcov() / predict() / formula() / family() interface the rest
# of the R modelling ecosystem (emmeans, marginaleffects) dispatches on.
# This file supplies those methods, reading the fixed-effect posterior
# from the INLA fit's `summary.fixed` (means, treatment-contrast basis)
# and a Monte-Carlo joint covariance from `inla.posterior.sample()`
# (the fit is built with `control.compute = list(config = TRUE)`).
#
# Scope: the fixed-effect (population-level) surface. Random effects are
# held at their population mean (zero) for prediction on new data, which
# is the convention emmeans / marginaleffects assume for marginal means
# and average predictions.


# ---------------------------------------------------------------- #
# Internal: fixed-effect posterior on the treatment-contrast basis  #
# ---------------------------------------------------------------- #

# Monte-Carlo draws of the fixed-effect coefficients from an INLA fit,
# as a matrix (n_samples x p) with `summary.fixed` rownames as columns.
# INLA names the fixed effects in the latent field as "<name>:1".
.inla_fixef_draws <- function(object, n_samples = 2000L) {
  if (!requireNamespace("INLA", quietly = TRUE))
    stop("Package 'INLA' is required to sample from a ",
         "<flexybayes_inla> fit.", call. = FALSE)
  if (is.null(object$inla))
    stop("Cannot sample: the INLA fit object is missing.",
         call. = FALSE)

  fixed_names <- rownames(object$inla$summary.fixed)
  # Force single-threaded sampling. inla.posterior.sample() otherwise
  # spawns one worker per requested sample, which (a) trips the core
  # limit R CMD check enforces via _R_CHECK_LIMIT_CORES_ and (b) is
  # wasteful for the modest sample counts the accessor draws. The fit
  # is built with control.compute = list(config = TRUE) (see
  # R/emit_inla.R), so config is not the failure mode here.
  samples <- tryCatch(
    INLA::inla.posterior.sample(as.integer(n_samples), object$inla,
                                num.threads = "1:1"),
    error = function(e)
      stop("INLA::inla.posterior.sample() failed: ",
           conditionMessage(e),
           ". Ensure the fit was built with ",
           "control.compute = list(config = TRUE).", call. = FALSE)
  )

  latent_rows <- rownames(samples[[1L]]$latent)
  row_for <- vapply(fixed_names, function(nm) {
    hit <- which(latent_rows == paste0(nm, ":1"))
    if (length(hit) != 1L)
      stop("Could not locate the latent row for fixed effect '", nm,
           "' in the INLA posterior sample.", call. = FALSE)
    latent_rows[hit]
  }, character(1L))

  mat <- vapply(samples, function(s) s$latent[row_for, 1L],
                numeric(length(fixed_names)))
  mat <- t(mat)
  colnames(mat) <- fixed_names
  mat
}


#' Fixed-effect coefficients of a per-row INLA fit
#'
#' Posterior means of the fixed effects, read from the INLA fit's
#' `summary.fixed` slot (treatment-contrast basis). These are the
#' coefficients consumed by [emmeans::emmeans()] and
#' [marginaleffects::predictions()] via the flexyBayes support methods.
#'
#' @param object A `flexybayes_inla` fit.
#' @param ... Ignored.
#' @return Named numeric vector of fixed-effect posterior means.
#' @export
coef.flexybayes_inla <- function(object, ...) {
  sf <- object$inla$summary.fixed
  stats::setNames(sf$mean, rownames(sf))
}

#' Posterior covariance of a per-row INLA fit's fixed effects
#'
#' Monte-Carlo estimate of the joint posterior covariance of the fixed
#' effects, computed from `inla.posterior.sample()`. The marginal
#' standard deviations match `summary.fixed$sd`; the off-diagonals carry
#' the joint dependence that contrast / marginal-mean standard errors
#' require. Because the estimate is sampling-based it varies slightly
#' between calls; raise `n_samples` for a tighter estimate.
#'
#' @param object A `flexybayes_inla` fit.
#' @param n_samples Posterior sample size for the covariance estimate
#'   (default 2000).
#' @param ... Ignored.
#' @return Posterior covariance matrix of the fixed effects, with
#'   `summary.fixed` rownames as dimnames.
#' @export
vcov.flexybayes_inla <- function(object, n_samples = 2000L, ...) {
  draws <- .inla_fixef_draws(object, n_samples = n_samples)
  v <- stats::cov(draws)
  dimnames(v) <- list(colnames(draws), colnames(draws))
  v
}

#' Fixed-effect model formula of a per-row INLA fit
#'
#' The fixed-effect (population-level) formula, recovered from the
#' captured call. Random-effect and residual-structure terms are not
#' part of this formula.
#'
#' @param x A `flexybayes_inla` fit.
#' @param ... Ignored.
#' @return A `formula`.
#' @export
formula.flexybayes_inla <- function(x, ...) {
  f <- x$extras$call_info$fixed
  if (is.null(f))
    stop("The INLA fit does not carry a fixed-effect formula.",
         call. = FALSE)
  stats::as.formula(f)
}

#' Response family of a per-row INLA fit
#'
#' @param object A `flexybayes_inla` fit.
#' @param ... Ignored.
#' @return A list with `family` and `link` entries.
#' @export
family.flexybayes_inla <- function(object, ...) {
  mi <- object$extras$model_info
  list(family = mi$family %||% "gaussian",
       link   = mi$link %||% "identity")
}

#' Population-level predictions from a per-row INLA fit
#'
#' Fixed-effect (population-level) predictions: the linear predictor is
#' `X beta` with random effects held at their population mean (zero).
#' On the identity link the response- and link-scale predictions
#' coincide. This is the prediction surface \pkg{marginaleffects} uses
#' for average predictions and slopes.
#'
#' @param object A `flexybayes_inla` fit.
#' @param newdata Optional data frame; defaults to the fit data.
#' @param type `"response"` or `"link"`.
#' @param se.fit Logical: also return delta-method standard errors from
#'   the fixed-effect covariance.
#' @param ... Ignored.
#' @return A numeric vector of predictions, or a list `fit` / `se.fit`
#'   when `se.fit = TRUE`.
#' @export
predict.flexybayes_inla <- function(object, newdata = NULL,
                                    type = c("response", "link"),
                                    se.fit = FALSE, ...) {
  type <- match.arg(type)
  fam  <- family(object)
  if (!identical(fam$link, "identity"))
    stop("predict.flexybayes_inla() currently supports the identity ",
         "link only; this fit uses link '", fam$link, "'. Work with ",
         "the posterior draws via fb_as_draws_simple() for non-identity ",
         "links.", call. = FALSE)

  if (is.null(newdata)) newdata <- object$data
  trms  <- stats::delete.response(stats::terms(formula(object)))
  bhat  <- coef(object)
  X     <- .fb_fixef_model_matrix(trms, newdata, names(bhat), object$data)
  eta   <- as.numeric(X %*% bhat)

  if (!se.fit) return(eta)
  V  <- vcov(object)
  se <- sqrt(rowSums((X %*% V) * X))
  list(fit = eta, se.fit = se)
}
