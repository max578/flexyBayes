# =============================================================================
# test-surrogate-ies.R -- surrogate-accelerated ensemble inversion (ES-MDA).
#
# Self-contained on the built-in `rff` reference surrogate (no sibling needed):
# a linear forward model y = G theta, an emulator trained on it, and the check
# that fb_surrogate_ies() pulls a prior ensemble toward the truth while the data
# misfit falls -- plus the surrogate-sd inflation path and argument validation.
# =============================================================================

# A linear forward model so the truth is known and the inversion is exact in
# expectation; the emulator must learn it before the inversion can use it.
.mk_ies_surrogate <- function() {
  set.seed(20260602L)
  g <- rbind(c(1.5, -0.8), c(0.4, 1.1), c(-0.9, 0.6)) # 3 outputs x 2 params
  n <- 250L
  theta <- cbind(p1 = stats::runif(n, -3, 3), p2 = stats::runif(n, -3, 3))
  y <- theta %*% t(g)
  colnames(y) <- c("o1", "o2", "o3")
  e <- fb_ensemble(
    params = as.data.frame(theta),
    outputs = as.data.frame(y),
    provenance = list(source = "raw")
  )
  list(surrogate = fit_surrogate(e, seed = 1L), g = g)
}

test_that("fb_surrogate_ies() moves the ensemble toward truth, misfit falls", {
  obj <- .mk_ies_surrogate()
  theta_true <- c(p1 = 1.2, p2 = -0.7)
  observed <- as.numeric(obj$g %*% theta_true)
  names(observed) <- c("o1", "o2", "o3")

  set.seed(11L)
  prior <- data.frame(
    p1 = stats::rnorm(300, 0, 1.5),
    p2 = stats::rnorm(300, 0, 1.5)
  )
  fit <- fb_surrogate_ies(
    obj$surrogate,
    observed = observed,
    obs_sd = 0.05,
    prior = prior,
    n_iter = 4L,
    seed = 7L
  )
  expect_s3_class(fit, "fb_surrogate_ies")
  expect_identical(nrow(fit$posterior), 300L)

  prior_err <- sqrt(sum((colMeans(prior) - theta_true)^2))
  post_err <- sqrt(sum((colMeans(fit$posterior) - theta_true)^2))
  expect_lt(post_err, prior_err) # the inversion improved the estimate
  expect_lt(post_err, 0.25) # and lands close to the truth

  # data misfit falls monotonically-ish from prior to posterior
  expect_lt(fit$misfit[length(fit$misfit)], fit$misfit[1L])
})

test_that("the surrogate-sd path inflates the data covariance (wider post)", {
  obj <- .mk_ies_surrogate()
  observed <- c(o1 = 1.0, o2 = 0.5, o3 = -0.3)
  set.seed(12L)
  prior <- data.frame(
    p1 = stats::rnorm(300, 0, 1.5),
    p2 = stats::rnorm(300, 0, 1.5)
  )
  fit_with <- fb_surrogate_ies(
    obj$surrogate,
    observed,
    0.05,
    prior,
    n_iter = 4L,
    use_surrogate_sd = TRUE,
    seed = 3L
  )
  fit_without <- fb_surrogate_ies(
    obj$surrogate,
    observed,
    0.05,
    prior,
    n_iter = 4L,
    use_surrogate_sd = FALSE,
    seed = 3L
  )
  # adding the emulator variance to the data covariance assimilates less
  # aggressively, so the posterior spread is not collapsed below the
  # sd-ignoring run
  sd_with <- mean(vapply(fit_with$posterior, stats::sd, numeric(1L)))
  sd_without <- mean(vapply(fit_without$posterior, stats::sd, numeric(1L)))
  expect_gte(sd_with, sd_without * 0.999)
  expect_true(fit_with$use_surrogate_sd)
})

test_that("fb_surrogate_ies() validates its arguments", {
  obj <- .mk_ies_surrogate()
  prior <- data.frame(p1 = stats::rnorm(50), p2 = stats::rnorm(50))
  expect_error(
    fb_surrogate_ies("nope", c(o1 = 1), 0.1, prior),
    "must be an fb_surrogate"
  )
  expect_error(
    fb_surrogate_ies(obj$surrogate, c(1, 2), 0.1, prior),
    "named numeric vector"
  )
  expect_error(
    fb_surrogate_ies(obj$surrogate, c(nope = 1), 0.1, prior),
    "does not\\s+emulate"
  )
  expect_error(
    fb_surrogate_ies(
      obj$surrogate,
      c(o1 = 1),
      0.1,
      data.frame(p1 = stats::rnorm(50))
    ),
    "missing parameter"
  )
  expect_error(
    fb_surrogate_ies(obj$surrogate, c(o1 = 1), -1, prior),
    "finite and positive"
  )
})

# ---- native low-rank consumer (Woodbury, contract clause 5) -----------------

test_that(".apply_inv_lowrank() equals the dense inverse-apply", {
  set.seed(3L)
  p <- 4L
  d <- 9L
  r <- 3L
  ctg <- matrix(stats::rnorm(p * d), p, d)
  rdiag <- stats::runif(d, 0.5, 2)
  lmat <- matrix(stats::rnorm(d * r), d, r)
  dense <- ctg %*% solve(diag(rdiag) + tcrossprod(lmat))
  wood <- .apply_inv_lowrank(ctg, rdiag, lmat)
  expect_equal(wood, dense) # Woodbury == dense to machine precision
})

test_that("a low-rank surrogate drives the IES native (Woodbury) solve", {
  # 5 outputs, rank-2 stored covariance -> the IES uses the factored Kalman path
  set.seed(20260603L)
  g <- rbind(
    c(1.5, -0.8),
    c(0.4, 1.1),
    c(-0.9, 0.6),
    c(0.7, 0.3),
    c(-0.4, 1.2)
  )
  n <- 250L
  theta <- cbind(p1 = stats::runif(n, -3, 3), p2 = stats::runif(n, -3, 3))
  y <- theta %*% t(g)
  colnames(y) <- paste0("o", seq_len(5L))
  e <- fb_ensemble(
    params = as.data.frame(theta),
    outputs = as.data.frame(y),
    provenance = list(source = "raw")
  )
  s_lr <- fit_surrogate(e, joint = TRUE, cov_rank = 2L, seed = 1L)

  theta_true <- c(p1 = 1.2, p2 = -0.7)
  observed <- as.numeric(g %*% theta_true)
  names(observed) <- paste0("o", seq_len(5L))
  set.seed(11L)
  prior <- data.frame(
    p1 = stats::rnorm(300L, 0, 1.5),
    p2 = stats::rnorm(300L, 0, 1.5)
  )
  fit <- fb_surrogate_ies(
    s_lr,
    observed,
    obs_sd = 0.05,
    prior = prior,
    n_iter = 4L,
    seed = 7L
  )
  expect_true(fit$lowrank_solve) # the native low-rank path ran
  post_err <- sqrt(sum((colMeans(fit$posterior) - theta_true)^2))
  expect_lt(post_err, 0.25) # and it recovers the truth
  expect_lt(fit$misfit[length(fit$misfit)], fit$misfit[1L])
})

test_that("a dense-joint surrogate falls back to the dense IES solve", {
  obj <- .mk_ies_surrogate() # joint, no cov_rank -> dense covariance
  set.seed(12L)
  prior <- data.frame(
    p1 = stats::rnorm(200L, 0, 1.5),
    p2 = stats::rnorm(200L, 0, 1.5)
  )
  fit <- fb_surrogate_ies(
    obj$surrogate,
    c(o1 = 1.0, o2 = 0.5, o3 = -0.3),
    obs_sd = 0.1,
    prior = prior,
    seed = 3L
  )
  expect_false(fit$lowrank_solve)
  # and use_surrogate_cov = FALSE also takes the dense (diagonal) path
  fit_diag <- fb_surrogate_ies(
    obj$surrogate,
    c(o1 = 1.0, o2 = 0.5, o3 = -0.3),
    obs_sd = 0.1,
    prior = prior,
    use_surrogate_cov = FALSE,
    seed = 3L
  )
  expect_false(fit_diag$lowrank_solve)
})

test_that("print.fb_surrogate_ies() summarises the prior -> posterior shift", {
  obj <- .mk_ies_surrogate()
  prior <- data.frame(p1 = stats::rnorm(80), p2 = stats::rnorm(80))
  fit <- fb_surrogate_ies(
    obj$surrogate,
    c(o1 = 1, o2 = 0.5, o3 = -0.3),
    0.1,
    prior,
    seed = 1L
  )
  expect_output(print(fit), "fb_surrogate_ies")
  expect_output(print(fit), "data misfit")
})
