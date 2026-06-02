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
#' @param seed Optional integer RNG seed (the caller's stream is restored).
#' @param ... Passed to [kernR::mmd_ppc()] (e.g. `n_permutations`, `kernel`).
#'
#' @return The `kernR::mmd_ppc` test object (carries `$statistic`, `$p_value`,
#'   `$reject`, `$surprise_bits`).
#' @seealso [fit_surrogate()], [predict.fb_surrogate()], [fb_surrogate_ies()].
#' @export
fb_surrogate_ppc <- function(
  surrogate,
  newdata,
  observed,
  n_draws = 1L,
  joint = TRUE,
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

  kernR::mmd_ppc(draws, observed = obs_mat, ...)
}
