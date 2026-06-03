# =============================================================================
# test-surrogate-refinement.R -- ARD lengthscales, the joint multi-output fit,
# the predict(cov = TRUE) surface, and the IES full-covariance consumer.
#
# These pin the C7 refinements on top of the reference rff surrogate: relevance
# determination from the evidence, cross-output covariance preservation (not
# only marginals), and that the joint covariance reaches the ES-MDA consumer.
# All self-contained on the built-in surrogate -- no sibling member needed.
# =============================================================================

# A minimal registered-conformer predict method (a ridge linear fit reporting
# mean + a constant sd) -- the PESTO-GP path shape, used to exercise the IES
# consumer against a registered method without needing a sibling member.
.predict_mock_conformer <- function(object, newdata, ...) {
  xb <- cbind(1, as.matrix(newdata))
  mu <- xb %*% object$beta
  out <- list()
  for (j in seq_along(object$onames)) {
    nm <- object$onames[j]
    out[[paste0(nm, "_mean")]] <- mu[, j]
    out[[paste0(nm, "_sd")]] <- rep(object$sigma[j], nrow(mu))
  }
  as.data.frame(out, stringsAsFactors = FALSE)
}

# ---- ARD lengthscales -------------------------------------------------------

test_that("ARD stretches an irrelevant input's lengthscale and sharpens fit", {
  set.seed(101L)
  n <- 300L
  x1 <- stats::runif(n, -2, 2)
  x2 <- stats::runif(n, -2, 2) # irrelevant: the response does not depend on it
  e <- fb_ensemble(
    params = data.frame(x1 = x1, x2 = x2),
    outputs = data.frame(y = sin(3 * x1) + stats::rnorm(n, 0, 0.05)),
    provenance = list(source = "raw")
  )
  s_ard <- fit_surrogate(e, ard = TRUE, joint = FALSE, seed = 1L)
  s_iso <- fit_surrogate(e, ard = FALSE, joint = FALSE, seed = 1L)

  ls <- s_ard$fit$lengthscales
  expect_length(ls, 2L)
  # the irrelevant dimension is stretched far beyond the relevant one
  expect_gt(ls[2L] / ls[1L], 5)
  # the isotropic reference shares one lengthscale across dimensions
  expect_equal(s_iso$fit$lengthscales[1L], s_iso$fit$lengthscales[2L])

  set.seed(5L)
  g <- data.frame(
    x1 = stats::runif(200, -1.8, 1.8),
    x2 = stats::runif(200, -1.8, 1.8)
  )
  truth <- sin(3 * g$x1)
  rmse_ard <- sqrt(mean((predict(s_ard, g)$y_mean - truth)^2))
  rmse_iso <- sqrt(mean((predict(s_iso, g)$y_mean - truth)^2))
  expect_lt(rmse_ard, 0.10) # ARD recovers the surface
  expect_lt(rmse_ard, rmse_iso) # and beats the isotropic fit here
})

test_that("ARD is deterministic and vacuous in one dimension", {
  set.seed(7L)
  x <- stats::runif(150L, -2, 2)
  e <- fb_ensemble(
    params = data.frame(x = x),
    outputs = data.frame(y = x^2 + stats::rnorm(150L, 0, 0.05)),
    provenance = list(source = "raw")
  )
  s1 <- fit_surrogate(e, seed = 3L)
  s2 <- fit_surrogate(e, seed = 3L)
  expect_length(s1$fit$lengthscales, 1L) # ARD vacuous with one input
  nd <- data.frame(x = c(-1, 0, 1))
  expect_equal(predict(s1, nd), predict(s2, nd))
})

# ---- the joint (multi-output) fit + cross-output covariance -----------------

.mk_correlated <- function(m = 350L, rho = 0.8, s2 = 0.20) {
  set.seed(202L)
  a <- stats::runif(m, -2, 2)
  b <- stats::runif(m, -2, 2)
  lcov <- matrix(c(s2, rho * s2, rho * s2, s2), 2L, 2L)
  eps <- matrix(stats::rnorm(m * 2L), m, 2L) %*% chol(lcov)
  fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = data.frame(
      o1 = sin(a) + 0.3 * b + eps[, 1L],
      o2 = sin(a) - 0.2 * b + eps[, 2L]
    ),
    provenance = list(source = "raw")
  )
}

test_that("the joint fit recovers the cross-output predictive covariance", {
  e <- .mk_correlated(rho = 0.8)
  sj <- fit_surrogate(e, joint = TRUE, seed = 1L)

  pc <- predict(sj, data.frame(a = c(0, 1), b = c(0, 0.5)), cov = TRUE)
  expect_s3_class(pc, "fb_surrogate_prediction")
  expect_identical(dim(pc$mean), c(2L, 2L))
  expect_identical(dim(pc$cov), c(2L, 2L, 2L))

  co <- pc$cov[,, 1L]
  expect_true(isSymmetric(co))
  expect_true(all(eigen(co, only.values = TRUE)$values > 0)) # PD
  corr <- co[1L, 2L] / sqrt(co[1L, 1L] * co[2L, 2L])
  expect_gt(corr, 0.6) # recovers the true 0.8 cross-output correlation
  expect_lt(corr, 1.0)
})

test_that("joint marginals match the independent fit; independent cov is diag", {
  e <- .mk_correlated()
  sj <- fit_surrogate(e, joint = TRUE, seed = 1L)
  si <- fit_surrogate(e, joint = FALSE, seed = 1L)

  nd <- data.frame(a = 0.5, b = -0.3)
  dj <- predict(sj, nd) # marginal data.frame from the joint fit
  di <- predict(si, nd) # marginal data.frame from the independent fit
  # the per-output <o>_sd contract is preserved either way (within ~10%)
  expect_equal(dj$o1_sd, di$o1_sd, tolerance = 0.1)
  expect_equal(dj$o2_sd, di$o2_sd, tolerance = 0.1)

  # the independent fit reports a strictly diagonal predictive covariance
  pci <- predict(si, nd, cov = TRUE)
  expect_identical(pci$cov[1L, 2L, 1L], 0)
})

test_that("predict(cov = TRUE) and the marginal default agree on mean + sd", {
  e <- .mk_correlated()
  sj <- fit_surrogate(e, joint = TRUE, seed = 1L)
  nd <- data.frame(a = c(0, 0.7), b = c(0.2, -0.4))
  df <- predict(sj, nd) # default marginal data.frame
  pc <- predict(sj, nd, cov = TRUE) # joint structured prediction
  expect_equal(df$o1_mean, pc$mean[, 1L])
  expect_equal(df$o2_mean, pc$mean[, 2L])
  # the marginal sd equals the square root of the covariance diagonal
  expect_equal(df$o1_sd, sqrt(pc$cov[1L, 1L, ]))
  expect_equal(df$o2_sd, sqrt(pc$cov[2L, 2L, ]))
})

# ---- the IES consumes the joint covariance ----------------------------------

test_that("the IES full-covariance path differs from the diagonal path", {
  e <- .mk_correlated()
  sj <- fit_surrogate(e, joint = TRUE, seed = 1L)
  observed <- c(o1 = 0.6, o2 = -0.2)

  set.seed(31L)
  prior <- data.frame(
    a = stats::rnorm(300L, 0, 1.2),
    b = stats::rnorm(300L, 0, 1.2)
  )
  fit_full <- fb_surrogate_ies(
    sj,
    observed,
    obs_sd = 0.1,
    prior = prior,
    use_surrogate_cov = TRUE,
    seed = 9L
  )
  fit_diag <- fb_surrogate_ies(
    sj,
    observed,
    obs_sd = 0.1,
    prior = prior,
    use_surrogate_cov = FALSE,
    seed = 9L
  )
  expect_true(fit_full$use_surrogate_cov)
  expect_false(fit_diag$use_surrogate_cov)
  # folding the cross-output covariance in changes the assimilation
  expect_gt(
    sum(abs(colMeans(fit_full$posterior) - colMeans(fit_diag$posterior))),
    1e-6
  )
  # both still reduce the data misfit
  expect_lt(fit_full$misfit[length(fit_full$misfit)], fit_full$misfit[1L])
  expect_lt(fit_diag$misfit[length(fit_diag$misfit)], fit_diag$misfit[1L])
})

test_that("a registered conformer flows through the IES end-to-end", {
  # The PESTO-GP path shape, exercised without PESTO: a registered conformer
  # (mean + sd, marginals only) is consumed by fb_surrogate_ies() via the
  # predict() contract -- the surrogate-accelerated inversion is backend-
  # agnostic, not tied to the built-in rff.
  registerS3method("predict", "mock_conformer", .predict_mock_conformer)
  on.exit(
    if (exists("mockgp", envir = flexyBayes:::.surrogate_registry)) {
      rm("mockgp", envir = flexyBayes:::.surrogate_registry)
    },
    add = TRUE
  )
  register_surrogate("mockgp", function(x, y, ...) {
    x <- as.matrix(x)
    y <- as.matrix(y)
    xb <- cbind(1, x)
    beta <- solve(crossprod(xb) + diag(1e-6, ncol(xb)), crossprod(xb, y))
    resid <- y - xb %*% beta
    structure(
      list(beta = beta, sigma = sqrt(colMeans(resid^2)), onames = colnames(y)),
      class = "mock_conformer"
    )
  })

  set.seed(20260602L)
  g <- rbind(c(1.5, -0.8), c(0.4, 1.1))
  n <- 200L
  theta <- cbind(p1 = stats::runif(n, -3, 3), p2 = stats::runif(n, -3, 3))
  y <- theta %*% t(g)
  colnames(y) <- c("o1", "o2")
  e <- fb_ensemble(
    params = as.data.frame(theta),
    outputs = as.data.frame(y),
    provenance = list(source = "raw")
  )
  s <- fit_surrogate(e, method = "mockgp")
  expect_identical(s$method, "mockgp")

  theta_true <- c(p1 = 1.2, p2 = -0.7)
  observed <- as.numeric(g %*% theta_true)
  names(observed) <- c("o1", "o2")
  set.seed(11L)
  prior <- data.frame(
    p1 = stats::rnorm(250L, 0, 1.5),
    p2 = stats::rnorm(250L, 0, 1.5)
  )
  fit <- fb_surrogate_ies(s, observed, obs_sd = 0.05, prior = prior, seed = 7L)
  prior_err <- sqrt(sum((colMeans(prior) - theta_true)^2))
  post_err <- sqrt(sum((colMeans(fit$posterior) - theta_true)^2))
  expect_lt(post_err, prior_err) # the conformer-backed inversion improved it
  expect_lt(post_err, 0.3)
})

# ---- backward compatibility -------------------------------------------------

test_that("ard = FALSE, joint = FALSE reproduces the independent marginal fit", {
  set.seed(303L)
  n <- 200L
  a <- stats::runif(n, -2, 2)
  b <- stats::runif(n, -2, 2)
  e <- fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = data.frame(
      y1 = sin(a) + stats::rnorm(n, 0, 0.05),
      y2 = b^2 + stats::rnorm(n, 0, 0.05)
    ),
    provenance = list(source = "raw")
  )
  s <- fit_surrogate(e, ard = FALSE, joint = FALSE, seed = 1L)
  expect_false(isTRUE(s$fit$joint))
  expect_true(s$fit$lengthscales[1L] == s$fit$lengthscales[2L])
  nd <- data.frame(a = 1.0, b = 1.5)
  pr <- predict(s, nd)
  expect_equal(pr$y1_mean, sin(1.0), tolerance = 0.15)
  expect_equal(pr$y2_mean, 1.5^2, tolerance = 0.20)
})
