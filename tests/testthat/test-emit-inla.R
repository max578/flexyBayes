# Tests for emit_inla() -- the INLA backend (deliverable 5 partial).
#
# All tests skip when INLA is not installed; INLA is in
# DESCRIPTION:Suggests with Additional_repositories pointing at
# inla.r-inla-download.org/R/stable. Tests that exercise only the
# pure helpers (.build_inla_formula, .resolve_inla_family) run
# without INLA.

skip_if_no_inla <- function() skip_if_not_installed("INLA")

mk_inla_data <- function() {
  set.seed(2026L)
  n <- 30L
  data.frame(
    y = rnorm(n),
    x = rnorm(n),
    g = factor(rep(1:5, length.out = n))
  )
}

mk_fb_for_inla <- function(data,
                            random_terms = list(list(type = "simple",
                                                       var  = "g"))) {
  fb <- bayesreml:::new_fb_terms(
    response     = "y",
    family       = "gaussian",
    link         = "identity",
    fixed_terms  = list(list(type = "continuous", var = "x")),
    random_terms = random_terms,
    rcov_terms   = list(list(type = "units")),
    source       = "asreml"
  )
  bayesreml:::lgm_gate(fb)
}

# ---------------------------------------------------------------- #
# Pure helpers (run without INLA)                                  #
# ---------------------------------------------------------------- #

test_that(".build_inla_formula() builds intercept + fixed + simple RE", {
  d  <- mk_inla_data()
  fb <- mk_fb_for_inla(d)
  form <- bayesreml:::.build_inla_formula(fb)
  expect_s3_class(form, "formula")
  fstr <- deparse(form)
  expect_match(fstr, "y ~ ")
  expect_match(fstr, "1")
  expect_match(fstr, "x")
  expect_match(fstr, 'f\\(g, model = "iid"\\)')
})

test_that(".build_inla_formula() refuses unsupported random term type", {
  d  <- mk_inla_data()
  fb <- mk_fb_for_inla(d, random_terms = list(list(type = "fa_gxe",
                                                    outer = "env",
                                                    inner = "geno",
                                                    k = 2L)))
  expect_error(
    bayesreml:::.build_inla_formula(fb),
    "does not support random term type \"fa_gxe\""
  )
})

test_that(".resolve_inla_family() maps common families", {
  mk <- function(fam) bayesreml:::new_fb_terms(response = "y",
                                                 family = fam,
                                                 source = "asreml")
  expect_identical(bayesreml:::.resolve_inla_family(mk("gaussian")),
                   "gaussian")
  expect_identical(bayesreml:::.resolve_inla_family(mk("binomial")),
                   "binomial")
  expect_identical(bayesreml:::.resolve_inla_family(mk("poisson")),
                   "poisson")
  expect_identical(bayesreml:::.resolve_inla_family(mk("negative_binomial")),
                   "nbinomial")
  expect_identical(bayesreml:::.resolve_inla_family(mk("gamma")),
                   "gamma")
})

test_that(".lgm_check_numerical() flags non-zero mode.status", {
  fake_fit <- list(mode = list(mode.status = 1L),
                   mlik = matrix(-100, 1, 1))
  res <- bayesreml:::.lgm_check_numerical(fake_fit)
  expect_false(res$pass)
  expect_match(paste(res$reasons, collapse = " "),
               "mode\\.status = 1")
})

test_that(".lgm_check_numerical() flags non-finite mlik", {
  fake_fit <- list(mode = list(mode.status = 0L),
                   mlik = matrix(NaN, 1, 1))
  res <- bayesreml:::.lgm_check_numerical(fake_fit)
  expect_false(res$pass)
  expect_match(paste(res$reasons, collapse = " "),
               "mlik|finite")
})

test_that(".lgm_check_numerical() passes a clean fit", {
  fake_fit <- list(mode = list(mode.status = 0L),
                   mlik = matrix(-50, 1, 1))
  res <- bayesreml:::.lgm_check_numerical(fake_fit)
  expect_true(res$pass)
  expect_length(res$reasons, 0L)
})

# ---------------------------------------------------------------- #
# emit_inla() requires fb_terms                                    #
# ---------------------------------------------------------------- #

test_that("emit_inla() rejects non-fb_terms input", {
  expect_error(
    bayesreml:::emit_inla(fb = list(response = "y"),
                           data = mk_inla_data()),
    "must be an fb_terms object"
  )
})

# ---------------------------------------------------------------- #
# Live fits -- skip when INLA is not installed                     #
# ---------------------------------------------------------------- #

test_that("emit_inla() fits a simple gaussian + RE model", {
  skip_if_no_inla()
  d  <- mk_inla_data()
  fb <- mk_fb_for_inla(d)

  fit <- bayesreml:::emit_inla(fb = fb, data = d, verbose = FALSE)

  expect_s3_class(fit, "bayesreml_inla")
  expect_true(!is.null(fit$inla))
  expect_true(!is.null(fit$extras$summary$fixed))
  expect_true(nrow(fit$extras$summary$fixed) >= 1L)
  expect_true(isTRUE(fit$num_check$pass) ||
              isTRUE(fit$num_check$pass == FALSE))
})

test_that("emit_inla() return_code returns formula and family without fitting", {
  skip_if_no_inla()
  d  <- mk_inla_data()
  fb <- mk_fb_for_inla(d)

  res <- bayesreml:::emit_inla(fb = fb, data = d,
                                verbose = FALSE, return_code = TRUE)
  expect_named(res, c("formula", "family", "hyper"))
  expect_s3_class(res$formula, "formula")
  expect_identical(res$family, "gaussian")
})

test_that("fb(... backend = 'inla') dispatches to emit_inla", {
  skip_if_no_inla()
  d <- mk_inla_data()

  fit <- fb(y ~ x + (1 | g), data = d, backend = "inla", verbose = FALSE)
  expect_s3_class(fit, "bayesreml_inla")
})

test_that("print.bayesreml_inla emits a brief summary", {
  skip_if_no_inla()
  d  <- mk_inla_data()
  fb <- mk_fb_for_inla(d)
  fit <- bayesreml:::emit_inla(fb = fb, data = d, verbose = FALSE)
  out <- capture.output(print(fit))
  expect_true(any(grepl("bayesreml_inla", out)))
  expect_true(any(grepl("formula", out)))
  expect_true(any(grepl("numerical confirm", out)))
})

test_that("summary.bayesreml_inla prints fixed effects and hyperparameters", {
  skip_if_no_inla()
  d  <- mk_inla_data()
  fb <- mk_fb_for_inla(d)
  fit <- bayesreml:::emit_inla(fb = fb, data = d, verbose = FALSE)
  out <- capture.output(summary(fit))
  expect_true(any(grepl("Fixed effects", out)))
  expect_true(any(grepl("Hyperparameters", out)))
})
