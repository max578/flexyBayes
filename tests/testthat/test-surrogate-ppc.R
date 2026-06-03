# =============================================================================
# test-surrogate-ppc.R -- emulator-distortion check via kernR's mmd_ppc().
#
# A well-trained surrogate's predictive draws should match held-out simulator
# outputs (no reject); an artificially distorted predictive distribution should
# be caught (reject -- power). Gated on kernR being installed.
# =============================================================================

.mk_ppc_surrogate <- function() {
  set.seed(20260602L)
  n <- 250L
  a <- stats::runif(n, -2, 2)
  b <- stats::runif(n, -2, 2)
  e <- fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = data.frame(y = sin(a) + 0.5 * b^2 + stats::rnorm(n, 0, 0.1)),
    provenance = list(source = "raw")
  )
  fit_surrogate(e, method = "rff", seed = 1L)
}

test_that("a faithful surrogate is not rejected by the PPC", {
  skip_if_not_installed("kernR")
  s <- .mk_ppc_surrogate()
  set.seed(4L)
  k <- 60L
  newdata <- data.frame(
    a = stats::runif(k, -1.6, 1.6),
    b = stats::runif(k, -1.6, 1.6)
  )
  # the true simulator outputs at the held-out sets (with the same noise scale)
  observed <- data.frame(
    y = sin(newdata$a) + 0.5 * newdata$b^2 + stats::rnorm(k, 0, 0.1)
  )
  res <- fb_surrogate_ppc(
    s,
    newdata,
    observed,
    n_draws = 5L,
    seed = 1L,
    n_permutations = 199L
  )
  expect_s3_class(res, "mmd_ppc")
  expect_false(res$reject)
})

test_that("a distorted (shifted) predictive distribution is rejected", {
  skip_if_not_installed("kernR")
  s <- .mk_ppc_surrogate()
  set.seed(4L)
  k <- 60L
  newdata <- data.frame(
    a = stats::runif(k, -1.6, 1.6),
    b = stats::runif(k, -1.6, 1.6)
  )
  # observed outputs carry a large systematic shift the surrogate never saw
  observed <- data.frame(
    y = sin(newdata$a) + 0.5 * newdata$b^2 + 3 + stats::rnorm(k, 0, 0.1)
  )
  res <- fb_surrogate_ppc(
    s,
    newdata,
    observed,
    n_draws = 5L,
    seed = 1L,
    n_permutations = 199L
  )
  expect_true(res$reject)
})

test_that("fb_surrogate_ppc() validates its arguments", {
  skip_if_not_installed("kernR")
  s <- .mk_ppc_surrogate()
  nd <- data.frame(a = 0, b = 0)
  expect_error(
    fb_surrogate_ppc("nope", nd, data.frame(y = 1)),
    "must be an fb_surrogate"
  )
  expect_error(
    fb_surrogate_ppc(s, nd, data.frame(nomatch = 1)),
    "shares no output column"
  )
})

# ---- the joint draw path (C7 v1.2, the second consumer of the joint cov) -----

# A 2-output simulator whose outputs are independent functions of separate
# parameters (so the mean surface carries no cross-output structure) plus a
# strongly correlated noise term -- the only cross-output correlation in the data
# is the noise, which a joint surrogate must reproduce.
.mk_corr_surrogate <- function() {
  set.seed(20260603L)
  n <- 300L
  a <- stats::runif(n, -2, 2)
  b <- stats::runif(n, -2, 2)
  s_noise <- chol(matrix(c(0.64, 0.95 * 0.64, 0.95 * 0.64, 0.64), 2L, 2L))
  eps <- matrix(stats::rnorm(n * 2L), n, 2L) %*% s_noise
  e <- fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = data.frame(o1 = 0.25 * a + eps[, 1], o2 = 0.25 * b + eps[, 2]),
    provenance = list(source = "raw")
  )
  list(
    surrogate = fit_surrogate(e, method = "rff", seed = 1L),
    s_noise = s_noise
  )
}

test_that("joint draws carry cross-output correlation a marginal draw destroys", {
  # deterministic: no kernR needed -- check the empirical correlation of the
  # predictive draws themselves at a held-out point.
  s <- .mk_corr_surrogate()$surrogate
  expect_true(isTRUE(s$fit$joint))
  nd <- data.frame(a = 0.3, b = -0.4)
  dj <- .surrogate_ppc_draws(
    s,
    nd,
    c("o1", "o2"),
    n_draws = 4000L,
    joint = TRUE,
    seed = 1L
  )
  dm <- .surrogate_ppc_draws(
    s,
    nd,
    c("o1", "o2"),
    n_draws = 4000L,
    joint = FALSE,
    seed = 1L
  )
  expect_gt(stats::cor(dj[, 1], dj[, 2]), 0.7) # joint draws reproduce the corr
  expect_lt(abs(stats::cor(dm[, 1], dm[, 2])), 0.1) # marginal draws are independent
  # both paths preserve the per-output marginal sd (the <o>_sd contract)
  expect_equal(stats::sd(dj[, 1]), stats::sd(dm[, 1]), tolerance = 0.05)
})

test_that("a single output draws identically under joint and marginal paths", {
  # for k == 1 the joint Cholesky of a 1x1 covariance is its sd, and the RNG is
  # consumed in the same order -- the joint default must not perturb scalar PPCs.
  s <- .mk_ppc_surrogate()
  nd <- data.frame(
    a = stats::runif(20L, -1.5, 1.5),
    b = stats::runif(20L, -1.5, 1.5)
  )
  dj <- .surrogate_ppc_draws(s, nd, "y", n_draws = 3L, joint = TRUE, seed = 7L)
  dm <- .surrogate_ppc_draws(s, nd, "y", n_draws = 3L, joint = FALSE, seed = 7L)
  expect_equal(dj, dm)
})

test_that("the joint PPC passes a faithful joint surrogate the marginal rejects", {
  skip_if_not_installed("kernR")
  obj <- .mk_corr_surrogate()
  s <- obj$surrogate
  set.seed(5L)
  k <- 80L
  nd <- data.frame(
    a = stats::runif(k, -1.8, 1.8),
    b = stats::runif(k, -1.8, 1.8)
  )
  eps2 <- matrix(stats::rnorm(k * 2L), k, 2L) %*% obj$s_noise
  observed <- data.frame(
    o1 = 0.25 * nd$a + eps2[, 1],
    o2 = 0.25 * nd$b + eps2[, 2]
  )
  res_joint <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 10L,
    joint = TRUE,
    seed = 1L,
    n_permutations = 299L
  )
  res_marg <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 10L,
    joint = FALSE,
    seed = 1L,
    n_permutations = 299L
  )
  # the joint draws reproduce the simulator's cross-output correlation, so a
  # faithful surrogate is not rejected; the marginal draws discard it and
  # false-reject -- the joint path is the correct distribution-preserving check.
  expect_false(res_joint$reject)
  expect_true(res_marg$reject)
})

# ---- the low-rank factored sampler (contract clause 5, native PPC consumer) --

# A 5-output simulator with low-rank residual noise -> a cov_rank surrogate whose
# joint draws can be sampled factored (never forming the k x k slice).
.mk_lowrank_ppc <- function() {
  set.seed(20260603L)
  n <- 400L
  k <- 5L
  q <- 2L
  a <- stats::runif(n, -2, 2)
  b <- stats::runif(n, -2, 2)
  loadings <- matrix(stats::rnorm(k * q), k, q)
  coefs <- matrix(stats::rnorm(k * 2L), k, 2L)
  gen <- function(aa, bb) {
    s <- cbind(sin(aa), 0.5 * bb) %*% t(coefs)
    zz <- matrix(stats::rnorm(length(aa) * q), length(aa), q)
    s +
      zz %*% t(loadings) +
      matrix(stats::rnorm(length(aa) * k, 0, 0.1), length(aa), k)
  }
  y <- gen(a, b)
  colnames(y) <- paste0("o", seq_len(k))
  e <- fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = as.data.frame(y),
    provenance = list(source = "raw")
  )
  list(
    surrogate = fit_surrogate(e, joint = TRUE, cov_rank = 2L, seed = 1L),
    gen = gen
  )
}

test_that("the low-rank factored sampler reproduces the per-row covariance", {
  s <- .mk_lowrank_ppc()$surrogate
  expect_false(is.null(s$fit$sigma_lr)) # the factored path applies
  nd <- data.frame(a = 0.3, b = -0.4)
  target <- fb_cov_slice(predict(s, nd, cov = "lowrank"), 1L)
  draws <- .surrogate_ppc_draws(
    s,
    nd,
    paste0("o", seq_len(5L)),
    n_draws = 20000L,
    joint = TRUE,
    seed = 1L
  )
  emp <- stats::cov(draws)
  # the factored sampler draws from infl (u u' + diag(d)) -- the same covariance
  # the dense slice would, to Monte-Carlo tolerance, without forming k x k
  expect_lt(max(abs(emp - target)) / max(abs(target)), 0.1)
})

test_that("the low-rank PPC passes a faithful surrogate and rejects a distortion", {
  skip_if_not_installed("kernR")
  obj <- .mk_lowrank_ppc()
  s <- obj$surrogate
  set.seed(5L)
  kk <- 80L
  nd <- data.frame(
    a = stats::runif(kk, -1.8, 1.8),
    b = stats::runif(kk, -1.8, 1.8)
  )
  observed <- as.data.frame(obj$gen(nd$a, nd$b))
  colnames(observed) <- paste0("o", seq_len(5L))
  res_ok <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 10L,
    joint = TRUE,
    seed = 1L,
    n_permutations = 199L
  )
  observed_bad <- observed
  observed_bad$o1 <- observed_bad$o1 + 3 # a distortion the surrogate never saw
  res_bad <- fb_surrogate_ppc(
    s,
    nd,
    observed_bad,
    n_draws = 10L,
    joint = TRUE,
    seed = 1L,
    n_permutations = 199L
  )
  expect_false(res_ok$reject) # the factored draws match the simulator
  expect_true(res_bad$reject) # and catch the distortion
})

# ---- the factor-space MMD (large k: test the correlated structure cheaply) --

test_that("project = TRUE catches a correlated distortion, is blind to idiosyncratic", {
  skip_if_not_installed("kernR")
  # k = 40 outputs with rank-3 structure; the factor-space test runs in 3 dims
  set.seed(20260603L)
  n <- 500L
  k <- 40L
  q <- 3L
  a <- stats::runif(n, -2, 2)
  b <- stats::runif(n, -2, 2)
  loadings <- matrix(stats::rnorm(k * q), k, q)
  coefs <- matrix(stats::rnorm(k * 2L), k, 2L)
  gen <- function(aa, bb, distort = "none") {
    s <- cbind(sin(aa), 0.5 * bb) %*% t(coefs)
    zz <- matrix(stats::rnorm(length(aa) * q), length(aa), q)
    y <- s +
      zz %*% t(loadings) +
      matrix(stats::rnorm(length(aa) * k, 0, 0.1), length(aa), k)
    if (identical(distort, "factor")) {
      # a coherent shift along factor 1 -- correlated across many outputs
      y <- y +
        matrix(stats::rnorm(length(aa)) * 1.5, length(aa), k) *
          matrix(loadings[, 1], length(aa), k, byrow = TRUE)
    }
    if (identical(distort, "idio")) {
      y[, 1] <- y[, 1] + 3 # one output shifted -- orthogonal to the factor span
    }
    y
  }
  y <- gen(a, b)
  colnames(y) <- paste0("o", seq_len(k))
  e <- fb_ensemble(
    params = data.frame(a = a, b = b),
    outputs = as.data.frame(y),
    provenance = list(source = "raw")
  )
  s <- fit_surrogate(e, joint = TRUE, cov_rank = 3L, seed = 1L)
  set.seed(5L)
  kk <- 80L
  nd <- data.frame(
    a = stats::runif(kk, -1.8, 1.8),
    b = stats::runif(kk, -1.8, 1.8)
  )
  ppc <- function(distort) {
    obs <- as.data.frame(gen(nd$a, nd$b, distort))
    colnames(obs) <- paste0("o", seq_len(k))
    fb_surrogate_ppc(
      s,
      nd,
      obs,
      n_draws = 8L,
      joint = TRUE,
      project = TRUE,
      seed = 1L,
      n_permutations = 199L
    )
  }
  expect_false(ppc("none")$reject) # faithful: the factor space matches
  expect_true(ppc("factor")$reject) # correlated distortion: caught in q dims
  expect_false(ppc("idio")$reject) # idiosyncratic: blind by design
})

test_that("project = TRUE needs a low-rank surrogate", {
  skip_if_not_installed("kernR")
  s <- .mk_corr_surrogate()$surrogate # joint, no cov_rank
  nd <- data.frame(a = c(0, 0.5), b = c(0.1, -0.2))
  observed <- data.frame(o1 = c(0, 0.1), o2 = c(0, -0.1))
  expect_error(
    fb_surrogate_ppc(s, nd, observed, project = TRUE, n_permutations = 49L),
    "low-rank"
  )
})

# ---- the aggregated multi-kernel MMD (MMDAgg, no bandwidth tuning) -----------

test_that("aggregate = TRUE passes a faithful surrogate and catches a distortion", {
  skip_if_not_installed("kernR")
  obj <- .mk_lowrank_ppc()
  s <- obj$surrogate
  set.seed(5L)
  k <- 70L
  nd <- data.frame(
    a = stats::runif(k, -1.8, 1.8),
    b = stats::runif(k, -1.8, 1.8)
  )
  observed <- as.data.frame(obj$gen(nd$a, nd$b))
  colnames(observed) <- paste0("o", seq_len(5L))
  res_ok <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 8L,
    aggregate = TRUE,
    seed = 1L,
    n_permutations = 199L
  )
  expect_s3_class(res_ok, "fb_mmd_agg")
  expect_identical(res_ok$n_kernels, 7L) # the default bandwidth grid
  expect_length(res_ok$p_per_bandwidth, 7L)
  expect_false(res_ok$reject)
  # deterministic given the seed
  res_ok2 <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 8L,
    aggregate = TRUE,
    seed = 1L,
    n_permutations = 199L
  )
  expect_equal(res_ok$p_value, res_ok2$p_value)

  observed_bad <- observed
  observed_bad$o1 <- observed_bad$o1 + 3
  res_bad <- fb_surrogate_ppc(
    s,
    nd,
    observed_bad,
    n_draws = 8L,
    aggregate = TRUE,
    seed = 1L,
    n_permutations = 199L
  )
  expect_true(res_bad$reject)
})

test_that("aggregate composes with project; print works", {
  skip_if_not_installed("kernR")
  obj <- .mk_lowrank_ppc()
  s <- obj$surrogate
  set.seed(5L)
  k <- 70L
  nd <- data.frame(
    a = stats::runif(k, -1.8, 1.8),
    b = stats::runif(k, -1.8, 1.8)
  )
  observed <- as.data.frame(obj$gen(nd$a, nd$b))
  colnames(observed) <- paste0("o", seq_len(5L))
  res <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 8L,
    project = TRUE,
    aggregate = TRUE,
    seed = 1L,
    n_permutations = 199L
  )
  expect_s3_class(res, "fb_mmd_agg")
  expect_false(res$reject) # faithful, factor space + aggregated
  expect_output(print(res), "fb_mmd_agg")
})

test_that("aggregate weight schemes are valid and uniform recovers the default", {
  skip_if_not_installed("kernR")
  obj <- .mk_lowrank_ppc()
  s <- obj$surrogate
  set.seed(5L)
  k <- 70L
  nd <- data.frame(
    a = stats::runif(k, -1.8, 1.8),
    b = stats::runif(k, -1.8, 1.8)
  )
  observed <- as.data.frame(obj$gen(nd$a, nd$b))
  colnames(observed) <- paste0("o", seq_len(5L))
  ppc <- function(w) {
    fb_surrogate_ppc(
      s,
      nd,
      observed,
      n_draws = 8L,
      aggregate = TRUE,
      agg_weights = w,
      seed = 1L,
      n_permutations = 199L
    )
  }
  r_unif <- ppc("uniform")
  # uniform is the default (cont.42 min-p form): same p-value as no agg_weights
  r_default <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 8L,
    aggregate = TRUE,
    seed = 1L,
    n_permutations = 199L
  )
  expect_equal(r_unif$p_value, r_default$p_value)
  for (scheme in c("increasing", "decreasing", "centred")) {
    r <- ppc(scheme)
    expect_s3_class(r, "fb_mmd_agg")
    expect_length(r$weights, r$n_kernels)
    expect_equal(sum(r$weights), 1) # normalised
    expect_false(r$reject) # faithful surrogate
  }
  # a custom numeric weight vector works
  r_vec <- ppc(c(1, 1, 2, 3, 2, 1, 1))
  expect_equal(sum(r_vec$weights), 1)
  # invalid schemes / wrong length error
  expect_error(ppc("nope"), "unknown")
  expect_error(ppc(c(1, 2, 3)), "positive finite values")
})

# ---- pooled-covariance whitening (a label-agnostic representation) -----------

test_that(".whiten_clouds yields a unit pooled covariance, shape-preserving", {
  # no kernR needed -- a pure transform check. Heterogeneous per-column scales
  # are the case whitening exists to equalise.
  set.seed(1L)
  scl <- diag(c(5, 1, 0.2, 3))
  x <- matrix(stats::rnorm(200L * 4L), 200L, 4L) %*% scl
  y <- matrix(stats::rnorm(60L * 4L), 60L, 4L) %*% scl + 2
  wc <- flexyBayes:::.whiten_clouds(x, y)
  pooled <- rbind(wc$x, wc$y)
  expect_equal(stats::cov(pooled), diag(4L), tolerance = 0.05) # whitened ~ I
  expect_identical(dim(wc$x), dim(x))
  expect_identical(dim(wc$y), dim(y))
})

test_that("whiten leaves a faithful surrogate unrejected and is deterministic", {
  skip_if_not_installed("kernR")
  obj <- .mk_lowrank_ppc()
  s <- obj$surrogate
  set.seed(5L)
  k <- 70L
  nd <- data.frame(
    a = stats::runif(k, -1.8, 1.8),
    b = stats::runif(k, -1.8, 1.8)
  )
  observed <- as.data.frame(obj$gen(nd$a, nd$b))
  colnames(observed) <- paste0("o", seq_len(5L))
  # single-kernel path: faithful not rejected (its permutation seed is kernR's,
  # exactly as for the un-whitened single-kernel path -- no p-value determinism
  # claim, matching the existing single-kernel tests)
  r0 <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 6L,
    whiten = TRUE,
    seed = 1L,
    n_permutations = 199L
  )
  expect_s3_class(r0, "mmd_ppc")
  expect_false(r0$reject)
  # aggregate path is seeded end-to-end (the seed reaches kernR::mmd_test): a
  # faithful surrogate is not rejected and the p-value is deterministic
  agg <- function() {
    fb_surrogate_ppc(
      s,
      nd,
      observed,
      n_draws = 6L,
      whiten = TRUE,
      aggregate = TRUE,
      seed = 1L,
      n_permutations = 199L
    )
  }
  a1 <- agg()
  expect_false(a1$reject)
  expect_equal(agg()$p_value, a1$p_value)
})

test_that("whiten lifts power on a localised distortion the raw check misses", {
  skip_if_not_installed("kernR")
  obj <- .mk_lowrank_ppc()
  s <- obj$surrogate
  set.seed(11L)
  k <- 70L
  nd <- data.frame(
    a = stats::runif(k, -1.8, 1.8),
    b = stats::runif(k, -1.8, 1.8)
  )
  observed <- as.data.frame(obj$gen(nd$a, nd$b))
  colnames(observed) <- paste0("o", seq_len(5L))
  # a fine-scale bimodal distortion on o1 with matched variance: a SHAPE change
  # the raw median-bandwidth MMD cannot resolve, but whitening exposes by putting
  # the low-variance idiosyncratic direction on a common footing (the gate
  # finding, encoded as a regression).
  observed$o1 <- observed$o1 + ifelse(stats::runif(k) < 0.5, -1, 1)
  ppc <- function(whiten) {
    fb_surrogate_ppc(
      s,
      nd,
      observed,
      n_draws = 6L,
      aggregate = TRUE,
      whiten = whiten,
      seed = 1L,
      n_permutations = 199L
    )
  }
  raw <- ppc(FALSE)
  wht <- ppc(TRUE)
  expect_false(raw$reject) # raw misses the localised matched-variance shift
  expect_true(wht$reject) # whitening exposes it
  expect_lt(wht$p_value, raw$p_value)
})

test_that("whiten composes with project and with aggregate", {
  skip_if_not_installed("kernR")
  obj <- .mk_lowrank_ppc()
  s <- obj$surrogate
  set.seed(5L)
  k <- 70L
  nd <- data.frame(
    a = stats::runif(k, -1.8, 1.8),
    b = stats::runif(k, -1.8, 1.8)
  )
  observed <- as.data.frame(obj$gen(nd$a, nd$b))
  colnames(observed) <- paste0("o", seq_len(5L))
  rp <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 6L,
    project = TRUE,
    whiten = TRUE,
    seed = 1L,
    n_permutations = 149L
  )
  expect_s3_class(rp, "mmd_ppc")
  ra <- fb_surrogate_ppc(
    s,
    nd,
    observed,
    n_draws = 6L,
    whiten = TRUE,
    aggregate = TRUE,
    seed = 1L,
    n_permutations = 149L
  )
  expect_s3_class(ra, "fb_mmd_agg")
})
