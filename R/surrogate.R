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

# Held-out predictive log-density of one standardised output: fit the RFF
# Bayesian-linear model on a training split (evidence (a, t) from the training
# rows), score the validation rows' predictive Normal density. Used by the
# cross-validated ARD objective -- a too-short lengthscale overfits the training
# rows and is penalised on the held-out rows, so the fuller evidence stops
# over-shortening (the regularised cure for the in-sample profiling's recovery
# loss).
.rff_cv_loglik <- function(phi_tr, y_tr, phi_va, y_va) {
  at <- .rff_evidence_at(phi_tr, y_tr)
  d <- ncol(phi_tr)
  amat <- at$t * crossprod(phi_tr) + diag(at$a, d)
  ch <- tryCatch(chol(amat), error = function(e) NULL)
  if (is.null(ch)) {
    return(-Inf)
  }
  ainv <- chol2inv(ch)
  m <- at$t * as.numeric(ainv %*% crossprod(phi_tr, y_tr))
  mu <- as.numeric(phi_va %*% m)
  vv <- 1 / at$t + rowSums((phi_va %*% ainv) * phi_va)
  sum(stats::dnorm(y_va, mu, sqrt(pmax(vv, 1e-12)), log = TRUE))
}

# Evidence-ARD: learn per-dimension lengthscales by maximising a per-input
# relevance objective. Irrelevant inputs -- along which the response is flat --
# raise the objective at a long lengthscale, so the optimiser stretches them and
# they drop out of the kernel. Deterministic given the seeded features; falls
# back to the isotropic start on any failure. ARD is vacuous in one dimension.
#
# Three regimes for the objective (the `refit` argument):
# - FALSE (default, cont.36): the RFF log marginal likelihood summed over
#   outputs, with the prior/noise precisions (a, t) held at their isotropic-fit
#   values `at_fixed` -- one alternating evidence step, cheap.
# - TRUE (cont.37 "fuller evidence-ARD"): (a, t) re-estimated by a short MacKay
#   loop at each candidate lengthscale -- the evidence *profiled* over (a, t), a
#   fuller (never-lower) marginal likelihood, but in-sample, so it can
#   over-shorten lengthscales (evidence-overfitting).
# - "cv": the *held-out* predictive log-density, summed over a k-fold partition
#   of the subsample, so a too-short lengthscale is penalised on the held-out
#   rows. Regularised fuller-ARD: it keeps the relevance sharpening of the
#   profiled evidence without its in-sample over-shortening.
.ard_learn_lengthscales <- function(
  xs,
  w0,
  b,
  ys,
  l0,
  at_fixed,
  refit = FALSE
) {
  if (ncol(xs) < 2L) {
    return(l0)
  }
  cv <- identical(refit, "cv")
  if (cv) {
    n <- nrow(xs)
    # k-fold held-out predictive density: the sum over folds is a far less noisy
    # objective than a single split, so the Nelder-Mead lands on sharper
    # lengthscales. The subsample is already a random draw, so contiguous folds
    # (rep_len) are an unbiased partition.
    n_folds <- min(5L, n)
    fold <- rep_len(seq_len(n_folds), n)
  }
  obj <- function(log_invl) {
    invl <- exp(log_invl)
    phi <- .rff_features(xs, sweep(w0, 2L, invl, "*"), b)
    tot <- 0
    if (cv) {
      for (f in seq_len(n_folds)) {
        va <- which(fold == f)
        tr <- which(fold != f)
        for (j in seq_len(ncol(ys))) {
          tot <- tot +
            .rff_cv_loglik(
              phi[tr, , drop = FALSE],
              ys[tr, j],
              phi[va, , drop = FALSE],
              ys[va, j]
            )
        }
      }
    } else {
      for (j in seq_len(ncol(ys))) {
        at <- if (isTRUE(refit)) {
          .rff_evidence_at(phi, ys[, j])
        } else {
          at_fixed[[j]]
        }
        tot <- tot + .rff_log_eml(phi, ys[, j], at$a, at$t)
      }
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

# Factor analysis Sigma ~= W W' + diag(Psi) by EM (Rubin & Thayer 1982), q
# factors, from a k x k covariance `s`. Unlike a plain eigen-truncation, EM
# separates the low-rank loadings W from a *heteroscedastic* residual diagonal
# Psi -- when the noise covariance is low-rank-plus-uneven-diagonal, the top
# eigenvectors of Sigma are contaminated by the diagonal and mis-estimate the
# loadings, while FA does not. Returns the k x q loading matrix W; the caller
# applies its own exact-diagonal correction so the marginals stay exact. Eigen
# init + a Woodbury inverse of (W W' + Psi) per step (q x q, never k x k).
.fa_em <- function(s, q, iters = 50L) {
  eig <- eigen(s, symmetric = TRUE)
  lam <- pmax(eig$values, 1e-8)
  w <- eig$vectors[, seq_len(q), drop = FALSE] %*%
    diag(sqrt(lam[seq_len(q)]), q)
  psi <- pmax(diag(s) - rowSums(w^2), 1e-6 * mean(diag(s)))
  iq <- diag(1, q)
  for (it in seq_len(iters)) {
    psinv <- 1 / psi
    wpsi <- w * psinv # k x q (row-scaled = Psinv W)
    wt_psinv <- t(wpsi) # q x k = W' Psinv
    wt_psinv_w <- wt_psinv %*% w # q x q = W' Psinv W
    innerinv <- chol2inv(chol(iq + wt_psinv_w))
    beta <- (iq - wt_psinv_w %*% innerinv) %*% wt_psinv # = W' (WW'+Psi)^-1
    bs <- beta %*% s # q x k
    ezz <- iq - beta %*% w + bs %*% t(beta) # q x q
    w_new <- (s %*% t(beta)) %*% chol2inv(chol(ezz)) # k x q
    psi_new <- pmax(diag(s) - rowSums(w_new * t(bs)), 1e-6 * mean(diag(s)))
    if (max(abs(w_new - w)) < 1e-7) {
      w <- w_new
      break
    }
    w <- w_new
    psi <- psi_new
  }
  w
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
#
# With `cov_rank = q` (q < k) the k x k noise covariance is also stored in
# a factor-analysis Sigma ~= U U' + diag(dd): a rank-q factor U (k x q) from
# the top-q eigenpairs plus a residual diagonal `dd` chosen so the DIAGONAL is
# reproduced exactly (dd = diag(Sigma) - rowSums(U^2), floored). The marginal
# `<o>_sd` (clause 2) and the cov-diagonal identity (clause 4) stay exact; only
# the off-diagonal cross-output covariance is approximated, at O(k q) storage --
# the path for large output counts. `sigma` is the rank-q reconstruction, so
# every downstream path (dense predict, the IES consumer) is unchanged.
.rff_fit_joint <- function(phi, y, cov_rank = NULL, cov_method = "eigen") {
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

  # Optional rank-q factor-analysis storage of the noise covariance (large k).
  # `cov_method = "eigen"` (default) truncates Sigma's eigendecomposition; "fa"
  # learns the loadings by EM (better when the residual diagonal is
  # heteroscedastic); "auto" picks between them by the heteroscedasticity of the
  # eigen-residual diagonal. Either way `dd` is set to reproduce the covariance
  # diagonal -- hence `<o>_sd` -- exactly. The eigen factor is computed once and
  # reused for the probe and the eigen path. `sigma_lr$method` records the
  # resolved method.
  sigma_lr <- NULL
  if (!is.null(cov_rank)) {
    q <- as.integer(cov_rank)
    if (q >= 1L && q < k) {
      eig <- eigen(sigma, symmetric = TRUE)
      lam <- pmax(eig$values[seq_len(q)], 0)
      u_eigen <- eig$vectors[, seq_len(q), drop = FALSE] %*% diag(sqrt(lam), q)
      method <- cov_method
      if (identical(method, "auto")) {
        # coefficient of variation of the eigen-residual diagonal: a near-even
        # residual (homoscedastic) is well served by eigen-truncation; an uneven
        # one (heteroscedastic) contaminates the top eigenvectors, so use FA.
        dd_eigen <- pmax(diag(sigma) - rowSums(u_eigen^2), 0)
        het <- stats::sd(dd_eigen) / mean(dd_eigen)
        method <- if (is.finite(het) && het > 0.5) "fa" else "eigen"
      }
      umat <- if (identical(method, "fa")) .fa_em(sigma, q) else u_eigen
      dd <- pmax(diag(sigma) - rowSums(umat^2), 0) # residual: exact diagonal
      sigma <- tcrossprod(umat) + diag(dd, k) # rank-q reconstruction
      sigma_lr <- list(u = umat, d = dd, rank = q, method = method)
    }
  }

  list(
    joint = TRUE,
    bmat = bmat,
    amat = amat,
    sigma = sigma,
    sigma_lr = sigma_lr,
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
#' @param ard_refit When `ard = TRUE`, controls the relevance objective.
#'   `FALSE` (default) holds the prior/noise precisions `(a, t)` at their
#'   isotropic-fit values. `TRUE` re-estimates `(a, t)` by evidence at each
#'   candidate lengthscale (the evidence *profiled* over `(a, t)`) -- a fuller,
#'   never-lower marginal likelihood, but in-sample, so it can over-shorten
#'   lengthscales. `"cv"` instead maximises the **held-out** predictive
#'   log-density over a k-fold split, the regularised fuller-ARD: it keeps the
#'   relevance sharpening without the in-sample over-shortening.
#' @param joint Logical; for `method = "rff"` with two or more outputs, fit a
#'   joint multi-output model preserving the cross-output predictive covariance
#'   (default `TRUE`). `FALSE` fits one independent model per output (marginals
#'   only). The per-output `<o>_sd` contract is unchanged either way; only the
#'   off-diagonal covariance (exposed by `predict(..., cov = TRUE)`) differs.
#' @param cov_rank Optional integer; for a joint `rff` fit with `k` outputs,
#'   store the cross-output covariance in a rank-`cov_rank` factor-analysis
#'   form (`U U' + diag`) instead of the dense `k x k`, for large output counts.
#'   The per-output marginal sd and the covariance diagonal are reproduced
#'   exactly; only the off-diagonal covariance is approximated. `NULL` (default)
#'   or `cov_rank >= k` keeps the full covariance. See `predict(...,
#'   cov = "lowrank")` for the compact predictive return.
#' @param cov_method How the rank-`cov_rank` factor is fitted (only when
#'   `cov_rank` is set): `"eigen"` (default) truncates the covariance's
#'   eigendecomposition; `"fa"` learns the loadings by factor-analysis EM, which
#'   recovers them more faithfully when the residual diagonal is heteroscedastic
#'   (the eigenvectors of the full covariance are otherwise contaminated by the
#'   uneven diagonal); `"auto"` picks `"fa"` or `"eigen"` from the
#'   heteroscedasticity of the eigen-residual diagonal. The covariance diagonal
#'   is reproduced exactly in every case. The resolved method is recorded in the
#'   fitted object.
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
  ard_refit = FALSE,
  joint = TRUE,
  cov_rank = NULL,
  cov_method = "eigen",
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
        at_fixed,
        refit = ard_refit
      )
    }

    w0 <- matrix(stats::rnorm(d * p), d, p)
    b <- stats::runif(d, 0, 2 * pi)
    w <- sweep(w0, 2L, 1 / lengthscales, "*")
    phi <- .rff_features(xs, w, b)

    if (joint && ncol(y) >= 2L) {
      fitobj <- .rff_fit_joint(
        phi,
        y,
        cov_rank = cov_rank,
        cov_method = cov_method
      )
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
#' With `cov = "lowrank"` a joint `rff` surrogate returns the same joint
#' predictive in a **compact factored** form for large output counts: an
#' `fb_surrogate_prediction` carrying `cov_lowrank = list(u, d, infl)` such that
#' per-row covariance is `infl[i] * (u u' + diag(d))` -- `O(k q + n)` storage
#' instead of the dense `O(k^2 n)` array. The factor `u` has the surrogate's
#' `cov_rank` columns (the full `k` if it was fit without `cov_rank`).
#' Reconstruct a slice with [fb_cov_slice()]. The diagonal still equals
#' `<o>_sd^2` exactly.
#'
#' @param object An `fb_surrogate` from [fit_surrogate()].
#' @param newdata A `data.frame` of new parameter sets; must contain the
#'   surrogate's `param_names` columns.
#' @param cov `FALSE` (default) for the marginal `data.frame`; `TRUE` for an
#'   `fb_surrogate_prediction` with the dense per-row cross-output covariance
#'   array; `"lowrank"` for the compact factored covariance (a joint `rff` fit
#'   only).
#' @param ... Unused.
#' @return With `cov = FALSE` (default) a `data.frame` with `<output>_mean` and
#'   `<output>_sd` columns, one row per row of `newdata`. With `cov = TRUE` an
#'   `fb_surrogate_prediction` (`mean`, `cov`, `output_names`). With
#'   `cov = "lowrank"` an `fb_surrogate_prediction` (`mean`, `cov_lowrank`,
#'   `output_names`).
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
  want_lr <- identical(cov, "lowrank")
  want_cov <- isTRUE(cov) || want_lr
  xnew <- as.matrix(newdata[, object$param_names, drop = FALSE])
  xs <- scale(xnew, center = object$x_center, scale = object$x_scale)
  onames <- object$output_names

  if (
    want_lr && !(identical(object$method, "rff") && isTRUE(object$fit$joint))
  ) {
    stop(
      "predict.fb_surrogate(): cov = \"lowrank\" is defined for a joint rff ",
      "surrogate only (fit_surrogate(joint = TRUE); set cov_rank for ",
      "compression). Use cov = TRUE for a dense covariance.",
      call. = FALSE
    )
  }

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
    if (!want_cov) {
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

  if (!want_cov) {
    return(.surrogate_meansd(mean_mat, sd_mat, onames))
  }

  if (want_lr) {
    # Compact factored joint covariance: per-row cov is infl[i] * sig0, and
    # sig0 = diag(y_sd)(u u' + diag(dd)) diag(y_sd) = u0 u0' + diag(d0). The
    # per-row scalar infl folds into the returned slice via fb_cov_slice().
    jt <- object$fit
    y_sd <- jt$y_sd
    infl <- 1 + rowSums((phi %*% jt$amat) * phi)
    if (!is.null(jt$sigma_lr)) {
      u0 <- diag(y_sd, k) %*% jt$sigma_lr$u # k x q
      d0 <- y_sd^2 * jt$sigma_lr$d # length k
    } else {
      # no cov_rank: a full-rank eigen factor (q = k), still exact
      sig0 <- diag(y_sd, k) %*% jt$sigma %*% diag(y_sd, k)
      eig <- eigen(sig0, symmetric = TRUE)
      lam <- pmax(eig$values, 0)
      u0 <- eig$vectors %*% diag(sqrt(lam), k)
      d0 <- rep(0, k)
    }
    rownames(u0) <- onames
    names(d0) <- onames
    return(structure(
      list(
        mean = mean_mat,
        cov_lowrank = list(u = u0, d = d0, infl = infl),
        output_names = onames
      ),
      class = "fb_surrogate_prediction"
    ))
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

# ---- reconstruct a covariance slice -----------------------------------------

#' Reconstruct a per-row covariance slice from a surrogate prediction
#'
#' Returns the `k x k` cross-output predictive covariance at one row of the
#' `newdata` passed to [predict.fb_surrogate()], from either the dense
#' (`cov = TRUE`) or the compact factored (`cov = "lowrank"`) form -- so a
#' consumer can work slice-by-slice without materialising the full dense array
#' for a large output count.
#'
#' @param prediction An `fb_surrogate_prediction` from
#'   `predict(<fb_surrogate>, newdata, cov = TRUE)` or `cov = "lowrank"`.
#' @param i Integer row index (a row of `newdata`; default `1`).
#' @return The `k x k` cross-output predictive covariance at row `i`, with
#'   output names on both dimensions.
#' @seealso [predict.fb_surrogate()].
#' @export
fb_cov_slice <- function(prediction, i = 1L) {
  if (!inherits(prediction, "fb_surrogate_prediction")) {
    stop(
      "fb_cov_slice(): `prediction` must be an fb_surrogate_prediction ",
      "(from predict(<fb_surrogate>, newdata, cov = TRUE | \"lowrank\")).",
      call. = FALSE
    )
  }
  onames <- prediction$output_names
  k <- length(onames)
  n <- nrow(prediction$mean)
  i <- as.integer(i)
  if (length(i) != 1L || is.na(i) || i < 1L || i > n) {
    stop(
      "fb_cov_slice(): `i` must be a single row index in 1:",
      n,
      ".",
      call. = FALSE
    )
  }
  # exact-match extraction: `$` would partial-match `cov` to `cov_lowrank`
  if (!is.null(prediction[["cov"]])) {
    sl <- matrix(prediction[["cov"]][seq_len(k), seq_len(k), i], k, k)
  } else {
    lr <- prediction[["cov_lowrank"]]
    sl <- lr$infl[i] * (tcrossprod(lr$u) + diag(lr$d, k))
  }
  dimnames(sl) <- list(onames, onames)
  sl
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
  if (!is.null(x$cov_lowrank)) {
    q <- ncol(x$cov_lowrank$u)
    cat(
      "  $mean (",
      n,
      " x ",
      k,
      "), $cov_lowrank: rank-",
      q,
      " factor (u u' + diag(d)) x infl[i]\n",
      sep = ""
    )
    cat("  reconstruct a slice with fb_cov_slice(prediction, i)\n")
  } else {
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
  }
  cat("------------------------------------------------------------\n")
  invisible(x)
}
