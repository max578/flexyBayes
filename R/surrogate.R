# =============================================================================
# surrogate.R -- the C7 surrogate seam: emulate a simulator from an ensemble,
# preserving predictive uncertainty.
#
# The methods-intense payoff downstream of C5: a surrogate maps parameter sets
# (X = ensemble$params) to outputs (Y = ensemble$outputs) so the expensive
# forward model can be replaced by a fast emulator -- AND it reports a
# predictive DISTRIBUTION (mean + sd), not a point, so the uncertainty an
# inverse/calibration step needs is not silently destroyed (the
# "distribution-preserving surrogate" the constellation's methods thesis names).
#
# flexyBayes owns the surrogate CONTRACT (inst/surrogate_contract.md) + a
# registry + a self-contained REFERENCE surrogate (random Fourier features +
# Bayesian linear regression, evidence-optimised UQ). kernR's CME /
# dist_regression and PESTO's GP / RFF surrogates are richer CONFORMING
# implementations that register here -- never reimplemented (the constellation
# "contracts not internals" rule, mirroring C1 / C5).
# =============================================================================

# ---- the reference surrogate: RFF + Bayesian linear regression --------------
# For an RBF kernel k(x,x') = exp(-||x-x'||^2 / (2 l^2)), random Fourier
# features phi(x) = sqrt(2/D) cos(Wx + b), W ~ N(0, l^-2 I), b ~ U(0, 2pi) give
# phi(x).phi(x') ~ k. A Bayesian linear model on phi (prior beta ~ N(0, a^-1 I),
# noise precision t) then has a closed-form predictive mean + variance; a + t
# are set by MacKay evidence maximisation, so the predictive sd is calibrated
# rather than an arbitrary ridge. One model per output column.

# Median-heuristic lengthscale on the (already standardised) design.
.rff_lengthscale <- function(x) {
  n <- nrow(x)
  if (n > 400L) {
    x <- x[sample.int(n, 400L), , drop = FALSE]
  }
  d <- stats::dist(x)
  l <- stats::median(d[d > 0])
  if (!is.finite(l) || l <= 0) {
    l <- 1.0
  }
  l
}

# Fit one output: returns the pieces predict needs. Evidence (a, t) via the
# MacKay fixed point (Bishop 3.91-3.95) on the RFF design.
.rff_fit_one <- function(phi, y) {
  n <- nrow(phi)
  d <- ncol(phi)
  y_mean <- mean(y)
  y_sd <- stats::sd(y)
  if (!is.finite(y_sd) || y_sd <= 0) {
    y_sd <- 1.0
  }
  ys <- (y - y_mean) / y_sd

  ptp <- crossprod(phi) # d x d
  pty <- crossprod(phi, ys) # d x 1
  ev <- eigen(ptp, symmetric = TRUE, only.values = TRUE)$values
  ev[ev < 0] <- 0

  a <- 1.0 # prior precision
  t <- 1.0 # noise precision
  m <- rep(0, d)
  for (iter in seq_len(100L)) {
    A <- t * ptp + diag(a, d)
    amat <- chol2inv(chol(A))
    m <- t * as.numeric(amat %*% pty)
    lam <- t * ev
    gamma <- sum(lam / (lam + a))
    mtm <- sum(m^2)
    a_new <- if (mtm > 0) gamma / mtm else a
    resid <- sum((ys - phi %*% m)^2)
    t_new <- if ((n - gamma) > 0 && resid > 0) (n - gamma) / resid else t
    if (abs(a_new - a) < 1e-6 * a && abs(t_new - t) < 1e-6 * t) {
      a <- a_new
      t <- t_new
      break
    }
    a <- a_new
    t <- t_new
  }
  A <- t * ptp + diag(a, d)
  amat <- chol2inv(chol(A))
  m <- t * as.numeric(amat %*% pty)
  list(
    m = m,
    amat = amat,
    noise_var = 1 / t,
    y_mean = y_mean,
    y_sd = y_sd
  )
}

.rff_features <- function(x, w, b) {
  d <- nrow(w)
  proj <- x %*% t(w) + matrix(b, nrow(x), d, byrow = TRUE)
  sqrt(2 / d) * cos(proj)
}

# ---- the surrogate registry (extensibility seam) ----------------------------
# method -> fit function. kernR registers "cme", PESTO registers "gp" / "rff_gp"
# from their own packages; flexyBayes ships "rff" (the self-contained default).

.surrogate_registry <- new.env(parent = emptyenv())

#' Register a surrogate-fitting method
#'
#' Extends [fit_surrogate()] with a new conforming surrogate (contract C7,
#' `inst/surrogate_contract.md`) without modifying flexyBayes. The fit function
#' takes the standardised design `x` (parameter sets), the response matrix `y`
#' (outputs), and `...`, and returns an object with a `predict()` method
#' yielding a per-output predictive mean and sd. This is how kernR's CME /
#' dist_regression and PESTO's GP surrogates plug in.
#'
#' @param method A single string naming the method.
#' @param fit_fn A function `function(x, y, ...) -> <surrogate model>`.
#' @return Invisibly `NULL`.
#' @export
register_surrogate <- function(method, fit_fn) {
  if (!is.character(method) || length(method) != 1L || !nzchar(method)) {
    stop(
      "register_surrogate(): `method` must be a single non-empty string.",
      call. = FALSE
    )
  }
  if (!is.function(fit_fn)) {
    stop("register_surrogate(): `fit_fn` must be a function.", call. = FALSE)
  }
  assign(method, fit_fn, envir = .surrogate_registry)
  invisible(NULL)
}

.surrogate_methods <- function() {
  c("rff", sort(ls(envir = .surrogate_registry, all.names = FALSE)))
}

# ---- the headline verb ------------------------------------------------------

#' Fit a distribution-preserving surrogate to a simulation ensemble
#'
#' Trains an emulator mapping the ensemble's parameter sets
#' (`ensemble$params`, the design `X`) to its outputs (`ensemble$outputs`, the
#' responses `Y`), so an expensive forward model can be replaced by a fast
#' surrogate that still reports predictive **uncertainty** (mean + sd per
#' output) -- the property a calibration / inverse step needs preserved
#' (contract C7, `inst/surrogate_contract.md`). The ensemble is ingested through
#' C5 ([as_fb_ensemble()]), so any conforming producer works.
#'
#' The built-in `method = "rff"` (default) is a self-contained random-Fourier-
#' features Bayesian linear surrogate with evidence-optimised predictive
#' variance -- one model per output. Richer methods (kernR's CME, PESTO's GP)
#' register via [register_surrogate()].
#'
#' @param ensemble A C5 ensemble source (an `fb_ensemble`, a PESTO manifest, a
#'   `list(params, outputs)`, or a path).
#' @param method One of the registered methods; `"rff"` (default) is always
#'   available. See [register_surrogate()].
#' @param outputs Optional character vector selecting output columns to emulate;
#'   `NULL` (default) emulates all of them.
#' @param n_features Number of random Fourier features for `method = "rff"`.
#' @param seed Integer RNG seed for the random features (reproducibility).
#' @param ... Passed to a registered method's fit function.
#'
#' @return An object of class `c("fb_surrogate", "list")` with a
#'   [predict.fb_surrogate()] method.
#' @seealso [predict.fb_surrogate()], [register_surrogate()],
#'   [as_fb_ensemble()].
#' @examples
#' set.seed(1)
#' x <- data.frame(a = runif(120, -2, 2), b = runif(120, -2, 2))
#' e <- fb_ensemble(
#'   params = x,
#'   outputs = data.frame(y = sin(x$a) + 0.5 * x$b^2 + rnorm(120, 0, 0.05))
#' )
#' s <- fit_surrogate(e)
#' predict(s, data.frame(a = 0, b = 1))
#' @export
fit_surrogate <- function(
  ensemble,
  method = NULL,
  outputs = NULL,
  n_features = 256L,
  seed = 1L,
  ...
) {
  e <- as_fb_ensemble(ensemble)
  method <- method %||% "rff"
  if (!method %in% .surrogate_methods()) {
    stop(
      "fit_surrogate(): unknown method '",
      method,
      "'. Available: ",
      paste(.surrogate_methods(), collapse = ", "),
      " (register more via register_surrogate()).",
      call. = FALSE
    )
  }

  x_num <- vapply(e$params, is.numeric, logical(1L))
  x <- as.matrix(e$params[, x_num, drop = FALSE])
  if (ncol(x) == 0L) {
    stop(
      "fit_surrogate(): the ensemble has no numeric parameter columns.",
      call. = FALSE
    )
  }
  y_df <- e$outputs
  if (!is.null(outputs)) {
    miss <- setdiff(outputs, colnames(y_df))
    if (length(miss) > 0L) {
      stop(
        "fit_surrogate(): outputs not in the ensemble: ",
        paste(miss, collapse = ", "),
        ".",
        call. = FALSE
      )
    }
    y_df <- y_df[, outputs, drop = FALSE]
  }
  y_num <- vapply(y_df, is.numeric, logical(1L))
  y <- as.matrix(y_df[, y_num, drop = FALSE])
  if (ncol(y) == 0L) {
    stop(
      "fit_surrogate(): the ensemble has no numeric output columns.",
      call. = FALSE
    )
  }

  # Standardise the design (store the transform for predict).
  x_center <- colMeans(x)
  x_scale <- apply(x, 2L, stats::sd)
  x_scale[!is.finite(x_scale) | x_scale <= 0] <- 1.0
  xs <- scale(x, center = x_center, scale = x_scale)

  if (identical(method, "rff")) {
    p <- ncol(xs)
    d <- as.integer(n_features)
    lengthscale <- .rff_lengthscale(xs)
    # deterministic random features (seeded; restore RNG state on exit)
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
      on.exit(assign(".Random.seed", old_seed, envir = .GlobalEnv), add = TRUE)
    }
    set.seed(seed)
    w <- matrix(stats::rnorm(d * p, sd = 1 / lengthscale), d, p)
    b <- stats::runif(d, 0, 2 * pi)
    phi <- .rff_features(xs, w, b)
    models <- lapply(seq_len(ncol(y)), function(j) .rff_fit_one(phi, y[, j]))
    names(models) <- colnames(y)
    fitobj <- list(w = w, b = b, models = models, lengthscale = lengthscale)
  } else {
    fit_fn <- get(method, envir = .surrogate_registry, inherits = FALSE)
    fitobj <- fit_fn(xs, y, ...)
  }

  structure(
    list(
      method = method,
      fit = fitobj,
      param_names = colnames(x),
      output_names = colnames(y),
      x_center = x_center,
      x_scale = x_scale,
      n_train = nrow(x),
      provenance = e$provenance
    ),
    class = c("fb_surrogate", "list")
  )
}

# ---- prediction (the distribution-preserving contract) ----------------------

#' Predict from a flexyBayes surrogate (mean + sd per output)
#'
#' Returns the surrogate's predictive distribution at new parameter sets: a
#' `data.frame` carrying, for each emulated output `<o>`, a `<o>_mean` and a
#' `<o>_sd` column. Reporting the predictive sd -- not only the mean -- is the
#' contract-C7 distribution-preserving requirement.
#'
#' @param object An `fb_surrogate` from [fit_surrogate()].
#' @param newdata A `data.frame` of new parameter sets; must contain the
#'   surrogate's `param_names` columns.
#' @param ... Unused.
#' @return A `data.frame` with `<output>_mean` and `<output>_sd` columns, one
#'   row per row of `newdata`.
#' @export
predict.fb_surrogate <- function(object, newdata, ...) {
  if (missing(newdata) || !is.data.frame(newdata)) {
    stop(
      "predict.fb_surrogate(): `newdata` must be a data.frame.",
      call. = FALSE
    )
  }
  miss <- setdiff(object$param_names, colnames(newdata))
  if (length(miss) > 0L) {
    stop(
      "predict.fb_surrogate(): newdata missing parameter column(s): ",
      paste(miss, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  xnew <- as.matrix(newdata[, object$param_names, drop = FALSE])
  xs <- scale(xnew, center = object$x_center, scale = object$x_scale)

  if (!identical(object$method, "rff")) {
    return(stats::predict(object$fit, newdata, ...))
  }

  phi <- .rff_features(xs, object$fit$w, object$fit$b)
  out <- list()
  for (nm in object$output_names) {
    mdl <- object$fit$models[[nm]]
    mean_s <- as.numeric(phi %*% mdl$m)
    # predictive variance: noise + feature-projected posterior variance
    var_s <- mdl$noise_var +
      rowSums((phi %*% mdl$amat) * phi)
    out[[paste0(nm, "_mean")]] <- mean_s * mdl$y_sd + mdl$y_mean
    out[[paste0(nm, "_sd")]] <- sqrt(pmax(var_s, 0)) * mdl$y_sd
  }
  as.data.frame(out, stringsAsFactors = FALSE)
}

# ---- display ----------------------------------------------------------------

#' @export
print.fb_surrogate <- function(x, ...) {
  cat("-- fb_surrogate (distribution-preserving emulator, C7) -----\n")
  cat("  method : ", x$method, " | train sets: ", x$n_train, "\n", sep = "")
  cat(
    "  params : ",
    length(x$param_names),
    " (",
    paste(utils::head(x$param_names, 6L), collapse = ", "),
    ")\n",
    sep = ""
  )
  cat(
    "  outputs: ",
    length(x$output_names),
    " (",
    paste(utils::head(x$output_names, 6L), collapse = ", "),
    ")\n",
    sep = ""
  )
  cat("  predict(): per-output <name>_mean + <name>_sd\n")
  cat("------------------------------------------------------------\n")
  invisible(x)
}
