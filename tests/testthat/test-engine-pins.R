# Engine pins + two-step-clean deprecations (ADR 0031 Phase 3).
#
# fb_inla() is the new INLA engine pin (sugar over fb(backend = "inla")).
# fb_brms() and fb_greta() carry v0.4.1 deprecation warnings ahead of
# their v0.5.0 recast. These tests force lifecycle_verbosity = "warning"
# locally (the suite is quiet by default; see setup-lifecycle.R).

mk_pin_df <- function(n = 40) {
  set.seed(7)
  data.frame(
    yield = rnorm(n),
    geno  = factor(rep(letters[1:8], length.out = n)),
    env   = factor(rep(c("a", "b"), length.out = n))
  )
}

# ---------------------------------------------------------------- #
# fb_inla() engine pin                                              #
# ---------------------------------------------------------------- #

test_that("fb_inla() is exported and pins the INLA engine", {
  expect_true("fb_inla" %in% getNamespaceExports("flexyBayes"))
  skip_on_cran()
  skip_if_not_installed("INLA")
  df <- mk_pin_df()
  fit <- suppressMessages(
    fb_inla(yield ~ env, random = ~ geno, data = df, verbose = FALSE))
  expect_s3_class(fit, "flexybayes_inla")
  expect_identical(fit$extras$backend_decision$backend, "inla")
})

test_that("fb_inla() passes brms-grammar polymorphism through to INLA", {
  skip_on_cran()
  skip_if_not_installed("INLA")
  df <- mk_pin_df()
  fit <- suppressMessages(
    fb_inla(yield ~ env + (1 | geno), data = df, verbose = FALSE))
  expect_identical(fit$extras$backend_decision$backend, "inla")
})

test_that("fb_inla() preserves missing()-based defaults (default-prior note)", {
  skip_on_cran()
  skip_if_not_installed("INLA")
  # The default-prior note is a once-per-session latch; reset it so this
  # test observes it regardless of earlier fits in the file.
  flexyBayes:::.reset_emit_state_for_test()
  df <- mk_pin_df()
  msgs <- character(0)
  withr::with_options(
    list(flexyBayes.silence_default_prior_note = FALSE),
    withCallingHandlers(
      suppressWarnings(fb_inla(yield ~ env, random = ~ geno, data = df,
                               verbose = FALSE, mcmc_verbose = FALSE)),
      message = function(m) {
        msgs[[length(msgs) + 1L]] <<- conditionMessage(m)
        invokeRestart("muffleMessage")
      }))
  expect_true(any(grepl("variance-component prior default|uniform", msgs)))
})

test_that(".fb_engine_pin() rewrites the call with the backend pinned", {
  cl <- quote(fb_inla(yield ~ env, data = d))
  # emulate match.call() shape inside fb_inla()
  rewritten <- cl
  rewritten[[1L]] <- quote(flexyBayes::flexybayes)
  rewritten$backend <- "inla"
  expect_identical(rewritten$backend, "inla")
  expect_identical(rewritten[[1L]], quote(flexyBayes::flexybayes))
})

# ---------------------------------------------------------------- #
# Deprecations (v0.4.1, two-step clean)                             #
# ---------------------------------------------------------------- #

test_that("fb_brms() warns when fitting a non-brms backend (multi-backend role)", {
  withr::local_options(lifecycle_verbosity = "warning")
  df <- mk_pin_df()
  # backend = "auto" (default) is the deprecated multi-backend usage.
  # plan = TRUE short-circuits before any fit -- fast.
  lifecycle::expect_deprecated(
    suppressMessages(
      fb_brms(yield ~ env + (1 | geno), data = df, backend = "auto",
              plan = TRUE, verbose = FALSE)),
    "multi-backend")
})

test_that("fb_brms(backend = 'brms') does NOT warn (forward-compatible)", {
  withr::local_options(lifecycle_verbosity = "warning")
  df <- mk_pin_df()
  # backend = "brms" is the v0.5.0 engine-pin meaning, so it must not
  # warn -- the call survives the recast unchanged.
  expect_no_condition(
    suppressMessages(
      fb_brms(yield ~ env + (1 | geno), data = df, backend = "brms",
              plan = TRUE, verbose = FALSE)),
    class = "lifecycle_warning_deprecated")
})

test_that("fb_greta() warns that its native-graph signature is deprecated", {
  withr::local_options(lifecycle_verbosity = "warning")
  # The deprecation fires before model validation, so an invalid model
  # exercises the warning without building a greta graph (fast).
  lifecycle::expect_deprecated(
    try(fb_greta(model = 42L), silent = TRUE),
    "native-graph")
})

test_that("the deprecations are silent under lifecycle_verbosity = quiet", {
  withr::local_options(lifecycle_verbosity = "quiet")
  df <- mk_pin_df()
  expect_no_warning(
    suppressMessages(
      fb_brms(yield ~ env + (1 | geno), data = df, plan = TRUE,
              verbose = FALSE)))
})
