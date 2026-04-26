# Tests for triangulate() -- cross-engine posterior comparison
# (deliverable 4).
#
# Pure-numeric tests (Wasserstein-1, R-hat-on-means, name alignment)
# run always. Live cross-engine triangulation tests skip when greta
# or INLA isn't installed.

skip_if_no_greta <- function() skip_if_not_installed("greta")
skip_if_no_inla  <- function() skip_if_not_installed("INLA")

# ---------------------------------------------------------------- #
# Synthetic fits via fb_as_draws_simple.default-replacement helper #
# ---------------------------------------------------------------- #

# Helper: build a synthetic fit-like object for which we can supply
# raw draws via a custom method without needing a real backend.
mk_synthetic <- function(draws) {
  obj <- list(draws = draws)
  class(obj) <- c("synthetic_fit", "list")
  obj
}

# Local method registration -- the test file gets sourced after
# the package is loaded, so this S3 method is visible during
# triangulate() invocation in the same session.
fb_as_draws_simple.synthetic_fit <- function(fit, ...) fit$draws
.S3method <- get("registerS3method")
.S3method("fb_as_draws_simple", "synthetic_fit",
          fb_as_draws_simple.synthetic_fit)

# ---------------------------------------------------------------- #
# Wasserstein-1 (1D)                                               #
# ---------------------------------------------------------------- #

test_that(".wasserstein1_1d() is zero for identical samples", {
  set.seed(1L)
  x <- rnorm(500)
  expect_equal(bayesreml:::.wasserstein1_1d(x, x), 0,
               tolerance = 1e-10)
})

test_that(".wasserstein1_1d() recovers a deterministic shift", {
  set.seed(2L)
  x <- rnorm(2000)
  shift <- 1.5
  expect_equal(bayesreml:::.wasserstein1_1d(x, x + shift),
               shift, tolerance = 0.05)
})

test_that(".wasserstein1_1d() handles edge case with empty samples", {
  expect_true(is.na(bayesreml:::.wasserstein1_1d(numeric(0), 1:5)))
})

# ---------------------------------------------------------------- #
# R-hat-on-means                                                   #
# ---------------------------------------------------------------- #

test_that(".rhat_means_2() is ~1 when posteriors are nearly identical", {
  set.seed(3L)
  x <- rnorm(500)
  y <- rnorm(500)  # same parent distribution
  rh <- bayesreml:::.rhat_means_2(x, y)
  expect_true(rh < 1.1)
})

test_that(".rhat_means_2() grows when posterior means differ", {
  set.seed(4L)
  x <- rnorm(500, mean = 0, sd = 1)
  y <- rnorm(500, mean = 5, sd = 1)
  rh <- bayesreml:::.rhat_means_2(x, y)
  expect_true(rh > 2)
})

test_that(".rhat_means_2() returns NA when within-variance is zero", {
  expect_true(is.na(bayesreml:::.rhat_means_2(rep(1, 5), rep(1, 5))))
})

# ---------------------------------------------------------------- #
# triangulate() integration via synthetic fits                     #
# ---------------------------------------------------------------- #

test_that("triangulate() detects literal-match common parameters", {
  set.seed(5L)
  d_a <- list(alpha = rnorm(500),       beta = rnorm(500))
  d_b <- list(alpha = rnorm(500, 0.1),  beta = rnorm(500, -0.1))
  fit_a <- mk_synthetic(d_a)
  fit_b <- mk_synthetic(d_b)

  tri <- triangulate(fit_a, fit_b)
  expect_s3_class(tri, "triangulate_result")
  expect_identical(tri$n_common, 2L)
  expect_setequal(tri$common, c("alpha", "beta"))
  expect_length(tri$only_a, 0L)
  expect_length(tri$only_b, 0L)
  expect_identical(nrow(tri$metrics), 2L)
})

test_that("triangulate() distinguishes only_a / only_b parameters", {
  set.seed(6L)
  d_a <- list(alpha = rnorm(500), beta = rnorm(500),
              gamma = rnorm(500))
  d_b <- list(alpha = rnorm(500), delta = rnorm(500))
  tri <- triangulate(mk_synthetic(d_a), mk_synthetic(d_b))

  expect_setequal(tri$common, "alpha")
  expect_setequal(tri$only_a, c("beta", "gamma"))
  expect_setequal(tri$only_b, "delta")
})

test_that("triangulate() applies a name_map to fit_b parameter names", {
  set.seed(7L)
  d_a <- list("(Intercept)" = rnorm(500))
  d_b <- list(mu_atg          = rnorm(500))
  tri <- triangulate(mk_synthetic(d_a), mk_synthetic(d_b),
                     name_map = c(mu_atg = "(Intercept)"))
  expect_identical(tri$n_common, 1L)
  expect_setequal(tri$common, "(Intercept)")
})

test_that("triangulate() reports zero common when names don't match", {
  set.seed(8L)
  d_a <- list(mu_atg = rnorm(500))
  d_b <- list("(Intercept):1" = rnorm(500))
  tri <- triangulate(mk_synthetic(d_a), mk_synthetic(d_b))
  expect_identical(tri$n_common, 0L)
  expect_identical(nrow(tri$metrics), 0L)
})

test_that("triangulate() metrics agree with hand calculation", {
  set.seed(9L)
  d_a <- list(p = rnorm(2000, mean = 1.0, sd = 0.5))
  d_b <- list(p = rnorm(2000, mean = 1.2, sd = 0.5))
  tri <- triangulate(mk_synthetic(d_a), mk_synthetic(d_b))

  m <- tri$metrics
  expect_identical(m$param, "p")
  expect_equal(m$mean_a,    mean(d_a$p), tolerance = 1e-10)
  expect_equal(m$mean_b,    mean(d_b$p), tolerance = 1e-10)
  expect_equal(m$mean_diff, mean(d_a$p) - mean(d_b$p),
               tolerance = 1e-10)
  expect_equal(m$sd_ratio,  stats::sd(d_a$p) / stats::sd(d_b$p),
               tolerance = 1e-10)
  expect_true(m$wasserstein_1 > 0.1 && m$wasserstein_1 < 0.4)
  expect_true(m$rhat_means    > 1)
})

test_that("triangulate() errors when no fb_as_draws_simple method exists", {
  bad <- structure(list(), class = "no_method_class")
  expect_error(triangulate(bad, bad),
               "does not know how to extract draws")
})

test_that("triangulate() rejects fb_as_draws_simple returning non-list", {
  registerS3method("fb_as_draws_simple", "bad_fit",
                   function(fit, ...) "not_a_list")
  on.exit(suppressWarnings(rm(fb_as_draws_simple.bad_fit,
                              envir = globalenv())),
          add = TRUE)
  bad <- structure(list(), class = "bad_fit")
  expect_error(triangulate(bad, bad),
               "must return a named list")
})

# ---------------------------------------------------------------- #
# Source detection                                                 #
# ---------------------------------------------------------------- #

test_that(".triangulate_source() distinguishes greta vs INLA fits", {
  greta_fit <- structure(list(), class = "bayesreml")
  inla_fit  <- structure(list(), class = c("bayesreml_inla", "list"))
  expect_identical(bayesreml:::.triangulate_source(greta_fit), "greta")
  expect_identical(bayesreml:::.triangulate_source(inla_fit),  "inla")
})

# ---------------------------------------------------------------- #
# Predicate + print                                                #
# ---------------------------------------------------------------- #

test_that("is_triangulate_result() recognises the class", {
  set.seed(10L)
  d <- list(p = rnorm(100))
  tri <- triangulate(mk_synthetic(d), mk_synthetic(d))
  expect_true(bayesreml:::is_triangulate_result(tri))
  expect_false(bayesreml:::is_triangulate_result(list()))
})

test_that("print.triangulate_result emits the structured header + table", {
  set.seed(11L)
  d_a <- list(p = rnorm(200))
  d_b <- list(p = rnorm(200))
  tri <- triangulate(mk_synthetic(d_a), mk_synthetic(d_b))
  out <- capture.output(print(tri))
  expect_true(any(grepl("triangulate_result", out)))
  expect_true(any(grepl("source_a", out)))
  expect_true(any(grepl("n_common: 1", out)))
  expect_true(any(grepl("Metrics", out)))
})

test_that("print.triangulate_result handles zero common parameters", {
  set.seed(12L)
  d_a <- list(p = rnorm(100))
  d_b <- list(q = rnorm(100))
  tri <- triangulate(mk_synthetic(d_a), mk_synthetic(d_b))
  out <- capture.output(print(tri))
  expect_true(any(grepl("No common parameters", out)))
})

# ---------------------------------------------------------------- #
# Live cross-engine: greta vs INLA -- skip when not installed       #
# ---------------------------------------------------------------- #

test_that("fb_as_draws_simple.bayesreml extracts greta draws", {
  skip_if_no_greta()
  d <- data.frame(y = rnorm(40), x = rnorm(40),
                  g = factor(rep(1:5, length.out = 40)))
  fit <- bayesreml(fixed = y ~ x, data = d,
                   n_samples = 50, warmup = 50, chains = 1,
                   verbose = FALSE, mcmc_verbose = FALSE)
  draws <- bayesreml:::fb_as_draws_simple(fit)
  expect_true(is.list(draws))
  expect_true(length(draws) >= 1L)
  expect_true(all(vapply(draws, is.numeric, logical(1))))
})

test_that("triangulate() runs end-to-end on greta vs INLA", {
  skip_on_cran()        # live greta + INLA + sn end-to-end is too flaky for CRAN
  skip_if_no_greta(); skip_if_no_inla()
  d <- data.frame(y = rnorm(40), x = rnorm(40),
                  g = factor(rep(1:5, length.out = 40)))
  fit_g <- bayesreml(fixed = y ~ x, data = d,
                     n_samples = 50, warmup = 50, chains = 1,
                     verbose = FALSE, mcmc_verbose = FALSE)
  fit_i <- fb(y ~ x, data = d, backend = "inla", verbose = FALSE)
  tri <- triangulate(fit_g, fit_i, n_samples = 200L)
  expect_s3_class(tri, "triangulate_result")
  # n_common may be 0 without name_map -- the test verifies the
  # function runs, not parity-of-naming.
  expect_true(is.numeric(tri$n_common))
})
