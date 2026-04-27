# Visual-regression snapshots for plot.flexybayes() via vdiffr.
#
# Audit Phase L (recipe 11). Snapshots are intentionally limited to
# the deterministic plot types -- "effects", "variance", "residuals" --
# whose output depends on the fitted GLM-compatible slot rather than
# on the live posterior trace. The "diagnostics" trace plot is run-
# dependent and is not snapshotted; "pp_check" depends on per-fit
# residual shapes that drift across greta backend revisions.
#
# All tests are skipped on CRAN because the underlying fit requires
# greta + Python + TensorFlow. The vdiffr svg snapshots will diverge
# whenever:
#   (a) the underlying base-R graphics output changes (font metrics,
#       margin defaults), or
#   (b) the upstream coef()/vcov()/variance_comps numerical content
#       drifts beyond reproducibility tolerance.
# Treat case (b) as a substantive regression -- update the snapshot
# only after a deliberate review.

skip_if_no_greta_quiet <- function() {
  testthat::skip_if_not_installed("vdiffr")
  testthat::skip_if_not_installed("greta")
  testthat::skip_on_cran()
  testthat::skip_on_ci()           # graphics device differs across runners
}

# Cache one tiny fit for all snapshot tests in this file. Cheap (n = 40,
# 100 samples, 1 chain) and deterministic given the seed.
.cached_fit <- local({
  fit <- NULL
  function() {
    if (is.null(fit)) {
      set.seed(20260427L)
      d <- data.frame(
        y = rnorm(40),
        x = rnorm(40),
        g = factor(rep(seq_len(5), length.out = 40))
      )
      fit <<- flexybayes(
        fixed     = y ~ x,
        random    = ~ g,
        data      = d,
        n_samples = 100,
        warmup    = 100,
        chains    = 1,
        verbose   = FALSE,
        mcmc_verbose = FALSE
      )
    }
    fit
  }
})

test_that("plot.flexybayes(type = 'effects') matches snapshot", {
  skip_if_no_greta_quiet()
  fit <- .cached_fit()
  vdiffr::expect_doppelganger(
    "plot-effects",
    function() plot(fit, type = "effects")
  )
})

test_that("plot.flexybayes(type = 'variance') matches snapshot", {
  skip_if_no_greta_quiet()
  fit <- .cached_fit()
  vdiffr::expect_doppelganger(
    "plot-variance",
    function() plot(fit, type = "variance")
  )
})

test_that("plot.flexybayes(type = 'residuals') matches snapshot", {
  skip_if_no_greta_quiet()
  fit <- .cached_fit()
  vdiffr::expect_doppelganger(
    "plot-residuals",
    function() plot(fit, type = "residuals")
  )
})
