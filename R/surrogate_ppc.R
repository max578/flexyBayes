# =============================================================================
# surrogate_ppc.R -- did the surrogate distort the output distribution?
#
# A C7 consumer that validates an emulator against held-out simulator outputs.
# fit_surrogate() preserves a predictive DISTRIBUTION; this checks whether that
# distribution actually matches the simulator's, rather than only its mean. It
# draws from the surrogate's predictive distribution at held-out parameter sets
# and hands the draws to kernR's mmd_ppc() (a maximum-mean-discrepancy
# posterior-predictive check) against the true simulator outputs there.
#
# Two draw paths. The JOINT path (default) samples from the full cross-output
# predictive covariance (predict(cov = TRUE) + a per-row Cholesky), so the
# emulator's cross-output correlation is exercised -- the second consumer of the
# joint covariance after fb_surrogate_ies(). The MARGINAL path (joint = FALSE)
# samples each output independently from its <o>_sd, the v1.1 behaviour. On a
# correlated-output simulator the marginal draws throw away the cross-output
# structure, so the joint path is the distribution-preserving check (the
# cont.20 marginal-vs-joint lesson, now applied to the PPC consumer).
#
# kernR owns the test (the MMD machinery is not reimplemented here); flexyBayes
# only generates the predictive sample from the surrogate -- the "contracts not
# internals" rule again. Requires kernR; without it, the check refuses cleanly.
# =============================================================================

# Cholesky factor of a covariance slice, with a graduated diagonal jitter on
# failure (a near-singular predictive covariance can arise when two outputs are
# almost perfectly correlated). Like .safe_solve() in surrogate_ies.R. Returns
# upper-triangular R with crossprod(R) == m, so a row vector z ~ N(0, I) maps
# to z %*% R ~ N(0, m).
.safe_chol <- function(m) {
  d <- nrow(m)
  scale_jit <- mean(diag(m))
  if (!is.finite(scale_jit) || scale_jit <= 0) {
    scale_jit <- 1
  }
  jit <- 0
  for (k in 0:8) {
    res <- tryCatch(chol(m + diag(jit, d)), error = function(e) NULL)
    if (!is.null(res)) {
      return(res)
    }
    jit <- if (jit == 0) 1e-10 * scale_jit else jit * 10
  }
  chol(m + diag(jit, d))
}

# Generate the predictive draw cloud the PPC compares against the simulator.
# Returns an (nrow(newdata) * n_draws) x length(out_names) matrix, columns named
# by out_names. Split from fb_surrogate_ppc() so the draw mechanism is unit-
# testable without kernR.
#
# Three paths. JOINT + a surrogate storing a low-rank covariance (`cov_rank`):
# the **factored sampler** -- draw from infl[i] (u u' + diag(d)) as
# sqrt(infl[i]) (u e + sqrt(d) (.) g), e ~ N(0, I_q), g ~ N(0, I_k), so the
# k x k slice is never formed (the native low-rank consumer for the PPC, O(k q)
# per draw). JOINT + a dense covariance: a per-row Cholesky of the k x k slice.
# MARGINAL (joint = FALSE): independent per-output sampling from <o>_sd. The
# factored and dense joint samplers draw from the same per-row covariance (the
# factored one consumes different RNG, being a cheaper sampler).
.surrogate_ppc_draws <- function(
  surrogate,
  newdata,
  out_names,
  n_draws,
  joint,
  seed
) {
  n_out <- length(out_names)
  lr_native <- isTRUE(joint) &&
    identical(surrogate$method, "rff") &&
    isTRUE(surrogate$fit$joint) &&
    !is.null(surrogate$fit[["sigma_lr"]])

  if (lr_native) {
    pred <- stats::predict(surrogate, newdata, cov = "lowrank")
    idx <- match(out_names, pred$output_names)
    mean_mat <- pred$mean[, idx, drop = FALSE]
    u <- pred$cov_lowrank$u[idx, , drop = FALSE] # k x q factor
    dsd <- sqrt(pred$cov_lowrank$d[idx]) # k idiosyncratic sd
    sqrt_infl <- sqrt(pred$cov_lowrank$infl) # per row
  } else if (isTRUE(joint)) {
    pred <- stats::predict(surrogate, newdata, cov = TRUE)
    idx <- match(out_names, pred$output_names)
    mean_mat <- pred$mean[, idx, drop = FALSE]
    carr <- pred$cov[idx, idx, , drop = FALSE]
  } else {
    pred <- stats::predict(surrogate, newdata)
    mean_mat <- as.matrix(pred[, paste0(out_names, "_mean"), drop = FALSE])
    sd_mat <- as.matrix(pred[, paste0(out_names, "_sd"), drop = FALSE])
  }
  n_rows <- nrow(mean_mat)

  if (!is.null(seed)) {
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
      on.exit(assign(".Random.seed", old_seed, envir = .GlobalEnv), add = TRUE)
    }
    set.seed(seed)
  }

  draws <- matrix(NA_real_, n_rows * n_draws, n_out)
  if (lr_native) {
    q <- ncol(u)
    for (r in seq_len(n_draws)) {
      e <- matrix(stats::rnorm(n_rows * q), n_rows, q) # factor noise
      g <- matrix(stats::rnorm(n_rows * n_out), n_rows, n_out) # idiosyncratic
      # row i covariance is sqrt_infl[i]^2 (u u' + diag(d)); the row-length
      # sqrt_infl scales each row (recycled down the columns)
      factor_part <- e %*% t(u) + sweep(g, 2L, dsd, "*")
      blk <- mean_mat + factor_part * sqrt_infl
      draws[((r - 1L) * n_rows + 1L):(r * n_rows), ] <- blk
    }
  } else if (isTRUE(joint)) {
    # one Cholesky factor per held-out row; slice i is the k x k cross-output
    # predictive covariance there.
    chols <- lapply(
      asplit(carr, 3L),
      function(s) .safe_chol(matrix(s, n_out, n_out))
    )
    for (r in seq_len(n_draws)) {
      z <- matrix(stats::rnorm(n_rows * n_out), n_rows, n_out)
      blk <- mean_mat
      for (i in seq_len(n_rows)) {
        blk[i, ] <- mean_mat[i, ] + as.numeric(z[i, ] %*% chols[[i]])
      }
      draws[((r - 1L) * n_rows + 1L):(r * n_rows), ] <- blk
    }
  } else {
    for (r in seq_len(n_draws)) {
      noise <- matrix(stats::rnorm(n_rows * n_out), n_rows, n_out)
      draws[((r - 1L) * n_rows + 1L):(r * n_rows), ] <- mean_mat +
        sd_mat * noise
    }
  }
  colnames(draws) <- out_names
  draws
}

# Mahalanobis-whiten the predictive draws and the observed outputs by their
# POOLED covariance. The whitening map depends only on the pooled multiset (the
# combined draws + observed), NOT on which rows are draws vs observed, so it is
# label-agnostic: permuting the labels cannot change the map, and so the
# permutation test on the whitened rows stays exactly valid. Its purpose is to
# remove the cross-output scale heterogeneity that makes a single median
# bandwidth too coarse to resolve structure in the low-variance directions. The
# same map is applied to both clouds, so a relative scale / shape / mean
# difference between them survives, while each output is put on a common
# footing.
# A graduated relative
# ridge guards a near-singular pooled covariance (highly collinear outputs).
# Returns the whitened (draws, observed) as plain numeric matrices.
.whiten_clouds <- function(draws, obs_mat) {
  z <- rbind(draws, obs_mat)
  mu <- colMeans(z)
  cc <- stats::cov(z)
  d <- ncol(z)
  ridge <- 1e-6 * mean(diag(cc))
  if (!is.finite(ridge) || ridge <= 0) {
    ridge <- 1e-8
  }
  r <- NULL
  for (k in 0:6) {
    r <- tryCatch(chol(cc + diag(ridge, d)), error = function(e) NULL)
    if (!is.null(r)) {
      break
    }
    ridge <- ridge * 10
  }
  if (is.null(r)) {
    r <- chol(cc + diag(ridge, d))
  }
  # R^{-1}; then (z - mu) %*% R^{-1} has unit covariance
  rinv <- backsolve(r, diag(d))
  list(
    x = sweep(draws, 2L, mu) %*% rinv,
    y = sweep(obs_mat, 2L, mu) %*% rinv
  )
}

# Aggregated (multi-kernel) MMD over a bandwidth grid -- the no-tuning,
# scale-robust test (an MMDAgg-style aggregation; Schrab et al. 2023).
# It orchestrates kernR's single-kernel mmd_test over a grid around
# the median bandwidth, sharing the SAME permutations across bandwidths
# (a fixed `seed`), then aggregates by the weighted-quantile statistic
# R = min_g p_g / w_g calibrated against the shared permutation null (uniform
# weights recover the min p-value). flexyBayes owns only the
# aggregation; the kernel, the MMD statistic, and the permutation null are
# all kernR's (the "contracts not internals" rule). Removes the bandwidth choice
# and recovers power lost when the median is mis-scaled (the cont.22
# triangulation-calibration result), at a valid level (null rejection ~ alpha).
# Resolve a kernel-weight scheme to a positive vector of length g summing to 1.
# A scheme name ("uniform" / "increasing" / "decreasing" / "centred", ordered
# from the smallest to the largest bandwidth) or a numeric vector. The
# weighted-quantile aggregation gives kernel g a (1 - u w_g)-quantile threshold,
# so a larger w_g loosens that kernel's threshold -- up-weight the bandwidth
# scale a distortion is expected to live at.
.mmd_agg_weights <- function(weights, g) {
  if (is.numeric(weights)) {
    if (length(weights) != g || any(weights <= 0) || any(!is.finite(weights))) {
      stop(
        ".mmd_agg(): numeric `weights` must be ",
        g,
        " positive finite values.",
        call. = FALSE
      )
    }
    return(weights / sum(weights))
  }
  idx <- seq_len(g)
  raw <- switch(
    weights,
    uniform = rep(1, g),
    increasing = idx,
    decreasing = rev(idx),
    centred = exp(-((idx - (g + 1) / 2)^2) / (2 * (g / 4)^2)),
    stop(
      ".mmd_agg(): unknown `weights` scheme '",
      weights,
      "' (uniform / increasing / decreasing / centred, or a numeric vector).",
      call. = FALSE
    )
  )
  raw / sum(raw)
}

.mmd_agg <- function(
  x,
  y,
  n_permutations,
  alpha,
  seed,
  mult = 2^(-3:3),
  weights = "uniform"
) {
  base_bw <- kernR::select_bandwidth(rbind(x, y), method = "median")
  grid <- base_bw * mult
  w <- .mmd_agg_weights(weights, length(grid))
  res <- lapply(grid, function(bw) {
    kernR::mmd_test(
      x,
      y,
      kernel = kernR::kernel_spec("rbf", bandwidth = bw),
      n_permutations = n_permutations,
      seed = seed
    )
  })
  t_obs <- vapply(res, function(r) r$statistic, numeric(1L))
  nmat <- vapply(res, function(r) r$null_distribution, numeric(n_permutations))
  b_perm <- nrow(nmat) # B permutations x G bandwidths
  p_obs <- vapply(
    seq_along(grid),
    function(g) (1 + sum(nmat[, g] >= t_obs[g])) / (1 + b_perm),
    numeric(1L)
  )
  # per-permutation p-value within each bandwidth's own (shared) null
  pj <- vapply(
    seq_along(grid),
    function(g) {
      col <- nmat[, g]
      (1 + colSums(outer(col, col, ">="))) / (1 + b_perm)
    },
    numeric(b_perm)
  )
  # weighted-quantile aggregation (Schrab et al. 2023): the statistic is
  # R = min_g p_g / w_g (kernel g exceeds its (1 - u w_g)-quantile iff
  # p_g <= u w_g), calibrated against the shared permutation null. Uniform
  # weights recover the min p-value form.
  r_obs <- min(p_obs / w)
  r_null <- apply(sweep(pj, 2L, w, "/"), 1L, min)
  p_agg <- (1 + sum(r_null <= r_obs)) / (1 + b_perm)
  structure(
    list(
      p_value = p_agg,
      reject = p_agg < alpha,
      statistic = r_obs,
      bandwidths = grid,
      weights = w,
      p_per_bandwidth = p_obs,
      n_kernels = length(grid),
      n_permutations = b_perm
    ),
    class = c("fb_mmd_agg", "list")
  )
}

#' @export
print.fb_mmd_agg <- function(x, ...) {
  cat("-- fb_mmd_agg (aggregated multi-kernel MMD PPC) -------------\n")
  cat(
    "  kernels: ",
    x$n_kernels,
    " (RBF, bandwidth grid) | weighted-quantile | permutations: ",
    x$n_permutations,
    "\n",
    sep = ""
  )
  cat(
    "  aggregated p-value: ",
    formatC(x$p_value, format = "g", digits = 3L),
    " | reject: ",
    x$reject,
    "\n",
    sep = ""
  )
  cat("------------------------------------------------------------\n")
  invisible(x)
}

#' Posterior-predictive check of a surrogate against held-out outputs
#'
#' Tests whether a surrogate's predictive *distribution* matches the simulator's
#' at held-out parameter sets, using kernR's maximum-mean-discrepancy
#' posterior-predictive check ([kernR::mmd_ppc()]). The surrogate's predictive
#' distribution at `newdata` is sampled into a predictive ensemble, which is
#' compared against `observed` -- the true simulator outputs at those parameter
#' sets. A rejection means the emulator distorted the output distribution
#' (typically by being over- or under-dispersed, or by getting the cross-output
#' correlation wrong), not merely that its mean is off.
#'
#' This is the distribution-preserving counterpart to a mean-only accuracy
#' check: it exercises the predictive uncertainty it reports, not just
#' the mean. With `joint = TRUE` (default) the draws are sampled from the **full
#' cross-output predictive covariance** ([predict.fb_surrogate()] with
#' `cov = TRUE`), so the emulator's cross-output correlation is tested; this is
#' the second consumer of the joint covariance after [fb_surrogate_ies()]. With
#' `joint = FALSE` each output is sampled independently from its `<o>_sd`. On a
#' simulator whose outputs are correlated, marginal draws discard that
#' correlation, so the joint path is the faithful check (a marginals-only
#' surrogate yields a diagonal covariance, and the two paths then coincide).
#'
#' @param surrogate An `fb_surrogate` from [fit_surrogate()].
#' @param newdata A `data.frame` of held-out parameter sets (must contain the
#'   surrogate's parameter columns).
#' @param observed A matrix or `data.frame` of the true simulator outputs at
#'   held-out parameter sets, with columns named for the emulated outputs.
#' @param n_draws Predictive draws per row of `newdata` (default `1`); the
#'   predictive ensemble has `n_draws * nrow(newdata)` rows.
#' @param joint Logical; sample from the joint cross-output covariance
#'   (default `TRUE`) rather than independently per output. Has no effect for a
#'   single output, or for a surrogate that reports only marginals (its
#'   covariance is diagonal). When the surrogate stores a low-rank covariance
#'   (`cov_rank`), the joint draws are sampled from the factored form directly,
#'   so the `k x k` slice is never formed (the native low-rank PPC consumer).
#' @param project Logical; for a surrogate that stores a low-rank covariance
#'   (`cov_rank`), project both the predictive draws and `observed` onto the
#'   surrogate's `q` factor directions before the MMD (default `FALSE`). It
#'   then runs in `q` dimensions, not `k` -- cheaper and higher-powered on the
#'   correlated cross-output structure for a large output count (the MMD loses
#'   power as the dimension grows). It is, deliberately, **blind to distortions
#'   orthogonal to the factor space** (purely idiosyncratic per-output errors,
#'   which the marginal `<o>_sd` and a `joint = FALSE` check cover), so it
#'   complements rather than replaces the full-space check.
#' @param whiten Logical; Mahalanobis-whiten both the predictive draws and
#'   `observed` by their **pooled covariance** before the MMD (default `FALSE`).
#'   This puts the outputs on a common footing, removing the cross-output scale
#'   heterogeneity that makes a single median bandwidth too coarse to resolve a
#'   distortion living in a low-variance direction. The map depends only on the
#'   pooled cloud (not the draws-vs-observed labels), so the permutation test
#'   stays valid; the same map is applied to both clouds, so a relative scale,
#'   shape, or mean difference between them is preserved. Empirically it lifts
#'   power substantially on localised / heterogeneous-scale distortions a
#'   raw-output check misses, with no blind spot found across a mean / variance
#'   / shape battery. A graduated relative ridge guards a near-singular pooled
#'   covariance (highly collinear outputs); it remains opt-in for that numerical
#'   reason. Composes with `project` (the projected coordinates are whitened)
#'   and `aggregate`.
#' @param aggregate Logical; run an **aggregated multi-kernel** MMD instead of a
#'   single-kernel (default `FALSE`). An MMDAgg test (Schrab et al. 2023) over
#'   an RBF bandwidth grid around the median heuristic, sharing the permutations
#'   across bandwidths and aggregating by the weighted-quantile statistic
#'   `min_g p_g / w_g` -- it removes the bandwidth choice and is robust when the
#'   median heuristic is mis-scaled, at a valid level. Composes with `project`.
#'   Reads `n_permutations` and `alpha` from `...`.
#' @param agg_weights Kernel weights for `aggregate = TRUE`: a scheme
#'   (`"uniform"` default, or `"increasing"` / `"decreasing"` / `"centred"`,
#'   ordered smallest-to-largest bandwidth) or a numeric vector over
#'   the bandwidth grid. A larger weight loosens that kernel's threshold, so
#'   up-weighting the scale a distortion is expected to live at recovers power;
#'   `"uniform"` is the safe default (it recovers the min p-value aggregation).
#' @param seed Optional integer RNG seed (the caller's stream is restored).
#' @param ... Passed to [kernR::mmd_ppc()] (e.g. `n_permutations`); for
#'   `aggregate = TRUE`, `n_permutations` and `alpha` are read from here.
#'
#' @return For the single-kernel, the `kernR::mmd_ppc` object (`$statistic`,
#'   `$p_value`, `$reject`, `$surprise_bits`); for `aggregate = TRUE` an
#'   `fb_mmd_agg` object (`$p_value`, `$reject`, `$statistic`, `$bandwidths`,
#'   `$p_per_bandwidth`).
#' @seealso [fit_surrogate()], [predict.fb_surrogate()], [fb_surrogate_ies()].
#' @export
fb_surrogate_ppc <- function(
  surrogate,
  newdata,
  observed,
  n_draws = 1L,
  joint = TRUE,
  project = FALSE,
  whiten = FALSE,
  aggregate = FALSE,
  agg_weights = "uniform",
  seed = NULL,
  ...
) {
  if (!inherits(surrogate, "fb_surrogate")) {
    stop(
      "fb_surrogate_ppc(): `surrogate` must be an fb_surrogate ",
      "(see fit_surrogate()).",
      call. = FALSE
    )
  }
  if (!requireNamespace("kernR", quietly = TRUE)) {
    stop(
      "fb_surrogate_ppc(): package 'kernR' is not installed; it provides the ",
      "mmd_ppc() test. Install the constellation member to run the check.",
      call. = FALSE
    )
  }
  n_draws <- as.integer(n_draws)
  if (n_draws < 1L) {
    stop("fb_surrogate_ppc(): `n_draws` must be >= 1.", call. = FALSE)
  }

  obs_mat <- as.matrix(as.data.frame(observed))
  out_names <- surrogate$output_names
  if (!is.null(colnames(obs_mat))) {
    common <- intersect(out_names, colnames(obs_mat))
    if (length(common) == 0L) {
      stop(
        "fb_surrogate_ppc(): `observed` shares no output column with the ",
        "surrogate (",
        paste(out_names, collapse = ", "),
        ").",
        call. = FALSE
      )
    }
    out_names <- common
    obs_mat <- obs_mat[, out_names, drop = FALSE]
  }

  draws <- .surrogate_ppc_draws(
    surrogate,
    newdata,
    out_names,
    n_draws = n_draws,
    joint = joint,
    seed = seed
  )

  if (isTRUE(project)) {
    has_lr <- identical(surrogate$method, "rff") &&
      isTRUE(surrogate$fit$joint) &&
      !is.null(surrogate$fit[["sigma_lr"]])
    if (!has_lr) {
      stop(
        "fb_surrogate_ppc(): project = TRUE needs a low-rank (cov_rank) rff ",
        "surrogate -- there is no factor space to project onto otherwise.",
        call. = FALSE
      )
    }
    # orthonormal basis of the surrogate's factor span (shared across rows),
    # restricted to the observed outputs; project both clouds into q dimensions
    pc <- stats::predict(surrogate, newdata, cov = "lowrank")
    u_obs <- pc$cov_lowrank$u[match(out_names, pc$output_names), , drop = FALSE]
    basis <- qr.Q(qr(u_obs))
    draws <- draws %*% basis
    obs_mat <- obs_mat %*% basis
  }

  if (isTRUE(whiten)) {
    # whiten the (possibly projected) coordinates by their pooled covariance --
    # a label-agnostic representation that puts the outputs on a common footing
    wc <- .whiten_clouds(draws, obs_mat)
    draws <- wc$x
    obs_mat <- wc$y
  }

  if (isTRUE(aggregate)) {
    dots <- list(...)
    return(.mmd_agg(
      draws,
      obs_mat,
      n_permutations = as.integer(dots$n_permutations %||% 199L),
      alpha = dots$alpha %||% 0.05,
      seed = seed %||% 1L,
      weights = agg_weights
    ))
  }

  kernR::mmd_ppc(draws, observed = obs_mat, ...)
}
