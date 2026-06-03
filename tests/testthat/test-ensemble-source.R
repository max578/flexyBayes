# =============================================================================
# test-ensemble-source.R -- the C5 ensemble-source ingest contract.
#
# Pins the canonical fb_ensemble object, the verifier, the ingest generic and
# its producer registry, the file round-trip, and the PESTO (C2 -> C5) bridge.
# The bridge is tested against a locally-built S7 object of class
# `pesto_ensemble_manifest` so it exercises the real dispatch + S7::prop() path
# without requiring PESTO to be installed.
# =============================================================================

.mk_raw_ensemble <- function(n = 12L, p = 2L, q = 3L) {
  set.seed(99L)
  params <- as.data.frame(stats::setNames(
    lapply(seq_len(p), function(j) stats::rnorm(n)),
    paste0("k", seq_len(p))
  ))
  outputs <- as.data.frame(stats::setNames(
    lapply(seq_len(q), function(j) stats::rnorm(n)),
    paste0("y", seq_len(q))
  ))
  list(params = params, outputs = outputs)
}

# ---- constructor + verifier --------------------------------------------------

test_that("fb_ensemble() builds a conforming canonical object", {
  r <- .mk_raw_ensemble()
  e <- fb_ensemble(r$params, r$outputs)
  expect_s3_class(e, "fb_ensemble")
  expect_identical(nrow(e$params), nrow(e$outputs))
  expect_identical(e$provenance$source, "raw")
  expect_identical(e$provenance$n_sets, nrow(r$params))
  expect_true(verify_fb_ensemble(e)$ok)
})

test_that("verify_fb_ensemble() catches every contract violation", {
  r <- .mk_raw_ensemble()
  # row misalignment
  bad <- list(
    params = r$params,
    outputs = r$outputs[-1, , drop = FALSE],
    provenance = list(source = "raw")
  )
  v <- verify_fb_ensemble(bad)
  expect_false(v$ok)
  expect_match(v$message, "row-aligned")
  # empty ensemble
  empty <- list(
    params = r$params[0, , drop = FALSE],
    outputs = r$outputs[0, , drop = FALSE],
    provenance = list(source = "raw")
  )
  expect_false(verify_fb_ensemble(empty)$ok)
  # observed names not a subset of outputs
  badobs <- list(
    params = r$params,
    outputs = r$outputs,
    observed = c(nope = 1.0),
    provenance = list(source = "raw")
  )
  expect_match(verify_fb_ensemble(badobs)$message, "observed")
  # output_dims wrong row count
  baddim <- list(
    params = r$params,
    outputs = r$outputs,
    output_dims = data.frame(variable = "y1"),
    provenance = list(source = "raw")
  )
  expect_match(verify_fb_ensemble(baddim)$message, "output_dims")
  # missing provenance source
  badprov <- list(params = r$params, outputs = r$outputs, provenance = list())
  expect_match(verify_fb_ensemble(badprov)$message, "source")
  # not an ensemble at all
  expect_false(verify_fb_ensemble(list(a = 1))$ok)
})

test_that("fb_ensemble() rejects a non-conforming construction", {
  r <- .mk_raw_ensemble()
  expect_error(
    fb_ensemble(r$params, r$outputs[-1, , drop = FALSE]),
    "row-aligned"
  )
})

test_that("a labelled, observed ensemble verifies", {
  r <- .mk_raw_ensemble(q = 3L)
  od <- data.frame(
    site = c("a", "a", "b"),
    variable = c("yield", "lai", "yield")
  )
  e <- fb_ensemble(
    r$params,
    r$outputs,
    observed = stats::setNames(c(4.0, 2.0), c("y1", "y2")),
    output_dims = od,
    provenance = list(source = "raw", apsim_version = "2024.1")
  )
  expect_true(verify_fb_ensemble(e)$ok)
  expect_identical(nrow(e$output_dims), ncol(e$outputs))
})

# ---- ingest generic + registry ----------------------------------------------

test_that("as_fb_ensemble() dispatches on producer shape", {
  r <- .mk_raw_ensemble()
  e <- fb_ensemble(r$params, r$outputs)
  # identity on an fb_ensemble
  expect_identical(as_fb_ensemble(e), e)
  # a list with params/outputs
  e2 <- as_fb_ensemble(list(params = r$params, outputs = r$outputs))
  expect_s3_class(e2, "fb_ensemble")
  # a list without the required components
  expect_error(as_fb_ensemble(list(foo = 1)), "params")
  # an unknown class with no registered coercer
  expect_error(as_fb_ensemble(structure(1, class = "mystery")), "no coercer")
})

test_that("register_ensemble_source() extends the ingest generic", {
  r <- .mk_raw_ensemble()
  on.exit(
    if (exists("greta_sim", envir = flexyBayes:::.ensemble_source_registry)) {
      rm("greta_sim", envir = flexyBayes:::.ensemble_source_registry)
    },
    add = TRUE
  )
  register_ensemble_source("greta_sim", function(x, ...) {
    fb_ensemble(x$p, x$o, provenance = list(source = "greta_sim"))
  })
  obj <- structure(list(p = r$params, o = r$outputs), class = "greta_sim")
  e <- as_fb_ensemble(obj)
  expect_s3_class(e, "fb_ensemble")
  expect_identical(e$provenance$source, "greta_sim")
})

test_that("register_ensemble_source() validates its arguments", {
  expect_error(register_ensemble_source("", function(x) x), "non-empty")
  expect_error(register_ensemble_source("k", "not a function"), "function")
})

# ---- file round-trip ---------------------------------------------------------

test_that("read_fb_ensemble() round-trips an .rds", {
  r <- .mk_raw_ensemble()
  e <- fb_ensemble(
    r$params,
    r$outputs,
    provenance = list(source = "raw", seed = 99L)
  )
  path <- tempfile(fileext = ".rds")
  on.exit(unlink(path), add = TRUE)
  saveRDS(e, path)
  back <- read_fb_ensemble(path)
  expect_s3_class(back, "fb_ensemble")
  expect_equal(back$params, e$params)
  expect_equal(back$outputs, e$outputs)
  # a path also routes through the generic
  expect_s3_class(as_fb_ensemble(path), "fb_ensemble")
})

test_that("read_fb_ensemble() rejects a missing path or wrong extension", {
  expect_error(read_fb_ensemble("/no/such/file.rds"), "existing file")
  bad <- tempfile(fileext = ".csv")
  file.create(bad)
  on.exit(unlink(bad), add = TRUE)
  expect_error(read_fb_ensemble(bad), "only .rds")
})

# ---- PESTO manifest bridge (C2 -> C5) ---------------------------------------

test_that("as_fb_ensemble() maps a PESTO-shaped S7 manifest (C2 -> C5)", {
  skip_if_not_installed("S7")
  # A faithful stand-in for PESTO's pesto_ensemble_manifest: same class name AND
  # namespace (package = "PESTO"), so class(x) is "PESTO::pesto_ensemble_manifest"
  # exactly as a real PESTO S7 object -- exercising the suffix-match dispatch +
  # S7::prop() reads without needing PESTO installed.
  r <- .mk_raw_ensemble(q = 3L)
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
    params = r$params,
    outputs = r$outputs,
    obs_target = stats::setNames(c(4.0, 2.0), c("y1", "y2")),
    apsim_version = "2024.1"
  )
  e <- as_fb_ensemble(m)
  expect_s3_class(e, "fb_ensemble")
  expect_identical(e$provenance$source, "pesto")
  expect_identical(e$provenance$apsim_version, "2024.1")
  expect_equal(e$params, r$params)
  expect_equal(e$outputs, r$outputs)
  expect_identical(names(e$observed), c("y1", "y2"))
  expect_true(verify_fb_ensemble(e)$ok)
})

# ---- display -----------------------------------------------------------------

test_that("print.fb_ensemble() is a clean one-screen summary", {
  r <- .mk_raw_ensemble()
  e <- fb_ensemble(r$params, r$outputs)
  expect_output(print(e), "fb_ensemble")
  expect_output(print(e), "sets")
})
