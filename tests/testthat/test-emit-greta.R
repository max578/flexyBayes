# Tests for emit_greta() — phase 0.C of deliverable 0.
#
# Snapshot regression firewall: bayesreml() must produce byte-
# identical greta code after migration through fb_from_asreml() +
# emit_greta() compared to the pre-0.C inline pipeline. Five
# representative call shapes are snapshotted via
# expect_snapshot(); a sixth test verifies the bayesreml() ->
# emit_greta() composition matches a direct emit_greta() call on
# the same fb_terms.
#
# Snapshots are recorded on first run after phase 0.C lands and
# committed; any divergence on subsequent commits indicates a
# regression in the IR-or-emit transposition. greta is required
# to be installed (the existing bayesreml() requireNamespace check
# triggers `skip_if_not_installed("greta")` here too).

skip_if_no_greta <- function() skip_if_not_installed("greta")

mk_emit_data <- function() {
  set.seed(42)
  n <- 30L
  data.frame(
    yield = rnorm(n),
    env   = factor(rep(1:3, length.out = n)),
    geno  = factor(rep(1:5, length.out = n)),
    row   = factor(rep(1:5, length.out = n)),
    col   = factor(rep(1:6, length.out = n)),
    x     = rnorm(n)
  )
}

# ---------------------------------------------------------------- #
# Snapshot regression firewall                                     #
# ---------------------------------------------------------------- #

test_that("bayesreml() reproduces minimal gaussian code byte-identical", {
  skip_if_no_greta()
  d <- mk_emit_data()
  code <- bayesreml(
    yield ~ x, data = d,
    verbose = FALSE, return_code = TRUE
  )
  expect_snapshot(cat(code))
})

test_that("bayesreml() reproduces simple random-effect code byte-identical", {
  skip_if_no_greta()
  d <- mk_emit_data()
  code <- bayesreml(
    yield ~ env, random = ~ geno, data = d,
    verbose = FALSE, return_code = TRUE
  )
  expect_snapshot(cat(code))
})

test_that("bayesreml() reproduces fa_gxe code byte-identical", {
  skip_if_no_greta()
  d <- mk_emit_data()
  code <- bayesreml(
    yield ~ env,
    random = ~ fa(env, 2):id(geno),
    data   = d,
    verbose = FALSE, return_code = TRUE
  )
  expect_snapshot(cat(code))
})

test_that("bayesreml() reproduces at(env):units rcov code byte-identical", {
  skip_if_no_greta()
  d <- mk_emit_data()
  code <- bayesreml(
    yield ~ env,
    random = ~ geno,
    rcov   = ~ at(env):units,
    data   = d,
    verbose = FALSE, return_code = TRUE
  )
  expect_snapshot(cat(code))
})

test_that("bayesreml() reproduces ar1_spatial code byte-identical", {
  skip_if_no_greta()
  d <- mk_emit_data()
  code <- bayesreml(
    yield ~ env,
    random = ~ ar1(row):id(col),
    data   = d,
    verbose = FALSE, return_code = TRUE
  )
  expect_snapshot(cat(code))
})

# ---------------------------------------------------------------- #
# Composability: bayesreml() goes through fb_from_asreml() +       #
# emit_greta() and yields the same code as a direct emit_greta()   #
# call on the same fb_terms object.                                #
# ---------------------------------------------------------------- #

test_that("bayesreml(...) and emit_greta(fb_from_asreml(...)) agree byte-for-byte", {
  skip_if_no_greta()
  d <- mk_emit_data()

  via_bayesreml <- bayesreml(
    yield ~ env, random = ~ geno, data = d,
    verbose = FALSE, return_code = TRUE
  )

  fb <- bayesreml:::fb_from_asreml(
    fixed = yield ~ env, random = ~ geno, data = d
  )
  via_emit <- bayesreml:::emit_greta(
    fb = fb, data = d,
    verbose = FALSE, return_code = TRUE,
    fixed = yield ~ env, random = ~ geno
  )

  expect_identical(via_bayesreml, via_emit)
})

# ---------------------------------------------------------------- #
# Guardrail: emit_greta() rejects a non-fb_terms `fb` argument.    #
# ---------------------------------------------------------------- #

test_that("emit_greta() rejects non-fb_terms input", {
  expect_error(
    bayesreml:::emit_greta(fb = list(response = "y"), data = mk_emit_data()),
    "must be an fb_terms object"
  )
})
