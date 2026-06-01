# Tests for the gretaR slot scaffold -- ADR 0013.
#
# Contract:
#   - gretaR_status() returns the v0.2 dormant-slot shape; the
#     activation procedure surfaces the three documented steps.
#   - The canonical-name registry has "gretaR" registered as a
#     scaffold-dormant mapper stub; calling the stub returns the
#     not-yet-available sentinel.
#   - lgm_gate() augments the capabilities of any LGM-compatible IR
#     with the "gretaR_slot_dormant" flag (or "gretaR_dispatch_
#     eligible" when activation lands in v0.3; v0.2 always reports
#     the dormant flag).
#   - User-facing entries (flexybayes(), fb_brms()) do NOT advertise
#     backend = "gretaR" in their match.arg sets; passing it raises
#     the standard match.arg error.
#   - The internal .dispatch_backend(..., backend = "gretaR")
#     branch raises a structured gretaR_dormant_refusal error
#     carrying the dormancy reason + activation procedure.
#
# No gretaR install is required by any subtest -- the scaffold is
# gretaR-independent at v0.2.

mk_lgm_data <- function() {
  set.seed(20260523L)
  n <- 20L
  data.frame(
    y = rnorm(n),
    x = rnorm(n),
    g = factor(rep(1:4, length.out = n))
  )
}


# ---------------------------------------------------------------- #
# (1) gretaR_status() returns the documented v0.2 shape            #
# ---------------------------------------------------------------- #

test_that("gretaR_status() returns the v0.2 dormant-slot shape", {
  old <- options(flexyBayes.gretaR_activated = FALSE)
  on.exit(options(old), add = TRUE)
  gs <- gretaR_status()
  expect_type(gs, "list")
  expect_setequal(
    names(gs),
    c(
      "activated",
      "gretaR_installed",
      "audit_clean",
      "dormancy_reason",
      "activation_procedure"
    )
  )
  expect_false(gs$activated)
  expect_true(
    is.logical(gs$gretaR_installed) &&
      length(gs$gretaR_installed) == 1L
  )
  expect_true(is.na(gs$audit_clean))
  expect_true(
    gs$dormancy_reason %in%
      c("slot_provisioned_not_activated", "gretaR_not_installed")
  )
  expect_true(length(gs$activation_procedure) >= 3L)
  expect_true(any(grepl("gretaR", gs$activation_procedure, fixed = TRUE)))
  expect_true(any(grepl(
    "flexyBayes\\.gretaR_activated",
    gs$activation_procedure
  )))
})


# ---------------------------------------------------------------- #
# (2) Canonical-name registry has the gretaR stub                  #
# ---------------------------------------------------------------- #

test_that("canonical-name registry exposes the gretaR scaffold stub", {
  reg <- flexyBayes:::.canonical_mappers
  expect_true(exists("gretaR", envir = reg, inherits = FALSE))
  mapper <- get("gretaR", envir = reg, inherits = FALSE)
  expect_true(is.function(mapper))
  res <- mapper(NULL, NULL)
  expect_setequal(
    names(res),
    c("map", "transform", "source", "dormancy_reason")
  )
  expect_identical(res$source, "scaffold_dormant")
  expect_identical(length(res$map), 0L)
  expect_identical(length(res$transform), 0L)
  expect_true(nzchar(res$dormancy_reason))
})


# ---------------------------------------------------------------- #
# (3) lgm_gate() appends the gretaR-slot capability flag           #
# ---------------------------------------------------------------- #

test_that("lgm_gate() appends the gretaR slot dormancy flag to LGM-compatible IRs", {
  old <- options(flexyBayes.gretaR_activated = FALSE)
  on.exit(options(old), add = TRUE)
  d <- mk_lgm_data()
  fb <- fb_from_asreml(
    fixed = y ~ x,
    random = ~g,
    data = d,
    family = "gaussian"
  )
  out <- lgm_gate(fb)
  expect_s3_class(out, "fb_terms")
  expect_true("lgm_compatible" %in% out$capabilities)
  expect_true("gretaR_slot_dormant" %in% out$capabilities)
  expect_false("gretaR_dispatch_eligible" %in% out$capabilities)
})


# ---------------------------------------------------------------- #
# (4) flexybayes(backend = 'gretaR') -> standard match.arg error   #
# ---------------------------------------------------------------- #

test_that("flexybayes() rejects backend = 'gretaR' via match.arg (slot not advertised in v0.2)", {
  d <- mk_lgm_data()
  err <- tryCatch(
    flexybayes(y ~ x, random = ~g, data = d, backend = "gretaR"),
    error = function(e) conditionMessage(e)
  )
  expect_true(grepl("'arg'.*should be one of|match.arg", err, perl = TRUE))
  # Confirm the error names the supported set and excludes "gretaR".
  expect_true(grepl("greta", err))
  expect_true(grepl("inla", err))
  expect_true(grepl("auto", err))
})


# ---------------------------------------------------------------- #
# (5) fb(backend = 'gretaR') -> standard match.arg error      #
# ---------------------------------------------------------------- #

test_that("fb_brms() rejects backend = 'gretaR' via match.arg (slot not advertised in v0.2)", {
  d <- mk_lgm_data()
  err <- tryCatch(
    fb(y ~ x + (1 | g), data = d, backend = "gretaR"),
    error = function(e) conditionMessage(e)
  )
  expect_true(grepl("'arg'.*should be one of|match.arg", err, perl = TRUE))
})


# ---------------------------------------------------------------- #
# (6) Internal .dispatch_backend('gretaR') -> structured refusal   #
# ---------------------------------------------------------------- #

test_that(".dispatch_backend(backend = 'gretaR') raises gretaR_dormant_refusal", {
  old <- options(flexyBayes.gretaR_activated = FALSE)
  on.exit(options(old), add = TRUE)
  d <- mk_lgm_data()
  fb <- fb_from_asreml(
    fixed = y ~ x,
    random = ~g,
    data = d,
    family = "gaussian"
  )
  caught <- tryCatch(
    flexyBayes:::.dispatch_backend(
      fb = fb,
      data = d,
      backend = "gretaR",
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
      random = ~g,
      rcov = ~units,
      family = "gaussian",
      link = NULL,
      data_name = "d"
    ),
    gretaR_dormant_refusal = function(e) e,
    error = function(e) e
  )
  expect_s3_class(caught, "gretaR_dormant_refusal")
  expect_true(nzchar(caught$dormancy_reason))
  expect_true(length(caught$activation_procedure) >= 3L)
  msg <- conditionMessage(caught)
  expect_true(grepl("gretaR", msg))
  expect_true(grepl("dormant", msg))
  expect_true(grepl("Activation procedure", msg))
  expect_true(grepl("backend = \"greta\"", msg, fixed = TRUE))
})


# ---------------------------------------------------------------- #
# (7) Activation boolean controls dormancy reason resolution       #
# ---------------------------------------------------------------- #

test_that("activation boolean transitions dormancy reason from not-activated to not-audit-clean", {
  # Only meaningful when gretaR is installed -- otherwise dormancy
  # reason resolves to "gretaR_not_installed" regardless of the
  # boolean. nzchar(system.file()) is the runtime check used
  # internally by .gretaR_dormancy_reason().
  if (!nzchar(system.file(package = "gretaR"))) {
    testthat::skip("gretaR not installed")
  }

  old <- options(flexyBayes.gretaR_activated = FALSE)
  on.exit(options(old), add = TRUE)
  gs_off <- gretaR_status()
  expect_identical(gs_off$dormancy_reason, "slot_provisioned_not_activated")
  expect_false(gs_off$activated)

  withr::local_options(flexyBayes.gretaR_activated = TRUE)
  gs_on <- gretaR_status()
  # v0.2 ships no audit mechanism, so flipping the boolean alone
  # moves the reason to "gretaR_not_audit_clean" rather than to
  # the eligible state.
  expect_identical(gs_on$dormancy_reason, "gretaR_not_audit_clean")
  expect_false(gs_on$activated)
})
