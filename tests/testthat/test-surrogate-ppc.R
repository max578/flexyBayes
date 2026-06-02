# =============================================================================
# test-surrogate-ppc.R -- emulator-distortion check via kernR's mmd_ppc().
#
# A well-trained surrogate's predictive draws should match held-out simulator
# outputs (no reject); an artificially distorted predictive distribution should
# be caught (reject -- power). Gated on kernR being installed.
# =============================================================================

.mk_ppc_surrogate <- function() {
  set.seed(20260602L)
  n <- 250L
  a <- stats::runif(n, -2, 2)
  b <- stats::runif(n, -2, 2)
  e <- fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = data.frame(y = sin(a) + 0.5 * b^2 + stats::rnorm(n, 0, 0.1)),
    provenance = list(source = "raw")
  )
  fit_surrogate(e, method = "rff", seed = 1L)
}

test_that("a faithful surrogate is not rejected by the PPC", {
  skip_if_not_installed("kernR")
  s <- .mk_ppc_surrogate()
  set.seed(4L)
  k <- 60L
  newdata <- data.frame(
    a = stats::runif(k, -1.6, 1.6),
    b = stats::runif(k, -1.6, 1.6)
  )
  # the true simulator outputs at the held-out sets (with the same noise scale)
  observed <- data.frame(
    y = sin(newdata$a) + 0.5 * newdata$b^2 + stats::rnorm(k, 0, 0.1)
  )
  res <- fb_surrogate_ppc(
    s,
    newdata,
    observed,
    n_draws = 5L,
    seed = 1L,
    n_permutations = 199L
  )
  expect_s3_class(res, "mmd_ppc")
  expect_false(res$reject)
})

test_that("a distorted (shifted) predictive distribution is rejected", {
  skip_if_not_installed("kernR")
  s <- .mk_ppc_surrogate()
  set.seed(4L)
  k <- 60L
  newdata <- data.frame(
    a = stats::runif(k, -1.6, 1.6),
    b = stats::runif(k, -1.6, 1.6)
  )
  # observed outputs carry a large systematic shift the surrogate never saw
  observed <- data.frame(
    y = sin(newdata$a) + 0.5 * newdata$b^2 + 3 + stats::rnorm(k, 0, 0.1)
  )
  res <- fb_surrogate_ppc(
    s,
    newdata,
    observed,
    n_draws = 5L,
    seed = 1L,
    n_permutations = 199L
  )
  expect_true(res$reject)
})

test_that("fb_surrogate_ppc() validates its arguments", {
  skip_if_not_installed("kernR")
  s <- .mk_ppc_surrogate()
  nd <- data.frame(a = 0, b = 0)
  expect_error(
    fb_surrogate_ppc("nope", nd, data.frame(y = 1)),
    "must be an fb_surrogate"
  )
  expect_error(
    fb_surrogate_ppc(s, nd, data.frame(nomatch = 1)),
    "shares no output column"
  )
})

# ---- the joint draw path (C7 v1.2, the second consumer of the joint cov) -----

# A 2-output simulator whose outputs are independent functions of separate
# parameters (so the mean surface carries no cross-output structure) plus a
# strongly correlated noise term -- the only cross-output correlation in the data
# is the noise, which a joint surrogate must reproduce.
.mk_corr_surrogate <- function() {
  set.seed(20260603L)
  n <- 300L
  a <- stats::runif(n, -2, 2)
  b <- stats::runif(n, -2, 2)
  s_noise <- chol(matrix(c(0.64, 0.95 * 0.64, 0.95 * 0.64, 0.64), 2L, 2L))
  eps <- matrix(stats::rnorm(n * 2L), n, 2L) %*% s_noise
  e <- fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = data.frame(o1 = 0.25 * a + eps[, 1], o2 = 0.25 * b + eps[, 2]),
    provenance = list(source = "raw")
  )
  list(
    surrogate = fit_surrogate(e, method = "rff", seed = 1L),
    s_noise = s_noise
  )
}

test_that("joint draws carry cross-output correlation a marginal draw destroys", {
  # deterministic: no kernR needed -- check the empirical correlation of the
  # predictive draws themselves at a held-out point.
  s <- .mk_corr_surrogate()$surrogate
  expect_true(isTRUE(s$fit$joint))
  nd <- data.frame(a = 0.3, b = -0.4)
  dj <- .surrogate_ppc_draws(
    s,
    nd,
    c("o1", "o2"),
    n_draws = 4000L,
    joint = TRUE,
    seed = 1L
  )
  dm <- .surrogate_ppc_draws(
    s,
    nd,
    c("o1", "o2"),
    n_draws = 4000L,
    joint = FALSE,
    seed = 1L
  )
  expect_gt(stats::cor(dj[, 1], dj[, 2]), 0.7) # joint draws reproduce the corr
  expect_lt(abs(stats::cor(dm[, 1], dm[, 2])), 0.1) # marginal draws are independent
  # both paths preserve the per-output marginal sd (the <o>_sd contract)
  expect_equal(stats::sd(dj[, 1]), stats::sd(dm[, 1]), tolerance = 0.05)
})

test_that("a single output draws identically under joint and marginal paths", {
  # for k == 1 the joint Cholesky of a 1x1 covariance is its sd, and the RNG is
  # consumed in the same order -- the joint default must not perturb scalar PPCs.
  s <- .mk_ppc_surrogate()
  nd <- data.frame(
    a = stats::runif(20L, -1.5, 1.5),
    b = stats::runif(20L, -1.5, 1.5)
  )
  dj <- .surrogate_ppc_draws(s, nd, "y", n_draws = 3L, joint = TRUE, seed = 7L)
  dm <- .surrogate_ppc_draws(s, nd, "y", n_draws = 3L, joint = FALSE, seed = 7L)
  expect_equal(dj, dm)
})

test_that("the joint PPC passes a faithful joint surrogate the marginal rejects", {
  skip_if_not_installed("kernR")
  obj <- .mk_corr_surrogate()
  s <- obj$surrogate
  set.seed(5L)
  k <- 80L
  nd <- data.frame(
    a = stats::runif(k, -1.8, 1.8),
    b = stats::runif(k, -1.8, 1.8)
  )
  eps2 <- matrix(stats::rnorm(k * 2L), k, 2L) %*% obj$s_noise
  observed <- data.frame(
    o1 = 0.25 * nd$a + eps2[, 1],
    o2 = 0.25 * nd$b + eps2[, 2]
  )
  res_joint <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 10L,
    joint = TRUE,
    seed = 1L,
    n_permutations = 299L
  )
  res_marg <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 10L,
    joint = FALSE,
    seed = 1L,
    n_permutations = 299L
  )
  # the joint draws reproduce the simulator's cross-output correlation, so a
  # faithful surrogate is not rejected; the marginal draws discard it and
  # false-reject -- the joint path is the correct distribution-preserving check.
  expect_false(res_joint$reject)
  expect_true(res_marg$reject)
})
