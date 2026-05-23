# canonical_names -- per-backend parameter-name resolver for flexyBayes.
#
# Implements ADR 0005 in design-notes-priors-brms-lgm.md. The
# `canonical_names()` S3 generic returns a list `(map, transform,
# source)` keyed by backend-native parameter names; values give the
# canonical (brms-style) parameter names; the optional transform
# slot carries value-transform functions (used by INLA's
# precision-to-SD `sqrt(1/prec)` mapping).
#
# Per-backend mapper functions register at package load via the
# internal list `.canonical_mappers`. Each mapper accepts (fit,
# fb_terms) and returns `list(map, transform)`. Users can register
# additional mappers via `register_canonical_mapper()` (internal in
# v0.2; exported in v0.3+ when third-party backend authors might use
# it).
#
# The greta-side mapping derives from the asreml-emit conventions
# (mu_atg = intercept, tau_<tag>[i,1] = factor level i of <tag>,
# sigma_<group> = SD of <group>, sigma_e_atg = residual SD). The
# INLA-side mapping uses summary.fixed rownames for fixed effects
# (already brms-canonical) and translates the "Precision for ..."
# hyperparameter names plus the precision-to-SD value transform.


# ---------------------------------------------------------------- #
# Internal registry                                                  #
# ---------------------------------------------------------------- #
# Populated at the bottom of this file with the v0.2 backend
# mappers (greta + inla). Additional mappers (e.g., for a future
# stan_via_brms triangulate-peer backend or NIMBLE) register via
# `register_canonical_mapper(backend, mapper)`.

.canonical_mappers <- new.env(parent = emptyenv())


# ---------------------------------------------------------------- #
# Internal helper -- coalescing operator                            #
# ---------------------------------------------------------------- #

`%||%` <- function(x, y) if (is.null(x)) y else x


# ---------------------------------------------------------------- #
# Generic + methods                                                  #
# ---------------------------------------------------------------- #

#' Canonical parameter-name view for a flexyBayes fit
#'
#' Returns the backend-native -> canonical parameter-name map for a
#' fit, plus per-parameter value transforms where applicable (e.g.,
#' the INLA precision-to-SD `sqrt(1/prec)` transform applied to
#' hyperparameters before triangulation). The canonical convention
#' follows brms (`(Intercept)`, `<term>`, `sd_<group>`, `sigma`,
#' `r_<group>[<level>]`).
#'
#' On `flexybayes` and `flexybayes_inla` fits, the per-backend
#' mapper registered at package load (`greta` or `inla`) drives the
#' resolution; the returned map is cached on
#' `fit$extras$canonical_map` for fast repeated access. On
#' `flexybayes_direct_greta` fits (built via [fb_greta()]) the map
#' comes from the user-supplied `canonical_names` argument, with a
#' verbatim-greta-name fallback when the argument is omitted.
#'
#' @param fit A `flexybayes` (or `flexybayes_inla`) object.
#' @param drop Logical: if `TRUE` (default `FALSE`), drop
#'   backend-native names that are not in the registered map
#'   (e.g., INLA's `Predictor.<i>` latent-predictor draws). When
#'   `FALSE`, un-mapped names appear in the returned `$unmapped`
#'   element.
#' @param ... Additional arguments (ignored by current methods).
#' @return A list with components:
#'   \describe{
#'     \item{`map`}{Named character vector keyed by backend-native
#'       parameter name with canonical name as the value.}
#'     \item{`transform`}{Named list of `function(x) -> x'`
#'       transforms keyed by canonical name. Empty list when no
#'       transforms apply.}
#'     \item{`source`}{Character: `"registry"`, `"user"`,
#'       `"registry_fallback_verbatim"`, or `"legacy_inferred"`.}
#'     \item{`unmapped`}{Character vector of backend-native names
#'       not in the map (when `drop = FALSE`).}
#'   }
#' @export
canonical_names <- function(fit, drop = FALSE, ...)
  UseMethod("canonical_names")

#' @rdname canonical_names
#' @export
canonical_names.flexybayes <- function(fit, drop = FALSE, ...) {
  if (!is.null(fit$extras$canonical_map))
    return(.maybe_attach_unmapped(fit$extras$canonical_map, fit,
                                  drop, backend = "greta"))
  fb <- fit$extras$fb_terms %||% .parse_info_as_pseudo_fb(fit)
  mapper <- .canonical_mappers$greta
  if (is.null(mapper))
    return(list(map = character(0), transform = list(),
                source = "no_mapper"))
  res <- mapper(fit, fb)
  res$source <- res$source %||% "registry"
  .maybe_attach_unmapped(res, fit, drop, backend = "greta")
}

#' @rdname canonical_names
#' @export
canonical_names.flexybayes_inla <- function(fit, drop = FALSE, ...) {
  if (!is.null(fit$extras$canonical_map))
    return(.maybe_attach_unmapped(fit$extras$canonical_map, fit,
                                  drop, backend = "inla"))
  fb <- fit$extras$fb_terms %||% fit$fb
  mapper <- .canonical_mappers$inla
  if (is.null(mapper))
    return(list(map = character(0), transform = list(),
                source = "no_mapper"))
  res <- mapper(fit, fb)
  res$source <- res$source %||% "registry"
  .maybe_attach_unmapped(res, fit, drop, backend = "inla")
}

#' @rdname canonical_names
#' @export
canonical_names.flexybayes_brms <- function(fit, drop = FALSE, ...) {
  if (!is.null(fit$extras$canonical_map))
    return(.maybe_attach_unmapped(fit$extras$canonical_map, fit,
                                  drop, backend = "brms"))
  fb <- fit$extras$fb_terms %||% fit$extras$parse_info
  mapper <- .canonical_mappers$brms
  if (is.null(mapper))
    return(list(map = character(0), transform = list(),
                source = "no_mapper"))
  res <- mapper(fit, fb)
  res$source <- res$source %||% "registry"
  .maybe_attach_unmapped(res, fit, drop, backend = "brms")
}

#' @rdname canonical_names
#' @export
canonical_names.flexybayes_direct_greta <- function(fit, drop = FALSE,
                                                    ...) {
  cm <- fit$extras$model_info$canonical_map
  if (is.null(cm))
    return(list(map = character(0), transform = list(),
                source = "no_canonical_map"))
  # When user supplied canonical_names, at least one name->canonical
  # pair differs from the identity; otherwise it's the verbatim
  # fallback per ADR 0012.
  has_renames <- any(names(cm) != unname(cm))
  list(map = cm,
       transform = list(),
       source = if (has_renames) "user" else "registry_fallback_verbatim")
}


# ---------------------------------------------------------------- #
# Registration helper                                               #
# ---------------------------------------------------------------- #

# Internal in v0.2 -- exported in v0.3 once the third-party backend
# author surface is documented. The helper attaches a mapper to the
# .canonical_mappers registry under the given backend key.
register_canonical_mapper <- function(backend, mapper) {
  if (!is.character(backend) || length(backend) != 1L || !nzchar(backend))
    stop("`backend` must be a non-empty length-1 character string.",
         call. = FALSE)
  if (!is.function(mapper))
    stop("`mapper` must be a function (fit, fb_terms) -> ",
         "list(map, transform).", call. = FALSE)
  assign(backend, mapper, envir = .canonical_mappers)
  invisible(NULL)
}


# ---------------------------------------------------------------- #
# Helpers                                                            #
# ---------------------------------------------------------------- #

# Build a pseudo-fb_terms shape from the parse_info structure on a
# greta fit when the full IR was not attached (legacy fits + the
# pre-ADR-0005 emit_greta path). Returns a list with the slots the
# greta mapper needs: response, intercept, fixed_terms,
# random_terms.
.parse_info_as_pseudo_fb <- function(fit) {
  pi <- fit$extras$parse_info
  if (is.null(pi))
    return(NULL)
  list(
    response     = pi$fixed$response,
    intercept    = pi$fixed$intercept %||% TRUE,
    fixed_terms  = pi$fixed$terms     %||% list(),
    random_terms = pi$random          %||% list(),
    rcov_terms   = pi$rcov            %||% list()
  )
}

# Attach an `$unmapped` element to the canonical-names result when
# requested. The `unmapped` set is the difference between (the
# names present in the fit's posterior draws) and (the keys of the
# canonical map). This surfaces backend-side draws (e.g., INLA's
# Predictor.* linear-predictor samples, or greta-side tracked-
# latent BLUPs) that the registry doesn't translate.
.maybe_attach_unmapped <- function(res, fit, drop, backend) {
  if (isTRUE(drop)) return(res)
  draws_names <- tryCatch(.backend_draw_names(fit, backend),
                          error = function(e) character(0))
  if (length(draws_names) == 0L) {
    res$unmapped <- character(0)
    return(res)
  }
  res$unmapped <- setdiff(draws_names, names(res$map))
  res
}

# Backend-native draw names for the unmapped set. Greta fits expose
# them via the mcmc.list at fit$greta$draws; INLA fits via
# rownames(summary.fixed) + rownames(summary.hyperpar).
.backend_draw_names <- function(fit, backend) {
  if (identical(backend, "greta")) {
    if (is.null(fit$greta) || is.null(fit$greta$draws))
      return(character(0))
    m <- as.matrix(fit$greta$draws)
    if (is.null(colnames(m))) character(0) else colnames(m)
  } else if (identical(backend, "inla")) {
    if (is.null(fit$inla)) return(character(0))
    c(rownames(fit$inla$summary.fixed)     %||% character(0),
      rownames(fit$inla$summary.hyperpar)  %||% character(0))
  } else if (identical(backend, "brms")) {
    if (is.null(fit$brms)) return(character(0))
    if (!requireNamespace("posterior", quietly = TRUE))
      return(character(0))
    m <- tryCatch(as.matrix(posterior::as_draws_matrix(fit$brms)),
                  error = function(e) NULL)
    if (is.null(m)) character(0) else colnames(m) %||% character(0)
  } else {
    character(0)
  }
}

# Parse an asreml-emit factor-coefficient name like "tau_env[3,1]"
# into its components: tag = "env", level_index = 3L. Returns NULL
# when the pattern does not match.
.parse_tau_factor <- function(nm) {
  m <- regmatches(nm, regexec("^tau_([^\\[]+)\\[(\\d+),(\\d+)\\]$", nm))[[1]]
  if (length(m) < 4L) return(NULL)
  list(tag = m[2], level = as.integer(m[3]),
       col = as.integer(m[4]))
}


# ---------------------------------------------------------------- #
# v0.2 mapper: greta backend                                        #
# ---------------------------------------------------------------- #
# asreml-emit-side names produced by emit_greta.R:
#   mu_atg                  -- intercept
#   tau_<tag>[<i>,1]        -- factor-level <i> of factor <tag>
#   <continuous_term>       -- raw column name for continuous slopes
#   sigma_<group>           -- SD of random-effect group <group>
#   sigma_e_atg             -- residual SD on the gaussian path

.mapper_greta <- function(fit, fb_terms) {
  if (is.null(fit$greta) || is.null(fit$greta$draws))
    return(list(map = character(0), transform = list()))

  m <- as.matrix(fit$greta$draws)
  draw_names <- colnames(m) %||% character(0)
  if (length(draw_names) == 0L)
    return(list(map = character(0), transform = list()))

  fixed_terms  <- fb_terms$fixed_terms  %||% list()
  random_terms <- fb_terms$random_terms %||% list()

  # Build a lookup of canonical factor-level labels from the IR.
  # For each fixed term of type "factor" / "factor_interaction" we
  # know the levels in order; tau_<tag>[i,1] -> "<tag><lvl_i>".
  factor_lookup <- list()
  for (t in fixed_terms) {
    if (is.null(t$type)) next
    if (t$type %in% c("factor")) {
      tag <- t$var %||% t$label %||% NA_character_
      if (is.na(tag)) next
      lvls <- t$levels %||% NULL
      if (is.null(lvls)) next
      factor_lookup[[tag]] <- as.character(lvls)
    }
  }

  # Walk the draw names; map each to canonical where recognized.
  map <- character(0)
  for (nm in draw_names) {
    if (identical(nm, "mu_atg")) {
      map[nm] <- "(Intercept)"; next
    }
    if (identical(nm, "sigma_e_atg")) {
      map[nm] <- "sigma"; next
    }
    if (startsWith(nm, "sigma_")) {
      # sigma_<group> -- SD of random group; canonical = sd_<group>.
      grp <- sub("^sigma_", "", nm)
      if (nzchar(grp) && !identical(grp, "e_atg"))
        map[nm] <- paste0("sd_", grp)
      next
    }
    if (startsWith(nm, "beta_")) {
      # beta_<term> -- continuous-slope / interaction coefficient on
      # emit_greta.R's continuous-fixed-effect surface. Canonical =
      # bare term name (brms convention). The ADR 0005 mapping table
      # documented "b_<term>" -> "<term>" but the live emit prefix is
      # "beta_"; surfaced by fb_brms() test 13 on continuous slopes
      # (asreml entries are factor-heavy and miss this row).
      term <- sub("^beta_", "", nm)
      if (nzchar(term) &&
          any(vapply(fixed_terms, function(t)
            identical(t$label, term) || identical(t$var, term),
            logical(1)))) {
        map[nm] <- term
      }
      next
    }
    # tau_<tag>[i,1] -- factor-level coefficient.
    parsed <- .parse_tau_factor(nm)
    if (!is.null(parsed)) {
      tag <- parsed$tag
      lvls <- factor_lookup[[tag]]
      lvl <- if (!is.null(lvls) && parsed$level <= length(lvls))
        lvls[parsed$level] else as.character(parsed$level)
      map[nm] <- paste0(tag, lvl)
      next
    }
    # Continuous-slope column (raw term name in fixed_terms).
    if (nm %in% draw_names &&
        any(vapply(fixed_terms, function(t)
          identical(t$label, nm) || identical(t$var, nm),
          logical(1)))) {
      map[nm] <- nm
      next
    }
    # Unknown -- leave un-mapped; surfaces via $unmapped.
  }

  list(map = map, transform = list())
}


# ---------------------------------------------------------------- #
# v0.2 mapper: INLA backend                                         #
# ---------------------------------------------------------------- #
# INLA-side names exposed via fit$inla$summary.{fixed,hyperpar}:
#   summary.fixed rownames    -- already brms-canonical:
#       "(Intercept)", "<term>" (treatment-coded factor levels)
#   summary.hyperpar rownames:
#       "Precision for the Gaussian observations" -> "sigma" + sqrt(1/prec)
#       "Precision for <group>"                   -> "sd_<group>" + sqrt(1/prec)

.mapper_inla <- function(fit, fb_terms) {
  if (is.null(fit$inla))
    return(list(map = character(0), transform = list()))

  map       <- character(0)
  transform <- list()

  # Fixed effects -- identity mapping (already brms-canonical). The
  # summary.fixed table uses the bare name ("(Intercept)") while the
  # inla.posterior.sample() latent rows use the ":1"-suffixed form
  # ("(Intercept):1"). Register both so the rename fires regardless
  # of which entry point feeds the consumer.
  fixed_names <- rownames(fit$inla$summary.fixed) %||% character(0)
  for (nm in fixed_names) {
    map[nm]                  <- nm
    map[paste0(nm, ":1")]    <- nm
  }

  # Hyperparameters -- precision-side names; rename + sqrt(1/prec).
  # Hyperpar names do not carry the ":1" suffix.
  prec_to_sd <- function(prec) sqrt(1 / prec)
  hyper_names <- rownames(fit$inla$summary.hyperpar) %||% character(0)
  for (nm in hyper_names) {
    if (identical(nm, "Precision for the Gaussian observations")) {
      map[nm]              <- "sigma"
      transform[["sigma"]] <- prec_to_sd
      next
    }
    if (startsWith(nm, "Precision for ")) {
      grp <- sub("^Precision for ", "", nm)
      canon <- paste0("sd_", grp)
      map[nm]            <- canon
      transform[[canon]] <- prec_to_sd
      next
    }
    # Other hyperparameters (e.g., rho-for-ar1) left un-mapped for
    # v0.2; future ADR will register them when the structured-cov
    # work lands.
  }

  list(map = map, transform = transform)
}


# ---------------------------------------------------------------- #
# v0.2 mapper: brms-via-Stan backend (Stan passthrough)             #
# ---------------------------------------------------------------- #
# brms parameter names are the canonical names by definition (the
# brms convention IS the flexyBayes canonical convention -- see the
# ADR on canonical-name registry, mapping-rule row for brms). The
# mapper is identity over the draw-matrix column names with one
# prefix-strip rule:
#
#   b_<term>           -> <term>             (e.g. b_Days -> Days)
#   b_Intercept        -> "(Intercept)"
#   sd_<group>__Intercept -> sd_<group>      (drop the __Intercept tail)
#   sigma              -> sigma              (identity)
#
# Hyperparameters that brms exposes but flexyBayes does not yet
# canonicalise (e.g. `lp__` log-posterior, `Intercept` -- the
# scaled intercept brms emits alongside b_Intercept) are left
# un-mapped and surface via `$unmapped`.

.mapper_brms_via_stan <- function(fit, fb_terms) {
  if (is.null(fit$brms))
    return(list(map = character(0), transform = list()))

  if (!requireNamespace("posterior", quietly = TRUE))
    return(list(map = character(0), transform = list()))

  draw_names <- tryCatch(
    colnames(as.matrix(posterior::as_draws_matrix(fit$brms))),
    error = function(e) character(0)
  )
  if (length(draw_names) == 0L)
    return(list(map = character(0), transform = list()))

  map <- character(0)
  for (nm in draw_names) {
    if (identical(nm, "b_Intercept")) {
      map[nm] <- "(Intercept)"; next
    }
    if (startsWith(nm, "b_")) {
      bare <- sub("^b_", "", nm)
      map[nm] <- bare
      next
    }
    if (startsWith(nm, "sd_")) {
      bare <- sub("^sd_", "", nm)
      # brms emits sd_<g>__<x> for uncorrelated random slopes
      # ((x || g) / (1 + x || g)) and sd_<g>__Intercept for the
      # corresponding intercept-deviation. ADR 0020 §Decision 3:
      # canonical name is sd_<x>_<g> for slopes; sd_<g> for the
      # intercept. The __Intercept rule comes first because it is a
      # subset of the __<x> rule.
      if (grepl("__Intercept$", bare)) {
        bare <- sub("__Intercept$", "", bare)
        if (nzchar(bare))
          map[nm] <- paste0("sd_", bare)
        next
      }
      m <- regmatches(bare, regexec("^([^_]+(?:_[^_]+)*?)__(.+)$", bare))[[1]]
      if (length(m) == 3L && nzchar(m[2L]) && nzchar(m[3L])) {
        # bare matched <g>__<x>; canonicalise to sd_<x>_<g> per ADR 0020.
        g_part <- m[2L]
        x_part <- m[3L]
        map[nm] <- paste0("sd_", x_part, "_", g_part)
        next
      }
      if (nzchar(bare))
        map[nm] <- paste0("sd_", bare)
      next
    }
    if (identical(nm, "sigma")) {
      map[nm] <- "sigma"; next
    }
    # Other names (lp__, Intercept-centered, r_<group>[<lvl>,Intercept],
    # cor_<group>__*, etc.) left un-mapped for v0.2; surfaced via
    # $unmapped when drop = FALSE.
  }

  list(map = map, transform = list())
}


# ---------------------------------------------------------------- #
# Package-load registration                                         #
# ---------------------------------------------------------------- #
# Run at file-source time. R's package-build process sources the R/
# files in alphabetical order; canonical_names.R sources before
# triangulate.R (the consumer), so the registry is populated by the
# time triangulate() runs.

register_canonical_mapper("greta", .mapper_greta)
register_canonical_mapper("inla",  .mapper_inla)
register_canonical_mapper("brms",  .mapper_brms_via_stan)
# The gretaR mapper stub registers from R/gretaR_slot.R (sourced
# later in alphabetical order); kept with its definition for
# v0.3-activation diff cleanliness.
