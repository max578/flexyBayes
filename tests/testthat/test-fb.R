# Tests for fb() — the brms-format public entry (deliverable 1).
#
# Covers IR construction via fb_from_brms(), lgm_gate() routing,
# backend dispatch, and the not-yet-implemented refusal paths for
# `inla` and `brms` backends. greta is required (the existing
# requireNamespace check inside fb() triggers
# `skip_if_not_installed("greta")` here too).

skip_if_no_greta <- function() skip_if_not_installed("greta")

mk_fb_data <- function() {
  set.seed(2026L)
  n <- 30L
  data.frame(
    y = rnorm(n),
    x = rnorm(n),
    g = factor(rep(1:5, length.out = n))
  )
}

# ---------------------------------------------------------------- #
# Code generation via greta backend                                #
# ---------------------------------------------------------------- #

test_that("fb() with backend='greta' generates greta code", {
  skip_if_no_greta()
  d <- mk_fb_data()
  code <- fb(
    y ~ x, data = d,
    backend = "greta",
    verbose = FALSE, return_code = TRUE
  )
  expect_type(code, "character")
  expect_true(nzchar(code))
  expect_match(code, "normal\\(")
})

test_that("fb() with backend='greta' handles random intercept", {
  skip_if_no_greta()
  d <- mk_fb_data()
  code <- fb(
    y ~ x + (1 | g), data = d,
    backend = "greta",
    verbose = FALSE, return_code = TRUE
  )
  expect_type(code, "character")
  # Random-effect signature in the existing greta codegen:
  # `sigma_g <- greta::lognormal(0, ...)` then `g_raw <- normal(...)`
  expect_match(code, "sigma_g")
  expect_match(code, "g_raw")
})

# ---------------------------------------------------------------- #
# backend = 'auto' — greta-fallback in v0.1                        #
# ---------------------------------------------------------------- #

test_that("fb() with backend='auto' messages and dispatches to greta", {
  skip_if_no_greta()
  d <- mk_fb_data()
  expect_message(
    code <- fb(
      y ~ x + (1 | g), data = d,
      backend = "auto",
      verbose = FALSE, return_code = TRUE
    ),
    "v0.1 dispatches to greta"
  )
  expect_type(code, "character")
})

test_that("fb() backend='auto' on non-LGM model still returns greta code", {
  skip_if_no_greta()
  d <- mk_fb_data()
  # Currently fb_from_brms() only supports gaussian/binomial/poisson/
  # gamma/beta/lognormal — i.e., LGM-feasible families. To trigger an
  # LGM-infeasible refusal in lgm_gate(), use a hyperparameter blow-up
  # via many random intercepts.
  d2 <- d
  for (i in 1:6) d2[[paste0("g", i)]] <- factor(rep(1:5, length.out = nrow(d2)))
  re_str <- paste(sprintf("(1 | g%d)", 1:6), collapse = " + ")
  form <- stats::as.formula(paste("y ~ x +", re_str))
  expect_message(
    code <- fb(form, data = d2, backend = "auto",
               verbose = FALSE, return_code = TRUE),
    "v0.1 dispatches to greta"   # 7 hypers = gaussian (1) + 6 RE (6) — soft warn but still LGM-feasible
  )
  expect_type(code, "character")
})

# ---------------------------------------------------------------- #
# Not-yet-implemented backends                                     #
# ---------------------------------------------------------------- #

test_that("fb() with backend='inla' errors politely without INLA installed", {
  skip_if_no_greta()
  if (requireNamespace("INLA", quietly = TRUE)) skip("INLA installed; live-fit tested in test-emit-inla.R")
  d <- mk_fb_data()
  expect_error(
    fb(y ~ x, data = d, backend = "inla", verbose = FALSE),
    "Package 'INLA' is required"
  )
})

test_that("fb() with backend='brms' errors as not-yet-implemented", {
  skip_if_no_greta()
  d <- mk_fb_data()
  expect_error(
    fb(y ~ x, data = d, backend = "brms", verbose = FALSE),
    "not yet implemented"
  )
})

# ---------------------------------------------------------------- #
# Invalid backend rejected by match.arg                            #
# ---------------------------------------------------------------- #

test_that("fb() rejects unknown backend names", {
  skip_if_no_greta()
  d <- mk_fb_data()
  expect_error(
    fb(y ~ x, data = d, backend = "tensorflow_jax_pyro"),
    "should be one of"
  )
})

# ---------------------------------------------------------------- #
# Round-trip: fb() should agree with flexybayes() on equivalent    #
# call shape (same response + same fixed + same RE => same code).  #
# ---------------------------------------------------------------- #

test_that("fb() and flexybayes() agree on a simple fixed + RE model", {
  skip_if_no_greta()
  d <- mk_fb_data()

  via_fb <- fb(
    y ~ x + (1 | g), data = d,
    backend = "greta",
    verbose = FALSE, return_code = TRUE
  )
  via_breml <- flexybayes(
    fixed = y ~ x, random = ~ g, data = d,
    verbose = FALSE, return_code = TRUE
  )

  # The two should be byte-identical because both produce a `simple`
  # random term descriptor for `g`, identical fixed_info, identical
  # rcov defaults, and identical legacy priors.
  expect_identical(via_fb, via_breml)
})
