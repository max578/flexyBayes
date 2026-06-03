# =============================================================================
# test-fb-pesto.R -- the first C5 consumer: calibration ensemble -> fb_prior.
#
# Pins fb_prior_from_ensemble() (the moments engine + the gated joint/kde
# methods) and fb_pesto() (the PESTO-facing headline verb), including ingest
# through the C5 contract from a PESTO-shaped S7 manifest.
# =============================================================================

.mk_calibration_ensemble <- function(n = 80L) {
  set.seed(7L)
  fb_ensemble(
    params = data.frame(
      k = stats::rnorm(n, mean = 2.0, sd = 0.30),
      r = stats::rnorm(n, mean = 0.5, sd = 0.10)
    ),
    outputs = data.frame(yield = stats::rnorm(n, mean = 5.0, sd = 1.0)),
    provenance = list(source = "raw")
  )
}

# ---- fb_prior_from_ensemble(): moments engine -------------------------------

test_that("fb_prior_from_ensemble() builds a marginal normal prior per parameter", {
  e <- .mk_calibration_ensemble()
  p <- fb_prior_from_ensemble(e, method = "moments")
  expect_true(is_fb_prior(p))
  # one spec per numeric parameter, each a b("<param>") fixed-effect coefficient
  expect_length(p$specs, 2L)
  targets <- vapply(p$specs, function(s) s$target$name, character(1L))
  expect_setequal(targets, c("k", "r"))
  expect_true(all(vapply(p$specs, function(s) s$target$type, character(1L)) ==
                    "b"))
})

test_that("the moments prior recovers the ensemble mean and sd", {
  e <- .mk_calibration_ensemble()
  p <- fb_prior_from_ensemble(e, method = "moments")
  k_spec <- Filter(function(s) s$target$name == "k", p$specs)[[1L]]
  expect_identical(k_spec$spec$family, "normal")
  # the prior's normal(mean, sd) is exactly the ensemble's marginal moments
  expect_equal(k_spec$spec$args$mean, mean(e$params$k))
  expect_equal(k_spec$spec$args$sd, stats::sd(e$params$k))
})

test_that("the gated joint and kde methods refuse with a named alternative", {
  e <- .mk_calibration_ensemble()
  expect_error(
    fb_prior_from_ensemble(e, method = "pesto"),
    "ADR 0008|moments"
  )
  expect_error(
    fb_prior_from_ensemble(e, method = "kde"),
    "kernR|moments"
  )
})

test_that("parameter selection + bad-name handling", {
  e <- .mk_calibration_ensemble()
  p <- fb_prior_from_ensemble(e, parameters = "k")
  expect_length(p$specs, 1L)
  expect_error(
    fb_prior_from_ensemble(e, parameters = "nope"),
    "not in the ensemble"
  )
})

test_that("degenerate (zero-SD) parameters are dropped with a message", {
  e <- fb_ensemble(
    params = data.frame(k = stats::rnorm(30, 1, 0.2), fixed = rep(3.0, 30L)),
    outputs = data.frame(y = stats::rnorm(30)),
    provenance = list(source = "raw")
  )
  expect_message(
    p <- fb_prior_from_ensemble(e),
    "degenerate"
  )
  expect_length(p$specs, 1L) # only k survives
})

test_that("an all-degenerate ensemble errors rather than building an empty prior", {
  e <- fb_ensemble(
    params = data.frame(fixed = rep(3.0, 20L)),
    outputs = data.frame(y = stats::rnorm(20)),
    provenance = list(source = "raw")
  )
  expect_error(suppressMessages(fb_prior_from_ensemble(e)), "no parameter")
})

# ---- fb_pesto(): the headline verb ------------------------------------------

test_that("fb_pesto() returns ensemble + prior + moments", {
  e <- .mk_calibration_ensemble()
  res <- fb_pesto(e)
  expect_s3_class(res, "fb_pesto")
  expect_s3_class(res$ensemble, "fb_ensemble")
  expect_true(is_fb_prior(res$prior))
  expect_identical(res$method, "moments")
  expect_identical(res$moments$parameter, c("k", "r"))
  expect_equal(res$moments$mean[res$moments$parameter == "k"], mean(e$params$k))
  expect_equal(
    res$moments$sd[res$moments$parameter == "r"],
    stats::sd(e$params$r)
  )
})

test_that("fb_pesto() ingests a PESTO-shaped S7 manifest through C5", {
  skip_if_not_installed("S7")
  set.seed(11L)
  manifest_class <- S7::new_class(
    "pesto_ensemble_manifest",
    package = "PESTO",
    properties = list(
      schema_version = S7::class_character,
      params = S7::class_data.frame,
      outputs = S7::class_data.frame,
      obs_target = S7::class_numeric,
      apsim_version = S7::class_character
    )
  )
  m <- manifest_class(
    schema_version = "1.0.0",
    params = data.frame(k = stats::rnorm(40, 2, 0.3)),
    outputs = data.frame(yield = stats::rnorm(40)),
    obs_target = stats::setNames(5.0, "yield"),
    apsim_version = "2024.1"
  )
  res <- fb_pesto(m)
  expect_s3_class(res, "fb_pesto")
  expect_identical(res$provenance$source, "pesto")
  expect_true(is_fb_prior(res$prior))
  expect_identical(res$moments$parameter, "k")
})

test_that("print.fb_pesto() summarises cleanly", {
  e <- .mk_calibration_ensemble()
  expect_output(print(fb_pesto(e)), "fb_pesto")
  expect_output(print(fb_pesto(e)), "moments")
})
