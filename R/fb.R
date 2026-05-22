# fb -- flexyBayes user-facing entry points and ingest dispatchers.
#
# - fb_from_asreml() (deliverable 0.B): asreml-format ingest path,
#   wraps the existing parse_formula.R helpers (.parse_fixed,
#   .parse_formula, .resolve_family) and emits an fb_terms object
#   (the intermediate representation, IR, introduced in phase 0.A;
#   see R/fb_terms.R).
# - fb() (ADR 0004 D1): literal alias for flexybayes(). The
#   brms-format ingest (former fb() body) is deferred to v0.2 under
#   the working name fb_brms().

# ---------------------------------------------------------------- #
# Asreml-format ingest -> fb_terms                                 #
# ---------------------------------------------------------------- #

# Construct an fb_terms object from asreml-format formula arguments.
#
# Argument names and defaults mirror flexybayes() one-for-one so the
# wrapper is a drop-in for the parsing portion of that function.
#
# @param fixed Two-sided formula: response ~ fixed_effects.
# @param random One-sided formula ~ random_terms (asreml syntax) or
#   NULL.
# @param rcov One-sided formula ~ residual_structure or NULL. NULL
#   defaults to list(list(type = "units")) -- iid residuals -- to
#   match flexybayes()'s behaviour.
# @param data data.frame containing all variables referenced.
# @param family character family name; resolved via .resolve_family
#   (gaussian, binomial, binary, poisson, negative_binomial,
#   negbinom, gamma, beta).
# @param link character or NULL: link override.
# @param weights optional numeric vector of length nrow(data). If
#   non-NULL, mapped to a single addition_term with type="weights".
# @param known_matrices named list of known matrices (e.g.
#   list(Gmat = G)). Names recorded in data_summary$known_matrices.
# @param prior an fb_prior object (deliverable 3) or NULL. NULL
#   falls back to legacy scalar priors prior_fixed_sd /
#   prior_vc_sd. Forward-compat hook -- fb_prior is wired in
#   deliverable 3.
# @param prior_fixed_sd numeric: SD for fixed-effect normal priors
#   (legacy).
# @param prior_vc_sd numeric: hyperparameter for lognormal variance-
#   component priors (legacy).
# @return an fb_terms object with source = "asreml".
fb_from_asreml <- function(fixed,
                           random         = NULL,
                           rcov           = NULL,
                           data,
                           family         = "gaussian",
                           link           = NULL,
                           weights        = NULL,
                           known_matrices = list(),
                           prior          = NULL,
                           prior_fixed_sd = 100,
                           prior_vc_sd    = 1) {

  # Delegate parsing to existing helpers verbatim -- no behaviour
  # change relative to flexybayes().
  fixed_info   <- .parse_fixed(fixed, data)
  random_terms <- if (!is.null(random))
    .parse_formula(random, data) else list()
  rcov_terms   <- if (!is.null(rcov))
    .parse_formula(rcov, data) else list(list(type = "units"))
  fam_link     <- .resolve_family(family, link)

  # weights -> addition_terms (per IR design sketch Sec.2)
  addition_terms <- if (!is.null(weights)) {
    if (!is.numeric(weights) || length(weights) != nrow(data))
      stop("`weights` must be a numeric vector of length nrow(data).",
           call. = FALSE)
    list(list(type = "weights", values = weights))
  } else {
    list()
  }

  # Priors: forward-compat -- accept an fb_prior object when supplied;
  # otherwise capture legacy scalar priors. Marked legacy = TRUE so
  # downstream code can detect and dispatch accordingly.
  priors <- if (!is.null(prior)) {
    prior
  } else {
    list(fixed_sd = prior_fixed_sd,
         vc_sd    = prior_vc_sd,
         legacy   = TRUE)
  }

  data_summary <- list(
    n              = nrow(data),
    known_matrices = names(known_matrices)
  )

  new_fb_terms(
    response       = fixed_info$response,
    family         = fam_link$family,
    link           = fam_link$link,
    intercept      = fixed_info$intercept,
    fixed_terms    = fixed_info$terms,
    random_terms   = random_terms,
    rcov_terms     = rcov_terms,
    addition_terms = addition_terms,
    priors         = priors,
    data_summary   = data_summary,
    capabilities   = character(),
    source         = "asreml"
  )
}

# Note: the `fb` alias for `flexybayes()` is defined at the bottom
# of R/flexybayes.R so that the alias target is in scope at source
# time (R sources files alphabetically; this file loads before
# flexybayes.R). See ADR 0004 in design-notes-priors-brms-lgm.md.
