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

  # Build INLA formula and family. priors_to_inla() returns a list
  # keyed by group / smoother var ("sigma" for residual). We thread
  # the per-term entries into f(..., hyper = list(prec = ...)) and
  # the "sigma" entry into control.family (residual precision).
  hyper_ctrl  <- if (inherits(fb$priors, "fb_prior"))
    priors_to_inla(fb$priors) else list()
  inla_form   <- .build_inla_formula(fb, hyper_ctrl = hyper_ctrl)
  inla_family <- .resolve_inla_family(fb)
  control_family <- .build_inla_control_family(hyper_ctrl,
                                                family = inla_family)

  if (return_code)
    return(invisible(list(formula        = inla_form,
                           family         = inla_family,
                           hyper          = hyper_ctrl,
                           control_family = control_family)))

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
      control.family  = control_family,
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

  # Wrap as a flexybayes_inla object
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
        # ADR 0018: thread the IR's smooth-objects slot through to the
        # extras so predict() on the INLA path can also use
        # mgcv::Predict.matrix() when smooths are present. The INLA
        # backend itself does not currently fit s() smooths via mgcv
        # (it uses INLA's own rw2 path), so this slot will normally be
        # an empty list; threaded for shape uniformity with emit_greta.
        parse_info = list(
          smooths = .collect_smooths(fb$random_terms)
        ),
        run_time  = elapsed,
        the_call  = the_call,
        formula   = inla_form
      )
    ),
    class = c("flexybayes_inla", "list")
  )
}

# ---------------------------------------------------------------- #
# fb_terms -> INLA formula                                         #
# ---------------------------------------------------------------- #

.build_inla_formula <- function(fb, hyper_ctrl = list()) {
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
      # ADR 0017: this stop() is an internal contract-violation
      # assertion. Under the new gate, .lgm_check_fixed_term_inla_support()
      # refuses any fixed term type outside the allowlist before
      # we reach here. A fired assertion means the gate and the
      # emit are out of sync -- a flexyBayes-side bug, not a
      # user-facing refusal.
      stop("lgm_gate broken contract: fixed term type \"",
           term$type, "\" reached emit_inla() despite a passing ",
           "gate. This is a flexyBayes internal bug -- the gate's ",
           ".lgm_check_fixed_term_inla_support() allowlist is out ",
           "of sync with .build_inla_formula()'s switch(). Please ",
           "file an issue.",
           call. = FALSE)
    )
    rhs_terms <- c(rhs_terms, contrib)
  }

  # Random-effect terms via INLA's f(). When the user-supplied
  # priors_to_inla() output names a hyperparameter for this term,
  # splice it in as `hyper = list(prec = list(prior = ..., param = ...))`
  # so the user's prior actually reaches INLA.
  for (term in fb$random_terms) {
    key <- switch(term$type,
      "simple" = ,
      "ide"    = ,
      "id"     = term$var,
      "spline" = term$var,
      NULL
    )
    model_name <- switch(term$type,
      "simple" = ,
      "ide"    = ,
      "id"     = "iid",
      "spline" = "rw2",
      # ADR 0017: internal contract-violation assertion. See the
      # fixed-term site above for the rationale; the gate's
      # .lgm_check_random_term_inla_support() owns this guard.
      stop("lgm_gate broken contract: random term type \"",
           term$type, "\" reached emit_inla() despite a passing ",
           "gate. This is a flexyBayes internal bug -- the gate's ",
           ".lgm_check_random_term_inla_support() allowlist is ",
           "out of sync with .build_inla_formula()'s switch(). ",
           "Please file an issue.",
           call. = FALSE)
    )
    hyper_str <- .inla_hyper_arg(hyper_ctrl[[key]])
    contrib   <- paste0("f(", term$var, ", model = \"", model_name, "\"",
                        if (nzchar(hyper_str)) paste0(", ", hyper_str) else "",
                        ")")
    rhs_terms <- c(rhs_terms, contrib)
  }

  # Heterogeneous residual / structured rcov
  for (term in fb$rcov_terms) {
    if (term$type != "units")
      # ADR 0017: internal contract-violation assertion. See the
      # fixed-term site above for the rationale; the gate's
      # .lgm_check_rcov_term_inla_support() owns this guard.
      stop("lgm_gate broken contract: rcov term type \"",
           term$type, "\" reached emit_inla() despite a passing ",
           "gate. This is a flexyBayes internal bug -- the gate's ",
           ".lgm_check_rcov_term_inla_support() allowlist is out ",
           "of sync with .build_inla_formula()'s rcov guard. ",
           "Please file an issue.",
           call. = FALSE)
  }

  rhs <- paste(rhs_terms, collapse = " + ")
  stats::as.formula(paste0(fb$response, " ~ ", rhs))
}

# Build the `hyper = list(prec = list(prior = ..., param = ...))`
# substring spliced into a random-effect f() call. Returns "" when
# no entry is present so default INLA priors apply.
.inla_hyper_arg <- function(entry) {
  if (is.null(entry)) return("")
  prior <- entry$prior
  param <- entry$param
  if (is.null(prior)) return("")
  body <- paste0("prior = ", deparse(prior))
  if (length(param))
    body <- paste0(body, ", param = c(",
                   paste(param, collapse = ", "), ")")
  paste0("hyper = list(prec = list(", body, "))")
}

# Build the control.family list passed to INLA::inla(). When the
# user supplies an fb_prior() spec keyed under "sigma", attach it as
# the residual-precision hyperprior -- but only for families whose
# likelihood actually carries a precision hyperparameter (Gaussian,
# lognormal, gamma, beta, T). For Poisson, binomial, exponential
# etc. the likelihood has no `prec` hyperparameter and INLA refuses
# any control.family$hyper input, so we silently drop the sigma prior
# in that case (it is not a no-op for the model -- there is no such
# parameter to constrain). Returns an empty list when no residual
# prior is specified, so INLA's default loggamma applies for the
# Gaussian-family case where prec is the lone hyperparameter.
.build_inla_control_family <- function(hyper_ctrl, family) {
  entry <- hyper_ctrl[["sigma"]]
  if (is.null(entry)) return(list())
  families_with_prec <- c("gaussian", "stdnormal", "lognormal",
                           "gamma", "beta", "T", "logistic")
  if (!tolower(family) %in% families_with_prec) return(list())
  body <- entry[c("prior", "param")]
  body <- body[!vapply(body, is.null, logical(1))]
  list(hyper = list(prec = body))
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
# Print + summary methods for the flexybayes_inla wrapper          #
# ---------------------------------------------------------------- #

#' Print method for flexybayes_inla
#'
#' Internal S3 method. Brief one-screen summary of an INLA fit
#' produced via `fb(... backend = "inla")` or `emit_inla()`.
#'
#' @param x   a `flexybayes_inla` object.
#' @param ... unused.
#' @return invisibly returns `x`.
#' @keywords internal
#' @export
print.flexybayes_inla <- function(x, ...) {
  mi <- x$extras$model_info
  cat("Bayesian fit  [flexybayes_inla / INLA backend]\n")
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

#' Summary method for flexybayes_inla
#'
#' Returns the fixed / random / hyperpar posterior summary tables
#' produced by INLA. Internal S3 method.
#'
#' @param object a `flexybayes_inla` object.
#' @param ... unused.
#' @return invisibly returns the summary list.
#' @keywords internal
#' @export
summary.flexybayes_inla <- function(object, ...) {
  cat("Bayesian fit summary  [flexybayes_inla / INLA backend]\n")
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
