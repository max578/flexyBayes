# =============================================================================
# test-koine-slot.R -- the dormant koine 4th-backend slot (R/koine_slot.R).
#
# koine is the synthesised fourth opinion on the orthogonal lens axis
# (CONSTELLATION.md C1 + C3). Its slot is provisioned but DORMANT -- the
# gretaR-pre-activation analogue. These tests pin the dormant-but-correct
# behaviour the constellation's invariant 6 requires: discoverable via
# koine_status(), refuses at dispatch with a structured condition (never a
# silent wrong fit), registered as a dormant backend, and a canonical-name
# mapper that short-circuits triangulate() cleanly.
# =============================================================================

# ---------------------------------------------------------------- #
# (1) koine_status() returns the documented dormant shape           #
# ---------------------------------------------------------------- #

test_that("koine_status() returns the documented dormant shape", {
  ks <- koine_status()
  expect_type(ks, "list")
  expect_named(
    ks,
    c(
      "activated",
      "koine_installed",
      "builder_confirmed",
      "dormancy_reason",
      "activation_procedure"
    )
  )
  expect_false(ks$activated)
  expect_type(ks$koine_installed, "logical")
  expect_true(is.na(ks$builder_confirmed))
  expect_true(
    ks$dormancy_reason %in%
      c(
        "koine_not_installed",
        "slot_provisioned_not_activated",
        "koine_builder_unconfirmed"
      )
  )
  expect_type(ks$activation_procedure, "character")
  expect_true(length(ks$activation_procedure) >= 1L)
})


# ---------------------------------------------------------------- #
# (2) dormancy reason resolves from install + activation state      #
# ---------------------------------------------------------------- #

test_that("dormancy reason resolves correctly when koine is absent", {
  # koine is not a published package in this environment, so the reason
  # resolves to not-installed regardless of the activation boolean.
  if (nzchar(system.file(package = "koine"))) {
    testthat::skip("koine installed -- this test exercises the absent path")
  }
  withr::local_options(flexyBayes.koine_activated = TRUE)
  expect_identical(
    flexyBayes:::.koine_dormancy_reason(),
    "koine_not_installed"
  )
  expect_identical(
    flexyBayes:::.koine_slot_capability(),
    "koine_slot_dormant"
  )
})


# ---------------------------------------------------------------- #
# (3) the registry capability predicate refuses while dormant       #
# ---------------------------------------------------------------- #

test_that("the dormant capability predicate refuses every model", {
  d <- data.frame(y = stats::rnorm(10L), x = stats::rnorm(10L))
  fb <- fb_from_asreml(fixed = y ~ x, data = d, family = "gaussian")
  expect_identical(
    flexyBayes:::.capability_koine_dormant(fb),
    "koine_slot_dormant"
  )
  # routed through the registry's dispatch-facing accessor
  cf <- flexyBayes:::.backend_can_fit("koine", fb)
  expect_false(cf$ok)
  expect_identical(cf$reason_code, "koine_slot_dormant")
})


# ---------------------------------------------------------------- #
# (4) flexybayes(backend = 'koine') -> match.arg rejection          #
# ---------------------------------------------------------------- #

test_that("flexybayes() does not advertise koine on the backend argument", {
  # The dormant slot is NOT in the user-facing match.arg set, so a user
  # request is rejected at the argument layer (not a dispatch refusal).
  d <- data.frame(y = stats::rnorm(10L), x = stats::rnorm(10L))
  err <- tryCatch(
    flexybayes(y ~ x, data = d, backend = "koine"),
    error = function(e) e
  )
  expect_s3_class(err, "condition")
  expect_match(conditionMessage(err), "should be one of|'arg'")
})


# ---------------------------------------------------------------- #
# (5) internal .dispatch_backend('koine') -> structured refusal     #
# ---------------------------------------------------------------- #

test_that(".dispatch_backend(backend = 'koine') raises koine_dormant_refusal", {
  d <- data.frame(y = stats::rnorm(10L), x = stats::rnorm(10L))
  fb <- fb_from_asreml(fixed = y ~ x, data = d, family = "gaussian")
  err <- tryCatch(
    flexyBayes:::.dispatch_backend(
      fb = fb,
      data = d,
      backend = "koine",
      known_matrices = list(),
      weights = NULL,
      n_samples = 1L,
      warmup = 1L,
      chains = 1L,
      prior_fixed_sd = 100,
      prior_vc_sd = 1,
      verbose = FALSE,
      mcmc_verbose = FALSE,
      return_code = FALSE,
      the_call = quote(test()),
      fixed = y ~ x,
      random = NULL,
      rcov = ~units,
      family = "gaussian",
      link = NULL,
      data_name = "d"
    ),
    error = function(e) e
  )
  expect_s3_class(err, "koine_dormant_refusal")
  expect_true(
    err$dormancy_reason %in%
      c(
        "koine_not_installed",
        "slot_provisioned_not_activated",
        "koine_builder_unconfirmed"
      )
  )
  expect_type(err$activation_procedure, "character")
  # the refusal names the lens-axis role + an active-engine fallback
  expect_match(conditionMessage(err), "lens axis")
  expect_match(conditionMessage(err), "greta|inla|brms|gretaR")
})


# ---------------------------------------------------------------- #
# (6) the canonical-name mapper stub short-circuits triangulate()   #
# ---------------------------------------------------------------- #

test_that("the koine canonical mapper stub returns the scaffold-dormant sentinel", {
  out <- flexyBayes:::.mapper_koine_stub(fit = NULL, fb_terms = NULL)
  expect_identical(out$source, "scaffold_dormant")
  expect_identical(out$map, character(0))
  expect_true(
    out$dormancy_reason %in%
      c(
        "koine_not_installed",
        "slot_provisioned_not_activated",
        "koine_builder_unconfirmed"
      )
  )
})
