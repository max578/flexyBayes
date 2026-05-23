# lgm_gate -- LGM (latent Gaussian model) feasibility filter (Q5).
#
# Deliverable 2. Structural-first hybrid filter per
# design-notes-priors-brms-lgm.md Sec.Q5. Operates on an fb_terms
# object (the IR -- intermediate representation) and decides whether
# the model is feasible for INLA (Integrated Nested Laplace
# Approximations) dispatch.
#
# v0.2.5 implements 9 of the 10 checks (the structural-first set):
# the original six (family, predictor, distributional, re_prior,
# latent_class, hyperparam_budget) plus three INLA-emit-support
# checks (fixed_term_type_inla, random_term_type_inla,
# rcov_term_type_inla) added under ADR 0017 to fold emit_inla()
# structural refusals into the gate. Check 10 -- the post-fit
# numerical-confirm gate -- is stubbed; it lands alongside
# emit_inla()'s numerical-confirm pass where it can inspect
# mode.status, mlik finiteness, hyperpar boundary proximity, and
# posterior skewness.
#
# Twin objectives: low false-negative rate (don't refuse INLA-
# feasible models) and zero silent failure (don't accept models
# where INLA gives a wrong answer). Non-silent by construction --
# every refusal carries the rule id that fired plus a one-line
# human gloss; overrides are two-key-armed.
#
# Internal in v0.1 -- called from flexybayes() / fb() / emit_inla()
# during dispatch. Power users can reach it via `flexyBayes:::`.
# print.lgm_refusal is exported so dispatch works in installed
# builds.

# ---------------------------------------------------------------- #
# Public-style entry                                               #
# ---------------------------------------------------------------- #

# Run the LGM-OK filter on an fb_terms object.
#
# Returns one of:
# - the input fb_terms with $capabilities augmented to include
#   "lgm_compatible" plus any soft-warning rule ids (when all
#   structural checks pass);
# - the input fb_terms with $capabilities augmented to include
#   "lgm_force_overridden" plus the bypassed rule ids (when force =
#   "inla" + acknowledge_silent_bias_risk = TRUE + non-empty reason);
# - an lgm_refusal object (when one or more structural checks fail
#   and the override path is not taken).
#
# Callers (emit_inla; flexybayes(... backend = "inla"); fb(... backend
# = "auto")) dispatch on the return value: fb_terms -> proceed;
# lgm_refusal -> stop() the user-facing call with the formatted
# refusal, or attempt re-route per backend = "auto" semantics.
#
# @param fb an fb_terms object.
# @param force NULL or "inla". When "inla" and the structural
#   checks failed, override the refusal (subject to the two-key
#   guard).
# @param acknowledge_silent_bias_risk logical(1). Must be TRUE for
#   override to take effect. Default FALSE -- refusals are non-silent
#   by construction.
# @param reason character(1) non-empty. Logged into capabilities so
#   downstream tooling can audit forced-INLA fits.
# @return fb_terms (pass / override) or lgm_refusal (default).
lgm_gate <- function(fb,
                     force                        = NULL,
                     acknowledge_silent_bias_risk = FALSE,
                     reason                       = NULL) {
  if (!is_fb_terms(fb))
    stop("`fb` must be an fb_terms object (see fb_from_asreml).",
         call. = FALSE)

  checks <- list(
    .lgm_check_family(fb),                       # check 1
    .lgm_check_predictor(fb),                    # check 2
    .lgm_check_distributional(fb),               # check 3
    .lgm_check_re_prior(fb),                     # check 4
    .lgm_check_latent_class(fb),                 # check 5
    .lgm_check_hyperparam_budget(fb),            # check 6
    .lgm_check_fixed_term_inla_support(fb),      # check 7 (ADR 0017)
    .lgm_check_random_term_inla_support(fb),     # check 8 (ADR 0017)
    .lgm_check_rcov_term_inla_support(fb),       # check 9 (ADR 0017)
    # check 10 (ADR 0019 §Decision 5) -- conditional INLA-mapping
    # verification for the factor_numeric_interaction term class.
    # Refuses the INLA emit path when verification has not been run
    # or did not pass on this host.
    .lgm_check_factor_numeric_interaction_inla_verified(fb)
    # post-fit numerical-confirm gate -- see emit_inla.
  )

  failures <- Filter(function(r) !isTRUE(r$pass), checks)
  warnings <- Filter(function(r) isTRUE(r$pass) && !is.null(r$warning),
                     checks)

  # All structural checks passed.
  if (length(failures) == 0L) {
    caps <- c(fb$capabilities, "lgm_compatible")
    for (w in warnings)
      caps <- c(caps, paste0("lgm_warning:", w$rule_id, ":", w$warning))
    # gretaR slot capability: informational at v0.2 (slot dormant);
    # at v0.3 the flag value flips to "gretaR_dispatch_eligible"
    # when the activation boolean + audit mechanism both agree.
    # Sole consumer at v0.2 is the gretaR_slot test suite + a future
    # v0.3 dispatch path; no v0.2 dispatch consults the flag.
    caps <- c(caps, .gretaR_slot_capability())
    fb$capabilities <- caps
    return(fb)
  }

  # Override path -- two-key armed; non-overridable check 7 (numerical)
  # is not yet implemented so all v0.1 failures are structural.
  if (identical(force, "inla") && isTRUE(acknowledge_silent_bias_risk)) {
    if (is.null(reason) || !is.character(reason) ||
        length(reason) != 1L || !nzchar(reason))
      stop("`reason` (non-empty character(1)) is required when forcing ",
           "INLA dispatch with acknowledge_silent_bias_risk = TRUE.",
           call. = FALSE)
    bypassed <- vapply(failures, function(f) f$rule_id, character(1))
    fb$capabilities <- c(
      fb$capabilities,
      "lgm_force_overridden",
      paste0("lgm_force_reason:",   reason),
      paste0("lgm_force_bypassed:", paste(bypassed, collapse = ","))
    )
    return(fb)
  }

  # Default -- return a structured refusal.
  new_lgm_refusal(failures, warnings, fb)
}

# ---------------------------------------------------------------- #
# Refusal class                                                    #
# ---------------------------------------------------------------- #

new_lgm_refusal <- function(failures, warnings = list(), fb = NULL) {
  obj <- list(
    failures     = failures,
    warnings     = warnings,
    n_failures   = length(failures),
    primary_rule = if (length(failures))
      failures[[1]]$rule_id else NA_character_,
    fb_source    = if (!is.null(fb)) fb$source    else NA_character_,
    fb_response  = if (!is.null(fb)) fb$response  else NA_character_
  )
  class(obj) <- c("lgm_refusal", "list")
  obj
}

is_lgm_refusal <- function(x) inherits(x, "lgm_refusal")

#' Print method for lgm_refusal -- LGM feasibility refusal
#'
#' Internal S3 method, registered for dispatch only. Emits the
#' structured refusal template: rule id + one-line gloss +
#' diagnostic + re-route hint + override hint + docs pointer.
#'
#' @param x   an `lgm_refusal` object.
#' @param ... unused.
#' @return invisibly returns `x`.
#' @keywords internal
#' @export
print.lgm_refusal <- function(x, ...) {
  cat("flexyBayes: INLA backend refused for this model.\n")
  cat("Reasons (", x$n_failures, " structural failure",
      if (x$n_failures != 1L) "s" else "", "):\n", sep = "")
  for (f in x$failures) {
    cat("  - [", f$rule_id, "] ", f$reason, "\n", sep = "")
    if (!is.null(f$diagnostic))
      cat("    Diagnostic: ", f$diagnostic, "\n", sep = "")
  }
  if (length(x$warnings)) {
    cat("Warnings:\n")
    for (w in x$warnings)
      cat("  - [", w$rule_id, "] ", w$warning, "\n", sep = "")
  }
  cat("Re-route: try backend = \"brms\" via fb_brms() for the Stan ",
      "passthrough\n  (model must be in the brms corpus), or ",
      "backend = \"greta\" for the broader\n  flexyBayes formula ",
      "path. NIMBLE is planned future work, not yet implemented.\n",
      sep = "")
  cat("For mixtures with <= 2 components, the planned ",
      "INLA-within-MCMC escape\n  (Gomez-Rubio & Rue 2018) is on ",
      "the roadmap.\n", sep = "")
  cat("Override (not recommended): lgm_gate(fb, force = \"inla\",\n")
  cat("  acknowledge_silent_bias_risk = TRUE, reason = \"<your ",
      "reason>\")\n", sep = "")
  cat("Docs: vignette(\"flexyBayes-11-lgm-feasibility\").\n")
  invisible(x)
}

# ---------------------------------------------------------------- #
# Check helpers -- internal                                         #
# ---------------------------------------------------------------- #
#
# Each check returns a list:
#   list(rule_id    = character(1),
#        pass       = logical(1),
#        reason     = character(1) or NULL,
#        diagnostic = character(1) or NULL,
#        warning    = character(1) or NULL)

.lgm_pass <- function(rule_id, warning = NULL) {
  list(rule_id = rule_id, pass = TRUE,
       reason = NULL, diagnostic = NULL, warning = warning)
}

.lgm_fail <- function(rule_id, reason, diagnostic = NULL) {
  list(rule_id = rule_id, pass = FALSE,
       reason = reason, diagnostic = diagnostic, warning = NULL)
}

# Check 1 -- Family allowlist
#
# family must be in INLA's likelihood roster. With INLA loaded we
# query inla.models()$likelihood; otherwise fall back to a static
# allowlist refreshed at v0.1 from INLA documentation.
.lgm_check_family <- function(fb) {
  fam_name <- if (inherits(fb$family, "family"))
    fb$family$family else as.character(fb$family)

  allowed <- .inla_likelihood_allowlist()
  if (tolower(fam_name) %in% tolower(allowed))
    return(.lgm_pass("family_allowlist"))

  .lgm_fail(
    "family_allowlist",
    paste0("family \"", fam_name, "\" is not in the INLA likelihood ",
           "allowlist (no built-in Laplace machinery)."),
    diagnostic = paste0("fb$family = \"", fam_name, "\"")
  )
}

.inla_likelihood_allowlist <- function() {
  # Prefer the live INLA roster when the package is installed
  # (Suggests + Additional_repositories declared in DESCRIPTION).
  # Fall back to the static list otherwise.
  if (requireNamespace("INLA", quietly = TRUE)) {
    dyn <- tryCatch(names(INLA::inla.models()$likelihood),
                    error = function(e) NULL)
    if (!is.null(dyn) && length(dyn)) return(dyn)
  }
  .inla_likelihood_allowlist_static()
}

# Static allowlist -- frozen at v0.1; refresh on each INLA major
# release if substantive changes are introduced. Covers the common
# agricultural / health / ecological likelihoods.
.inla_likelihood_allowlist_static <- function() {
  c(
    # Continuous
    "gaussian", "stdnormal", "lognormal", "logistic", "T",
    "exponential", "loggaussian", "loglogistic", "loggamma",
    "gamma", "beta",
    # Counts
    "poisson", "zeroinflatedpoisson0", "zeroinflatedpoisson1",
    "nbinomial", "nbinomial2",
    "zeroinflatednbinomial0", "zeroinflatednbinomial1",
    # Binary / binomial
    "binomial", "binary", "betabinomial", "cbinomial",
    "zeroinflatedbinomial0", "zeroinflatedbinomial1",
    # Survival
    "exponentialsurv", "weibullsurv", "loggaussiansurv",
    "lognormalsurv", "coxph",
    # Negative-binomial alias common in asreml workflows
    "negative_binomial", "negbinom"
  )
}

# Check 2 -- Predictor linearity
#
# asreml ingest is always linear (the asreml-format DSL has no
# non-linear syntax in v0.1). brms ingest (deliverable 1) sets a
# `nl = TRUE` flag or surfaces a non-linear term type -- refuse
# there.
.lgm_check_predictor <- function(fb) {
  has_nl <- any(vapply(fb$fixed_terms, function(t) {
    isTRUE(t$type == "non_linear") || isTRUE(t$nl)
  }, logical(1)))
  if (has_nl)
    return(.lgm_fail(
      "predictor_linearity",
      paste0("non-linear predictor detected (brms `nl = TRUE` or ",
             "equivalent). INLA stage-2 requires linearity in the ",
             "latent field."),
      diagnostic = "fixed_terms with type = \"non_linear\""
    ))
  .lgm_pass("predictor_linearity")
}

# Check 3 -- Distributional regression
#
# brms-style: refuse if any auxiliary parameter (sigma, phi, nu,
# zi, hu) has a non-trivial RHS. asreml v0.1 has none -- addition
# slot may carry weights but never dpar regressions.
.lgm_check_distributional <- function(fb) {
  dpar_terms <- Filter(function(t) {
    isTRUE(grepl("^dpar_", t$type)) && !isTRUE(t$is_intercept_only)
  }, fb$addition_terms)
  if (length(dpar_terms))
    return(.lgm_fail(
      "distributional_regression",
      paste0("auxiliary parameter has non-intercept RHS (",
             paste(vapply(dpar_terms, function(t) t$type, character(1)),
                   collapse = ", "),
             "). INLA requires scalar dpars."),
      diagnostic = "addition_terms with type matching ^dpar_"
    ))
  .lgm_pass("distributional_regression")
}

# Check 4 -- Random-effect prior is Gaussian / MVN / GMRF
#
# Legacy asreml priors (lognormal scalar wrapped via
# fb$priors$legacy = TRUE) map to Gaussian-equivalent on sigma and pass
# trivially. fb_prior() declarations (deliverable 3) will be
# inspected term-by-term; v0.1 placeholder accepts.
.lgm_check_re_prior <- function(fb) {
  if (isTRUE(fb$priors$legacy))
    return(.lgm_pass("re_gaussian_prior"))
  if (is.null(fb$priors))
    return(.lgm_pass("re_gaussian_prior"))

  # If priors is an fb_prior object (deliverable 3), look for
  # explicit non-Gaussian RE priors. Until that DSL ships, accept.
  bad <- character(0)
  if (inherits(fb$priors, "fb_prior") && !is.null(fb$priors$re)) {
    for (entry in fb$priors$re) {
      if (!is.null(entry$family) &&
          !tolower(entry$family) %in% c("normal", "gaussian", "mvn",
                                         "gmrf", "half_normal",
                                         "exponential"))
        bad <- c(bad, entry$family)
    }
  }
  if (length(bad))
    return(.lgm_fail(
      "re_gaussian_prior",
      paste0("non-Gaussian random-effect prior detected (",
             paste(unique(bad), collapse = ", "),
             "). INLA's latent field is Gaussian by construction."),
      diagnostic = "fb$priors$re entries with non-Gaussian family"
    ))
  .lgm_pass("re_gaussian_prior")
}

# Check 5 -- Latent-class detection
#
# Refuse models that introduce a discrete latent variable: finite
# mixtures, hidden Markov models, multistate transitions. Also
# catches family = "mixture(...)" from brms.
.lgm_check_latent_class <- function(fb) {
  bad_types <- c("mixture", "hmm", "multistate")
  found <- character(0)

  for (slot_name in c("fixed_terms", "random_terms", "rcov_terms")) {
    slot <- fb[[slot_name]]
    for (term in slot) {
      if (is.character(term$type) && term$type %in% bad_types)
        found <- c(found, term$type)
    }
  }
  fam_name <- if (inherits(fb$family, "family"))
    fb$family$family else as.character(fb$family)
  if (is.character(fam_name) &&
      grepl("^mixture", tolower(fam_name)))
    found <- c(found, paste0("family:", fam_name))

  if (length(found))
    return(.lgm_fail(
      "latent_class",
      paste0("latent-class structure detected (",
             paste(unique(found), collapse = ", "),
             "). INLA cannot represent finite mixtures or HMM ",
             "directly without the INLA-within-MCMC escape ",
             "(Gomez-Rubio & Rue 2018)."),
      diagnostic = "fb$family or fb$<slot>_terms"
    ))
  .lgm_pass("latent_class")
}

# Check 6 -- Hyperparameter budget
#
# Count hyperparameters: 1 likelihood (depending on family) + per
# random-effect contribution (1 for simple, 2 for fa, k+ for fa_gxe,
# n*(n+1)/2 for us_gxe, etc.) + per heterogeneous-rcov term. Refuse
# if total > 15 (CCD/grid intractable). Warn at >10 -- emit_inla
# (deliverable 5+) will set int.strategy = "ccd" automatically.
.lgm_check_hyperparam_budget <- function(fb,
                                          hard_limit = 15L,
                                          warn_limit = 10L) {
  n_hyp <- .lgm_count_hyperparams(fb)

  if (n_hyp > hard_limit)
    return(.lgm_fail(
      "hyperparam_budget",
      paste0("hyperparameter count = ", n_hyp,
             " exceeds hard limit ", hard_limit,
             " (CCD/grid integration intractable; INLA Laplace ",
             "approximation deteriorates)."),
      diagnostic = paste0("count = likelihood (",
                          .lgm_family_hypers(fb),
                          ") + random + rcov contributions")
    ))

  if (n_hyp > warn_limit)
    return(.lgm_pass(
      "hyperparam_budget",
      warning = paste0("hyperparameter count = ", n_hyp,
                       " exceeds soft limit ", warn_limit,
                       "; emit_inla will set int.strategy = \"ccd\".")
    ))

  .lgm_pass("hyperparam_budget")
}

# Likelihood-side hyperparameter count, by family.
.lgm_family_hypers <- function(fb) {
  fam_name <- if (inherits(fb$family, "family"))
    fb$family$family else as.character(fb$family)
  switch(tolower(as.character(fam_name)),
    "gaussian"          = 1L,
    "stdnormal"         = 0L,
    "binomial"          = 0L,
    "binary"            = 0L,
    "poisson"           = 0L,
    "negative_binomial" = 1L,
    "negbinom"          = 1L,
    "nbinomial"         = 1L,
    "gamma"             = 1L,
    "beta"              = 1L,
    "t"                 = 2L,
    "lognormal"         = 1L,
    "exponential"       = 0L,
    1L
  )
}

.lgm_count_hyperparams <- function(fb) {
  fam_hypers <- .lgm_family_hypers(fb)

  re_hypers <- 0L
  for (term in fb$random_terms) {
    contrib <- switch(term$type,
      "simple"      = 1L,
      "ide"         = 1L,
      "id"          = 1L,
      "vm"          = 1L,
      "ped"         = 1L,
      "fa"          = 2L,
      "fa_gxe"      = if (!is.null(term$k))
                        as.integer(2L * term$k) else 2L,
      "us_gxe"      = {
        n <- if (!is.null(term$n_outer)) term$n_outer else 4L
        as.integer(n * (n + 1L) / 2L)
      },
      "at_simple"   = if (!is.null(term$n_outer))
                        as.integer(term$n_outer) else 2L,
      "at_units"    = if (!is.null(term$n_var))
                        as.integer(term$n_var) else 2L,
      "ar1_spatial" = 3L,
      "spline"      = 1L,
      "polynomial"  = 1L,
      1L
    )
    re_hypers <- re_hypers + contrib
  }

  rcov_hypers <- 0L
  for (term in fb$rcov_terms) {
    if (term$type != "units")
      rcov_hypers <- rcov_hypers + 1L
  }

  fam_hypers + re_hypers + rcov_hypers
}

# ---------------------------------------------------------------- #
# Checks 7-9 -- INLA emit-support allowlists                       #
# ---------------------------------------------------------------- #
#
# Added under ADR 0017 ("Gate truth = emit truth"). Each check
# mirrors the corresponding switch() default in
# `.build_inla_formula()` (R/emit_inla.R) and refuses at the gate
# what emit_inla would refuse at emit time. After this ADR lands,
# `lgm_gate(fb) == accept` is a sufficient condition for
# `.build_inla_formula(gated)` to succeed structurally; the
# emit-side `stop()`s become internal contract-violation
# assertions.
#
# Allowlists are maintained as flat character vectors next to the
# checks so the gate's source-of-truth is co-located with the
# refusal text. Adding a new IR term type in the codegen layer
# requires updating both the emit switch() and the corresponding
# allowlist here.

# Allowlist: fixed-term types that emit_inla()'s fixed-effect
# switch() accepts. Anything else is refused at the gate with the
# offending type named. ADR 0019 (Stage 1A, v0.2.6) adds
# `factor_numeric_interaction` -- treatment-coded indexed slopes for
# factor x continuous interactions -- to the allowlist. INLA's
# native `f:x` notation handles this term shape directly for the
# gaussian-identity case; non-gaussian cases re-route to greta per
# the §3.4 INLA verification policy (see
# .lgm_check_factor_numeric_interaction_inla_verified() below).
.inla_fixed_term_type_allowlist <- function() {
  c("factor", "continuous", "interaction",
    "factor_interaction", "factor_numeric_interaction",
    "expression")
}

# Allowlist: random-term types that emit_inla()'s random-effect
# switch() accepts. The refused set (vm/ped/at/us/fa/ar1 +
# variants) maps to greta's broader formula path; the refusal
# text names the structured-covariance class.
.inla_random_term_type_allowlist <- function() {
  c("simple", "ide", "id", "spline")
}

# Allowlist: rcov-term types that emit_inla()'s rcov-term guard
# accepts. INLA folds residual variance into the likelihood and
# does not represent structured-rcov forms; those refit via greta.
.inla_rcov_term_type_allowlist <- function() {
  c("units")
}

# Human-readable label for a structured-covariance random-term
# type, used in the refusal diagnostic so the user sees the
# semantic class (e.g., "variance-matrix / GBLUP") not just the
# bare type string.
.inla_random_term_class_label <- function(term_type) {
  switch(term_type,
    "vm"           = "variance-matrix (e.g., GBLUP / kinship-driven random effect)",
    "ped"          = "pedigree-based (numerator relationship matrix)",
    "at"           = "heterogeneous variance by factor level",
    "at_simple"    = "heterogeneous variance by simple factor",
    "us"           = "unstructured covariance",
    "fa"           = "factor-analytic",
    "fa_gxe"       = "factor-analytic G\u00d7E",
    "us_gxe"       = "unstructured G\u00d7E",
    "ar1"          = "autoregressive lag-1",
    "ar1_spatial"  = "AR1 spatial",
    "polynomial"   = "polynomial random effect",
    paste0("random term type \"", term_type, "\"")
  )
}

# Human-readable label for a structured-rcov term type.
.inla_rcov_term_class_label <- function(term_type) {
  switch(term_type,
    "at_units"  = "heterogeneous residual by factor",
    "dsum"      = "diagonal heterogeneous residual",
    "ar1_units" = "AR1 residual",
    paste0("rcov term type \"", term_type, "\"")
  )
}

# Check 7 -- Fixed-term type allowlist for the INLA emit path.
#
# emit_inla()'s fixed-effect switch() recognises factor /
# continuous / interaction / factor_interaction / expression.
# Anything else falls through to a stop(); under ADR 0017 we
# catch that at the gate instead. In v0.2 the codegen does not
# produce out-of-allowlist fixed-term types; this check is
# defensive against codegen drift.
.lgm_check_fixed_term_inla_support <- function(fb) {
  allowed <- .inla_fixed_term_type_allowlist()
  bad <- character(0)
  for (term in fb$fixed_terms) {
    if (!is.character(term$type) || !(term$type %in% allowed))
      bad <- c(bad, as.character(term$type))
  }
  if (length(bad))
    return(.lgm_fail(
      "fixed_term_type_inla",
      paste0("fixed term type \"", bad[[1L]],
             "\" is outside the INLA emit allowlist. ",
             "Re-route via backend = \"greta\" (broader formula path) ",
             "or backend = \"brms\" (Stan passthrough)."),
      diagnostic = paste0("fb$fixed_terms type(s): ",
                           paste(unique(bad), collapse = ", "),
                           "; allowed: ",
                           paste(allowed, collapse = ", "))
    ))
  .lgm_pass("fixed_term_type_inla")
}

# Check 8 -- Random-term type allowlist for the INLA emit path.
#
# emit_inla()'s random-effect switch() recognises simple / ide /
# id (mapped to INLA "iid") and spline (mapped to INLA "rw2").
# Structured-covariance forms (vm / ped / at / us / fa / ar1 and
# variants) are not currently translatable to an INLA f() call
# without an SPDE / kronecker / spde2 expansion that the v0.2
# emit does not produce. These re-route to greta; the refusal
# names the structured-cov class.
.lgm_check_random_term_inla_support <- function(fb) {
  allowed <- .inla_random_term_type_allowlist()
  bad     <- character(0)
  labels  <- character(0)
  for (term in fb$random_terms) {
    if (!is.character(term$type) || !(term$type %in% allowed)) {
      bad    <- c(bad, as.character(term$type))
      labels <- c(labels, .inla_random_term_class_label(term$type))
    }
  }
  if (length(bad)) {
    first_type  <- bad[[1L]]
    first_label <- labels[[1L]]
    return(.lgm_fail(
      "random_term_type_inla",
      paste0("random term type \"", first_type,
             "\" (", first_label, ") is outside the INLA emit ",
             "allowlist. INLA's f() machinery does not currently ",
             "represent this structured-covariance class without ",
             "an SPDE / kronecker expansion that the v0.2 emit ",
             "does not produce. Re-route via backend = \"greta\"."),
      diagnostic = paste0("fb$random_terms type(s): ",
                           paste(unique(bad), collapse = ", "),
                           "; allowed: ",
                           paste(allowed, collapse = ", "))
    ))
  }
  .lgm_pass("random_term_type_inla")
}

# Check 9 -- Rcov-term type allowlist for the INLA emit path.
#
# INLA folds residual variance into the likelihood and does not
# expose a separate residual-structure surface. Only `units`
# (homogeneous residual) passes; everything else (at_units / dsum
# / ar1_units) refits via greta where the residual structure can
# be represented explicitly. Refusal names the structured-rcov
# case.
.lgm_check_rcov_term_inla_support <- function(fb) {
  allowed <- .inla_rcov_term_type_allowlist()
  bad     <- character(0)
  labels  <- character(0)
  for (term in fb$rcov_terms) {
    if (!is.character(term$type) || !(term$type %in% allowed)) {
      bad    <- c(bad, as.character(term$type))
      labels <- c(labels, .inla_rcov_term_class_label(term$type))
    }
  }
  if (length(bad)) {
    first_type  <- bad[[1L]]
    first_label <- labels[[1L]]
    return(.lgm_fail(
      "rcov_term_type_inla",
      paste0("rcov term type \"", first_type,
             "\" (", first_label, ") is outside the INLA emit ",
             "allowlist. INLA folds residual variance into the ",
             "likelihood; structured-rcov forms refit via ",
             "backend = \"greta\"."),
      diagnostic = paste0("fb$rcov_terms type(s): ",
                           paste(unique(bad), collapse = ", "),
                           "; allowed: ",
                           paste(allowed, collapse = ", "))
    ))
  }
  .lgm_pass("rcov_term_type_inla")
}

# Check 10 -- ADR 0019 §Decision 5 / merged-v2 §3.4 verification gate
# for the `factor_numeric_interaction` term class.
#
# The fixed-term allowlist (check 7) accepts the new term class
# structurally, but the INLA mapper for this class only ships if the
# three-arbitrator verification test (INLA vs greta vs lme4 on a
# gaussian-identity fixture) has passed on this host. The
# verification artefact lives at
# `inst/extdata/inla-verification/factor_numeric_interaction.rds`
# and carries `pass = TRUE` only after the verification test in
# `tests/testthat/test-factor-continuous-inla-verification.R` runs.
#
# If the IR contains no `factor_numeric_interaction` term, this
# check is a trivial pass -- the gate is term-class-specific.
.lgm_check_factor_numeric_interaction_inla_verified <- function(fb) {
  rule_id <- "factor_numeric_interaction_inla_verified"
  has_fni <- any(vapply(fb$fixed_terms, function(t)
    identical(t$type, "factor_numeric_interaction"),
    logical(1)))
  if (!has_fni) return(.lgm_pass(rule_id))

  # Probe the on-disk verification artefact. The artefact is written
  # by tests/testthat/test-factor-continuous-inla-verification.R after
  # a successful three-arbitrator run. Absence is treated identically
  # to a recorded failure -- the §3.4 policy forbids silent translation
  # of an unverified mapping.
  verified <- .factor_numeric_interaction_inla_verified()
  if (isTRUE(verified)) return(.lgm_pass(rule_id))

  .lgm_fail(
    rule_id,
    paste0("factor:continuous indexed interaction INLA mapping ",
           "deferred to v0.3 (no successful three-arbitrator ",
           "verification artefact on this host). Re-route via ",
           "backend = \"greta\" (treatment-coded indexed-slope emit ",
           "ships in v0.2.6) or backend = \"brms\" (Stan ",
           "passthrough)."),
    diagnostic = paste0(
      "verification artefact path: ",
      .factor_numeric_interaction_verification_path(),
      "; expected `pass = TRUE` on a stored ",
      "<flexybayes_inla_verification> record.")
  )
}

# Look up the on-disk INLA-verification artefact for the
# factor_numeric_interaction term class. Returns TRUE iff the
# artefact exists, is readable, and reports a passing verification
# run; FALSE in every other case (missing, unreadable, malformed,
# pass = FALSE).
.factor_numeric_interaction_inla_verified <- function() {
  path <- .factor_numeric_interaction_verification_path()
  if (!file.exists(path)) return(FALSE)
  rec <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(rec)) return(FALSE)
  isTRUE(rec$pass)
}

# Absolute path to the verification artefact. Lives in inst/extdata
# so it ships with the installed package (and is reachable via
# system.file() from the test harness). The directory is created on
# demand by the verification test; the directory may not exist on a
# fresh checkout, in which case .factor_numeric_interaction_inla_verified()
# returns FALSE as expected.
.factor_numeric_interaction_verification_path <- function() {
  base <- system.file("extdata", "inla-verification",
                       package = "flexyBayes",
                       mustWork = FALSE)
  if (!nzchar(base)) {
    base <- file.path(tempdir(), "flexyBayes-inla-verification")
  }
  file.path(base, "factor_numeric_interaction.rds")
}
