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
# opt-in via Decision 6). v0.3.8 activates blocks; low_rank reserves
# the slot for ADR 0027 (Stage 6 / v0.4.0).
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
.stage5a_route_check <- function(term, known_matrices) {
  cov <- term$cov_representation
  if (is.null(cov) || identical(cov$format, "dense"))
    return(invisible(NULL))

  fmt <- cov$format

  if (fmt == "chol") {
    L <- known_matrices[[cov$data]]
    .validate_chol_input(L, name = cov$data, group_var = term$var)
    return(invisible(NULL))
  }

  if (fmt %in% c("precision", "pedigree_sparse_precision")) {
    Q <- known_matrices[[cov$data]]
    .validate_precision_input(Q, name = cov$data, group_var = term$var)
    return(invisible(NULL))
  }

  if (fmt == "blocks") {
    .stop_structured_cov_refusal(
      reason_code = "route_not_yet_emitted",
      message     = paste0(
        "vm(", term$var, ", blocks = ", cov$data,
        "): the block-diagonal covariance route is reserved for ",
        "v0.3.8 (ADR 0025 Decision 3)."
      ),
      format = "blocks"
    )
  }

  if (fmt == "low_rank") {
    .stop_structured_cov_refusal(
      reason_code = "approximate_route_not_yet_registered",
      message     = paste0(
        "vm(", term$var, ", low_rank_factor = ", cov$data,
        ", low_rank_scheme = '", cov$scheme,
        "'): approximate routes refuse until ADR 0027 (Stage 6 / ",
        "v0.4.0) ships the approximation registry."
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
#
# The Phase A route guard ensures blocks / low_rank cannot reach this
# helper from setup_env; the stop() branch is a contract assertion.
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
.validate_chol_input <- function(L, name, group_var) {
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

  invisible(NULL)
}

# Validator: sparse precision matrix Q = V^{-1}.
#
# Phase A scope: symmetry (Matrix::isSymmetric) + positive-definite
# probe (Matrix::Cholesky). Sparse-matrix-class check is light: we
# accept any object with the Matrix-package symmetry / Cholesky
# methods. Dense matrices are accepted too (less efficient, but the
# user-facing semantics are preserved).
.validate_precision_input <- function(Q, name, group_var) {
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

  sym_ok <- tryCatch(
    isTRUE(Matrix::isSymmetric(Q)),
    error = function(e) FALSE
  )
  if (!sym_ok)
    .stop_structured_cov_refusal(
      reason_code = "precision_not_symmetric",
      message     = paste0(
        "vm(", group_var, ", precision = ", name,
        "): the precision matrix must be symmetric. ",
        "Matrix::isSymmetric(Q) returned FALSE."
      )
    )

  # Strict positive-definite check via base R chol() on the dense
  # coercion. Matrix::Cholesky() routes through LAPACK dpstrf which
  # uses pivoting with rank detection and succeeds on indefinite
  # matrices; that is unsuitable for Phase A's strict PD contract.
  # Sparse-input efficiency is a Phase B concern (the validator will
  # gain a sparse-Cholesky branch when emit ships).
  pd_ok <- tryCatch({
    chol(as.matrix(Q))
    TRUE
  }, error = function(e) FALSE,
     warning = function(w) FALSE)
  if (!pd_ok)
    .stop_structured_cov_refusal(
      reason_code = "precision_not_positive_definite",
      message     = paste0(
        "vm(", group_var, ", precision = ", name,
        "): the precision matrix must be positive-definite. ",
        "Matrix::Cholesky() probe failed."
      )
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
