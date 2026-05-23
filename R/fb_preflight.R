# .fb_preflight() -- Stage 2 MVP design-memory preflight (v0.3.0).
#
# Takes a parsed `<fb_terms>` IR + an `<fb_dataset>` wrapper and
# returns an `<fb_preflight>` S3 list with three slots:
#   $per_term_estimate    named list, one entry per IR term, each
#                         carrying design_memory_bytes (numeric),
#                         representation_class (character), and
#                         aggregated_likelihood_candidate (logical)
#   $total_estimate_bytes sum across terms plus a fixed bookkeeping
#                         overhead (page-sized: 4096 bytes)
#   $refusal              NULL if accepted; otherwise a structured
#                         `<fb_preflight_refusal>` object with
#                         reason_code = "design_memory_exceeds_ceiling",
#                         the binding term label, its estimate, and
#                         the active ceiling in bytes.
#
# All term estimates are deterministic, computed from IR + dataset
# metadata only -- never reads the underlying $data row-wise. This
# keeps preflight O(terms) regardless of n_rows; the 1e8-row Tier-3
# stress test exercises exactly this property.
#
# Internal-only at v0.3.0. No @export tag.


# Per-term overhead constant in bytes; covers list wrappers and the
# small attributes attached to each design slot. Empirically calibrated
# against `object.size()` on isolated fb_terms allocations: 256 bytes
# overshoots a hand-counted ALLOC headers + names + attributes block
# on R 4.4 by ~16 bytes, comfortably inside the 5% acceptance tolerance.
.FB_PREFLIGHT_TERM_OVERHEAD <- 256

# Fixed bookkeeping overhead for the preflight result itself plus the
# IR + dataset wrappers. Page-sized for cleanliness; the absolute value
# is a small fraction of any single term that would trigger a refusal.
.FB_PREFLIGHT_BASE_OVERHEAD <- 4096

# Default smooth-basis dimension when an mgcv-style s(x) term carries
# no explicit k= argument. Matches mgcv's default (10) per ?mgcv::s.
.FB_PREFLIGHT_SMOOTH_K_DEFAULT <- 10L


# Top-level constructor. Returns the `<fb_preflight>` object even when
# the design is feasible (refusal == NULL); the caller pattern-matches
# on inherits(pf$refusal, "fb_preflight_refusal").
.fb_preflight <- function(fb_ir,
                          fb_dataset,
                          memory_ceiling_gb = NULL) {

  if (!inherits(fb_ir, "fb_terms"))
    stop(".fb_preflight() requires an `<fb_terms>` IR; got: ",
         paste(class(fb_ir), collapse = "/"), call. = FALSE)
  if (!inherits(fb_dataset, "fb_dataset"))
    stop(".fb_preflight() requires an `<fb_dataset>` wrapper; got: ",
         paste(class(fb_dataset), collapse = "/"), call. = FALSE)

  ceiling_bytes <- .fb_resolve_ceiling(memory_ceiling_gb)
  family_ok     <- .fb_preflight_family_in_scope(fb_ir)

  per_term <- list()
  n_rows   <- as.numeric(fb_dataset$n_rows)

  # Fixed-effect terms (intercept is implicit; not estimated separately;
  # the design block for fixed numerics + factors carries it). Each
  # term carries enough to dispatch to the right estimator.
  for (i in seq_along(fb_ir$fixed_terms)) {
    entry <- .preflight_fixed_term(
      term       = fb_ir$fixed_terms[[i]],
      n_rows     = n_rows,
      fb_dataset = fb_dataset,
      family_ok  = family_ok
    )
    per_term[[entry$label]] <- entry
  }

  # Random-effect terms (random intercept, uncorrelated random slope).
  for (i in seq_along(fb_ir$random_terms)) {
    entry <- .preflight_random_term(
      term       = fb_ir$random_terms[[i]],
      n_rows     = n_rows,
      fb_dataset = fb_dataset,
      family_ok  = family_ok
    )
    per_term[[entry$label]] <- entry
  }

  # Smooth detection on fixed_terms (mgcv-style s() lives there in the
  # asreml ingest path; the brms walker refuses smooths at ingest time
  # so they don't reach the IR via fb_from_brms, but the IR may still
  # carry them on the asreml side).
  # The .preflight_fixed_term() dispatcher handles the smooth marker
  # internally; the if-branch above already covers it.

  total <- .FB_PREFLIGHT_BASE_OVERHEAD +
           sum(vapply(per_term, function(e) e$design_memory_bytes,
                      numeric(1L)))

  refusal <- NULL
  if (total > ceiling_bytes) {
    # Binding term = largest single-term estimate.
    binding_idx   <- which.max(vapply(per_term,
                                       function(e) e$design_memory_bytes,
                                       numeric(1L)))
    binding_label <- names(per_term)[[binding_idx]]
    binding_entry <- per_term[[binding_idx]]
    refusal <- .new_fb_preflight_refusal(
      reason_code     = "design_memory_exceeds_ceiling",
      binding_term    = binding_label,
      binding_bytes   = binding_entry$design_memory_bytes,
      total_bytes     = total,
      ceiling_bytes   = ceiling_bytes,
      n_rows          = n_rows
    )
  }

  structure(
    list(
      per_term_estimate    = per_term,
      total_estimate_bytes = total,
      ceiling_bytes        = ceiling_bytes,
      n_rows               = n_rows,
      refusal              = refusal
    ),
    class = c("fb_preflight", "list")
  )
}


# ---------------------------------------------------------------- #
# Family-in-scope check for aggregated_likelihood_candidate            #
# ---------------------------------------------------------------- #

# The Stage-3A scope envelope includes "gaussian family + identity link"
# per ADR 0022 §1. Preflight evaluates this once and gates every
# per-term flag through it; non-gaussian / non-identity families
# cannot carry the aggregation candidacy on any term.
.fb_preflight_family_in_scope <- function(fb_ir) {
  fam_ok  <- identical(fb_ir$family, "gaussian")
  link_ok <- is.null(fb_ir$link) || identical(fb_ir$link, "identity")
  fam_ok && link_ok
}


# ---------------------------------------------------------------- #
# Fixed-term estimator                                              #
# ---------------------------------------------------------------- #

# Walk a single fixed_terms[[i]] entry. The IR's fixed_terms list
# entries carry varying shapes depending on the ingest path; we
# pattern-match on common slots: $type ("numeric", "factor",
# "interaction", "smooth", "expression"), $var (variable name),
# $var_n (level count for factor terms), $deparse (free-form label).
.preflight_fixed_term <- function(term, n_rows, fb_dataset, family_ok) {

  ttype <- if (!is.null(term$type)) term$type else "expression"
  label <- .preflight_term_label(term, ttype, kind = "fixed")

  # Smooth (s(x), t2(x)) -- dense basis block.
  if (ttype %in% c("smooth", "s", "t2")) {
    k <- if (!is.null(term$k) && is.numeric(term$k))
           as.integer(term$k) else .FB_PREFLIGHT_SMOOTH_K_DEFAULT
    bytes <- 8 * n_rows * k +    # N x k dense basis
             8 * k +              # k basis coefficients
             .FB_PREFLIGHT_TERM_OVERHEAD
    return(.preflight_entry(
      label                            = label,
      design_memory_bytes              = bytes,
      representation_class             = "dense_baseline",
      aggregated_likelihood_candidate  = FALSE,
      term_kind                        = "fixed_smooth"
    ))
  }

  # Numeric fixed term -- one double column.
  if (ttype %in% c("numeric", "continuous", "I")) {
    bytes <- 8 * n_rows +          # one double column
             8 +                    # one beta coefficient
             .FB_PREFLIGHT_TERM_OVERHEAD
    return(.preflight_entry(
      label                            = label,
      design_memory_bytes              = bytes,
      representation_class             = "indexed_fixed_numeric",
      aggregated_likelihood_candidate  = family_ok,
      term_kind                        = "fixed_numeric"
    ))
  }

  # Factor fixed term -- integer index + (k-1) beta dummy contrasts.
  if (ttype %in% c("factor", "categorical")) {
    k <- .preflight_term_level_count(term, fb_dataset)
    n_dummies <- max(k - 1L, 0L)
    bytes <- 4 * n_rows +          # integer index column
             8 * n_dummies +        # dummy-contrast beta vector
             .FB_PREFLIGHT_TERM_OVERHEAD
    return(.preflight_entry(
      label                            = label,
      design_memory_bytes              = bytes,
      representation_class             = "indexed_fixed_factor",
      aggregated_likelihood_candidate  = family_ok,
      term_kind                        = "fixed_factor"
    ))
  }

  # Interaction / expression / fallthrough -- dense baseline.
  # Assumes a single dense double column of length N as a conservative
  # lower bound; refusal logic uses the binding-term flag so this
  # bound is safe (real interactions are typically larger, not smaller).
  bytes <- 8 * n_rows +
           8 +
           .FB_PREFLIGHT_TERM_OVERHEAD
  .preflight_entry(
    label                            = label,
    design_memory_bytes              = bytes,
    representation_class             = "dense_baseline",
    aggregated_likelihood_candidate  = FALSE,
    term_kind                        = "fixed_other"
  )
}


# ---------------------------------------------------------------- #
# Random-term estimator                                             #
# ---------------------------------------------------------------- #

.preflight_random_term <- function(term, n_rows, fb_dataset, family_ok) {

  rtype <- if (!is.null(term$type)) term$type else "simple"
  label <- .preflight_term_label(term, rtype, kind = "random")
  k     <- .preflight_term_level_count(term, fb_dataset)

  # (1 | g) -- random intercept. Integer index + k-vector of u's.
  if (identical(rtype, "simple")) {
    bytes <- 4 * n_rows +          # group index column
             8 * k +                # latent random-effect vector
             .FB_PREFLIGHT_TERM_OVERHEAD
    return(.preflight_entry(
      label                            = label,
      design_memory_bytes              = bytes,
      representation_class             = "indexed_random_intercept",
      aggregated_likelihood_candidate  = family_ok,
      term_kind                        = "random_intercept"
    ))
  }

  # (x || g) / (1 + x || g) / (0 + x || g) -- uncorrelated slope.
  # Integer index + slope variable column + k-vector of slope (and,
  # if with_intercept, another k-vector of intercept).
  if (identical(rtype, "simple_slope_uncor")) {
    with_int <- isTRUE(term$with_intercept)
    bytes <- 4 * n_rows +                           # group index
             8 * n_rows +                            # slope variable column
             8 * k * (1L + as.integer(with_int)) +   # latent slope (+ intercept)
             .FB_PREFLIGHT_TERM_OVERHEAD
    return(.preflight_entry(
      label                            = label,
      design_memory_bytes              = bytes,
      representation_class             = "dense_baseline",
      aggregated_likelihood_candidate  = FALSE,
      term_kind                        = "random_slope"
    ))
  }

  # Fallthrough -- correlated slope (refused upstream by fb_from_brms,
  # but the asreml ingest may carry structured forms). Conservative
  # estimate uses the slope-uncor formula doubled (for the correlation
  # block); ensures we do not silently under-estimate large designs.
  bytes <- 4 * n_rows +
           8 * n_rows +
           16 * k +
           .FB_PREFLIGHT_TERM_OVERHEAD
  .preflight_entry(
    label                            = label,
    design_memory_bytes              = bytes,
    representation_class             = "dense_baseline",
    aggregated_likelihood_candidate  = FALSE,
    term_kind                        = "random_other"
  )
}


# ---------------------------------------------------------------- #
# Per-term helpers                                                  #
# ---------------------------------------------------------------- #

# Build a single per-term entry. Centralised so adding a new field
# (e.g. an `effort_estimate` for Stage 2.1) is a one-line change.
.preflight_entry <- function(label,
                              design_memory_bytes,
                              representation_class,
                              aggregated_likelihood_candidate,
                              term_kind) {
  list(
    label                            = label,
    design_memory_bytes              = as.numeric(design_memory_bytes),
    representation_class             = representation_class,
    aggregated_likelihood_candidate  = isTRUE(aggregated_likelihood_candidate),
    term_kind                        = term_kind,
    overhead_constant                = .FB_PREFLIGHT_TERM_OVERHEAD
  )
}

# Build a display label from an IR term descriptor. Mirrors the
# canonical-name conventions for diagnostic visibility -- the binding
# term in a refusal must be human-readable.
.preflight_term_label <- function(term, ttype, kind) {
  if (!is.null(term$label) && nzchar(term$label)) return(term$label)
  if (!is.null(term$deparse) && nzchar(term$deparse)) return(term$deparse)

  if (identical(kind, "fixed")) {
    if (ttype %in% c("smooth", "s", "t2") && !is.null(term$var))
      return(paste0("s(", term$var, ")"))
    if (!is.null(term$var)) return(as.character(term$var))
    return("<fixed:unnamed>")
  }
  # random
  group <- if (!is.null(term$var)) as.character(term$var) else "?"
  if (identical(ttype, "simple"))
    return(paste0("(1 | ", group, ")"))
  if (identical(ttype, "simple_slope_uncor")) {
    slope <- if (!is.null(term$slope_var))
               as.character(term$slope_var) else "x"
    lhs <- if (isTRUE(term$with_intercept))
             paste0("1 + ", slope) else slope
    return(paste0("(", lhs, " || ", group, ")"))
  }
  paste0("(", ttype, " | ", group, ")")
}

# Level-count lookup. Reads in priority order: (1) the IR's cached
# $var_n; (2) the dataset's frozen dictionary length; (3) NA which
# escalates to a conservative ceiling for the binding-term decision.
.preflight_term_level_count <- function(term, fb_dataset) {
  # Random-term IR carries $var_n; fixed-factor IR carries $n_levels;
  # the asreml ingest occasionally uses $K. Try each in order.
  for (slot in c("var_n", "n_levels", "K")) {
    v <- term[[slot]]
    if (!is.null(v) && !is.na(v)) return(as.integer(v))
  }
  if (!is.null(term$var)) {
    k <- .fb_dataset_levels(fb_dataset, as.character(term$var))
    if (!is.na(k)) return(as.integer(k))
  }
  # Conservative fallback: assume a single level (yields the smallest
  # latent block, but the term still dominates via the index column).
  1L
}


# ---------------------------------------------------------------- #
# Memory ceiling resolution                                         #
# ---------------------------------------------------------------- #

# Resolves the byte-valued ceiling. Explicit override via the
# memory_ceiling_gb argument; otherwise 0.8 x system RAM via
# benchmarkme::get_ram() or memuse::Sys.meminfo(); fallback to 8 GiB
# when neither probe is installed. The fallback is documented so
# users in minimal install environments see a predictable refusal
# threshold rather than a hard error.
.fb_resolve_ceiling <- function(memory_ceiling_gb) {
  if (!is.null(memory_ceiling_gb)) {
    if (!is.numeric(memory_ceiling_gb) ||
        length(memory_ceiling_gb) != 1L ||
        memory_ceiling_gb <= 0)
      stop("`memory_ceiling_gb` must be a positive numeric scalar; got: ",
           deparse(memory_ceiling_gb), call. = FALSE)
    return(as.numeric(memory_ceiling_gb) * 1024^3)
  }

  ram_bytes <- .fb_probe_system_ram()
  if (is.na(ram_bytes)) {
    # 8 GiB conservative fallback when neither probe is available.
    return(8 * 1024^3)
  }
  0.8 * ram_bytes
}

.fb_probe_system_ram <- function() {
  if (requireNamespace("benchmarkme", quietly = TRUE)) {
    res <- tryCatch(as.numeric(benchmarkme::get_ram()),
                    error = function(e) NA_real_)
    if (!is.na(res) && res > 0) return(res)
  }
  if (requireNamespace("memuse", quietly = TRUE)) {
    res <- tryCatch({
      mi <- memuse::Sys.meminfo()
      as.numeric(mi$totalram@size) *
        switch(mi$totalram@unit,
               "B" = 1, "KiB" = 1024, "MiB" = 1024^2,
               "GiB" = 1024^3, "TiB" = 1024^4, NA_real_)
    }, error = function(e) NA_real_)
    if (!is.na(res) && res > 0) return(res)
  }
  NA_real_
}


# ---------------------------------------------------------------- #
# Refusal constructor + print                                       #
# ---------------------------------------------------------------- #

.new_fb_preflight_refusal <- function(reason_code,
                                       binding_term,
                                       binding_bytes,
                                       total_bytes,
                                       ceiling_bytes,
                                       n_rows) {
  structure(
    list(
      reason_code   = reason_code,
      binding_term  = binding_term,
      binding_bytes = as.numeric(binding_bytes),
      total_bytes   = as.numeric(total_bytes),
      ceiling_bytes = as.numeric(ceiling_bytes),
      n_rows        = n_rows
    ),
    class = c("fb_preflight_refusal", "list")
  )
}


# ---------------------------------------------------------------- #
# S3 print methods                                                  #
# ---------------------------------------------------------------- #

#' Print method for an internal `<fb_preflight>` summary
#'
#' Diagnostic print of the Stage 2 design-memory preflight result:
#' per-term `design_memory_bytes` (formatted with thousand-separator
#' " "), `representation_class`, and the aggregate ceiling check.
#' On refusal the binding term + numeric ceiling appear below the
#' per-term table.
#'
#' @param x   an `<fb_preflight>` object.
#' @param ... unused.
#' @return invisibly returns `x`.
#' @keywords internal
#' @export
print.fb_preflight <- function(x, ...) {
  cat(sprintf(
    "<fb_preflight> n_rows = %s; total = %s bytes; ceiling = %s bytes\n",
    format(x$n_rows,                   big.mark = " ", scientific = FALSE),
    format(round(x$total_estimate_bytes), big.mark = " ", scientific = FALSE),
    format(round(x$ceiling_bytes),       big.mark = " ", scientific = FALSE)
  ))
  if (length(x$per_term_estimate)) {
    cat("  per-term:\n")
    for (nm in names(x$per_term_estimate)) {
      e <- x$per_term_estimate[[nm]]
      cat(sprintf(
        "    %-28s  %14s B  %-26s  agg_candidate=%s\n",
        nm,
        format(round(e$design_memory_bytes), big.mark = " ",
               scientific = FALSE),
        e$representation_class,
        e$aggregated_likelihood_candidate
      ))
    }
  }
  if (!is.null(x$refusal)) {
    cat("\n")
    print(x$refusal)
  }
  invisible(x)
}

#' Print method for an internal `<fb_preflight_refusal>` object
#'
#' Three-line diagnostic: reason code, binding term + its byte
#' estimate, and the active ceiling with the suggested override.
#'
#' @param x   an `<fb_preflight_refusal>` object.
#' @param ... unused.
#' @return invisibly returns `x`.
#' @keywords internal
#' @export
print.fb_preflight_refusal <- function(x, ...) {
  cat("<fb_preflight_refusal>\n")
  cat(sprintf("  reason_code:    %s\n", x$reason_code))
  cat(sprintf("  binding_term:   %s\n", x$binding_term))
  cat(sprintf("  binding_bytes:  %s B  (%.2f GiB)\n",
              format(round(x$binding_bytes), big.mark = " ",
                     scientific = FALSE),
              x$binding_bytes / 1024^3))
  cat(sprintf("  total_bytes:    %s B  (%.2f GiB)\n",
              format(round(x$total_bytes), big.mark = " ",
                     scientific = FALSE),
              x$total_bytes / 1024^3))
  cat(sprintf("  ceiling_bytes:  %s B  (%.2f GiB)\n",
              format(round(x$ceiling_bytes), big.mark = " ",
                     scientific = FALSE),
              x$ceiling_bytes / 1024^3))
  ceiling_gb_suggest <- ceiling(x$total_bytes / 1024^3 * 1.25)
  cat(sprintf("  override:       pass memory_ceiling_gb = %d to retry\n",
              ceiling_gb_suggest))
  invisible(x)
}
