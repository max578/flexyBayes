# Numerical validation: bayesreml() vs lme4::lmer() (and asreml::asreml()
# when available).
#
# Audit Phase L (recipe 12). Archetype-1 invariant: the model must
# return coefficients within tolerance of an established reference
# implementation on a benchmark dataset. We use sleepstudy (lme4) as
# the reference fixture: a balanced random-intercept-and-slope mixed
# model with well-known maximum-likelihood point estimates.
#
# Tolerances: posterior-mean fixed effects must agree with REML point
# estimates within 0.5 * REML SE. Variance components (sigma_e and
# sigma_subject) within 25% on the SD scale. Bayesian point estimates
# differ from REML by an amount that scales with prior strength and
# sample size; the chosen tolerances are loose enough to accommodate
# n = 180 sleepstudy + the v0.1.x default PC prior, but tight enough
# to flag a regression in the codegen path.

skip_if_no_greta_quiet <- function() {
  testthat::skip_if_not_installed("greta")
  testthat::skip_if_not_installed("lme4")
  testthat::skip_on_cran()
  testthat::skip_on_ci()
}

test_that("bayesreml fixed effects agree with lme4 on sleepstudy", {
  skip_if_no_greta_quiet()

  data(sleepstudy, package = "lme4")

  set.seed(20260427L)
  fit_b <- bayesreml(
    fixed     = Reaction ~ Days,
    random    = ~ Subject,
    data      = sleepstudy,
    n_samples = 1000,
    warmup    = 1000,
    chains    = 2,
    verbose   = FALSE,
    mcmc_verbose = FALSE
  )

  fit_l <- lme4::lmer(Reaction ~ Days + (1 | Subject),
                       data = sleepstudy, REML = TRUE)

  # Posterior means
  beta_b <- coef(fit_b)
  beta_l <- lme4::fixef(fit_l)
  se_l   <- sqrt(diag(as.matrix(stats::vcov(fit_l))))

  # Align by name
  common <- intersect(names(beta_b), names(beta_l))
  expect_gt(length(common), 0L)

  for (term in common) {
    expect_lt(
      abs(beta_b[[term]] - beta_l[[term]]),
      0.5 * se_l[[term]],
      label = paste("|delta| for", term, "exceeds 0.5 * REML SE")
    )
  }

  # Variance components on the SD scale
  vc_b   <- fit_b$extras$variance_comps
  vc_l   <- as.data.frame(lme4::VarCorr(fit_l))

  sigma_e_b <- vc_b$estimate[vc_b$component == "Residual"]
  sigma_e_l <- vc_l$sdcor[vc_l$grp == "Residual"]
  expect_lt(
    abs(sigma_e_b - sigma_e_l) / sigma_e_l, 0.25,
    label = "|sigma_e| relative error vs REML > 25%"
  )

  sigma_s_b <- vc_b$estimate[grepl("Subject", vc_b$component, fixed = TRUE)][1]
  sigma_s_l <- vc_l$sdcor[vc_l$grp == "Subject"]
  expect_lt(
    abs(sigma_s_b - sigma_s_l) / sigma_s_l, 0.25,
    label = "|sigma_subject| relative error vs REML > 25%"
  )
})

test_that("bayesreml fixed effects agree with asreml on sleepstudy (when asreml available)", {
  skip_if_no_greta_quiet()
  testthat::skip_if_not_installed("asreml")

  data(sleepstudy, package = "lme4")

  set.seed(20260427L)
  fit_b <- bayesreml(
    fixed     = Reaction ~ Days,
    random    = ~ Subject,
    data      = sleepstudy,
    n_samples = 1000,
    warmup    = 1000,
    chains    = 2,
    verbose   = FALSE,
    mcmc_verbose = FALSE
  )

  # asreml-R is licence-restricted; the call below is gated by the
  # skip_if_not_installed() above and therefore never runs in CI
  # nor on contributors' machines without an explicit licence.
  fit_a <- asreml::asreml(
    fixed   = Reaction ~ Days,
    random  = ~ Subject,
    data    = sleepstudy,
    trace   = FALSE
  )

  beta_b <- coef(fit_b)
  beta_a <- summary(fit_a, coef = TRUE)$coef.fixed
  beta_a_means <- stats::setNames(beta_a[, "solution"],
                                   rownames(beta_a))

  common <- intersect(names(beta_b), names(beta_a_means))
  expect_gt(length(common), 0L)

  # asreml produces a vcov via the inverse Average-Information matrix.
  vcov_a <- stats::vcov(fit_a)
  se_a   <- sqrt(diag(as.matrix(vcov_a)))
  names(se_a) <- rownames(vcov_a)

  for (term in common) {
    expect_lt(
      abs(beta_b[[term]] - beta_a_means[[term]]),
      0.5 * se_a[[term]],
      label = paste("|delta| for", term, "exceeds 0.5 * asreml SE")
    )
  }
})
