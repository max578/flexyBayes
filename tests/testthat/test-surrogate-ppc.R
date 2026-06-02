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
