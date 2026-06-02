# =============================================================================
# test-surrogate.R -- the C7 surrogate seam.
#
# Pins the reference RFF Bayesian-linear surrogate (recovery of a known
# function + calibrated predictive sd = the distribution-preserving property),
# the predict contract (per-output mean + sd), the registry, multi-output, and
# ingest through C5.
# =============================================================================

.mk_surrogate_train <- function(n = 250L, noise = 0.05) {
  set.seed(20260602L)
  a <- stats::runif(n, -2, 2)
  b <- stats::runif(n, -2, 2)
  fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = data.frame(
      y = sin(a) + 0.5 * b^2 + stats::rnorm(n, 0, noise)
    ),
    provenance = list(source = "raw")
  )
}

.truth <- function(a, b) sin(a) + 0.5 * b^2

# ---- recovery ---------------------------------------------------------------

test_that("the RFF surrogate recovers a known smooth function", {
  e <- .mk_surrogate_train()
  s <- fit_surrogate(e, method = "rff", n_features = 256L, seed = 1L)
  expect_s3_class(s, "fb_surrogate")

  set.seed(5L)
  grid <- data.frame(
    a = stats::runif(200, -1.8, 1.8),
    b = stats::runif(200, -1.8, 1.8)
  )
  pr <- predict(s, grid)
  truth <- .truth(grid$a, grid$b)
  rmse <- sqrt(mean((pr$y_mean - truth)^2))
  expect_lt(rmse, 0.20) # comfortably recovers the surface
})

test_that("the predictive sd is calibrated (distribution-preserving)", {
  e <- .mk_surrogate_train(noise = 0.10)
  s <- fit_surrogate(e, method = "rff", n_features = 256L, seed = 2L)
  set.seed(6L)
  grid <- data.frame(
    a = stats::runif(300, -1.8, 1.8),
    b = stats::runif(300, -1.8, 1.8)
  )
  pr <- predict(s, grid)
  truth <- .truth(grid$a, grid$b)
  expect_true(all(pr$y_sd > 0))
  # standardised errors z = (truth - mean) / sd should be ~O(1): a badly
  # calibrated sd would push mean|z| far from 1 in either direction.
  z <- (truth - pr$y_mean) / pr$y_sd
  expect_gt(mean(abs(z)), 0.2)
  expect_lt(mean(abs(z)), 3.0)
  # ~95% interval covers a healthy majority of held-out points
  cover <- mean(abs(z) < 1.96)
  expect_gt(cover, 0.6)
})

# ---- predict contract -------------------------------------------------------

test_that("predict() returns per-output mean + sd, one row per newdata row", {
  e <- .mk_surrogate_train()
  s <- fit_surrogate(e, seed = 1L)
  nd <- data.frame(a = c(0, 1, -1), b = c(0, 0.5, 1.5))
  pr <- predict(s, nd)
  expect_identical(nrow(pr), 3L)
  expect_true(all(c("y_mean", "y_sd") %in% colnames(pr)))
  expect_error(predict(s, data.frame(a = 0)), "missing parameter")
  expect_error(predict(s, "notdata"), "data.frame")
})

# ---- multi-output -----------------------------------------------------------

test_that("the surrogate emulates multiple outputs independently", {
  set.seed(3L)
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
  s <- fit_surrogate(e, seed = 1L)
  expect_identical(s$output_names, c("y1", "y2"))
  pr <- predict(s, data.frame(a = 1.0, b = 1.5))
  expect_true(all(c("y1_mean", "y1_sd", "y2_mean", "y2_sd") %in% colnames(pr)))
  expect_equal(pr$y1_mean, sin(1.0), tolerance = 0.15)
  expect_equal(pr$y2_mean, 1.5^2, tolerance = 0.20)
})

# ---- argument handling + ingest --------------------------------------------

test_that("fit_surrogate() validates outputs / params and method", {
  e <- .mk_surrogate_train()
  expect_error(fit_surrogate(e, outputs = "nope"), "outputs not in")
  expect_error(fit_surrogate(e, method = "nope"), "unknown method")
  enop <- fb_ensemble(
    params = data.frame(g = factor(rep(letters[1:4], 5L))),
    outputs = data.frame(y = stats::rnorm(20)),
    provenance = list(source = "raw")
  )
  expect_error(fit_surrogate(enop), "no numeric parameter")
})

test_that("fit_surrogate() is deterministic for a fixed seed", {
  e <- .mk_surrogate_train()
  s1 <- fit_surrogate(e, seed = 42L)
  s2 <- fit_surrogate(e, seed = 42L)
  nd <- data.frame(a = 0.3, b = -0.7)
  expect_equal(predict(s1, nd), predict(s2, nd))
})

test_that("fit_surrogate() does not perturb the caller's RNG stream", {
  e <- .mk_surrogate_train() # build first (the fixture reseeds internally)
  set.seed(123L)
  before <- stats::runif(1L)
  set.seed(123L)
  invisible(fit_surrogate(e, seed = 7L))
  after <- stats::runif(1L)
  expect_identical(before, after)
})

# ---- registry ---------------------------------------------------------------

test_that("register_surrogate() routes a custom method through fit_surrogate()", {
  on.exit(
    if (exists("toy", envir = flexyBayes:::.surrogate_registry)) {
      rm("toy", envir = flexyBayes:::.surrogate_registry)
    },
    add = TRUE
  )
  register_surrogate("toy", function(x, y, ...) {
    list(called = TRUE, n_out = ncol(y), n_feat = ncol(x))
  })
  expect_true("toy" %in% flexyBayes:::.surrogate_methods())
  e <- .mk_surrogate_train()
  s <- fit_surrogate(e, method = "toy")
  expect_identical(s$method, "toy")
  expect_true(s$fit$called)
  expect_identical(s$fit$n_out, 1L)
})

test_that("register_surrogate() validates its arguments", {
  expect_error(register_surrogate("", function(x, y) x), "non-empty")
  expect_error(register_surrogate("k", "nope"), "function")
})

# ---- display -----------------------------------------------------------------

test_that("print.fb_surrogate() summarises cleanly", {
  e <- .mk_surrogate_train()
  expect_output(print(fit_surrogate(e, seed = 1L)), "fb_surrogate")
  expect_output(print(fit_surrogate(e, seed = 1L)), "distribution-preserving")
})
