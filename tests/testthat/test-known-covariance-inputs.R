# ADR 0025 Stage 5A known-covariance input formats --- Phase A
# (parser + IR slot + validators + route guard; emit deferred to
# Phase B). The byte-identical-posterior commitment of ADR 0025
# §iii is enforced at Phase B against the v0.2 fixture corpus;
# Phase A holds at IR level (snapshot of .parse_formula output for
# the dense path) plus structural / shape validator coverage.

# ---------------------------------------------------------------- #
# (a) Dense V path --- regression guard at IR level.                #
# ---------------------------------------------------------------- #

test_that("dense vm(geno, V = K) parses to an unchanged IR shape with cov_representation slot", {
  dat <- data.frame(geno = factor(1:5))

  positional <- flexyBayes:::.parse_formula(~ vm(geno, Gmat), dat)
  named      <- flexyBayes:::.parse_formula(~ vm(geno, V = Gmat), dat)

  for (terms in list(positional, named)) {
    expect_length(terms, 1L)
    expect_equal(terms[[1]]$type, "vm")
    expect_equal(terms[[1]]$var,  "geno")
    expect_equal(terms[[1]]$mat,  "Gmat")
    expect_equal(terms[[1]]$cov_representation$format, "dense")
    expect_equal(terms[[1]]$cov_representation$data,   "Gmat")
    expect_null(terms[[1]]$cov_representation$scheme)
  }
})

test_that("dense ped(animal, A) parses to IR with cov_representation$format = 'dense'", {
  dat   <- data.frame(animal = factor(1:5))
  terms <- flexyBayes:::.parse_formula(~ ped(animal, Amat), dat)
  expect_equal(terms[[1]]$type, "ped")
  expect_equal(terms[[1]]$var,  "animal")
  expect_equal(terms[[1]]$mat,  "Amat")
  expect_equal(terms[[1]]$cov_representation$format, "dense")
})

# ---------------------------------------------------------------- #
# Stage 5A named-arg parser coverage.                               #
# ---------------------------------------------------------------- #

test_that("vm(geno, chol = L) parses to cov_representation$format = 'chol'", {
  dat   <- data.frame(geno = factor(1:5))
  terms <- flexyBayes:::.parse_formula(~ vm(geno, chol = L), dat)
  expect_equal(terms[[1]]$type, "vm")
  expect_equal(terms[[1]]$var,  "geno")
  expect_true(is.na(terms[[1]]$mat))
  expect_equal(terms[[1]]$cov_representation$format, "chol")
  expect_equal(terms[[1]]$cov_representation$data,   "L")
})

test_that("vm(geno, precision = Q) parses to cov_representation$format = 'precision'", {
  dat   <- data.frame(geno = factor(1:5))
  terms <- flexyBayes:::.parse_formula(~ vm(geno, precision = Q), dat)
  expect_equal(terms[[1]]$cov_representation$format, "precision")
  expect_equal(terms[[1]]$cov_representation$data,   "Q")
})

test_that("ped(animal, A_obj, use_sparse_precision = TRUE) parses to pedigree_sparse_precision", {
  dat   <- data.frame(animal = factor(1:5))
  terms <- flexyBayes:::.parse_formula(
    ~ ped(animal, A_obj, use_sparse_precision = TRUE), dat
  )
  expect_equal(terms[[1]]$type, "ped")
  expect_equal(terms[[1]]$cov_representation$format,
               "pedigree_sparse_precision")
  expect_equal(terms[[1]]$cov_representation$data, "A_obj")
})

test_that("ped(animal, A_obj, use_sparse_precision = FALSE) stays on dense format", {
  dat   <- data.frame(animal = factor(1:5))
  terms <- flexyBayes:::.parse_formula(
    ~ ped(animal, A_obj, use_sparse_precision = FALSE), dat
  )
  expect_equal(terms[[1]]$cov_representation$format, "dense")
})

# ---------------------------------------------------------------- #
# (k) Mutual-exclusion refusal --- ADR 0025 §8 subtest (k).        #
# ---------------------------------------------------------------- #

test_that("vm(geno, V = K, chol = L) refuses with vm_redundant_specification", {
  dat <- data.frame(geno = factor(1:5))
  err <- tryCatch(
    flexyBayes:::.parse_formula(~ vm(geno, V = K, chol = L), dat),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "vm_redundant_specification")
  expect_match(err$message, "V \\+ chol")
})

test_that("vm(geno, chol = L, precision = Q) refuses with vm_redundant_specification", {
  dat <- data.frame(geno = factor(1:5))
  err <- tryCatch(
    flexyBayes:::.parse_formula(~ vm(geno, chol = L, precision = Q), dat),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "vm_redundant_specification")
})

# ---------------------------------------------------------------- #
# Low-rank refusal coverage at parse time (subtest j of ADR 0025).  #
# ---------------------------------------------------------------- #

test_that("vm(geno, low_rank_factor = F) without low_rank_scheme refuses at parse", {
  dat <- data.frame(geno = factor(1:5))
  err <- tryCatch(
    flexyBayes:::.parse_formula(~ vm(geno, low_rank_factor = F_mat), dat),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "low_rank_scheme_required")
})

# ---------------------------------------------------------------- #
# Setup-env: dense path unchanged (regression guard at runtime).    #
# ---------------------------------------------------------------- #

test_that("setup_env dense vm path binds the matrix and falls through Phase A guard", {
  dat <- data.frame(geno = factor(1:5))
  G_mat <- diag(5)
  rownames(G_mat) <- colnames(G_mat) <- as.character(1:5)

  fixed_info <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))
  random_terms <- flexyBayes:::.parse_formula(~ vm(geno, Gmat), dat)

  ev <- new.env(parent = emptyenv())
  flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                          list(list(type = "units")),
                          dat, list(Gmat = G_mat), NULL)

  expect_true("Gmat" %in% ls(ev))
  expect_equal(ev$Gmat, G_mat)
  expect_equal(ev$geno_id, 1:5)
  expect_equal(ev$n_geno, 5L)
})

# ---------------------------------------------------------------- #
# Setup-env: chol path runs validator + Phase A route refusal.      #
# ---------------------------------------------------------------- #

test_that("chol path: lower-triangular L passes validator then refuses with route_not_yet_emitted", {
  dat <- data.frame(geno = factor(1:5))
  L   <- diag(5); L[lower.tri(L)] <- 0.1
  random_terms <- flexyBayes:::.parse_formula(~ vm(geno, chol = L), dat)
  fixed_info   <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))

  ev <- new.env(parent = emptyenv())
  err <- tryCatch(
    flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                            list(list(type = "units")),
                            dat, list(L = L), NULL),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "route_not_yet_emitted")
  expect_equal(err$format, "chol")
})

test_that("chol path: upper-triangular L refuses with chol_not_triangular before route guard", {
  dat <- data.frame(geno = factor(1:5))
  U   <- diag(5); U[upper.tri(U)] <- 0.1   # upper, not lower
  random_terms <- flexyBayes:::.parse_formula(~ vm(geno, chol = U), dat)
  fixed_info   <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))

  ev <- new.env(parent = emptyenv())
  err <- tryCatch(
    flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                            list(list(type = "units")),
                            dat, list(U = U), NULL),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "chol_not_triangular")
})

test_that("chol path: non-square L refuses with chol_not_square before route guard", {
  dat <- data.frame(geno = factor(1:5))
  L   <- matrix(0.1, nrow = 5, ncol = 3)
  random_terms <- flexyBayes:::.parse_formula(~ vm(geno, chol = L), dat)
  fixed_info   <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))

  ev <- new.env(parent = emptyenv())
  err <- tryCatch(
    flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                            list(list(type = "units")),
                            dat, list(L = L), NULL),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "chol_not_square")
})

# ---------------------------------------------------------------- #
# Setup-env: precision path runs validator + Phase A route refusal. #
# ---------------------------------------------------------------- #

test_that("precision path: PD symmetric Q passes validator then refuses with route_not_yet_emitted", {
  skip_if_not_installed("Matrix")
  dat <- data.frame(geno = factor(1:5))
  Q   <- diag(5) + 0.01 * matrix(1, 5, 5)   # symmetric PD
  random_terms <- flexyBayes:::.parse_formula(~ vm(geno, precision = Q), dat)
  fixed_info   <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))

  ev <- new.env(parent = emptyenv())
  err <- tryCatch(
    flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                            list(list(type = "units")),
                            dat, list(Q = Q), NULL),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "route_not_yet_emitted")
  expect_equal(err$format, "precision")
})

test_that("precision path: asymmetric Q refuses with precision_not_symmetric", {
  skip_if_not_installed("Matrix")
  dat <- data.frame(geno = factor(1:5))
  Q   <- matrix(c(1, 0.5, 0,   0,   0,
                  0,  1,  0.5, 0,   0,
                  0,  0,  1,   0.5, 0,
                  0,  0,  0,   1,   0.5,
                  0,  0,  0,   0,   1),
                nrow = 5, byrow = TRUE)
  random_terms <- flexyBayes:::.parse_formula(~ vm(geno, precision = Q), dat)
  fixed_info   <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))

  ev <- new.env(parent = emptyenv())
  err <- tryCatch(
    flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                            list(list(type = "units")),
                            dat, list(Q = Q), NULL),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "precision_not_symmetric")
})

test_that("precision path: indefinite symmetric Q refuses with precision_not_positive_definite", {
  skip_if_not_installed("Matrix")
  dat <- data.frame(geno = factor(1:5))
  Q   <- diag(c(1, 1, 1, 1, -1))   # symmetric, indefinite
  random_terms <- flexyBayes:::.parse_formula(~ vm(geno, precision = Q), dat)
  fixed_info   <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))

  ev <- new.env(parent = emptyenv())
  err <- tryCatch(
    flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                            list(list(type = "units")),
                            dat, list(Q = Q), NULL),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "precision_not_positive_definite")
})

# ---------------------------------------------------------------- #
# Setup-env: missing-from-known_matrices refusals.                  #
# ---------------------------------------------------------------- #

test_that("chol path with L missing from known_matrices refuses cleanly", {
  dat <- data.frame(geno = factor(1:5))
  random_terms <- flexyBayes:::.parse_formula(~ vm(geno, chol = L), dat)
  fixed_info   <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))

  ev <- new.env(parent = emptyenv())
  err <- tryCatch(
    flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                            list(list(type = "units")),
                            dat, list(), NULL),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "chol_not_in_known_matrices")
})

# ---------------------------------------------------------------- #
# v0.3.8 forward-pointer refusals.                                  #
# ---------------------------------------------------------------- #

test_that("blocks path refuses with route_not_yet_emitted pointing to v0.3.8", {
  dat <- data.frame(geno = factor(1:5))
  random_terms <- flexyBayes:::.parse_formula(~ vm(geno, blocks = Bs), dat)
  fixed_info   <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))

  ev <- new.env(parent = emptyenv())
  err <- tryCatch(
    flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                            list(list(type = "units")),
                            dat, list(Bs = list(diag(2), diag(3))), NULL),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "route_not_yet_emitted")
  expect_equal(err$format, "blocks")
  expect_match(err$message, "v0\\.3\\.8")
})

test_that("low_rank path with registered-looking scheme refuses with approximate_route_not_yet_registered", {
  dat <- data.frame(geno = factor(1:5))
  random_terms <- flexyBayes:::.parse_formula(
    ~ vm(geno, low_rank_factor = F_mat, low_rank_scheme = "pca"), dat
  )
  fixed_info <- flexyBayes:::.parse_fixed(V1 ~ 1, cbind(dat, V1 = 1))

  ev <- new.env(parent = emptyenv())
  err <- tryCatch(
    flexyBayes:::.setup_env(ev, fixed_info, random_terms,
                            list(list(type = "units")),
                            dat, list(F_mat = matrix(0, 5, 2)), NULL),
    flexybayes_structured_cov_refusal = identity
  )
  expect_s3_class(err, "flexybayes_structured_cov_refusal")
  expect_equal(err$reason_code, "approximate_route_not_yet_registered")
  expect_equal(err$format, "low_rank")
  expect_equal(err$scheme, "pca")
})
