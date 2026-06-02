# =============================================================================
# surrogate_conformers.R -- C7 conformers from constellation siblings.
#
# The C7 surrogate contract (inst/surrogate_contract.md) is honoured by the
# self-contained reference `rff` (R/surrogate.R) and, optionally, by richer
# surrogates from sibling members that REGISTER here rather than being
# reimplemented (the "contracts not internals" rule, mirroring C1 / C5):
#
#   * PESTO's GP surrogate -- train_gp_surrogate() / predict_gp_surrogate()
#     already report a per-output predictive mean AND variance, so it maps
#     straight onto the C7 `<o>_mean` / `<o>_sd` shape.
#   * kernR's conditional mean embedding -- fit_cme() / predict.cme_fit() give a
#     conditional *mean* (a linear smoother y_hat(x*) = w(x*)' y), but no
#     predictive variance. The conformer supplies the standard linear-smoother
#     predictive variance sigma^2 (1 + ||w(x*)||^2) -- honest UQ on top of
#     kernR's mean, not a reimplementation of the embedding.
#
# Both adapters are requireNamespace-gated: flexyBayes stays standalone (the
# `rff` reference needs no sibling). The registration helpers below are also
# called opportunistically from .onLoad when a sibling is installed, so
# `fit_surrogate(method = "gp" / "cme")` works when the member is present.
# =============================================================================

# ---- shared helper: assemble the per-output <o>_mean / <o>_sd data.frame -----

.surrogate_mean_sd_df <- function(mean_mat, sd_mat, output_names) {
  mean_mat <- as.matrix(mean_mat)
  sd_mat <- as.matrix(sd_mat)
  if (ncol(mean_mat) != length(output_names)) {
    stop(
      "surrogate conformer: predicted ",
      ncol(mean_mat),
      " output column(s) but the ensemble declared ",
      length(output_names),
      " (",
      paste(output_names, collapse = ", "),
      ").",
      call. = FALSE
    )
  }
  out <- list()
  for (j in seq_along(output_names)) {
    nm <- output_names[j]
    out[[paste0(nm, "_mean")]] <- mean_mat[, j]
    out[[paste0(nm, "_sd")]] <- sd_mat[, j]
  }
  as.data.frame(out, stringsAsFactors = FALSE)
}

# ---- PESTO GP conformer ------------------------------------------------------

.fit_pesto_gp <- function(x, y, ...) {
  if (!requireNamespace("PESTO", quietly = TRUE)) {
    stop(
      "the 'gp' surrogate needs the 'PESTO' package (not installed).",
      call. = FALSE
    )
  }
  gp <- PESTO::train_gp_surrogate(as.matrix(x), as.matrix(y), ...)
  structure(
    list(gp = gp, output_names = colnames(y)),
    class = "fb_surrogate_pesto_gp"
  )
}

#' @export
predict.fb_surrogate_pesto_gp <- function(object, newdata, ...) {
  pr <- PESTO::predict_gp_surrogate(object$gp, as.matrix(newdata))
  .surrogate_mean_sd_df(
    pr$mean,
    sqrt(pmax(as.matrix(pr$variance), 0)),
    object$output_names
  )
}

#' Register PESTO's GP surrogate as a flexyBayes C7 conformer
#'
#' Makes `method = "gp"` available to [fit_surrogate()] by registering an
#' adapter around PESTO's `train_gp_surrogate()` / `predict_gp_surrogate()`.
#' PESTO's GP already reports a per-output predictive mean and variance, so the
#' adapter only reshapes its output into the contract-C7 `<o>_mean` / `<o>_sd`
#' data.frame (`inst/surrogate_contract.md`) -- PESTO's surrogate is consumed
#' through the registry, never copied into flexyBayes.
#'
#' Called opportunistically from `.onLoad()` when PESTO is installed, so the
#' method is usually already available; call it explicitly to (re-)register.
#'
#' @return Invisibly, the registered method name (`"gp"`).
#' @seealso [register_surrogate()], [fit_surrogate()],
#'   [register_kernr_surrogates()].
#' @export
register_pesto_surrogates <- function() {
  if (!requireNamespace("PESTO", quietly = TRUE)) {
    stop(
      "register_pesto_surrogates(): package 'PESTO' is not installed. ",
      "Install the constellation member, or use the built-in method = ",
      "\"rff\".",
      call. = FALSE
    )
  }
  register_surrogate("gp", .fit_pesto_gp)
  invisible("gp")
}

# ---- kernR CME conformer -----------------------------------------------------

.fit_kernr_cme <- function(x, y, ...) {
  if (!requireNamespace("kernR", quietly = TRUE)) {
    stop(
      "the 'cme' surrogate needs the 'kernR' package (not installed).",
      call. = FALSE
    )
  }
  x <- as.matrix(x)
  y <- as.matrix(y)
  fit <- kernR::fit_cme(x, y, ...)
  # In-sample linear-smoother matrix S = K_xx W = predict(fit, x_train); the
  # CME prediction y_hat(x*) = w(x*)' y is a linear smoother, so its residual
  # noise variance is RSS / (n - tr(S)) and the predictive variance of a NEW
  # observation is sigma^2 (1 + ||w(x*)||^2). This is the honest UQ the C7
  # contract requires; kernR owns the mean, the adapter owns only the spread.
  s_mat <- stats::predict(fit, x)
  edf <- sum(diag(s_mat))
  resid <- y - s_mat %*% y
  n <- nrow(x)
  denom <- max(n - edf, 1)
  sigma2 <- colSums(resid^2) / denom
  sigma2[!is.finite(sigma2) | sigma2 < 0] <- NA_real_
  structure(
    list(
      cme = fit,
      y_train = y,
      sigma2 = sigma2,
      output_names = colnames(y)
    ),
    class = "fb_surrogate_kernr_cme"
  )
}

#' @export
predict.fb_surrogate_kernr_cme <- function(object, newdata, ...) {
  w <- stats::predict(object$cme, as.matrix(newdata)) # n_new x n_train weights
  mean_mat <- w %*% object$y_train # n_new x d_y
  wnorm2 <- rowSums(w^2) # smoother weight energy per row
  sd_mat <- matrix(NA_real_, nrow(mean_mat), ncol(mean_mat))
  for (j in seq_along(object$output_names)) {
    sd_mat[, j] <- sqrt(object$sigma2[j] * (1 + wnorm2))
  }
  .surrogate_mean_sd_df(mean_mat, sd_mat, object$output_names)
}

#' Register kernR's conditional mean embedding as a flexyBayes C7 conformer
#'
#' Makes `method = "cme"` available to [fit_surrogate()] by registering an
#' adapter around kernR's `fit_cme()`. kernR's CME is a kernel linear smoother
#' that yields a conditional *mean* but no predictive variance; the adapter
#' supplies the standard linear-smoother predictive variance
#' `sigma^2 (1 + ||w||^2)` (with `sigma^2 = RSS / (n - tr(S))` from the
#' in-sample smoother), so the emulator honours the C7 distribution-preserving
#' `<o>_sd` requirement. The conditional-mean map stays kernR's; only the
#' uncertainty quantification is added here -- not a reimplementation.
#'
#' Called opportunistically from `.onLoad()` when kernR is installed.
#'
#' @return Invisibly, the registered method name (`"cme"`).
#' @seealso [register_surrogate()], [fit_surrogate()],
#'   [register_pesto_surrogates()].
#' @export
register_kernr_surrogates <- function() {
  if (!requireNamespace("kernR", quietly = TRUE)) {
    stop(
      "register_kernr_surrogates(): package 'kernR' is not installed. ",
      "Install the constellation member, or use the built-in method = ",
      "\"rff\".",
      call. = FALSE
    )
  }
  register_surrogate("cme", .fit_kernr_cme)
  invisible("cme")
}
