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

# Lengthscales on the (already standardised) design. With `ard = TRUE` a
# per-dimension median-heuristic vector (the ARD starting point); with
# `ard = FALSE` a single pooled median repeated across dimensions (the
# isotropic reference). Subsamples large designs for the distance computation.
.rff_lengthscales <- function(x, ard = TRUE) {
  p <- ncol(x)
  n <- nrow(x)
  if (n > 400L) {
    x <- x[sample.int(n, 400L), , drop = FALSE]
  }
  .med <- function(v) {
    d <- stats::dist(v)
    l <- stats::median(d[d > 0])
    if (!is.finite(l) || l <= 0) 1.0 else l
  }
  if (!ard) {
    return(rep(.med(x), p))
  }
  vapply(seq_len(p), function(k) .med(x[, k, drop = FALSE]), numeric(1L))
}

# Log marginal likelihood of the RFF Bayesian-linear model for one standardised
# output, prior precision `a` and noise precision `t` held fixed (Bishop 3.86).
# Used as the per-dimension relevance objective for evidence-ARD.
.rff_log_eml <- function(phi, ys, a, t) {
  n <- nrow(phi)
  d <- ncol(phi)
  amat <- t * crossprod(phi) + diag(a, d)
  ch <- tryCatch(chol(amat), error = function(e) NULL)
  if (is.null(ch)) {
    return(-Inf)
  }
  pty <- crossprod(phi, ys)
  m <- t * backsolve(ch, backsolve(ch, pty, transpose = TRUE))
  data_fit <- t * sum((ys - phi %*% m)^2) + a * sum(m^2)
  0.5 *
    d *
    log(a) +
    0.5 * n * log(t) -
    0.5 * data_fit -
    sum(log(diag(ch))) -
    0.5 * n * log(2 * pi)
}

# A short MacKay evidence loop returning (a, t) for one standardised output --
# the prior/noise precisions the ARD objective holds fixed while it varies the
# lengthscales. The shared kernel of the full-data fit lives in .rff_fit_one().
.rff_evidence_at <- function(phi, ys, iters = 40L) {
  n <- nrow(phi)
  d <- ncol(phi)
  ptp <- crossprod(phi)
  pty <- crossprod(phi, ys)
  ev <- eigen(ptp, symmetric = TRUE, only.values = TRUE)$values
  ev[ev < 0] <- 0
  a <- 1.0
  t <- 1.0
  for (iter in seq_len(iters)) {
    amat <- chol2inv(chol(t * ptp + diag(a, d)))
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
  list(a = a, t = t)
}

# Evidence-ARD: learn per-dimension lengthscales by maximising the total RFF
# Bayesian-linear log marginal likelihood summed over outputs, with the
# prior/noise precisions held at their isotropic-fit values (one alternating
# evidence step). Irrelevant inputs -- along which the response is flat --
# raise the evidence at a long lengthscale, so the optimiser stretches them and
# they drop out of the kernel. Deterministic given the seeded features; falls
# back to the isotropic start on any failure. ARD is vacuous in one dimension.
.ard_learn_lengthscales <- function(xs, w0, b, ys, l0, at_fixed) {
  if (ncol(xs) < 2L) {
    return(l0)
  }
  obj <- function(log_invl) {
    invl <- exp(log_invl)
    phi <- .rff_features(xs, sweep(w0, 2L, invl, "*"), b)
    tot <- 0
    for (j in seq_len(ncol(ys))) {
      tot <- tot + .rff_log_eml(phi, ys[, j], at_fixed[[j]]$a, at_fixed[[j]]$t)
    }
    if (is.finite(tot)) -tot else 1e6
  }
  start <- log(1 / l0)
  res <- tryCatch(
    stats::optim(
      start,
      obj,
      method = "Nelder-Mead",
      control = list(maxit = 80L, reltol = 1e-3)
    ),
    error = function(e) NULL
  )
  if (is.null(res) || !is.finite(res$value)) {
    return(l0)
  }
  # keep the learned inverse-lengthscales within ~e^4 of the heuristic start so
  # a degenerate evidence surface cannot send a dimension to 0 or Inf.
  invl <- exp(pmax(pmin(res$par, start + 4), start - 4))
  1 / invl
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

# ---- the joint (multi-output) fit: a distribution-preserving emulator -------
# The independent path (one .rff_fit_one per column) preserves only the output
# MARGINALS. The joint path preserves the output COVARIANCE: a matrix-normal --
# inverse-Wishart Bayesian multivariate regression on the shared feature map,
# Y = Phi B + E with rows of E ~ N(0, Sigma). With a shared prior precision `a`
# on the rows of B, the posterior predictive at phi* is a matrix-t whose
# covariance factorises as a scalar epistemic inflation times a single shared
# noise covariance: Cov(x*) = (1 + phi*' A^-1 phi*) Sigma, A = Phi'Phi + aI.
# Its diagonal is the per-output predictive variance (so the marginal `<o>_sd`
# contract is unchanged); the off-diagonals are the cross-output covariance the
# joint-distribution-preserving thesis and the ES-MDA consumer need. `a` is set
# by a pooled MacKay evidence step; Sigma_hat is the posterior noise covariance.
.rff_fit_joint <- function(phi, y) {
  n <- nrow(phi)
  d <- ncol(phi)
  k <- ncol(y)
  y_mean <- colMeans(y)
  y_sd <- apply(y, 2L, stats::sd)
  y_sd[!is.finite(y_sd) | y_sd <= 0] <- 1.0
  ys <- sweep(sweep(y, 2L, y_mean, "-"), 2L, y_sd, "/") # n x k standardised

  ptp <- crossprod(phi) # d x d (shared design)
  pty <- crossprod(phi, ys) # d x k
  ev <- eigen(ptp, symmetric = TRUE, only.values = TRUE)$values
  ev[ev < 0] <- 0

  # Pooled MacKay for the shared prior precision a: the effective number of
  # well-determined parameters is k * gamma (gamma per output, shared design),
  # balanced against the total coefficient energy ||B||_F^2.
  a <- 1.0
  bmat <- matrix(0, d, k)
  for (iter in seq_len(100L)) {
    amat <- chol2inv(chol(ptp + diag(a, d)))
    bmat <- amat %*% pty
    gamma <- sum(ev / (ev + a))
    bnorm <- sum(bmat^2)
    a_new <- if (bnorm > 0) (k * gamma) / bnorm else a
    if (abs(a_new - a) < 1e-6 * a) {
      a <- a_new
      break
    }
    a <- a_new
  }
  amat <- chol2inv(chol(ptp + diag(a, d)))
  bmat <- amat %*% pty # d x k posterior mean coefficients
  resid <- ys - phi %*% bmat # n x k
  gamma <- sum(ev / (ev + a))
  dof <- max(n - gamma, 1)
  sigma <- crossprod(resid) / dof # k x k noise covariance (standardised scale)
  list(
    joint = TRUE,
    bmat = bmat,
    amat = amat,
    sigma = sigma,
    y_mean = y_mean,
    y_sd = y_sd
  )
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
#' variance. By default it uses **ARD** lengthscales (per-input relevance
#' learned from the evidence) and a **joint** multi-output fit that preserves
#' the predictive covariance across outputs (not only the marginals) -- the
#' distribution-preserving property the calibration / inverse consumers rely on.
#' Richer methods (kernR's CME, PESTO's GP) register via [register_surrogate()].
#'
#' @param ensemble A C5 ensemble source (an `fb_ensemble`, a PESTO manifest, a
#'   `list(params, outputs)`, or a path).
#' @param method One of the registered methods; `"rff"` (default) is always
#'   available. See [register_surrogate()].
#' @param outputs Optional character vector selecting output columns to emulate;
#'   `NULL` (default) emulates all of them.
#' @param n_features Number of random Fourier features for `method = "rff"`.
#' @param ard Logical; for `method = "rff"`, learn per-dimension (automatic
#'   relevance determination) lengthscales by maximising the model evidence
#'   (default `TRUE`). `FALSE` uses a single isotropic median-heuristic
#'   lengthscale. Vacuous with one parameter.
#' @param joint Logical; for `method = "rff"` with two or more outputs, fit a
#'   joint multi-output model preserving the cross-output predictive covariance
#'   (default `TRUE`). `FALSE` fits one independent model per output (marginals
#'   only). The per-output `<o>_sd` contract is unchanged either way; only the
#'   off-diagonal covariance (exposed by `predict(..., cov = TRUE)`) differs.
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
  ard = TRUE,
  joint = TRUE,
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
    # deterministic random features (seeded; restore RNG state on exit)
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
      on.exit(assign(".Random.seed", old_seed, envir = .GlobalEnv), add = TRUE)
    }
    set.seed(seed)
    lengthscales <- .rff_lengthscales(xs, ard = ard)

    if (ard && p >= 2L) {
      # Learn relevance on a subsample with a smaller feature set (cheap), then
      # build the full features at the learned per-dimension lengthscales.
      ns <- nrow(xs)
      idx <- if (ns > 200L) sample.int(ns, 200L) else seq_len(ns)
      xsub <- xs[idx, , drop = FALSE]
      ysub <- scale(y[idx, , drop = FALSE])
      ysub[!is.finite(ysub)] <- 0
      ds <- min(d, 128L)
      w0s <- matrix(stats::rnorm(ds * p), ds, p)
      bs <- stats::runif(ds, 0, 2 * pi)
      phi_iso <- .rff_features(xsub, sweep(w0s, 2L, 1 / lengthscales, "*"), bs)
      at_fixed <- lapply(
        seq_len(ncol(ysub)),
        function(j) .rff_evidence_at(phi_iso, ysub[, j])
      )
      lengthscales <- .ard_learn_lengthscales(
        xsub,
        w0s,
        bs,
        ysub,
        lengthscales,
        at_fixed
      )
    }

    w0 <- matrix(stats::rnorm(d * p), d, p)
    b <- stats::runif(d, 0, 2 * pi)
    w <- sweep(w0, 2L, 1 / lengthscales, "*")
    phi <- .rff_features(xs, w, b)

    if (joint && ncol(y) >= 2L) {
      fitobj <- .rff_fit_joint(phi, y)
    } else {
      models <- lapply(seq_len(ncol(y)), function(j) .rff_fit_one(phi, y[, j]))
      names(models) <- colnames(y)
      fitobj <- list(joint = FALSE, models = models)
    }
    fitobj$w <- w
    fitobj$b <- b
    fitobj$lengthscales <- lengthscales
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

# Assemble a per-output <o>_mean / <o>_sd data.frame from mean/sd matrices.
.surrogate_meansd <- function(mean_mat, sd_mat, output_names) {
  out <- list()
  for (j in seq_along(output_names)) {
    nm <- output_names[j]
    out[[paste0(nm, "_mean")]] <- mean_mat[, j]
    out[[paste0(nm, "_sd")]] <- sd_mat[, j]
  }
  as.data.frame(out, stringsAsFactors = FALSE)
}

# Promote a marginal <o>_mean / <o>_sd data.frame (a conformer or independent
# fit) to an fb_surrogate_prediction with a diagonal per-row covariance -- the
# honest fallback when only marginals are available (cov = TRUE on a
# marginals-only surrogate).
.prediction_from_marginals <- function(df, output_names) {
  n <- nrow(df)
  k <- length(output_names)
  mean_mat <- matrix(0, n, k, dimnames = list(NULL, output_names))
  carr <- array(
    0,
    dim = c(k, k, n),
    dimnames = list(output_names, output_names, NULL)
  )
  for (j in seq_along(output_names)) {
    nm <- output_names[j]
    mean_mat[, j] <- df[[paste0(nm, "_mean")]]
    sdj <- df[[paste0(nm, "_sd")]]
    for (i in seq_len(n)) {
      carr[j, j, i] <- sdj[i]^2
    }
  }
  structure(
    list(mean = mean_mat, cov = carr, output_names = output_names),
    class = "fb_surrogate_prediction"
  )
}

#' Predict from a flexyBayes surrogate (mean + sd per output)
#'
#' Returns the surrogate's predictive distribution at new parameter sets. By
#' default a `data.frame` carrying, for each emulated output `<o>`, a `<o>_mean`
#' and a `<o>_sd` column. Reporting the predictive sd -- not only the mean -- is
#' the contract-C7 distribution-preserving requirement.
#'
#' With `cov = TRUE` it returns the **joint** predictive distribution: an
#' `fb_surrogate_prediction` carrying the predictive mean matrix and a per-row
#' cross-output covariance array (contract C7 clause 4). A joint `rff` surrogate
#' supplies the full covariance; a marginals-only surrogate (independent `rff`,
#' or a conformer reporting only `<o>_sd`) returns a diagonal covariance built
#' from the marginal sds, so the call is always honest.
#'
#' @param object An `fb_surrogate` from [fit_surrogate()].
#' @param newdata A `data.frame` of new parameter sets; must contain the
#'   surrogate's `param_names` columns.
#' @param cov Logical; if `TRUE` return an `fb_surrogate_prediction` with the
#'   per-row cross-output predictive covariance (default `FALSE`).
#' @param ... Unused.
#' @return With `cov = FALSE` (default) a `data.frame` with `<output>_mean` and
#'   `<output>_sd` columns, one row per row of `newdata`. With `cov = TRUE` an
#'   `fb_surrogate_prediction` (`mean`, `cov`, `output_names`).
#' @export
predict.fb_surrogate <- function(object, newdata, cov = FALSE, ...) {
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
  onames <- object$output_names

  if (!identical(object$method, "rff")) {
    # A registered conformer is trained on the *standardised* design --
    # fit_surrogate() hands the standardised `xs` to the fit function -- so it
    # must predict on the same scale. Pass the standardised newdata (keyed by
    # param_names), not the raw newdata, or train and predict would disagree on
    # scale. The conformer's predict method returns the per-output `<o>_mean` /
    # `<o>_sd` data.frame (contract C7 clause 2).
    xs_df <- as.data.frame(xs)
    colnames(xs_df) <- object$param_names
    df <- stats::predict(object$fit, xs_df, ...)
    if (!isTRUE(cov)) {
      return(df)
    }
    return(.prediction_from_marginals(df, onames))
  }

  phi <- .rff_features(xs, object$fit$w, object$fit$b)
  n_new <- nrow(phi)
  k <- length(onames)
  mean_mat <- matrix(0, n_new, k, dimnames = list(NULL, onames))
  sd_mat <- matrix(0, n_new, k, dimnames = list(NULL, onames))

  if (isTRUE(object$fit$joint)) {
    jt <- object$fit
    mean_s <- phi %*% jt$bmat # n_new x k (standardised)
    infl <- 1 + rowSums((phi %*% jt$amat) * phi) # epistemic inflation per row
    mean_mat[] <- sweep(sweep(mean_s, 2L, jt$y_sd, "*"), 2L, jt$y_mean, "+")
    # noise covariance on the original output scale
    sig0 <- diag(jt$y_sd, k) %*% jt$sigma %*% diag(jt$y_sd, k)
    sd_mat[] <- outer(sqrt(infl), sqrt(pmax(diag(sig0), 0)))
  } else {
    for (j in seq_len(k)) {
      mdl <- object$fit$models[[onames[j]]]
      mean_s <- as.numeric(phi %*% mdl$m)
      var_s <- mdl$noise_var + rowSums((phi %*% mdl$amat) * phi)
      mean_mat[, j] <- mean_s * mdl$y_sd + mdl$y_mean
      sd_mat[, j] <- sqrt(pmax(var_s, 0)) * mdl$y_sd
    }
  }

  if (!isTRUE(cov)) {
    return(.surrogate_meansd(mean_mat, sd_mat, onames))
  }

  if (isTRUE(object$fit$joint)) {
    sig0 <- diag(object$fit$y_sd, k) %*%
      object$fit$sigma %*%
      diag(object$fit$y_sd, k)
    infl <- 1 + rowSums((phi %*% object$fit$amat) * phi)
    # slice i is infl[i] * sig0 -- outer() builds the k x k x n_new array
    carr <- outer(sig0, infl)
  } else {
    # slice i is the diagonal of the per-output variances at row i; build the
    # flat k*k columns then reshape, so the result is always a k x k x n_new
    # array (vapply with a matrix template collapses dims when k == 1).
    flat <- vapply(
      seq_len(n_new),
      function(i) diag(sd_mat[i, ]^2, k),
      numeric(k * k)
    )
    carr <- array(flat, dim = c(k, k, n_new))
  }
  dimnames(carr) <- list(onames, onames, NULL)
  structure(
    list(mean = mean_mat, cov = carr, output_names = onames),
    class = "fb_surrogate_prediction"
  )
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
  if (identical(x$method, "rff")) {
    structure_lab <- if (isTRUE(x$fit$joint)) {
      "joint (cross-output covariance)"
    } else {
      "independent (marginals)"
    }
    ard_lab <- if (length(x$fit$lengthscales) > 1L) "ARD" else "isotropic"
    cat("  rff fit: ", structure_lab, " | ", ard_lab, "\n", sep = "")
  }
  cat(
    "  predict(): per-output <name>_mean + <name>_sd (cov = TRUE for joint)\n"
  )
  cat("------------------------------------------------------------\n")
  invisible(x)
}

#' @export
print.fb_surrogate_prediction <- function(x, ...) {
  k <- length(x$output_names)
  n <- nrow(x$mean)
  cat(
    "-- fb_surrogate_prediction (joint predictive, C7) ----------\n",
    sep = ""
  )
  cat("  rows: ", n, " | outputs: ", k, "\n", sep = "")
  cat(
    "  $mean (",
    n,
    " x ",
    k,
    "), $cov (",
    k,
    " x ",
    k,
    " x ",
    n,
    ")\n",
    sep = ""
  )
  cat("------------------------------------------------------------\n")
  invisible(x)
}
