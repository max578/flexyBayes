# Tests for the internal Stage 2 MVP `.fb_preflight()` design-memory
# preflight layer (ADR 0021 / v0.3.0). Covers:
#   - the accept path on small in-scope designs
#   - the refusal path with the binding-term identity
#   - the ceiling override (memory_ceiling_gb) accept-after-refuse
#   - aggregated_likelihood_candidate gating: in-scope per term-class,
#     in-scope per family, closed by random-slope, closed by smooth,
#     closed by non-gaussian family
#   - per-term estimate accuracy against object.size() of the actually-
#     allocated representation (the 5% ADR acceptance tolerance)
#   - the metadata-only path produces estimates without touching $data
#   - the refusal-object print surfaces both binding_term and ceiling
#   - the system-RAM probe's fallback to 8 GiB when probes absent
#   - default ceiling resolution yields a positive byte count

# Hand-build a minimal <fb_terms> IR for a given term spec; convenient
# helper for the agg_candidate / smooth / refusal tests where we want
# to bypass the brms walker's smooth refusal.
.test_make_fb_ir <- function(family = "gaussian",
                              link = "identity",
                              n_rows = 1000L,
                              fixed_terms = list(),
                              random_terms = list()) {
  structure(list(
    response       = "y",
    family         = family,
    link           = link,
    intercept      = TRUE,
    fixed_terms    = fixed_terms,
    random_terms   = random_terms,
    rcov_terms     = list(),
    addition_terms = list(),
    priors         = list(),
    data_summary   = list(n = n_rows),
    capabilities   = character(),
    source         = "test"
  ), class = c("fb_terms", "list"))
}


# ---------------------------------------------------------------- #
# Accept / refusal core                                             #
# ---------------------------------------------------------------- #

test_that(".fb_preflight() accepts a small in-scope design", {
  df <- data.frame(y = rnorm(50), x = rnorm(50),
                   g = factor(rep(letters[1:5], 10)))
  fb <- fb_from_brms(y ~ x + (1 | g), data = df)
  pf <- .fb_preflight(fb, .fb_dataset(df))

  expect_s3_class(pf, "fb_preflight")
  expect_null(pf$refusal)
  expect_true(pf$total_estimate_bytes > 0)
  expect_true(pf$ceiling_bytes > 0)
  expect_identical(pf$n_rows, 50)
  # Two terms (fixed numeric x + random intercept g)
  expect_identical(length(pf$per_term_estimate), 2L)
  expect_true("x"        %in% names(pf$per_term_estimate))
  expect_true("(1 | g)"  %in% names(pf$per_term_estimate))
})

test_that(".fb_preflight() refuses when design exceeds tight ceiling", {
  ds <- .fb_dataset(
    data = NULL, n_rows = 1e7,
    col_types = list(y = "double", x = "double", g = "factor"),
    dictionaries = list(g = as.character(seq_len(1e5)))
  )
  fb <- .test_make_fb_ir(
    n_rows = 1e7,
    fixed_terms  = list(list(type = "smooth", var = "x", k = 10L)),
    random_terms = list(list(type = "simple", var = "g", var_n = 1e5))
  )
  pf <- .fb_preflight(fb, ds, memory_ceiling_gb = 0.5)

  expect_s3_class(pf$refusal, "fb_preflight_refusal")
  expect_identical(pf$refusal$reason_code, "design_memory_exceeds_ceiling")
  # Smooth at 1e7 x 10 dense block (~800 MB) is the binding term
  expect_identical(pf$refusal$binding_term, "s(x)")
  expect_true(pf$refusal$binding_bytes > pf$refusal$ceiling_bytes / 2)
})

test_that(".fb_preflight() ceiling override accepts a previously-refused design", {
  ds <- .fb_dataset(
    data = NULL, n_rows = 1e7,
    col_types = list(y = "double", x = "double", g = "factor"),
    dictionaries = list(g = as.character(seq_len(1e5)))
  )
  fb <- .test_make_fb_ir(
    n_rows = 1e7,
    fixed_terms  = list(list(type = "smooth", var = "x", k = 10L)),
    random_terms = list(list(type = "simple", var = "g", var_n = 1e5))
  )
  expect_s3_class(.fb_preflight(fb, ds, memory_ceiling_gb = 0.5)$refusal,
                  "fb_preflight_refusal")
  expect_null(.fb_preflight(fb, ds, memory_ceiling_gb = 16)$refusal)
})

test_that(".fb_preflight() rejects malformed memory_ceiling_gb", {
  ds <- .fb_dataset(data.frame(y = 1:3, x = 1:3))
  fb <- fb_from_brms(y ~ x, data = data.frame(y = rnorm(3), x = rnorm(3)))
  expect_error(.fb_preflight(fb, ds, memory_ceiling_gb = -1),
               regexp = "positive")
  expect_error(.fb_preflight(fb, ds, memory_ceiling_gb = "16"),
               regexp = "positive numeric")
  expect_error(.fb_preflight(fb, ds, memory_ceiling_gb = c(1, 2)),
               regexp = "positive numeric")
})

test_that(".fb_preflight() requires fb_terms IR + fb_dataset wrapper", {
  fb <- fb_from_brms(y ~ x, data = data.frame(y = rnorm(3), x = rnorm(3)))
  ds <- .fb_dataset(data.frame(y = 1:3, x = 1:3))
  expect_error(.fb_preflight(list(), ds), regexp = "fb_terms")
  expect_error(.fb_preflight(fb, list()), regexp = "fb_dataset")
})


# ---------------------------------------------------------------- #
# aggregated_likelihood_candidate flag                              #
# ---------------------------------------------------------------- #

test_that("agg_candidate: gaussian + fixed numeric + random intercept = TRUE", {
  df <- data.frame(y = rnorm(100), x = rnorm(100),
                   g = factor(rep(1:10, 10)))
  fb <- fb_from_brms(y ~ x + (1 | g), data = df)
  pf <- .fb_preflight(fb, .fb_dataset(df))

  expect_true(pf$per_term_estimate$x$aggregated_likelihood_candidate)
  expect_true(pf$per_term_estimate[["(1 | g)"]]$aggregated_likelihood_candidate)
})

test_that("agg_candidate: gaussian + fixed factor = TRUE", {
  df <- data.frame(y = rnorm(100), f = factor(rep(letters[1:4], 25)))
  fb <- fb_from_brms(y ~ f, data = df)
  pf <- .fb_preflight(fb, .fb_dataset(df))

  expect_true(pf$per_term_estimate$f$aggregated_likelihood_candidate)
  expect_identical(pf$per_term_estimate$f$representation_class,
                   "indexed_fixed_factor")
})

test_that("agg_candidate: (x || g) random slope = FALSE", {
  df <- data.frame(y = rnorm(100), x = rnorm(100),
                   g = factor(rep(1:10, 10)))
  fb <- fb_from_brms(y ~ (x || g), data = df)
  pf <- .fb_preflight(fb, .fb_dataset(df))

  # The slope term is the one with " || " in its label
  slope_idx <- grepl("||", names(pf$per_term_estimate), fixed = TRUE)
  expect_true(any(slope_idx))
  slope_entry <- pf$per_term_estimate[[which(slope_idx)[[1L]]]]
  expect_false(slope_entry$aggregated_likelihood_candidate)
  expect_identical(slope_entry$representation_class, "dense_baseline")
})

test_that("agg_candidate: smooth s(x) = FALSE; representation_class = dense_baseline", {
  ds <- .fb_dataset(
    data = NULL, n_rows = 1000L,
    col_types = list(y = "double", x = "double"),
    dictionaries = list()
  )
  fb <- .test_make_fb_ir(
    n_rows      = 1000L,
    fixed_terms = list(list(type = "smooth", var = "x", k = 10L))
  )
  pf <- .fb_preflight(fb, ds)

  expect_false(pf$per_term_estimate[["s(x)"]]$aggregated_likelihood_candidate)
  expect_identical(pf$per_term_estimate[["s(x)"]]$representation_class,
                   "dense_baseline")
})

test_that("agg_candidate: non-gaussian family closes the flag on every term", {
  df <- data.frame(y = rpois(100, 2), x = rnorm(100),
                   g = factor(rep(1:10, 10)))
  fb <- fb_from_brms(y ~ x + (1 | g), data = df, family = "poisson")
  pf <- .fb_preflight(fb, .fb_dataset(df))

  expect_false(pf$per_term_estimate$x$aggregated_likelihood_candidate)
  expect_false(pf$per_term_estimate[["(1 | g)"]]$aggregated_likelihood_candidate)
})


# ---------------------------------------------------------------- #
# Estimate accuracy vs object.size() (5% acceptance tolerance)      #
# ---------------------------------------------------------------- #

test_that("estimate accuracy: fixed numeric within 5% of object.size()", {
  N <- 5000L
  df <- data.frame(y = rnorm(N), x = rnorm(N))
  fb <- fb_from_brms(y ~ x, data = df)
  pf <- .fb_preflight(fb, .fb_dataset(df))

  predicted <- pf$per_term_estimate$x$design_memory_bytes - 256
  actual    <- as.numeric(object.size(df$x)) +
               as.numeric(object.size(numeric(1L)))
  expect_lte(abs(predicted - actual) / actual, 0.05)
})

test_that("estimate accuracy: fixed factor within 5% of object.size()", {
  N <- 5000L; k <- 8L
  df <- data.frame(y = rnorm(N), f = factor(sample.int(k, N, replace = TRUE)))
  fb <- fb_from_brms(y ~ f, data = df)
  pf <- .fb_preflight(fb, .fb_dataset(df))

  predicted <- pf$per_term_estimate$f$design_memory_bytes - 256
  # Integer index (4*N) + (k-1) beta-dummy vector
  actual <- as.numeric(object.size(as.integer(df$f))) +
            as.numeric(object.size(numeric(k - 1L)))
  expect_lte(abs(predicted - actual) / actual, 0.05)
})

test_that("estimate accuracy: random intercept within 5% of object.size()", {
  N <- 5000L; k_g <- 200L
  g <- factor(sample.int(k_g, N, replace = TRUE))
  df <- data.frame(y = rnorm(N), g = g)
  fb <- fb_from_brms(y ~ (1 | g), data = df)
  pf <- .fb_preflight(fb, .fb_dataset(df))

  predicted <- pf$per_term_estimate[["(1 | g)"]]$design_memory_bytes - 256
  actual    <- as.numeric(object.size(as.integer(g))) +
               as.numeric(object.size(numeric(k_g)))
  expect_lte(abs(predicted - actual) / actual, 0.05)
})

test_that("estimate accuracy: smooth s(x) basis block within 5%", {
  N <- 5000L; k <- 10L
  ds <- .fb_dataset(
    data = NULL, n_rows = N,
    col_types = list(y = "double", x = "double"),
    dictionaries = list()
  )
  fb <- .test_make_fb_ir(
    n_rows      = N,
    fixed_terms = list(list(type = "smooth", var = "x", k = k))
  )
  pf <- .fb_preflight(fb, ds)

  predicted <- pf$per_term_estimate[["s(x)"]]$design_memory_bytes - 256
  # Dense N x k double block + k basis coefs
  actual <- as.numeric(object.size(matrix(0, N, k))) +
            as.numeric(object.size(numeric(k)))
  expect_lte(abs(predicted - actual) / actual, 0.05)
})


# ---------------------------------------------------------------- #
# Metadata-only path: O(terms), independent of n_rows               #
# ---------------------------------------------------------------- #

test_that(".fb_preflight() runs on metadata-only fb_dataset without touching $data", {
  ds <- .fb_dataset(
    data = NULL, n_rows = 1e6,
    col_types = list(y = "double", x = "double", g = "factor"),
    dictionaries = list(g = as.character(seq_len(1000L)))
  )
  expect_true(.fb_dataset_is_metadata(ds))
  expect_null(ds$data)

  fb <- .test_make_fb_ir(
    n_rows = 1e6,
    fixed_terms  = list(list(type = "numeric", var = "x")),
    random_terms = list(list(type = "simple", var = "g", var_n = 1000L))
  )
  pf <- .fb_preflight(fb, ds, memory_ceiling_gb = 16)

  expect_null(pf$refusal)
  expect_identical(length(pf$per_term_estimate), 2L)
  # The random-intercept estimate uses the dictionary's 1000 levels
  expect_true(pf$per_term_estimate[["(1 | g)"]]$design_memory_bytes >
              4 * 1e6)
})


# ---------------------------------------------------------------- #
# Ceiling resolution + RAM probe fallback                           #
# ---------------------------------------------------------------- #

test_that("default ceiling resolves to a positive byte count", {
  df <- data.frame(y = rnorm(50), x = rnorm(50))
  fb <- fb_from_brms(y ~ x, data = df)
  pf <- .fb_preflight(fb, .fb_dataset(df))

  expect_true(pf$ceiling_bytes > 0)
  # 8 GiB minimum guaranteed by the fallback even if no probe is present
  expect_true(pf$ceiling_bytes >= 8 * 1024^3 * 0.8 - 1)
})

test_that("ceiling fallback returns 8 GiB when probes return NA", {
  # Use unloadNamespace to simulate the no-probe environment if both
  # packages happen to be installed; safe-skip otherwise.
  with_mock <- function() {
    stub_fn <- function(...) NA_real_
    assignInNamespace(".fb_probe_system_ram", stub_fn,
                      ns = "flexyBayes")
    on.exit({
      # Restore the original probe by re-sourcing the file via load_all
      suppressMessages(devtools::load_all())
    }, add = TRUE)
    df <- data.frame(y = rnorm(50), x = rnorm(50))
    fb <- fb_from_brms(y ~ x, data = df)
    pf <- .fb_preflight(fb, .fb_dataset(df))
    expect_identical(pf$ceiling_bytes, 8 * 1024^3)
  }
  # Wrap in a tryCatch so the test infrastructure rollback always runs
  withCallingHandlers(with_mock(), error = function(e) message(e))
})


# ---------------------------------------------------------------- #
# Print contents + class invariants                                 #
# ---------------------------------------------------------------- #

test_that("print.fb_preflight_refusal() surfaces binding_term + ceiling", {
  ds <- .fb_dataset(
    data = NULL, n_rows = 1e7,
    col_types = list(y = "double", x = "double", g = "factor"),
    dictionaries = list(g = as.character(seq_len(1e5)))
  )
  fb <- .test_make_fb_ir(
    n_rows = 1e7,
    fixed_terms  = list(list(type = "smooth", var = "x", k = 10L)),
    random_terms = list(list(type = "simple", var = "g", var_n = 1e5))
  )
  pf <- .fb_preflight(fb, ds, memory_ceiling_gb = 0.5)

  out <- capture.output(print(pf$refusal))
  expect_true(any(grepl("binding_term:",  out, fixed = TRUE)))
  expect_true(any(grepl("s(x)",           out, fixed = TRUE)))
  expect_true(any(grepl("ceiling_bytes:", out, fixed = TRUE)))
  expect_true(any(grepl("override:",      out, fixed = TRUE)))
  expect_true(any(grepl("memory_ceiling_gb", out, fixed = TRUE)))
})

test_that("class invariants: <fb_preflight> + <fb_preflight_refusal>", {
  df <- data.frame(y = rnorm(50), x = rnorm(50))
  fb <- fb_from_brms(y ~ x, data = df)
  pf <- .fb_preflight(fb, .fb_dataset(df))

  expect_s3_class(pf, "fb_preflight")
  # Inner class is "list" so length() / names() work as expected
  expect_true("list" %in% class(pf))

  # Refusal class only attached when refusing
  ds_big <- .fb_dataset(
    data = NULL, n_rows = 1e8,
    col_types = list(y = "double", g = "factor"),
    dictionaries = list(g = as.character(seq_len(1e7)))
  )
  fb_big <- .test_make_fb_ir(
    n_rows = 1e8,
    random_terms = list(list(type = "simple", var = "g", var_n = 1e7))
  )
  pf_big <- .fb_preflight(fb_big, ds_big, memory_ceiling_gb = 0.1)
  expect_s3_class(pf_big$refusal, "fb_preflight_refusal")
})

test_that(".fb_preflight is internal -- no exported binding", {
  ns  <- asNamespace("flexyBayes")
  exp <- getNamespaceExports(ns)
  expect_false(".fb_preflight"        %in% exp)
  expect_false("fb_preflight"         %in% exp)
  expect_false(".fb_preflight_refusal" %in% exp)
  expect_true(exists(".fb_preflight", envir = ns, inherits = FALSE))
})
