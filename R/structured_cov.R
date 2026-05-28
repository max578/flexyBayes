# Stage 5A known-covariance input formats (ADR 0025).
#
# The cov_representation slot on a vm() / ped() IR term carries the
# user's chosen carrier for the structured covariance:
#
#   list(format = c("dense", "chol", "precision", "blocks",
#                   "low_rank", "pedigree_sparse_precision"),
#        data   = <deparsed symbol name resolving via known_matrices>,
#        scheme = <NULL for exact formats; registered approximation
#                  name for low_rank>)
#
# v0.3.7 activates dense + chol + precision (+ ped sparse-precision
# opt-in via Decision 6). v0.3.10 activates blocks (ADR 0025 Decision
# 3); low_rank reserves the slot for ADR 0027 (Stage 6 / v0.4.0) and
# the refusal message names `validate_approximation()` as the v0.4.0
# Wave 1 Phase 1B forward export.
#
# Phase A (this file) ships:
#   - The IR slot constructor (.cov_representation_from_call).
#   - The dense-arg extractor that backward-compatibly reads V=
#     (named) or position 3 (positional), but routes new Stage 5A
#     named args away from the dense bucket so they cannot silently
#     shadow V.
#   - Validators that run after known_matrices binding resolves
#     (.validate_chol_input, .validate_precision_input). These are
#     called from setup_env when the format is non-dense; their
#     refusals fire before the route-not-yet-emitted Phase A guard
#     so users see structural input errors at the right granularity.
#   - The Phase A route guard (.stage5a_route_check) that refuses
#     non-dense formats with route_not_yet_emitted until Phase B
#     activates them.
#
# All refusals raise a typed flexybayes_structured_cov_refusal
# condition with a reason_code slot, mirroring the pattern
# established by flexybayes_preflight_refusal.

# Names reserved by Stage 5A for vm() / ped() named-argument extension.
# Backward-compat for historic calls (vm(geno, K), vm(geno, V = K), or
# vm(geno, mat = K)) is preserved: the 3rd-position arg is treated as
# the dense V unless its name is in this reserved set.
.STAGE5A_VM_RESERVED_NAMES <- c(
  "chol", "precision", "blocks",
  "low_rank_factor", "low_rank_scheme",
  "use_sparse_precision"
)

# Recover a literal scalar string from its deparsed form. The formula
# parser's .dep_named() helper returns deparsed expressions; for the
# low_rank_scheme arg the user writes "pca" (a string literal) which
# deparses to the quoted form '"pca"'. Strip the wrapping quotes so
# the stored scheme name matches the ADR 0027 registry vocabulary.
.strip_string_literal <- function(s) {
  if (is.na(s)) return(NA_character_)
  if (startsWith(s, '"') && endsWith(s, '"'))
    return(substr(s, 2L, nchar(s) - 1L))
  if (startsWith(s, "'") && endsWith(s, "'"))
    return(substr(s, 2L, nchar(s) - 1L))
  s
}

# Backward-compatible dense-V extractor for vm() / ped() calls.
#
# Accepts either positional position-3 OR named V=. Routes new Stage 5A
# named args (chol, precision, ...) away from the dense bucket so they
# do not shadow V silently.
.extract_vm_dense_arg <- function(expr) {
  v_named <- .dep_named(expr, "V")
  if (!is.na(v_named)) return(v_named)
  nms <- names(expr)
  if (length(expr) < 3L) return(NA_character_)
  third_name <- if (is.null(nms)) "" else nms[[3L]]
  if (third_name %in% .STAGE5A_VM_RESERVED_NAMES)
    return(NA_character_)
  .dep(expr, 3)
}

# Build the cov_representation IR slot from a vm() / ped() call's
# captured named args. Enforces mutual exclusion across V / chol /
# precision / blocks / low_rank_factor (Decision 1--4 of ADR 0025).
#
# All args arrive as deparsed character strings or NA_character_.
.cov_representation_from_call <- function(fn,
                                          mat                  = NA_character_,
                                          chol                 = NA_character_,
                                          precision            = NA_character_,
                                          blocks               = NA_character_,
                                          low_rank_factor      = NA_character_,
                                          low_rank_scheme      = NA_character_,
                                          use_sparse_precision = NA_character_) {
  # Mutual exclusion across the five vm() covariance carriers.
  supplied <- c(
    V               = !is.na(mat),
    chol            = !is.na(chol),
    precision       = !is.na(precision),
    blocks          = !is.na(blocks),
    low_rank_factor = !is.na(low_rank_factor)
  )
  if (sum(supplied) > 1L) {
    .stop_structured_cov_refusal(
      reason_code = "vm_redundant_specification",
      message     = paste0(
        fn, "(): exactly one covariance carrier may be supplied; ",
        "got ", paste(names(supplied)[supplied], collapse = " + "),
        ". Pick one of V / chol / precision / blocks / low_rank_factor."
      ),
      supplied = names(supplied)[supplied]
    )
  }

  # ped() with use_sparse_precision = TRUE routes through the
  # sparse-precision format internally; phase B turns getA() into
  # getAInv() and lifts the matrix through the precision codepath.
  if (identical(fn, "ped") &&
      identical(toupper(use_sparse_precision), "TRUE")) {
    return(list(
      format = "pedigree_sparse_precision",
      data   = mat,  # the pedigree symbol; phase B converts to Q at fit time
      scheme = NULL
    ))
  }

  if (!is.na(chol))
    return(list(format = "chol",      data = chol,      scheme = NULL))
  if (!is.na(precision))
    return(list(format = "precision", data = precision, scheme = NULL))
  if (!is.na(blocks))
    return(list(format = "blocks",    data = blocks,    scheme = NULL))
  if (!is.na(low_rank_factor)) {
    if (is.na(low_rank_scheme))
      .stop_structured_cov_refusal(
        reason_code = "low_rank_scheme_required",
        message     = paste0(
          fn, "(): low_rank_factor requires an explicit ",
          "low_rank_scheme naming the registered approximation. ",
          "See ADR 0027 (Stage 6 / v0.4.0) for the registry."
        )
      )
    return(list(format = "low_rank", data = low_rank_factor,
                scheme = .strip_string_literal(low_rank_scheme)))
  }
  list(format = "dense", data = mat, scheme = NULL)
}

# Stage 5A route guard. Runs at setup_env time on the greta dispatch
# path (setup_env is greta-only; emit_inla() runs its own allowlist
# check via lgm_gate). Dispatches:
#
#   format = "dense"                      -> no-op (legacy path).
#   format = "chol"                       -> v0.3.7 Phase B active on
#                                            greta: run input validator,
#                                            then proceed silently.
#   format = "precision" /
#   format = "pedigree_sparse_precision"  -> v0.3.7 Phase B active on
#                                            greta: run input validator
#                                            (precision validator
#                                            applies to both), then
#                                            proceed silently. (Sparse
#                                            efficiency wins land on
#                                            the INLA path at Phase
#                                            B-inla; greta densifies
#                                            via as.matrix() at
#                                            codegen time.)
#   format = "blocks"                     -> v0.3.8 forward-pointer
#                                            refusal (ADR 0025
#                                            Decision 3).
#   format = "low_rank"                   -> ADR 0027 / Stage 6
#                                            approximate-route refusal.
#
# The validators raise typed structural refusals (chol_not_triangular,
# precision_not_positive_definite, ...) so users see input errors at
# input granularity, not as a downstream emit failure.
.stage5a_route_check <- function(term, known_matrices,
                                 expected_n = NULL,
                                 fit_levels = NULL) {
  cov <- term$cov_representation
  if (is.null(cov) || identical(cov$format, "dense"))
    return(invisible(NULL))

  fmt <- cov$format

  if (fmt == "chol") {
    L <- known_matrices[[cov$data]]
    .validate_chol_input(L, name = cov$data, group_var = term$var,
                          expected_n = expected_n,
                          fit_levels = fit_levels)
    return(invisible(NULL))
  }

  if (fmt %in% c("precision", "pedigree_sparse_precision")) {
    Q <- known_matrices[[cov$data]]
    .validate_precision_input(Q, name = cov$data, group_var = term$var,
                               expected_n = expected_n,
                               fit_levels = fit_levels)
    return(invisible(NULL))
  }

  if (fmt == "blocks") {
    blocks_list <- known_matrices[[cov$data]]
    .validate_blocks_input(
      blocks_list,
      name       = cov$data,
      group_var  = term$var,
      expected_n = expected_n
    )
    return(invisible(NULL))
  }

  if (fmt == "low_rank") {
    .stop_structured_cov_refusal(
      reason_code = "approximate_route_not_yet_registered",
      message     = paste0(
        "vm(", term$var, ", low_rank_factor = ", cov$data,
        ", low_rank_scheme = '", cov$scheme,
        "'): low-rank covariance carriers require the approximation ",
        "registry (ADR 0027), which lands at flexyBayes v0.4.0 as ",
        "validate_approximation() (Wave 1 Phase 1B). Until then, ",
        "materialise the rank-K matrix and route through the dense ",
        "path: vm(", term$var, ", V = ", cov$data, " %*% t(",
        cov$data, "))."
      ),
      format = "low_rank",
      scheme = cov$scheme
    )
  }

  invisible(NULL)
}

# Codegen helper. Returns the R expression (as a string) that
# constructs a square root B of V such that B B' = V on the greta
# emit path. Inputs:
#
#   cov          The cov_representation slot from the parsed term
#                (NULL or absent for legacy IRs).
#   legacy_mat   The pre-Stage-5A `term$mat` field, used as the
#                dense fallback when cov_representation is absent
#                (saved fits, parser-bypass test fixtures).
#
# Per-format square roots:
#   dense:                       t(chol(V))                lower-tri Cholesky of V
#   chol:                        as.matrix(L)              user supplies L directly
#   precision /
#   pedigree_sparse_precision:   solve(chol(Q))            B = R^{-1} where R = chol(Q),
#                                                          giving B B' = Q^{-1} = V
#   blocks:                      t(chol(bdiag(V_1, ...)))  block-diagonal V; the
#                                                          K-independent MVN draws are
#                                                          algebraically identical to
#                                                          a single MVN with V = bdiag,
#                                                          which the dense codepath
#                                                          already handles correctly
#                                                          ("exact and boring" per the
#                                                          2026-05-28 planning correction).
#
# The Phase A route guard ensures low_rank cannot reach this helper
# from setup_env; the stop() branch is a contract assertion.
.vm_ped_sqrt_expr <- function(cov, legacy_mat) {
  if (is.null(cov))
    return(paste0("t(chol(", legacy_mat, "))"))
  switch(cov$format,
    "dense"                     = paste0("t(chol(", cov$data, "))"),
    "chol"                      = paste0("as.matrix(", cov$data, ")"),
    "precision"                 = paste0("as.matrix(solve(chol(",
                                          cov$data, ")))"),
    "pedigree_sparse_precision" = paste0("as.matrix(solve(chol(",
                                          cov$data, ")))"),
    "blocks"                    = paste0("t(chol(as.matrix(",
                                          "Matrix::bdiag(", cov$data,
                                          "))))"),
    stop("internal: vm/ped cov_representation$format = '", cov$format,
         "' reached .vm_ped_sqrt_expr() despite the setup_env route ",
         "guard. This is a flexyBayes bug -- the guard's allowlist ",
         "and this dispatch are out of sync.", call. = FALSE)
  )
}

# Validator: user-supplied Cholesky factor.
#
# Phase A scope: lower-triangular pattern check + square-shape check +
# group-level-count dim match. Accepts dense base-R matrix or
# Matrix::dtCMatrix. Both refusal classes name the offending symbol +
# group var so the message is actionable at the formula level.
.validate_chol_input <- function(L, name, group_var,
                                  expected_n = NULL,
                                  fit_levels = NULL) {
  if (is.null(L))
    .stop_structured_cov_refusal(
      reason_code = "chol_not_in_known_matrices",
      message     = paste0(
        "vm(", group_var, ", chol = ", name,
        "): the Cholesky factor '", name,
        "' is not in known_matrices. Pass it via known_matrices = list(",
        name, " = <your Cholesky factor>)."
      )
    )

  d <- dim(L)
  if (length(d) != 2L || d[[1L]] != d[[2L]])
    .stop_structured_cov_refusal(
      reason_code = "chol_not_square",
      message     = paste0(
        "vm(", group_var, ", chol = ", name,
        "): the Cholesky factor must be square; got dim ",
        paste(d, collapse = " x "), "."
      )
    )

  if (!.is_lower_triangular(L))
    .stop_structured_cov_refusal(
      reason_code = "chol_not_triangular",
      message     = paste0(
        "vm(", group_var, ", chol = ", name,
        "): the Cholesky factor must be lower-triangular. ",
        "If you have the upper factor U with V = U^T U, pass t(U) ",
        "or chol = t(U)."
      )
    )

  # v0.3.8 audit Critical Fix #2: known-matrix dim + level alignment.
  # Pre-v0.3.8 the validator stopped at structural checks; a chol
  # factor with wrong dim or permuted dimnames would silently
  # produce wrong predictions downstream. Both checks no-op when
  # the dispatch layer cannot supply expected_n / fit_levels (e.g.
  # parser-bypass test fixtures) and refuse cleanly otherwise.
  .check_known_matrix_dim(L, name = name, group_var = group_var,
                           expected_n = expected_n)
  .check_known_matrix_dimnames(L, name = name, group_var = group_var,
                                fit_levels = fit_levels)

  invisible(NULL)
}

# Validator: sparse precision matrix Q = V^{-1}.
#
# Phase A scope: symmetry (Matrix::isSymmetric) + positive-definite
# probe (Matrix::Cholesky). Sparse-matrix-class check is light: we
# accept any object with the Matrix-package symmetry / Cholesky
# methods. Dense matrices are accepted too (less efficient, but the
# user-facing semantics are preserved).
.validate_precision_input <- function(Q, name, group_var,
                                       expected_n = NULL,
                                       fit_levels = NULL) {
  .validate_precision_input_structural(Q, name = name,
                                        group_var = group_var)

  # v0.3.8 audit Critical Fix #2: known-matrix dim + level alignment.
  # See .validate_chol_input() for the rationale.
  .check_known_matrix_dim(Q, name = name, group_var = group_var,
                           expected_n = expected_n)
  .check_known_matrix_dimnames(Q, name = name, group_var = group_var,
                                fit_levels = fit_levels)

  # v0.3.8 audit Critical Fix #3: PD check via the size-appropriate
  # algorithm. For Matrix::dsCMatrix and other sparse symmetric
  # inputs, route through Matrix::Cholesky(perm = TRUE) so a 1e5 x
  # 1e5 sparse precision is not dense-coerced (the pre-v0.3.8
  # chol(as.matrix(Q)) path materialised the dense matrix and would
  # OOM on production-scale pedigree inputs). Dense inputs continue
  # to use base R chol() for the strict-PD contract.
  #
  # The flexyBayes.trust_pd option skips PD entirely when the user
  # has externally validated Q -- useful for repeated fits where the
  # PD probe is on the critical path.
  if (!isTRUE(getOption("flexyBayes.trust_pd", FALSE)))
    .validate_precision_input_pd(Q, name = name, group_var = group_var)

  invisible(NULL)
}

# Structural checks (cheap; always run). Splits out from
# .validate_precision_input() so callers that have externally trusted
# the PD property can still gate on nullness / dim / symmetry.
.validate_precision_input_structural <- function(Q, name, group_var) {
  if (is.null(Q))
    .stop_structured_cov_refusal(
      reason_code = "precision_not_in_known_matrices",
      message     = paste0(
        "vm(", group_var, ", precision = ", name,
        "): the precision matrix '", name,
        "' is not in known_matrices. Pass it via known_matrices = list(",
        name, " = <your precision matrix>)."
      )
    )

  d <- dim(Q)
  if (is.null(d) || length(d) != 2L || d[[1L]] != d[[2L]])
    .stop_structured_cov_refusal(
      reason_code = "precision_not_square",
      message     = paste0(
        "vm(", group_var, ", precision = ", name,
        "): the precision matrix must be square; got dim ",
        paste(d %||% "NULL", collapse = " x "), "."
      )
    )

  # Strip dimnames before the symmetry probe: dimnames are checked
  # for level alignment downstream by .check_known_matrix_dimnames(),
  # not as part of the structural symmetry contract. Pre-v0.3.8 the
  # symmetry check called Matrix::isSymmetric(Q) directly, which
  # refuses when dimnames(Q)[[1]] != dimnames(Q)[[2]] (a per-attribute
  # check); that swallowed the more actionable
  # known_matrix_dimnames_mismatch refusal downstream.
  Q_unnamed <- Q
  dimnames(Q_unnamed) <- NULL
  sym_ok <- tryCatch(
    isTRUE(Matrix::isSymmetric(Q_unnamed)),
    error = function(e) FALSE
  )
  if (!sym_ok)
    .stop_structured_cov_refusal(
      reason_code = "precision_not_symmetric",
      message     = paste0(
        "vm(", group_var, ", precision = ", name,
        "): the precision matrix must be symmetric. ",
        "Matrix::isSymmetric(Q) returned FALSE on values (ignoring ",
        "dimnames; the level-alignment check is separate)."
      )
    )

  invisible(NULL)
}

# Positive-definite probe (expensive; skipped under
# flexyBayes.trust_pd = TRUE). Dispatches by sparsity class:
#
#   - Sparse symmetric (Matrix::dsCMatrix, Matrix::dsRMatrix, or any
#     Matrix-class with a Cholesky method) routes through
#     Matrix::Cholesky(forceSymmetric(Q), perm = TRUE). The
#     fill-reducing permutation lets the sparse Cholesky run in
#     near-linear time on sparse-structured precision matrices
#     (pedigree A^{-1}; spatial BYM2 Q). The Cholesky factorisation
#     itself succeeds iff Q is PD; failure surfaces as an error or
#     warning that this tryCatch traps.
#   - Dense (base matrix) routes through base R chol() for the same
#     strict-PD contract the pre-v0.3.8 validator used. No behaviour
#     change for small-dense V^{-1} inputs.
.validate_precision_input_pd <- function(Q, name, group_var) {
  pd_ok <- if (inherits(Q, "sparseMatrix") || inherits(Q, "Matrix")) {
    # Sparse-native PD probe via Matrix::chol() on the symmetric form.
    # Matrix::chol() (S4-dispatched to the sparse symmetric method)
    # raises a CHOLMOD warning "not positive definite" when Q is
    # indefinite, which the tryCatch traps. Critically, this does
    # NOT dense-coerce Q -- the audit's Critical Fix #3 concern.
    # Matrix::Cholesky() (the higher-level factor-returning function)
    # is not a strict PD test -- it returns a CHMfactor with
    # non-positive pivot entries for indefinite Q rather than
    # raising; we use the lower-level chol() entry to get the
    # warning-based PD contract.
    tryCatch({
      Matrix::chol(Matrix::forceSymmetric(Q))
      TRUE
    }, error   = function(e) FALSE,
       warning = function(w) FALSE)
  } else {
    tryCatch({
      chol(as.matrix(Q))
      TRUE
    }, error   = function(e) FALSE,
       warning = function(w) FALSE)
  }
  if (!pd_ok)
    .stop_structured_cov_refusal(
      reason_code = "precision_not_positive_definite",
      message     = paste0(
        "vm(", group_var, ", precision = ", name,
        "): the precision matrix must be positive-definite. ",
        if (inherits(Q, "sparseMatrix") || inherits(Q, "Matrix"))
          "Matrix::chol(forceSymmetric(Q)) probe failed."
        else
          "chol(as.matrix(Q)) probe failed.",
        " Pass options(flexyBayes.trust_pd = TRUE) if you have ",
        "externally verified Q's positive-definiteness."
      )
    )
  invisible(NULL)
}

# Validator: user-supplied block-diagonal covariance carrier.
#
# Ships at v0.3.10 with ADR 0025 Decision 3. The user supplies a
# named list `blocks = my_blocks` where `my_blocks` resolves at fit
# time to `list(V_1, ..., V_K)` --- each V_k is the dense covariance
# matrix for one block of the grouping factor's levels (taken in the
# natural ordering of `levels(group_var)`). The validator runs both
# on the greta path (from `.stage5a_route_check()`) and on the INLA
# path (from `emit_inla()`'s data_inla setup loop); both pass the
# same `expected_n` (the level count) so the partition contract is
# enforced uniformly.
#
# Returns a list with `block_sizes` (integer vector of n_k) and
# `total_n` so callers can pre-compute per-block integer index
# columns + per-block precision matrices without re-walking the
# block list.
#
# Refusal contracts:
#   blocks_not_in_known_matrices    --- the symbol resolves to NULL.
#   blocks_not_a_list               --- value is not a list.
#   blocks_empty_list               --- length-zero list.
#   block_not_positive_definite     --- some V_k fails PD probe;
#                                       message names the offending
#                                       block index.
#   block_partition_incomplete      --- sum(n_k) != expected_n.
.validate_blocks_input <- function(blocks_list, name, group_var,
                                    expected_n = NULL) {
  if (is.null(blocks_list))
    .stop_structured_cov_refusal(
      reason_code = "blocks_not_in_known_matrices",
      message     = paste0(
        "vm(", group_var, ", blocks = ", name,
        "): the block list '", name,
        "' is not in known_matrices. Pass it via known_matrices = list(",
        name, " = list(V_1, ..., V_K))."
      )
    )

  if (!is.list(blocks_list) || is.data.frame(blocks_list))
    .stop_structured_cov_refusal(
      reason_code = "blocks_not_a_list",
      message     = paste0(
        "vm(", group_var, ", blocks = ", name,
        "): the block carrier must be a base-R list of K covariance ",
        "matrices; got class '",
        paste(class(blocks_list), collapse = "/"), "'."
      )
    )

  K <- length(blocks_list)
  if (K == 0L)
    .stop_structured_cov_refusal(
      reason_code = "blocks_empty_list",
      message     = paste0(
        "vm(", group_var, ", blocks = ", name,
        "): the block list is empty; expected at least one ",
        "covariance matrix."
      )
    )

  block_sizes <- integer(K)
  for (k in seq_len(K)) {
    V_k <- blocks_list[[k]]
    d   <- dim(V_k)
    if (is.null(d) || length(d) != 2L || d[[1L]] != d[[2L]])
      .stop_structured_cov_refusal(
        reason_code = "block_not_positive_definite",
        message     = paste0(
          "vm(", group_var, ", blocks = ", name,
          "): block ", k, " is not a square matrix (dim = ",
          paste(d %||% "NULL", collapse = " x "), "). ",
          "Each V_k must be a square, symmetric, positive-definite ",
          "covariance matrix."
        ),
        block_index = k
      )
    block_sizes[[k]] <- d[[1L]]

    pd_ok <- tryCatch({
      if (inherits(V_k, "Matrix"))
        Matrix::chol(Matrix::forceSymmetric(V_k))
      else
        chol(as.matrix(V_k))
      TRUE
    }, error   = function(e) FALSE,
       warning = function(w) FALSE)
    if (!pd_ok)
      .stop_structured_cov_refusal(
        reason_code = "block_not_positive_definite",
        message     = paste0(
          "vm(", group_var, ", blocks = ", name,
          "): block ", k, " (size ", d[[1L]],
          " x ", d[[2L]], ") failed the positive-definite probe. ",
          "Each V_k must be symmetric and positive-definite; ",
          "chol() / Matrix::chol() did not succeed."
        ),
        block_index = k
      )
  }

  total_n <- sum(block_sizes)
  if (!is.null(expected_n) && total_n != expected_n)
    .stop_structured_cov_refusal(
      reason_code = "block_partition_incomplete",
      message     = paste0(
        "vm(", group_var, ", blocks = ", name,
        "): the block sizes (",
        paste(block_sizes, collapse = " + "),
        " = ", total_n,
        ") do not sum to the grouping factor's level count (",
        expected_n, "). The blocks must partition levels(`",
        group_var, "`) exactly --- each level lands in one and ",
        "only one block."
      ),
      expected_n  = expected_n,
      actual_n    = total_n,
      block_sizes = block_sizes
    )

  list(
    block_sizes = block_sizes,
    total_n     = total_n,
    blocks      = blocks_list
  )
}

# v0.3.8 audit Critical Fix #2: dim alignment between a user-supplied
# known matrix and the inferred level count of its grouping factor.
# No-op when expected_n is NULL (parser-bypass test fixture, or
# called from a dispatch site that does not yet supply the level
# count).
.check_known_matrix_dim <- function(M, name, group_var, expected_n) {
  if (is.null(expected_n)) return(invisible(NULL))
  d <- dim(M)
  if (is.null(d) || length(d) != 2L)
    return(invisible(NULL))  # caught by structural checks upstream
  if (d[[1L]] != expected_n || d[[2L]] != expected_n)
    .stop_structured_cov_refusal(
      reason_code = "known_matrix_dim_mismatch",
      message     = paste0(
        "vm(", group_var, "): the known matrix '", name,
        "' has dimension ", d[[1L]], " x ", d[[2L]],
        ", but the grouping factor `", group_var, "` carries ",
        expected_n, " levels. The matrix must be ",
        expected_n, " x ", expected_n,
        " (one row + column per level)."
      ),
      expected_n = expected_n,
      actual_dim = d
    )
  invisible(NULL)
}

# v0.3.8 audit Critical Fix #2: dimname-driven level alignment. When
# the matrix carries dimnames, we can enforce that the rows / columns
# correspond positionally to levels(<group>). When dimnames are
# absent the check no-ops -- the dispatch layer surfaces an alignment
# caution on backend_decision instead (the user-side responsibility
# pre-v0.3.8 comment in emit_inla() was the symptom this fix
# addresses).
.check_known_matrix_dimnames <- function(M, name, group_var, fit_levels) {
  if (is.null(fit_levels)) return(invisible(NULL))
  dn <- dimnames(M)
  if (is.null(dn) || is.null(dn[[1L]]) || is.null(dn[[2L]]))
    return(invisible(NULL))  # dimnames absent -> caution surfaced upstream

  if (!identical(dn[[1L]], dn[[2L]]))
    .stop_structured_cov_refusal(
      reason_code = "known_matrix_dimnames_mismatch",
      message     = paste0(
        "vm(", group_var, "): the known matrix '", name,
        "' has different rownames and colnames. The matrix represents ",
        "the per-level covariance / precision structure; rownames and ",
        "colnames must be identical and must equal levels(`",
        group_var, "`)."
      ),
      rownames = utils::head(dn[[1L]], 5L),
      colnames = utils::head(dn[[2L]], 5L)
    )

  if (!setequal(dn[[1L]], fit_levels))
    .stop_structured_cov_refusal(
      reason_code = "known_matrix_level_mismatch",
      message     = paste0(
        "vm(", group_var, "): the known matrix '", name,
        "' carries dimnames that do not match levels(`", group_var,
        "`). Compare setdiff(dimnames(", name, ")[[1]], levels(`",
        group_var, "`)) and setdiff(levels(`", group_var,
        "`), dimnames(", name, ")[[1]]) to surface the gap."
      ),
      matrix_levels_head = utils::head(dn[[1L]], 5L),
      fit_levels_head    = utils::head(fit_levels, 5L)
    )

  if (!identical(dn[[1L]], fit_levels))
    .stop_structured_cov_refusal(
      reason_code = "known_matrix_level_mismatch",
      message     = paste0(
        "vm(", group_var, "): the known matrix '", name,
        "' has the correct level set but is ordered differently from ",
        "levels(`", group_var, "`). INLA's generic0 model and ",
        "greta's t(chol(V)) emit both require positional alignment ",
        "with levels(`", group_var, "`). Permute the matrix:\n",
        "  perm <- match(levels(`", group_var, "`), dimnames(",
        name, ")[[1]])\n",
        "  ", name, " <- ", name, "[perm, perm]"
      ),
      matrix_levels_head = utils::head(dn[[1L]], 5L),
      fit_levels_head    = utils::head(fit_levels, 5L)
    )

  invisible(NULL)
}

# Lower-triangular pattern detector. Works on dense matrix and
# Matrix::dtCMatrix / Matrix::Matrix subclasses. The check tolerates
# numerically-zero entries above the diagonal at default-tolerance.
.is_lower_triangular <- function(L) {
  if (inherits(L, "dtCMatrix") || inherits(L, "dtrMatrix"))
    return(isTRUE(L@uplo == "L"))
  if (inherits(L, "Matrix"))
    L <- as.matrix(L)
  if (!is.matrix(L)) return(FALSE)
  upper <- L[upper.tri(L)]
  isTRUE(all(abs(upper) < .Machine$double.eps^0.5))
}

# Typed-condition refusal raiser. Mirrors the pattern established by
# .stop_preflight_refusal() in R/fb_preflight.R. Additional named
# args land in the condition object so callers can pattern-match on
# format, scheme, etc.
.stop_structured_cov_refusal <- function(reason_code, message, ...) {
  payload <- c(
    list(message = message, reason_code = reason_code, call = NULL),
    list(...)
  )
  cond <- structure(
    payload,
    class = c("flexybayes_structured_cov_refusal",
              "flexybayes_refusal", "error", "condition")
  )
  stop(cond)
}
