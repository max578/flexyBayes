# emit_inla -- flexyBayes INLA backend emit (deliverable 5 partial).
#
# v0.1 MINIMUM SUBSET: takes an fb_terms object (the IR --
# intermediate representation; see R/fb_terms.R) that has passed
# lgm_gate() and runs INLA -- Integrated Nested Laplace
# Approximations -- via INLA::inla() to produce a posterior fit.
#
# v0.1 supported model classes:
#   - Gaussian / binomial / binary / poisson / Gamma / beta /
#     lognormal / nbinomial families.
#   - Linear fixed effects (factor / continuous / interaction /
#     factor_interaction / I() expressions).
#   - Random intercepts via term type "simple" / "ide" / "id"
#     emitted as `f(group, model = "iid")`.
#   - Random walk / spline smoothers (term type "spline") emitted
#     as `f(var, model = "rw2")`.
#   - Heterogeneous residual via `at_units` -- v0.1 refused;
#     re-route via lgm_gate or backend = "greta".
#   - Spatial / GxE structured covariances -- v0.1 refused; route
#     via greta.
#
# Anything not in the supported set raises an INLA-side refusal
# pointing the user back to backend = "greta".
#
# Per project CLAUDE.md and design notes Q5, post-fit numerical-
# confirm gate (check 7) lives here: assert mode.status == 0;
# mlik finite. Failures escalate to a structured warning.
#
# INLA is not on CRAN; ships via inla.r-inla-download.org. Added to
# DESCRIPTION:Suggests with Additional_repositories declaration.

# ---------------------------------------------------------------- #
# Public-style entry -- internal in v0.1                           #
# ---------------------------------------------------------------- #

emit_inla <- function(fb,
                      data,
                      verbose      = TRUE,
                      return_code  = FALSE,
                      the_call     = NULL,
                      fixed        = NULL,
                      random       = NULL,
                      rcov         = NULL,
                      family       = NULL,
                      link         = NULL,
                      data_name    = NA_character_,
                      ...) {

  if (!is_fb_terms(fb))
    stop("`fb` must be an fb_terms object.", call. = FALSE)

  if (!requireNamespace("INLA", quietly = TRUE))
    stop("Package 'INLA' is required for backend = \"inla\". ",
         "Install via:\n",
         "  install.packages('INLA',\n",
         "    repos = c(CRAN = 'https://cran.r-project.org',\n",
         "             INLA = 'https://inla.r-inla-download.org/R/stable'),\n",
         "    dep = TRUE)",
         call. = FALSE)

  # Build INLA formula and family
  inla_form   <- .build_inla_formula(fb)
  inla_family <- .resolve_inla_family(fb)
  hyper_ctrl  <- if (inherits(fb$priors, "fb_prior"))
    priors_to_inla(fb$priors) else list()

  if (return_code)
    return(invisible(list(formula = inla_form,
                           family  = inla_family,
                           hyper   = hyper_ctrl)))

  if (verbose) {
    cat("\n-- flexyBayes: INLA fit ",
        paste(rep("-", 40), collapse = ""), "\n", sep = "")
    cat("  formula: ", deparse(inla_form), "\n", sep = "")
    cat("  family:  ", inla_family, "\n", sep = "")
    cat(paste(rep("-", 60), collapse = ""), "\n\n")
  }

  # Fit
  t0 <- proc.time()
  fit <- tryCatch(
    INLA::inla(
      formula         = inla_form,
      family          = inla_family,
      data            = data,
      control.compute = list(config = TRUE,
                              return.marginals = TRUE,
                              dic = TRUE, waic = TRUE),
      ...
    ),
    error = function(e)
      stop("INLA fit failed: ", conditionMessage(e), call. = FALSE)
  )
  elapsed <- unname((proc.time() - t0)["elapsed"])

  # Post-fit numerical-confirm gate (lgm_gate check 7)
  num_check <- .lgm_check_numerical(fit)
  if (!num_check$pass)
    warning("flexyBayes: INLA numerical-confirm gate flagged: ",
            paste(num_check$reasons, collapse = "; "),
            ". Treat the fit with caution.", call. = FALSE)

  # Wrap as a bayesreml_inla object
  structure(
    list(
      inla       = fit,
      fb         = fb,
      data       = data,
      num_check  = num_check,
      extras     = list(
        summary = list(
          fixed    = fit$summary.fixed,
          random   = fit$summary.random,
          hyperpar = fit$summary.hyperpar,
          fitted   = if (!is.null(fit$summary.fitted.values))
            utils::head(fit$summary.fitted.values) else NULL
        ),
        model_info = list(
          n_obs    = nrow(data),
          n_fixed  = if (!is.null(fit$summary.fixed))
                       nrow(fit$summary.fixed) else 0L,
          n_random = length(fit$summary.random),
          n_hyper  = if (!is.null(fit$summary.hyperpar))
                       nrow(fit$summary.hyperpar) else 0L,
          family   = inla_family,
          link     = fb$link
        ),
        call_info = list(
          fixed     = fixed,
          random    = random,
          rcov      = rcov,
          data_name = data_name,
          family    = family,
          link      = link
        ),
        run_time  = elapsed,
        the_call  = the_call,
        formula   = inla_form
      )
    ),
    class = c("bayesreml_inla", "list")
  )
}

# ---------------------------------------------------------------- #
# fb_terms -> INLA formula                                         #
# ---------------------------------------------------------------- #

.build_inla_formula <- function(fb) {
  rhs_terms <- character(0)

  # Intercept
  rhs_terms <- c(rhs_terms, if (fb$intercept) "1" else "0")

  # Fixed-effect terms
  for (term in fb$fixed_terms) {
    contrib <- switch(term$type,
      "factor"             = term$var,
      "continuous"         = term$var,
      "interaction"        = paste(term$vars, collapse = ":"),
      "factor_interaction" = paste(term$vars, collapse = ":"),
      "expression"         = term$label,
      stop("emit_inla() does not support fixed term type \"",
           term$type, "\". Use backend = \"greta\".",
           call. = FALSE)
    )
    rhs_terms <- c(rhs_terms, contrib)
  }

  # Random-effect terms via INLA's f()
  for (term in fb$random_terms) {
    contrib <- switch(term$type,
      "simple" = ,
      "ide"    = ,
      "id"     = paste0("f(", term$var, ", model = \"iid\")"),
      "spline" = paste0("f(", term$var, ", model = \"rw2\")"),
      stop("emit_inla() v0.1 does not support random term type \"",
           term$type, "\". Re-route via backend = \"greta\".",
           call. = FALSE)
    )
    rhs_terms <- c(rhs_terms, contrib)
  }

  # Heterogeneous residual / structured rcov
  for (term in fb$rcov_terms) {
    if (term$type != "units")
      stop("emit_inla() v0.1 does not support rcov term type \"",
           term$type, "\". INLA folds residual variance into the ",
           "likelihood; structured rcov refits via backend = \"greta\".",
           call. = FALSE)
  }

  rhs <- paste(rhs_terms, collapse = " + ")
  stats::as.formula(paste0(fb$response, " ~ ", rhs))
}

# ---------------------------------------------------------------- #
# fb$family -> INLA family name                                    #
# ---------------------------------------------------------------- #

.resolve_inla_family <- function(fb) {
  fam <- if (inherits(fb$family, "family"))
    fb$family$family else as.character(fb$family)
  switch(tolower(fam),
    "gaussian"          = "gaussian",
    "stdnormal"         = "stdnormal",
    "binomial"          = "binomial",
    "binary"            = "binomial",
    "poisson"           = "poisson",
    "negative_binomial" = "nbinomial",
    "negbinom"          = "nbinomial",
    "nbinomial"         = "nbinomial",
    "gamma"             = "gamma",
    "beta"              = "beta",
    "lognormal"         = "lognormal",
    "exponential"       = "exponential",
    fam
  )
}

# ---------------------------------------------------------------- #
# Post-fit numerical-confirm gate -- lgm_gate check 7              #
# ---------------------------------------------------------------- #

.lgm_check_numerical <- function(fit) {
  pass    <- TRUE
  reasons <- character(0)

  if (!is.null(fit$mode$mode.status) &&
      !isTRUE(fit$mode$mode.status == 0)) {
    pass <- FALSE
    reasons <- c(reasons,
                 paste0("INLA mode.status = ", fit$mode$mode.status,
                        " (non-zero indicates non-convergence)"))
  }

  if (!is.null(fit$mlik) && nrow(fit$mlik) > 0L) {
    if (!is.finite(fit$mlik[1, 1])) {
      pass <- FALSE
      reasons <- c(reasons, "marginal log-likelihood is non-finite")
    }
  }

  list(pass = pass, reasons = reasons)
}

# ---------------------------------------------------------------- #
# Print + summary methods for the bayesreml_inla wrapper           #
# ---------------------------------------------------------------- #

#' Print method for bayesreml_inla
#'
#' Internal S3 method. Brief one-screen summary of an INLA fit
#' produced via `fb(... backend = "inla")` or `emit_inla()`.
#'
#' @param x   a `bayesreml_inla` object.
#' @param ... unused.
#' @return invisibly returns `x`.
#' @keywords internal
#' @export
print.bayesreml_inla <- function(x, ...) {
  mi <- x$extras$model_info
  cat("Bayesian fit  [bayesreml_inla / INLA backend]\n")
  cat(strrep("-", 55), "\n")
  cat("  formula: ", deparse(x$extras$formula), "\n", sep = "")
  cat("  family:  ", mi$family, "\n", sep = "")
  cat("  n_obs:   ", mi$n_obs, "\n", sep = "")
  cat("  fixed:   ", mi$n_fixed, "\n", sep = "")
  cat("  random:  ", mi$n_random, "\n", sep = "")
  cat("  hyper:   ", mi$n_hyper, "\n", sep = "")
  cat("  runtime: ", round(x$extras$run_time, 2), " sec\n", sep = "")
  cat("  numerical confirm: ",
      if (isTRUE(x$num_check$pass)) "PASS" else "FAIL",
      if (!isTRUE(x$num_check$pass))
        paste0(" (", paste(x$num_check$reasons, collapse = "; "), ")")
      else "",
      "\n", sep = "")
  cat(strrep("-", 55), "\n")
  cat("  $inla -- raw INLA fit (use INLA's summary, plot, etc.)\n")
  cat("  $fb   -- the fb_terms IR used for dispatch\n")
  invisible(x)
}

#' Summary method for bayesreml_inla
#'
#' Returns the fixed / random / hyperpar posterior summary tables
#' produced by INLA. Internal S3 method.
#'
#' @param object a `bayesreml_inla` object.
#' @param ... unused.
#' @return invisibly returns the summary list.
#' @keywords internal
#' @export
summary.bayesreml_inla <- function(object, ...) {
  cat("Bayesian fit summary  [bayesreml_inla / INLA backend]\n")
  cat(strrep("-", 60), "\n")
  cat("Fixed effects:\n")
  if (!is.null(object$extras$summary$fixed) &&
      nrow(object$extras$summary$fixed) > 0L) {
    print(round(object$extras$summary$fixed, 4))
  } else cat("  (none)\n")
  cat("\nHyperparameters:\n")
  if (!is.null(object$extras$summary$hyperpar) &&
      nrow(object$extras$summary$hyperpar) > 0L) {
    print(round(object$extras$summary$hyperpar, 4))
  } else cat("  (none)\n")
  cat("\nRandom effects:\n")
  if (length(object$extras$summary$random) > 0L) {
    cat("  groups: ",
        paste(names(object$extras$summary$random), collapse = ", "),
        "\n", sep = "")
  } else cat("  (none)\n")
  cat(strrep("-", 60), "\n")
  invisible(object$extras$summary)
}
