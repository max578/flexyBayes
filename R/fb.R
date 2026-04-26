# fb -- flexyBayes user-facing entry points and ingest dispatchers.
#
# - fb_from_asreml() (deliverable 0.B): asreml-format ingest path,
#   wraps the existing parse_formula.R helpers (.parse_fixed,
#   .parse_formula, .resolve_family) and emits an fb_terms object
#   (the intermediate representation, IR, introduced in phase 0.A;
#   see R/fb_terms.R).
# - fb() (deliverable 1): brms-format public entry. Calls
#   fb_from_brms() to build the IR (see R/fb_from_brms.R), runs
#   lgm_gate() to assess INLA feasibility (see R/lgm_gate.R), and
#   dispatches to the requested backend.
#
# v0.1 backend support inside fb(): "greta" (always available);
# "auto" (greta-only fallback in v0.1; will prefer INLA when
# emit_inla lands in deliverable 5+); "inla" and "brms" both error
# politely as not-yet-implemented.

# ---------------------------------------------------------------- #
# Asreml-format ingest -> fb_terms                                 #
# ---------------------------------------------------------------- #

# Construct an fb_terms object from asreml-format formula arguments.
#
# Argument names and defaults mirror bayesreml() one-for-one so the
# wrapper is a drop-in for the parsing portion of that function.
#
# @param fixed Two-sided formula: response ~ fixed_effects.
# @param random One-sided formula ~ random_terms (asreml syntax) or
#   NULL.
# @param rcov One-sided formula ~ residual_structure or NULL. NULL
#   defaults to list(list(type = "units")) -- iid residuals -- to
#   match bayesreml()'s behaviour.
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
                           prior_fixed_sd = 10,
                           prior_vc_sd    = 1) {

  # Delegate parsing to existing helpers verbatim -- no behaviour
  # change relative to bayesreml().
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

# ---------------------------------------------------------------- #
# fb() -- brms-format public entry (deliverable 1)                  #
# ---------------------------------------------------------------- #

#' Flexible Bayesian fit -- brms-formula entry
#'
#' Public entry point for the brms-format ingest path. Accepts a
#' brms-style formula (e.g., `y ~ x + (1 | g)`), parses to the
#' flexyBayes intermediate representation (IR; an `fb_terms`
#' object), runs `lgm_gate()` to assess INLA (Integrated Nested
#' Laplace Approximations) feasibility, and dispatches to the
#' requested backend.
#'
#' v0.1 backend support:
#'
#' - `"greta"`: existing greta backend (always available).
#' - `"auto"`: prefers INLA when LGM (latent Gaussian model)
#'   feasible, else greta. v0.1 falls back to greta in all cases --
#'   `emit_inla()` and `emit_brms()` land in deliverable 5+ -- and
#'   surfaces the chosen path via a `message()`.
#' - `"inla"`: not yet implemented; errors politely.
#' - `"brms"`: not yet implemented; errors politely.
#'
#' @param formula a brms-style formula (e.g., `y ~ x + (1 | g)`),
#'   or a `brmsformula` object built via `brms::bf()`.
#' @param data a data.frame containing all referenced variables.
#' @param family character family name or a `family()` object.
#' @param prior an `fb_prior` object (deliverable 3) or NULL --
#'   NULL invokes legacy scalar priors.
#' @param backend one of `"auto"`, `"greta"`, `"brms"`, `"inla"`.
#' @param weights optional numeric weights vector of length
#'   `nrow(data)`.
#' @param n_samples integer: posterior samples per chain.
#' @param warmup integer: warmup iterations per chain.
#' @param chains integer: number of MCMC chains.
#' @param prior_fixed_sd numeric: SD for fixed-effect normal priors
#'   (legacy).
#' @param prior_vc_sd numeric: hyperparameter for lognormal
#'   variance-component priors (legacy).
#' @param verbose logical: print generated greta code.
#' @param mcmc_verbose logical: show MCMC progress bar.
#' @param return_code logical: if TRUE, return the generated code
#'   string without fitting.
#' @return a `bayesreml`-class object (same shape as `bayesreml()`)
#'   if dispatch succeeds; an error if the requested backend is not
#'   yet implemented or the model is non-LGM under
#'   `backend = "inla"`.
#' @examples
#' \donttest{
#' if (requireNamespace("greta", quietly = TRUE)) {
#'   set.seed(1)
#'   d <- data.frame(y = rnorm(40), x = rnorm(40),
#'                   g = factor(rep(1:5, 8)))
#'   fit <- fb(y ~ x + (1 | g), data = d, backend = "greta",
#'             n_samples = 100, warmup = 100, chains = 1,
#'             verbose = FALSE)
#'   summary(fit)
#' }
#' }
#' @importFrom stats as.formula
#' @export
fb <- function(formula,
               data,
               family         = "gaussian",
               prior          = NULL,
               backend        = c("auto", "greta", "brms", "inla"),
               weights        = NULL,
               n_samples      = 1000,
               warmup         = 500,
               chains         = 4,
               prior_fixed_sd = 10,
               prior_vc_sd    = 1,
               verbose        = TRUE,
               mcmc_verbose   = TRUE,
               return_code    = FALSE) {

  backend <- match.arg(backend)

  if (!requireNamespace("greta", quietly = TRUE))
    stop("Package 'greta' is required. Install with:\n",
         "  install.packages('greta')\n",
         "  greta::install_greta_deps()", call. = FALSE)

  the_call  <- match.call()
  data_name <- deparse(substitute(data))

  # Detect "all defaults" -- v0.1.x activates a PC default for
  # variance components when neither `prior` nor `prior_vc_sd` is
  # supplied explicitly. See ?fb and NEWS.md.
  default_prior_active <- is.null(prior) && missing(prior_vc_sd)

  # 1. Build IR via the brms-format ingest path.
  fb_obj <- fb_from_brms(
    formula = formula,
    data    = data,
    family  = family,
    prior   = prior,
    weights = weights
  )

  # If the default fired, replace the legacy scalar priors slot with
  # the PC default fb_prior() built from the IR's random groups and
  # the response scale, and emit the one-time deprecation note.
  if (default_prior_active) {
    grp_names <- vapply(fb_obj$random_terms,
      function(t) {
        if (!is.null(t$var) && t$type %in% c("simple", "ide", "id"))
          t$var else NA_character_
      }, character(1))
    grp_names <- grp_names[!is.na(grp_names)]
    pc_default <- .default_pc_prior(
      data          = data,
      response      = fb_obj$response,
      family        = family,
      link          = NULL,
      random_groups = grp_names,
      alpha         = 0.05
    )
    fb_obj$priors <- pc_default
    prior         <- pc_default
    .default_prior_note_once(
      scale = attr(pc_default, "fb_prior_default_scale"),
      basis = attr(pc_default, "fb_prior_default_basis")
    )
  }

  # 2. Run LGM-OK filter (deliverable 2).
  gate_result <- lgm_gate(fb_obj)
  is_refusal  <- is_lgm_refusal(gate_result)

  # 3. Choose the effective backend.
  effective_backend <- backend
  if (backend == "auto") {
    if (is_refusal) {
      message("flexyBayes: LGM-infeasible model (",
              gate_result$primary_rule,
              "); falling back to greta backend.")
    } else {
      message("flexyBayes: LGM-feasible model -- v0.1 dispatches to ",
              "greta (emit_inla and emit_brms land in deliverable ",
              "5+).")
    }
    effective_backend <- "greta"
  }

  # 4. Dispatch.
  if (effective_backend == "greta") {
    fb_for_emit <- if (is_refusal) fb_obj else gate_result
    return(emit_greta(
      fb             = fb_for_emit,
      data           = data,
      known_matrices = list(),
      weights        = weights,
      n_samples      = n_samples,
      warmup         = warmup,
      chains         = chains,
      prior_fixed_sd = prior_fixed_sd,
      prior_vc_sd    = prior_vc_sd,
      verbose        = verbose,
      mcmc_verbose   = mcmc_verbose,
      return_code    = return_code,
      the_call       = the_call,
      fixed          = formula,
      random         = NULL,
      rcov           = NULL,
      family         = family,
      link           = NULL,
      data_name      = data_name
    ))
  }

  if (effective_backend == "inla") {
    if (is_refusal) stop(gate_result, call. = FALSE)
    return(emit_inla(
      fb        = gate_result,
      data      = data,
      verbose   = verbose,
      return_code = return_code,
      the_call  = the_call,
      fixed     = formula,
      random    = NULL,
      rcov      = NULL,
      family    = family,
      link      = NULL,
      data_name = data_name
    ))
  }

  if (effective_backend == "brms")
    stop("Backend \"brms\" passthrough is not yet implemented. ",
         "emit_brms() lands in deliverable 5+. ",
         "Use brms::brm() directly for now.", call. = FALSE)

  stop("Unsupported backend: ", effective_backend, call. = FALSE)
}
