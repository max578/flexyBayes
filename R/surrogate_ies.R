# =============================================================================
# surrogate_ies.R -- surrogate-accelerated ensemble inversion (a C7 consumer).
#
# The distribution-preserving surrogate (C7) is built so an expensive forward
# model can be replaced by a fast emulator that still reports predictive
# uncertainty. fb_surrogate_ies() is the inverse / calibration consumer of that
# property: an Ensemble Smoother with Multiple Data Assimilation (ES-MDA,
# Emerick & Reynolds 2013) that drives the parameter ensemble toward agreement
# with observed data using only the surrogate's predictions, never a simulator.
#
# Because the surrogate is distribution-preserving, its predictive variance is
# folded into the data covariance, so emulator error inflates the assimilation
# noise (the principled use of `<o>_sd`): the inversion is appropriately less
# confident where the emulator is. This consumes any conforming fb_surrogate via
# its predict() contract -- it does not depend on PESTO's internal IES (which is
# monolithic and cannot accept an external surrogate), so flexyBayes is
# standalone-functional for surrogate-accelerated inversion (invariant 1).
# =============================================================================

.safe_solve <- function(m) {
  d <- nrow(m)
  scale_jit <- mean(diag(m))
  if (!is.finite(scale_jit) || scale_jit <= 0) {
    scale_jit <- 1
  }
  jit <- 0
  for (k in 0:8) {
    res <- tryCatch(
      chol2inv(chol(m + diag(jit, d))),
      error = function(e) NULL
    )
    if (!is.null(res)) {
      return(res)
    }
    jit <- if (jit == 0) 1e-10 * scale_jit else jit * 10
  }
  solve(m + diag(jit, d))
}

# Compute `ctg %*% (diag(rdiag) + lmat lmat')^-1` by the Woodbury identity --
# the inner solve is `r x r` (r = ncol(lmat)) instead of the dense `d x d`. When
# the data covariance is diagonal-plus-low-rank (a low-rank emulator covariance
# plus the forecast anomalies, both factored), this is the native low-rank
# consumer of contract clause 5: the Kalman gain never forms the dense cd, so
# the ES-MDA cost scales with the covariance rank, not the output count. Returns
# the same `p x d` gain the dense path would (tested for equivalence).
.apply_inv_lowrank <- function(ctg, rdiag, lmat) {
  rinv <- 1 / rdiag
  ctg_rinv <- sweep(ctg, 2L, rinv, "*") # p x d  (ctg Rinv)
  l_rinv <- sweep(lmat, 1L, rinv, "*") # d x r  (Rinv L)
  inner <- diag(1, ncol(lmat)) + crossprod(lmat, l_rinv) # r x r = I + L' Rinv L
  innerinv <- .safe_solve(inner)
  ctg_rinv_l <- ctg_rinv %*% lmat # p x r
  ctg_rinv - (ctg_rinv_l %*% innerinv) %*% t(l_rinv) # p x d
}

#' Surrogate-accelerated ensemble inversion (ES-MDA)
#'
#' Calibrates a parameter ensemble against observed data using a
#' distribution-preserving surrogate (contract C7) in place of the forward
#' model. Runs Ensemble Smoother with Multiple Data Assimilation (ES-MDA;
#' Emerick and Reynolds, 2013): each of `n_iter` iterations applies a Kalman
#' update with the data covariance inflated by `n_iter`, so the combined update
#' equals a single tempered assimilation. No simulator is run -- every forward
#' evaluation is a surrogate `predict()`.
#'
#' When `use_surrogate_sd = TRUE` (default) the surrogate's predictive
#' uncertainty is added to the observation-error covariance, so emulator
#' uncertainty inflates the assimilation noise -- the inversion trusts the
#' surrogate less where it is less certain. This is the consumer that the
#' distribution-preserving surrogate exists to serve. When the surrogate is
#' joint (its `predict(cov = TRUE)` yields a cross-output covariance) and
#' `use_surrogate_cov = TRUE` (default), the **full** mean predictive covariance
#' enters the data covariance, so correlated emulator errors are assimilated
#' coherently rather than as independent per-output noise; otherwise only the
#' per-output predictive variance (the diagonal) is used.
#'
#' @param surrogate An `fb_surrogate` from [fit_surrogate()].
#' @param observed A named numeric vector of target observations; names must
#'   be a subset of the surrogate's emulated outputs.
#' @param obs_sd Observation-error standard deviation: a single number (shared)
#'   or a named numeric vector aligned with `observed`.
#' @param prior A `data.frame` (or matrix) of the prior parameter ensemble --
#'   one row per realisation; must contain the surrogate's parameter columns.
#' @param n_iter Number of ES-MDA iterations (equal inflation `alpha = n_iter`).
#' @param use_surrogate_sd Add the surrogate's mean predictive uncertainty to
#'   the data covariance (default `TRUE`).
#' @param use_surrogate_cov When the surrogate is joint, fold its full
#'   cross-output predictive covariance (not just the per-output variance) into
#'   the data covariance (default `TRUE`). Ignored when `use_surrogate_sd` is
#'   `FALSE` or the surrogate reports only marginals (the covariance is then
#'   diagonal and the two paths coincide).
#' @param seed Optional integer RNG seed for the observation perturbations
#'   (reproducibility); the caller's RNG stream is restored on exit.
#'
#' @return An object of class `c("fb_surrogate_ies", "list")` with components
#'   `posterior` (the updated ensemble `data.frame`), `prior`, `observed`,
#'   `misfit` (mean data-misfit before each iteration and after the last),
#'   `n_iter`, `use_surrogate_sd`, `surrogate_method`, `param_names`, and
#'   `output_names`.
#' @references Emerick, A. A. and Reynolds, A. C. (2013). Ensemble smoother with
#'   multiple data assimilation. *Computers & Geosciences*, 55, 3-15.
#' @seealso [fit_surrogate()], [fb_surrogate_ppc()].
#' @examples
#' set.seed(1)
#' # forward model y = G theta; build a training ensemble and an emulator
#' g <- c(1.5, -0.8)
#' tr <- data.frame(p1 = runif(150, -1, 3), p2 = runif(150, -2, 2))
#' e <- fb_ensemble(
#'   params = tr,
#'   outputs = data.frame(y = g[1] * tr$p1 + g[2] * tr$p2)
#' )
#' s <- fit_surrogate(e)
#' prior <- data.frame(p1 = rnorm(200, 1, 1), p2 = rnorm(200, 0, 1))
#' fit <- fb_surrogate_ies(s, c(y = 2.3), obs_sd = 0.1, prior = prior)
#' colMeans(fit$posterior)
#' @export
fb_surrogate_ies <- function(
  surrogate,
  observed,
  obs_sd,
  prior,
  n_iter = 4L,
  use_surrogate_sd = TRUE,
  use_surrogate_cov = TRUE,
  seed = NULL
) {
  if (!inherits(surrogate, "fb_surrogate")) {
    stop(
      "fb_surrogate_ies(): `surrogate` must be an fb_surrogate ",
      "(see fit_surrogate()).",
      call. = FALSE
    )
  }
  if (is.null(names(observed)) || !is.numeric(observed)) {
    stop(
      "fb_surrogate_ies(): `observed` must be a named numeric vector.",
      call. = FALSE
    )
  }
  out_names <- names(observed)
  miss <- setdiff(out_names, surrogate$output_names)
  if (length(miss) > 0L) {
    stop(
      "fb_surrogate_ies(): observed output(s) the surrogate does not ",
      "emulate: ",
      paste(miss, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  n_iter <- as.integer(n_iter)
  if (n_iter < 1L) {
    stop("fb_surrogate_ies(): `n_iter` must be >= 1.", call. = FALSE)
  }

  d <- length(out_names)
  obs <- as.numeric(observed)
  if (length(obs_sd) == 1L) {
    sd_used <- rep(obs_sd, d)
  } else {
    if (is.null(names(obs_sd))) {
      stop(
        "fb_surrogate_ies(): a vector `obs_sd` must be named by output.",
        call. = FALSE
      )
    }
    sd_used <- obs_sd[out_names]
  }
  if (any(!is.finite(sd_used)) || any(sd_used <= 0)) {
    stop(
      "fb_surrogate_ies(): `obs_sd` must be finite and positive.",
      call. = FALSE
    )
  }
  obs_var <- sd_used^2

  prior_df <- as.data.frame(prior)
  pmiss <- setdiff(surrogate$param_names, colnames(prior_df))
  if (length(pmiss) > 0L) {
    stop(
      "fb_surrogate_ies(): `prior` is missing parameter column(s): ",
      paste(pmiss, collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  ens <- as.matrix(prior_df[, surrogate$param_names, drop = FALSE])
  colnames(ens) <- surrogate$param_names
  n_real <- nrow(ens)
  if (n_real < 3L) {
    stop(
      "fb_surrogate_ies(): need at least 3 prior realisations for sample ",
      "covariances.",
      call. = FALSE
    )
  }

  # Deterministic perturbations (seeded; restore the caller's RNG on exit).
  if (!is.null(seed)) {
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
      on.exit(assign(".Random.seed", old_seed, envir = .GlobalEnv), add = TRUE)
    }
    set.seed(seed)
  }

  alpha <- n_iter
  misfit <- numeric(n_iter + 1L)

  # Native low-rank consumer (contract clause 5): when the surrogate stores a
  # low-rank covariance, fold its factored form straight into the Kalman update
  # (Woodbury, rank-sized solve) and the observation perturbation -- the d x d
  # data covariance is never materialised. Falls back to the dense path for a
  # dense-joint / marginal surrogate or when the surrogate sd is not used.
  lr_native <- isTRUE(use_surrogate_sd) &&
    isTRUE(use_surrogate_cov) &&
    !is.null(surrogate$fit[["sigma_lr"]])

  .misfit <- function(g_mat) {
    # mean over realisations of the data misfit (G - obs)' diag(1/obs_var) (.)
    res <- sweep(g_mat, 2L, obs)
    mean(rowSums(sweep(res^2, 2L, obs_var, "/")))
  }

  # The surrogate's predictive distribution at the current ensemble, restricted
  # to the observed outputs: the mean matrix, plus the mean emulator covariance
  # either dense (`emu_cov`) or factored (`emu_u`, `emu_d` for the low-rank
  # native path; mean cov = emu_u emu_u' + diag(emu_d)).
  .predict_obs <- function(ens) {
    if (lr_native) {
      pc <- stats::predict(surrogate, as.data.frame(ens), cov = "lowrank")
      idx <- match(out_names, pc$output_names)
      cbar <- mean(pc$cov_lowrank$infl) # mean epistemic inflation
      u_obs <- pc$cov_lowrank$u[idx, , drop = FALSE]
      dd_obs <- pc$cov_lowrank$d[idx]
      return(list(
        g_mat = pc$mean[, idx, drop = FALSE],
        emu_u = sqrt(cbar) * u_obs, # d x q
        emu_d = cbar * dd_obs # d
      ))
    }
    pc <- stats::predict(surrogate, as.data.frame(ens), cov = TRUE)
    idx <- match(out_names, pc$output_names)
    g_mat <- pc$mean[, idx, drop = FALSE]
    if (!use_surrogate_sd) {
      emu_cov <- matrix(0, d, d)
    } else if (use_surrogate_cov) {
      # mean over realisations of the full d x d emulator covariance
      emu_cov <- apply(pc$cov[idx, idx, , drop = FALSE], c(1L, 2L), mean)
    } else {
      # diagonal only: mean over realisations of the per-output variance
      vars <- apply(
        pc$cov[idx, idx, , drop = FALSE],
        3L,
        function(m) diag(as.matrix(m))
      )
      emu_cov <- diag(rowMeans(matrix(vars, nrow = d)), d)
    }
    list(g_mat = g_mat, emu_cov = emu_cov)
  }

  for (it in seq_len(n_iter)) {
    pr <- .predict_obs(ens)
    g_mat <- pr$g_mat
    misfit[it] <- .misfit(g_mat)

    gbar <- colMeans(g_mat)
    tbar <- colMeans(ens)
    dg <- sweep(g_mat, 2L, gbar)
    dt <- sweep(ens, 2L, tbar)
    ctg <- crossprod(dt, dg) / (n_real - 1L) # p x d

    if (lr_native) {
      # cgg + alpha cd = diag(rdiag) + Lfull Lfull', Lfull = [anomalies |
      # sqrt(alpha) emulator factor]; Woodbury solves r x r, not d x d.
      rdiag <- alpha * (obs_var + pr$emu_d)
      lg <- t(dg) / sqrt(n_real - 1L) # d x n_real
      lfull <- cbind(lg, sqrt(alpha) * pr$emu_u) # d x (n_real + q)
      kgain <- .apply_inv_lowrank(ctg, rdiag, lfull) # p x d
      # perturb with covariance alpha cd = diag(rdiag) + alpha emu_u emu_u',
      # sampled factored (no d x d Cholesky)
      q_e <- ncol(pr$emu_u)
      z1 <- matrix(stats::rnorm(n_real * d), n_real, d)
      z2 <- matrix(stats::rnorm(n_real * q_e), n_real, q_e)
      pert <- sweep(z1, 2L, sqrt(rdiag), "*") +
        z2 %*% (sqrt(alpha) * t(pr$emu_u))
    } else {
      cd <- diag(obs_var, d) + pr$emu_cov # d x d data covariance
      cgg <- crossprod(dg) / (n_real - 1L) # d x d
      kgain <- ctg %*% .safe_solve(cgg + alpha * cd) # p x d
      # perturb the observations with covariance alpha * cd (diagonal cd
      # reproduces the per-output sampling of the marginal path exactly; cd is
      # strictly positive-definite via the obs_var floor)
      rmat <- chol(alpha * cd)
      pert <- matrix(stats::rnorm(n_real * d), n_real, d) %*% rmat
    }
    d_pert <- matrix(obs, n_real, d, byrow = TRUE) + pert
    ens <- ens + (d_pert - g_mat) %*% t(kgain)
    colnames(ens) <- surrogate$param_names
  }

  misfit[n_iter + 1L] <- .misfit(.predict_obs(ens)$g_mat)

  structure(
    list(
      posterior = as.data.frame(ens),
      prior = prior_df[, surrogate$param_names, drop = FALSE],
      observed = observed,
      obs_sd = obs_sd,
      misfit = misfit,
      n_iter = n_iter,
      use_surrogate_sd = use_surrogate_sd,
      use_surrogate_cov = use_surrogate_cov,
      lowrank_solve = lr_native,
      surrogate_method = surrogate$method,
      param_names = surrogate$param_names,
      output_names = out_names
    ),
    class = c("fb_surrogate_ies", "list")
  )
}

#' @export
print.fb_surrogate_ies <- function(x, ...) {
  cat("-- fb_surrogate_ies (surrogate-accelerated ES-MDA, C7 consumer) -\n")
  cat(
    "  surrogate: ",
    x$surrogate_method,
    " | iters: ",
    x$n_iter,
    " | realisations: ",
    nrow(x$posterior),
    "\n",
    sep = ""
  )
  cat(
    "  data misfit: ",
    formatC(x$misfit[1L], format = "g", digits = 4L),
    " -> ",
    formatC(x$misfit[length(x$misfit)], format = "g", digits = 4L),
    "\n",
    sep = ""
  )
  shift <- data.frame(
    parameter = x$param_names,
    prior_mean = vapply(x$prior, mean, numeric(1L)),
    posterior_mean = vapply(x$posterior, mean, numeric(1L)),
    row.names = NULL
  )
  print(utils::head(shift, 10L))
  cat("----------------------------------------------------------------\n")
  invisible(x)
}
