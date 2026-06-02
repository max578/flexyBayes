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
# kernR owns the test (the MMD machinery is not reimplemented here); flexyBayes
# only generates the predictive sample from the surrogate -- the "contracts not
# internals" rule again. Requires kernR; without it, the check refuses cleanly.
# =============================================================================

#' Posterior-predictive check of a surrogate against held-out outputs
#'
#' Tests whether a surrogate's predictive *distribution* matches the simulator's
#' at held-out parameter sets, using kernR's maximum-mean-discrepancy
#' posterior-predictive check ([kernR::mmd_ppc()]). The surrogate's per-output
#' predictive mean and sd at `newdata` are sampled into a predictive ensemble,
#' which is compared against `observed` -- the true simulator outputs at those
#' parameter sets. A rejection means the emulator distorted the output
#' distribution (typically by being over- or under-dispersed), not merely that
#' its mean is off.
#'
#' This is the distribution-preserving counterpart to a mean-only accuracy
#' check: it exercises the `<o>_sd` the surrogate reports, not just `<o>_mean`.
#'
#' @param surrogate An `fb_surrogate` from [fit_surrogate()].
#' @param newdata A `data.frame` of held-out parameter sets (must contain the
#'   surrogate's parameter columns).
#' @param observed A matrix or `data.frame` of the true simulator outputs at
#'   held-out parameter sets, with columns named for the emulated outputs.
#' @param n_draws Predictive draws per row of `newdata` (default `1`); the
#'   predictive ensemble has `n_draws * nrow(newdata)` rows.
#' @param seed Optional integer RNG seed (the caller's stream is restored).
#' @param ... Passed to [kernR::mmd_ppc()] (e.g. `n_permutations`, `kernel`).
#'
#' @return The `kernR::mmd_ppc` test object (carries `$statistic`, `$p_value`,
#'   `$reject`, `$surprise_bits`).
#' @seealso [fit_surrogate()], [fb_surrogate_ies()].
#' @export
fb_surrogate_ppc <- function(
  surrogate,
  newdata,
  observed,
  n_draws = 1L,
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

  pred <- stats::predict(surrogate, newdata)
  mean_mat <- as.matrix(pred[, paste0(out_names, "_mean"), drop = FALSE])
  sd_mat <- as.matrix(pred[, paste0(out_names, "_sd"), drop = FALSE])
  k <- nrow(mean_mat)
  dcol <- ncol(mean_mat)

  if (!is.null(seed)) {
    if (exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE)) {
      old_seed <- get(".Random.seed", envir = .GlobalEnv, inherits = FALSE)
      on.exit(assign(".Random.seed", old_seed, envir = .GlobalEnv), add = TRUE)
    }
    set.seed(seed)
  }

  draws <- matrix(NA_real_, k * n_draws, dcol)
  for (r in seq_len(n_draws)) {
    noise <- matrix(stats::rnorm(k * dcol), k, dcol)
    draws[((r - 1L) * k + 1L):(r * k), ] <- mean_mat + sd_mat * noise
  }
  colnames(draws) <- out_names

  kernR::mmd_ppc(draws, observed = obs_mat, ...)
}
