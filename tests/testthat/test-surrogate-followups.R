# =============================================================================
# test-surrogate-followups.R -- the cont.37 C7 v1.2 follow-ups:
#   (a) fuller evidence-ARD (ard_refit): profile (a, t) at each lengthscale;
#   (b) low-rank predictive covariance (cov_rank) for large output counts.
#
# Both build on the reference rff surrogate. ard_refit is tested by its
# mathematical guarantee (profiling can only raise the evidence) + determinism +
# preserved relevance ordering, NOT a recovery-improvement claim (it can
# over-shorten lengthscales -- an honest evidence-vs-generalisation tradeoff, so
# it stays opt-in). cov_rank is tested by the two exact guarantees it makes (the
# covariance diagonal is reproduced exactly; the compact and dense forms agree)
# plus accurate reconstruction when the true covariance is genuinely low-rank.
# =============================================================================

# ---- (a) fuller evidence-ARD (ard_refit) ------------------------------------

# A design with one relevant and two irrelevant inputs, so the ARD ordering
# (relevant lengthscale < irrelevant) is checkable, and the internal pieces are
# reachable for the profiling-guarantee assertion.
.mk_ard_design <- function() {
  set.seed(42L)
  n <- 250L
  x1 <- stats::runif(n, -2, 2)
  x2 <- stats::runif(n, -2, 2)
  x3 <- stats::runif(n, -2, 2)
  fb_ensemble(
    params = data.frame(x1 = x1, x2 = x2, x3 = x3),
    outputs = data.frame(y = sin(1.5 * x1) + stats::rnorm(n, 0, 0.05)),
    provenance = list(source = "raw")
  )
}

test_that("ard_refit runs, is deterministic, and preserves relevance ordering", {
  e <- .mk_ard_design()
  s_ref <- fit_surrogate(e, ard = TRUE, ard_refit = TRUE, seed = 1L)
  s_ref2 <- fit_surrogate(e, ard = TRUE, ard_refit = TRUE, seed = 1L)
  ls <- s_ref$fit$lengthscales
  expect_length(ls, 3L)
  expect_equal(ls, s_ref2$fit$lengthscales) # deterministic
  # the relevant input keeps the shortest lengthscale; the irrelevant ones are
  # stretched past it (relevance ranking survives the fuller objective)
  expect_lt(ls[1L], min(ls[2L], ls[3L]))
  expect_gt(min(ls[2L], ls[3L]) / ls[1L], 3)
  # and predict still recovers the surface
  nd <- data.frame(
    x1 = c(-1, 0, 1),
    x2 = c(0, 0, 0),
    x3 = c(0, 0, 0)
  )
  expect_equal(
    predict(s_ref, nd)$y_mean,
    sin(1.5 * c(-1, 0, 1)),
    tolerance = 0.2
  )
})

test_that("ard_refit profiles the evidence: never lower than fixed-(a,t)", {
  # The mathematical guarantee: at the SAME lengthscales, re-fitting (a, t) by
  # evidence (refit) can only raise -- never lower -- the marginal likelihood,
  # because the fixed-(a,t) value is one feasible point of the profiled max.
  e <- .mk_ard_design()
  xs <- scale(as.matrix(e$params))
  ys <- scale(as.matrix(e$outputs))
  ys[!is.finite(ys)] <- 0
  set.seed(1L)
  d <- 200L
  p <- ncol(xs)
  w0 <- matrix(stats::rnorm(d * p), d, p)
  b <- stats::runif(d, 0, 2 * pi)
  l0 <- .rff_lengthscales(xs, ard = TRUE)
  phi_iso <- .rff_features(xs, sweep(w0, 2L, 1 / l0, "*"), b)
  at_fixed <- lapply(
    seq_len(ncol(ys)),
    function(j) .rff_evidence_at(phi_iso, ys[, j])
  )
  l_ref <- .ard_learn_lengthscales(xs, w0, b, ys, l0, at_fixed, refit = TRUE)

  eml_tot <- function(ls, refit) {
    phi <- .rff_features(xs, sweep(w0, 2L, 1 / ls, "*"), b)
    sum(vapply(
      seq_len(ncol(ys)),
      function(j) {
        at <- if (refit) .rff_evidence_at(phi, ys[, j]) else at_fixed[[j]]
        .rff_log_eml(phi, ys[, j], at$a, at$t)
      },
      numeric(1L)
    ))
  }
  # at the refit-learned lengthscales, the profiled evidence >= the fixed one
  expect_gte(eml_tot(l_ref, TRUE), eml_tot(l_ref, FALSE) - 1e-8)
})

test_that("ard_refit is vacuous in one dimension (no per-dim relevance)", {
  set.seed(7L)
  x <- stats::runif(150L, -2, 2)
  e <- fb_ensemble(
    params = data.frame(x = x),
    outputs = data.frame(y = x^2 + stats::rnorm(150L, 0, 0.05)),
    provenance = list(source = "raw")
  )
  s <- fit_surrogate(e, ard = TRUE, ard_refit = TRUE, seed = 3L)
  expect_length(s$fit$lengthscales, 1L)
})

# ---- (b) low-rank predictive covariance (cov_rank) --------------------------

# k correlated outputs whose RESIDUAL noise is genuinely low-rank: a q-factor
# loading shared across outputs plus small idiosyncratic noise, so the noise
# covariance is ~ F F' + diag -- the regime a rank-q factorisation captures well.
.mk_lowrank_outputs <- function(k = 5L, q_true = 2L, n = 400L, idio = 0.05) {
  set.seed(7L)
  a <- stats::runif(n, -2, 2)
  b <- stats::runif(n, -2, 2)
  loadings <- matrix(stats::rnorm(k * q_true), k, q_true)
  z <- matrix(stats::rnorm(n * q_true), n, q_true) # shared latent noise factors
  signal <- cbind(sin(a), 0.5 * b) %*% t(matrix(stats::rnorm(k * 2L), k, 2L))
  noise <- z %*% t(loadings) + matrix(stats::rnorm(n * k, 0, idio), n, k)
  y <- signal + noise
  colnames(y) <- paste0("o", seq_len(k))
  fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = as.data.frame(y),
    provenance = list(source = "raw")
  )
}

test_that("cov_rank reproduces the covariance diagonal (and <o>_sd) exactly", {
  e <- .mk_lowrank_outputs(k = 5L)
  s_full <- fit_surrogate(e, joint = TRUE, seed = 1L)
  s_lr <- fit_surrogate(e, joint = TRUE, cov_rank = 2L, seed = 1L)
  expect_false(is.null(s_lr$fit$sigma_lr))
  expect_identical(s_lr$fit$sigma_lr$rank, 2L)

  nd <- data.frame(a = c(0.3, -0.5), b = c(0.1, 0.4))
  # the marginal sd is identical to the full-rank fit (diagonal preserved)
  expect_equal(predict(s_full, nd)$o1_sd, predict(s_lr, nd)$o1_sd)
  expect_equal(predict(s_full, nd)$o3_sd, predict(s_lr, nd)$o3_sd)

  # and the covariance diagonal equals <o>_sd^2 exactly
  pc <- predict(s_lr, nd, cov = TRUE)
  sl <- fb_cov_slice(pc, 1L)
  m <- predict(s_lr, nd)
  sds <- vapply(paste0("o", 1:5, "_sd"), function(cn) m[[cn]][1L], numeric(1L))
  expect_equal(unname(diag(sl)), unname(sds^2))
})

test_that("the compact lowrank form matches the dense reconstruction", {
  e <- .mk_lowrank_outputs(k = 5L)
  s_lr <- fit_surrogate(e, joint = TRUE, cov_rank = 2L, seed = 1L)
  nd <- data.frame(a = c(0.3, -0.5, 1.0), b = c(0.1, 0.4, -0.2))
  p_dense <- predict(s_lr, nd, cov = TRUE)
  p_lr <- predict(s_lr, nd, cov = "lowrank")
  expect_s3_class(p_lr, "fb_surrogate_prediction")
  expect_false(is.null(p_lr$cov_lowrank))
  expect_identical(ncol(p_lr$cov_lowrank$u), 2L) # rank-q factor
  for (i in seq_len(nrow(nd))) {
    expect_equal(fb_cov_slice(p_lr, i), fb_cov_slice(p_dense, i))
  }
})

test_that("rank-q recovers a genuinely low-rank covariance accurately", {
  e <- .mk_lowrank_outputs(k = 6L, q_true = 2L, idio = 0.03)
  s_full <- fit_surrogate(e, joint = TRUE, seed = 1L)
  s_lr <- fit_surrogate(e, joint = TRUE, cov_rank = 2L, seed = 1L)
  nd <- data.frame(a = 0.4, b = -0.3)
  cov_full <- fb_cov_slice(predict(s_full, nd, cov = TRUE), 1L)
  cov_lr <- fb_cov_slice(predict(s_lr, nd, cov = "lowrank"), 1L)
  off_full <- cov_full[upper.tri(cov_full)]
  rel_err <- max(abs(cov_lr[upper.tri(cov_lr)] - off_full)) / max(abs(off_full))
  expect_lt(rel_err, 0.1) # rank-2 captures the 2-factor cross-output structure
})

test_that("cov_rank storage is smaller and cov_rank >= k keeps the full cov", {
  e <- .mk_lowrank_outputs(k = 6L)
  s_lr <- fit_surrogate(e, joint = TRUE, cov_rank = 2L, seed = 1L)
  # factored store u (k x q) + d (k) is smaller than the dense k x k
  store_lr <- length(s_lr$fit$sigma_lr$u) + length(s_lr$fit$sigma_lr$d)
  expect_lt(store_lr, 6L * 6L)
  # cov_rank >= k is a no-op (the full covariance is kept)
  s_keep <- fit_surrogate(e, joint = TRUE, cov_rank = 6L, seed = 1L)
  expect_null(s_keep$fit$sigma_lr)
})

test_that("cov = lowrank errors on a non-joint surrogate; fb_cov_slice bounds", {
  e <- .mk_lowrank_outputs(k = 4L)
  s_indep <- fit_surrogate(e, joint = FALSE, seed = 1L)
  nd <- data.frame(a = 0.2, b = 0.1)
  expect_error(
    predict(s_indep, nd, cov = "lowrank"),
    "joint rff surrogate only"
  )
  s_joint <- fit_surrogate(e, joint = TRUE, cov_rank = 2L, seed = 1L)
  p_lr <- predict(s_joint, nd, cov = "lowrank")
  expect_error(fb_cov_slice(p_lr, 5L), "row index in 1:")
  expect_error(fb_cov_slice("nope"), "must be an fb_surrogate_prediction")
})
