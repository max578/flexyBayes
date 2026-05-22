# Tests for the canonical parameter-name registry (ADR 0005).
#
# Contract:
#   - canonical_names(fit) returns a list(map, transform, source, unmapped)
#     resolving the backend-native parameter names to canonical
#     (brms-style) names; transforms carry value-side conversions
#     such as INLA's sqrt(1/prec) precision-to-SD mapping.
#   - The greta mapper translates asreml-emit names: mu_atg ->
#     (Intercept); tau_<tag>[i,1] -> <tag><lvl_i>; sigma_<group> ->
#     sd_<group>; sigma_e_atg -> sigma.
#   - The INLA mapper translates summary.fixed (identity) +
#     summary.hyperpar (Precision for ... -> sd_<group> / sigma)
#     with the precision-to-SD transform attached.
#   - triangulate(fit_a, fit_b, name_map = NULL) auto-resolves via
#     the registry; user-supplied name_map / transform_a / transform_b
#     win over the registry for any keys they carry.
#   - register_canonical_mapper() round-trips a custom mapper.
#   - fb_greta() user-supplied canonical_names argument wins over the
#     verbatim-greta fallback (carried through ADR 0012 sec.1).

skip_if_no_greta <- function() {
  testthat::skip_if_not_installed("greta")
  testthat::skip_on_cran()
  testthat::skip_on_ci()
}

mk_canon_data <- function() {
  set.seed(20260522L)
  n <- 30L
  data.frame(
    yield = rnorm(n, 100, 10),
    env   = factor(rep(1:3, length.out = n)),
    geno  = factor(rep(1:5, length.out = n))
  )
}


# ---------------------------------------------------------------- #
# (a) Greta canonical mapping per ADR 0005 mapping table            #
# ---------------------------------------------------------------- #

test_that("canonical_names() on a greta fit translates asreml-emit names", {
  skip_if_no_greta()
  d <- mk_canon_data()
  fit <- suppressMessages(flexybayes(
    yield ~ env, random = ~ geno, data = d,
    backend = "greta",
    n_samples = 50L, warmup = 50L, chains = 1L,
    verbose = FALSE, mcmc_verbose = FALSE
  ))
  cn <- canonical_names(fit)

  expect_true(is.list(cn))
  expect_true(all(c("map", "transform", "source") %in% names(cn)))
  expect_identical(cn$source, "registry")

  # The mu_atg / sigma_e_atg / sigma_<group> renames are deterministic.
  expect_identical(cn$map[["mu_atg"]], "(Intercept)")
  expect_identical(cn$map[["sigma_e_atg"]], "sigma")
  expect_identical(cn$map[["sigma_geno"]], "sd_geno")

  # tau_env[*,1] -> "env<level-label>" -- factor lookup by IR levels.
  tau_keys <- grep("^tau_env\\[", names(cn$map), value = TRUE)
  expect_true(length(tau_keys) >= 1L)
  for (k in tau_keys) {
    canon <- cn$map[[k]]
    expect_true(startsWith(canon, "env"))
  }

  # No transforms on the greta path.
  expect_length(cn$transform, 0L)
})


# ---------------------------------------------------------------- #
# (b) INLA canonical mapping + sqrt(1/prec) transform               #
# ---------------------------------------------------------------- #

test_that("canonical_names() on an INLA fit translates Precision-for and attaches sqrt(1/prec)", {
  testthat::skip_if_not_installed("INLA")
  d <- mk_canon_data()
  fit <- suppressMessages(flexybayes(
    yield ~ env, random = ~ geno, data = d,
    backend = "inla", verbose = FALSE
  ))
  cn <- canonical_names(fit)

  expect_identical(cn$source, "registry")

  # Fixed-effect rownames are identity.
  expect_identical(cn$map[["(Intercept)"]], "(Intercept)")
  expect_identical(cn$map[["env2"]],        "env2")

  # Hyperparameter rename + transform.
  expect_identical(
    cn$map[["Precision for the Gaussian observations"]], "sigma")
  expect_identical(cn$map[["Precision for geno"]], "sd_geno")

  expect_true(is.function(cn$transform[["sigma"]]))
  expect_true(is.function(cn$transform[["sd_geno"]]))

  # sqrt(1/4) = 0.5 -- the transform is the precision-to-SD form.
  expect_equal(cn$transform[["sigma"]](4),     0.5)
  expect_equal(cn$transform[["sd_geno"]](100), 0.1)
})


# ---------------------------------------------------------------- #
# (c) triangulate(fit_a, fit_b) with name_map = NULL                #
# ---------------------------------------------------------------- #
# Two greta fits of the same model should auto-resolve common
# canonical parameters via the registry without a user-supplied
# name_map. INLA-vs-greta cross-engine resolution lives behind the
# skip_if_not_installed("INLA") guard.

test_that("triangulate() auto-resolves common parameters via the registry", {
  skip_if_no_greta()
  d <- mk_canon_data()
  fit_a <- suppressMessages(flexybayes(
    yield ~ env, random = ~ geno, data = d,
    backend = "greta",
    n_samples = 50L, warmup = 50L, chains = 1L,
    verbose = FALSE, mcmc_verbose = FALSE
  ))
  fit_b <- suppressMessages(flexybayes(
    yield ~ env, random = ~ geno, data = d,
    backend = "greta",
    n_samples = 50L, warmup = 50L, chains = 1L,
    verbose = FALSE, mcmc_verbose = FALSE
  ))
  tri <- triangulate(fit_a, fit_b)

  # Both fits speak canonical names after the rename; intersection
  # should include the four canonical parameters present on a
  # Gaussian random-intercept model.
  expect_true("(Intercept)" %in% tri$common)
  expect_true("sd_geno"     %in% tri$common)
  expect_true("sigma"       %in% tri$common)
  # At least one env-level coefficient survives the rename.
  expect_true(any(grepl("^env", tri$common)))
})


# ---------------------------------------------------------------- #
# (d) Cross-engine triangulate(greta, inla) via the registry         #
# ---------------------------------------------------------------- #

test_that("triangulate() resolves greta vs INLA on a Gaussian random-intercept model", {
  skip_if_no_greta()
  testthat::skip_if_not_installed("INLA")
  d <- mk_canon_data()
  fit_g <- suppressMessages(flexybayes(
    yield ~ env, random = ~ geno, data = d,
    backend = "greta",
    n_samples = 100L, warmup = 100L, chains = 1L,
    verbose = FALSE, mcmc_verbose = FALSE
  ))
  fit_i <- suppressMessages(flexybayes(
    yield ~ env, random = ~ geno, data = d,
    backend = "inla", verbose = FALSE
  ))

  tri <- triangulate(fit_g, fit_i)
  # Canonical names that survive in both fits' renames.
  expect_true("(Intercept)" %in% tri$common)
  expect_true("sd_geno"     %in% tri$common)
  expect_true("sigma"       %in% tri$common)
})


# ---------------------------------------------------------------- #
# (e) register_canonical_mapper() round-trip                         #
# ---------------------------------------------------------------- #

test_that("register_canonical_mapper() round-trips a custom mapper", {
  # Save / restore the registry slot to avoid contaminating the
  # package-level state for other tests.
  prev <- if (exists("test_backend",
                     envir = flexyBayes:::.canonical_mappers,
                     inherits = FALSE))
    get("test_backend",
        envir = flexyBayes:::.canonical_mappers,
        inherits = FALSE)
  else NULL
  on.exit({
    if (is.null(prev))
      rm("test_backend", envir = flexyBayes:::.canonical_mappers)
    else
      assign("test_backend", prev,
             envir = flexyBayes:::.canonical_mappers)
  })

  mapper <- function(fit, fb_terms) {
    list(map = c(x = "X_canon"), transform = list())
  }
  flexyBayes:::register_canonical_mapper("test_backend", mapper)
  out <- get("test_backend",
             envir = flexyBayes:::.canonical_mappers,
             inherits = FALSE)
  expect_identical(out, mapper)

  # Invalid inputs raise clean errors.
  expect_error(
    flexyBayes:::register_canonical_mapper(123, mapper),
    "backend.*non-empty"
  )
  expect_error(
    flexyBayes:::register_canonical_mapper("x", "not a function"),
    "must be a function"
  )
})


# ---------------------------------------------------------------- #
# (f) fb_greta() user-supplied canonical_names wins                  #
# ---------------------------------------------------------------- #

test_that("fb_greta(canonical_names = ...) takes precedence over the verbatim fallback", {
  skip_if_no_greta()
  d <- mk_canon_data()
  y    <- greta::as_data(d$yield)
  b0   <- greta::normal(0, 100)
  sigma <- greta::uniform(0, 50)
  greta::distribution(y) <- greta::normal(b0, sigma)
  m <- greta::model(b0, sigma)

  fit <- suppressMessages(fb_greta(
    m, data = d,
    canonical_names = c(b0 = "(Intercept)", sigma = "sigma"),
    n_samples = 50L, warmup = 50L, chains = 1L,
    verbose = FALSE, mcmc_verbose = FALSE
  ))
  cn <- canonical_names(fit)
  expect_identical(cn$source, "user")
  expect_identical(cn$map[["b0"]],    "(Intercept)")
  expect_identical(cn$map[["sigma"]], "sigma")

  # Without the user-supplied map, fb_greta() falls back to verbatim.
  fit2 <- suppressMessages(fb_greta(
    m, data = d,
    n_samples = 50L, warmup = 50L, chains = 1L,
    verbose = FALSE, mcmc_verbose = FALSE
  ))
  cn2 <- canonical_names(fit2)
  expect_identical(cn2$source, "registry_fallback_verbatim")
  expect_identical(cn2$map[["b0"]], "b0")
})


# ---------------------------------------------------------------- #
# (g) name_map user-supplied wins over registry                      #
# ---------------------------------------------------------------- #

test_that("triangulate() name_map overrides the registry for keyed parameters", {
  skip_if_no_greta()
  d <- mk_canon_data()
  fit_a <- suppressMessages(flexybayes(
    yield ~ env, random = ~ geno, data = d,
    backend = "greta",
    n_samples = 50L, warmup = 50L, chains = 1L,
    verbose = FALSE, mcmc_verbose = FALSE
  ))
  fit_b <- suppressMessages(flexybayes(
    yield ~ env, random = ~ geno, data = d,
    backend = "greta",
    n_samples = 50L, warmup = 50L, chains = 1L,
    verbose = FALSE, mcmc_verbose = FALSE
  ))
  # Override the registry's "sigma_e_atg -> sigma" rename for fit_b
  # only; the canonical "sigma" stays present on fit_a but appears
  # as "renamed_sigma" on fit_b -- so they should NOT intersect on
  # sigma.
  tri <- triangulate(fit_a, fit_b,
                     name_map = c(sigma_e_atg = "renamed_sigma"))
  expect_false("sigma" %in% intersect(
    setdiff(tri$common, "renamed_sigma"),
    "sigma"
  ))
  expect_true("renamed_sigma" %in% tri$only_b ||
              "renamed_sigma" %in% tri$common)
})
