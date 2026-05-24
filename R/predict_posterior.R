# predict_posterior.R -- Stage 3B per-draw posterior prediction
# (ADR 0023 Decision 4 file-output + "sample" activation).
#
# Three internal helpers for per-draw posterior prediction:
#
#   .predict_per_draw(object, mm, common, n_draws_cap, sampled_re)
#     Returns an n_rows x n_draws_eff matrix of linear predictor
#     values by computing mm[, common] %*% t(beta_per_draw) for the
#     posterior draws on the fit's $greta$draws slot. Caps draws at
#     `n_draws_cap` (default 4000 per ADR 0023 §3 memory budget) via
#     deterministic stride-subsampling so chunked vs unchunked
#     file output is bitwise identical regardless of RNG state.
#     If `sampled_re` is non-NULL (list keyed by row index, each
#     entry a length-n_draws_eff vector of sampled random-effect
#     realisations), the per-row, per-draw RE realisation is added
#     to the linear predictor. Used by both the file-backed
#     predict() path and the allow_new_levels = "sample" activation.
#
#   .predict_intervals(per_draw_mat, level = 0.95)
#     Returns list(point, lower, upper) with point = posterior mean
#     (rowMeans) and lower / upper = posterior quantiles at
#     (1 - level) / 2 and 1 - (1 - level) / 2.
#
#   .predict_sample_re_for_unknowns(object, unknown_summary,
#                                    n_draws_eff)
#     For each unknown level in each column with allow_new_levels =
#     "sample", samples (n_unknown_levels x n_draws_eff) random
#     effect realisations rnorm(0, tau_per_draw) where tau_per_draw
#     reads off the codegen-named tau_<group> draw column on
#     $greta$draws. Returns a list keyed by row index (global; not
#     chunk-relative), each entry a length-n_draws_eff vector. Uses
#     the caller's RNG state (set.seed() upstream is the
#     reproducibility hook).
#
# Not exported. See R/predict_file_output.R for the file-writing
# layer and R/predict_chunked.R for the chunk-iteration layer; both
# call into these helpers when the relevant ADR 0023 §Decision
# branches are active.

.predict_per_draw <- function(object, mm, common,
                               n_draws_cap = 4000L,
                               sampled_re  = NULL) {
  if (is.null(object$greta) || is.null(object$greta$draws))
    stop(".predict_per_draw(): fit object does not carry posterior ",
         "draws on $greta$draws. File-backed predict(output_file = ",
         "...) and allow_new_levels = \"sample\" both require ",
         "per-draw posterior access. INLA fits do not currently ",
         "carry draws on $greta$draws; an INLA draws adapter is ",
         "queued for a future release.",
         call. = FALSE)

  draws_mat  <- do.call(rbind, lapply(object$greta$draws, as.matrix))
  fixed_info <- object$extras$parse_info$fixed
  beta_cols  <- .get_fixed_draw_columns(fixed_info, colnames(draws_mat))
  if (length(beta_cols) == 0L)
    stop(".predict_per_draw(): no fixed-effect draw columns found ",
         "on the fit. The fit may have no fixed effects or have ",
         "been built under a pre-v0.2 codegen.", call. = FALSE)

  avail         <- beta_cols[beta_cols %in% colnames(draws_mat)]
  beta_per_draw <- draws_mat[, avail, drop = FALSE]

  # Deterministic stride-subsample to the draws cap. Stride-based
  # rather than sample.int() so that chunk_size = 10000 and
  # chunk_size = 1000 give bitwise-identical file output regardless
  # of caller-set RNG state (ADR 0023 §6.d).
  n_total <- nrow(beta_per_draw)
  if (n_total > n_draws_cap) {
    idx <- as.integer(seq.int(1L, n_total, length.out = n_draws_cap))
    beta_per_draw <- beta_per_draw[idx, , drop = FALSE]
  }
  n_draws_eff <- nrow(beta_per_draw)

  # Reorder beta_per_draw columns by `common` so the matrix-multiply
  # below aligns positionally with mm[, common]. The draw-column
  # order is the codegen enumeration of fixed-effect terms; the
  # `common` order is the model.matrix column enumeration on
  # newdata. coef()-aligned beta names sit on beta_per_draw via
  # confint.flexybayes()'s positional contract.
  beta_names <- names(stats::coef(object))
  if (length(beta_names) >= length(avail))
    colnames(beta_per_draw) <- beta_names[seq_along(avail)]
  beta_keep <- intersect(common, colnames(beta_per_draw))
  if (length(beta_keep) == 0L)
    stop(".predict_per_draw(): no overlap between newdata model.",
         "matrix columns and draw-column beta names; check that the ",
         "fit's fixed-effect coding matches the newdata factor levels.",
         call. = FALSE)
  beta_per_draw <- beta_per_draw[, beta_keep, drop = FALSE]
  mm_sub        <- mm[, beta_keep, drop = FALSE]

  # n_rows x n_draws_eff per-draw linear predictor.
  lin_pred <- mm_sub %*% t(beta_per_draw)

  # Sampled-RE contribution for allow_new_levels = "sample" rows.
  # `sampled_re` is keyed by chunk-relative row index (1..nrow(mm))
  # and carries length-n_draws_eff vectors. Add row-wise.
  if (!is.null(sampled_re) && length(sampled_re) > 0L) {
    for (row_idx in names(sampled_re)) {
      i <- as.integer(row_idx)
      if (i < 1L || i > nrow(lin_pred)) next
      re_vec <- sampled_re[[row_idx]]
      if (length(re_vec) != n_draws_eff) {
        # Length mismatch -- truncate / pad with zeros (defensive;
        # caller's responsibility but better than a silent crash).
        len <- min(length(re_vec), n_draws_eff)
        lin_pred[i, seq_len(len)] <- lin_pred[i, seq_len(len)] +
                                       re_vec[seq_len(len)]
      } else {
        lin_pred[i, ] <- lin_pred[i, ] + re_vec
      }
    }
  }

  lin_pred
}


.predict_intervals <- function(per_draw_mat, level = 0.95) {
  if (!is.numeric(level) || length(level) != 1L ||
      level <= 0 || level >= 1)
    stop(".predict_intervals(): `level` must be a numeric scalar in ",
         "(0, 1); got: ", deparse(level), call. = FALSE)
  alpha <- 1 - level
  probs <- c(alpha / 2, 1 - alpha / 2)
  point <- rowMeans(per_draw_mat)
  q_mat <- apply(per_draw_mat, 1L, stats::quantile, probs = probs,
                 names = FALSE)
  # apply() on a single-row input returns a vector, not a matrix.
  if (is.null(dim(q_mat))) q_mat <- matrix(q_mat, nrow = 2L)
  list(point = unname(point),
       lower = unname(q_mat[1L, ]),
       upper = unname(q_mat[2L, ]))
}


.predict_sample_re_for_unknowns <- function(object, unknown_summary,
                                             n_draws_eff,
                                             n_draws_cap = 4000L) {
  if (length(unknown_summary) == 0L) return(list())
  if (is.null(object$greta) || is.null(object$greta$draws))
    stop(".predict_sample_re_for_unknowns(): allow_new_levels = ",
         "\"sample\" requires posterior draws on $greta$draws. ",
         "Fit does not carry them.", call. = FALSE)

  draws_mat <- do.call(rbind, lapply(object$greta$draws, as.matrix))
  n_total   <- nrow(draws_mat)
  if (n_total > n_draws_cap) {
    idx       <- as.integer(seq.int(1L, n_total,
                                     length.out = n_draws_cap))
    draws_mat <- draws_mat[idx, , drop = FALSE]
  }

  out <- list()
  for (col in names(unknown_summary)) {
    info <- unknown_summary[[col]]
    sigma_col <- paste0("sigma_", col)
    tau_pat   <- paste0("^tau_", col, "(\\[|$)")
    tau_cols  <- grep(tau_pat, colnames(draws_mat), value = TRUE)

    # Resolve a length-n_draws_eff vector of group-level RE SDs. The
    # codegen names the group's RE precision-scale as `sigma_<col>`
    # for the per-row path and `tau_<col>[k]` for the indexed path.
    # The standard deviation for the unknown level is best
    # approximated by the prior SD `sigma_<col>` when available
    # (this is the population-level posterior on the RE
    # distribution's scale); fall back to the empirical SD of the
    # known-level tau draws if not.
    if (sigma_col %in% colnames(draws_mat)) {
      tau_per_draw <- draws_mat[, sigma_col]
    } else if (length(tau_cols) > 0L) {
      # Per-draw empirical SD across the known levels.
      tau_mat      <- draws_mat[, tau_cols, drop = FALSE]
      tau_per_draw <- apply(tau_mat, 1L, stats::sd)
    } else {
      stop(".predict_sample_re_for_unknowns(): no RE-scale draws ",
           "found for column `", col, "`. Looked for `", sigma_col,
           "` and `tau_", col, "[k]`. allow_new_levels = \"sample\" ",
           "requires the fit's codegen to expose the RE-scale ",
           "posterior; this fit does not.", call. = FALSE)
    }

    if (length(tau_per_draw) != n_draws_eff) {
      # Stride-subsample tau_per_draw to match n_draws_eff.
      n_t <- length(tau_per_draw)
      i   <- as.integer(seq.int(1L, n_t, length.out = n_draws_eff))
      tau_per_draw <- tau_per_draw[i]
    }

    # For each unknown row index in this column, sample one RE
    # realisation per draw: rnorm(n_draws_eff, 0, tau_per_draw[k]).
    # Caller's set.seed() determines the realisations.
    row_indices <- info$row_indices
    for (i in row_indices) {
      key <- as.character(i)
      out[[key]] <- stats::rnorm(n_draws_eff, mean = 0,
                                  sd = tau_per_draw)
    }
  }

  out
}


# In-memory predict() helper for allow_new_levels = "sample" mode.
# Computes per-draw predictions including sampled-RE contributions
# on the unknown rows, then returns the posterior-mean point
# estimate (and optional posterior-SD se.fit) as a numeric vector
# (or list when se.fit = TRUE). Single-pass; the in-memory sample
# path does not chunk -- chunk-aware sample is in the file-output
# path (.predict_to_file).
.predict_in_memory_sample <- function(object, newdata, type,
                                       se.fit) {
  fixed_formula <- object$glm$formula
  beta          <- stats::coef(object)
  fam_link      <- object$extras$parse_info$family

  mm <- stats::model.matrix(
    stats::delete.response(stats::terms(fixed_formula)),
    data = newdata
  )
  common <- intersect(colnames(mm), names(beta))
  if (length(common) == 0L)
    return(if (isTRUE(se.fit))
             list(fit    = rep(NA_real_, nrow(newdata)),
                  se.fit = rep(NA_real_, nrow(newdata)))
           else
             rep(NA_real_, nrow(newdata)))

  sample_re_summary <- attr(newdata, "sample_re_summary")
  draws_count <- nrow(do.call(rbind,
                        lapply(object$greta$draws, as.matrix)))
  n_draws_eff <- min(draws_count, 4000L)

  sampled_re <- if (!is.null(sample_re_summary))
                  .predict_sample_re_for_unknowns(
                    object          = object,
                    unknown_summary = sample_re_summary,
                    n_draws_eff     = n_draws_eff,
                    n_draws_cap     = 4000L)
                else
                  NULL

  per_draw_lin <- .predict_per_draw(
    object      = object,
    mm          = mm,
    common      = common,
    n_draws_cap = 4000L,
    sampled_re  = sampled_re
  )

  per_draw <- if (identical(type, "response"))
                .apply_link_inverse(per_draw_lin, fam_link$link)
              else
                per_draw_lin

  point <- rowMeans(per_draw)
  if (isTRUE(se.fit)) {
    se <- apply(per_draw, 1L, stats::sd)
    return(list(fit = point, se.fit = se))
  }
  point
}
