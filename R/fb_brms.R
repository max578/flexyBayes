# fb_brms() -- brms-formula entry to flexyBayes.
#
# The second of the four v0.2 verbs alongside flexybayes() (asreml
# entry, principal) and fb_greta() (direct-greta entry, expert).
# Accepts the five-shape brms corpus: fixed-only Gaussian; fixed +
# one random intercept; fixed + crossed random intercepts; binomial
# random-intercept GLMM (Bernoulli on a single 0/1 response);
# Poisson random-intercept GLMM. Everything outside the corpus is
# refused at ingest with a structured message.
#
# Per ADR 0014 in design-notes-priors-brms-lgm.md. The verb is a
# thin wrapper over fb_from_brms() (parse) + .dispatch_backend()
# (the ADR 0006 dispatch helper shared with flexybayes()). Inherits
# ADR 0011 (review_code semantics), ADR 0006 (backend = "auto" +
# decision trace), and ADR 0005 (canonical-name registry --- the
# greta and INLA mappers cover fb_brms() fits without registration
# change, since dispatch routes through the same emitters).

#' Fit a brms-style formula via the flexyBayes dispatch
#'
#' Accept the five-shape brms-style corpus (fixed-only Gaussian;
#' fixed + one random intercept; fixed + crossed random intercepts;
#' binomial random-intercept GLMM as single-column Bernoulli;
#' Poisson random-intercept GLMM), dispatch through the shared
#' `lgm_gate()`-driven backend router, and return a classed result
#' compatible with [summary()], [coef()], [vcov()],
#' [prior_summary()], [backend_decision()], and [triangulate()].
#'
#' `fb_brms()` is the brms-grammar entry point on the four-verb API
#' spine. Use it when the model is expressed in lme4 / brms-style
#' formula notation (`response ~ fixed + (1 | group)`); use
#' [flexybayes()] for asreml-style formulas; use [fb_greta()] for
#' models already expressed in native greta primitives. The three
#' verbs are explicit alternatives, never silent fallbacks --- the
#' grammar choice is made at verb selection time, never inferred
#' from the formula shape.
#'
#' Outside the supported corpus, ingest refuses with a structured
#' message naming both the offending construct and the closest
#' supported alternative. The v0.2.6 corpus extends the v0.2.5
#' five shapes with uncorrelated random slopes per ADR 0020 --
#' `(x || g)` and `(1 + x || g)` now parse and emit on the greta
#' and brms backends. Refused constructs in v0.2.6: LHS addition
#' forms (`y | trials(n) ~ ...`, `y | cens(c) ~ ...`, etc.);
#' correlated random slopes (`(x | g)` -- raises condition class
#' `flexybayes_correlated_slope_unsupported` with a v0.3 deferral
#' pointer to Stage 5A structured-covariance representation per
#' ADR 0025); smoothers (`s()`, `t2()`); Gaussian processes
#' (`gp()`); autocorrelation (`ar()`, `ma()`, `arma()`, `cosy()`,
#' `car()`); multivariate / hurdle / mixture / categorical
#' families.
#'
#' @param formula A brms-style two-sided formula. Random intercepts
#'   are expressed via `(1 | group)` or `(1 || group)`; multiple
#'   crossed RIs are joined with `+`. Fixed effects accept the same
#'   shapes as the asreml entry (factor levels, continuous slopes,
#'   interactions, `I()` expressions).
#' @param data A data.frame containing every variable referenced in
#'   `formula`.
#' @param family Character family name (`"gaussian"`, `"binomial"`,
#'   `"poisson"`, `"negative_binomial"`, `"gamma"`, `"beta"`,
#'   `"lognormal"`) or a base-R `family()` object. Default
#'   `"gaussian"`.
#' @param link Character link override (e.g., `"probit"` for
#'   binomial) or `NULL` to use the family default.
#' @param backend One of `"greta"` (default; preserves the
#'   additive-default behaviour of the existing entry), `"inla"`
#'   (explicit LGM fast path; raises a structured refusal if the
#'   model is not LGM-feasible), `"brms"` (Stan passthrough --
#'   flexyBayes builds the IR, translates the prior, calls
#'   `brms::brm()`, wraps the result), or `"auto"` (gate-driven
#'   routing: INLA on accept, greta on refuse, with a silenceable
#'   note carrying the gate's primary failure rule). The Stan
#'   passthrough is opt-in only; `backend = "auto"` never routes
#'   to Stan because brms's first-call compile latency (typically
#'   30--60 seconds) is incompatible with the auto-dispatch
#'   transparent-fast-path promise. See [backend_decision()] for
#'   the recorded trace.
#' @param prior An optional `fb_prior()` object specifying priors
#'   via the PC-canonical hybrid DSL. When supplied it overrides
#'   the default bounded-uniform-on-SD prior; otherwise the v0.1
#'   family-aware default fires (Gelman 2006, *Bayesian Analysis*
#'   1(3):515-534 for the variance-component default; the
#'   weakly-informative fixed-effect default follows the same
#'   weakly-informative philosophy).
#' @param n_samples Integer: number of posterior samples per chain.
#' @param warmup Integer: number of warmup iterations per chain.
#' @param chains Integer: number of MCMC chains.
#' @param prior_fixed_sd Numeric SD for fixed-effect normal priors.
#'   Default `100`, a weakly-informative scale on the natural
#'   response scale following Gelman et al. (2008, *Annals of
#'   Applied Statistics* 2(4):1360-1383). Applied uniformly to
#'   intercept, contrast levels, continuous slopes, interactions,
#'   and `I()` expressions.
#' @param prior_vc_sd Numeric: hyperparameter for the legacy
#'   lognormal variance-component prior. The bounded-uniform
#'   default (Gelman 2006, *Bayesian Analysis* 1(3):515-534)
#'   fires when both `prior` and `prior_vc_sd` are at their
#'   defaults.
#' @param weights Optional numeric weights vector of length
#'   `nrow(data)`. Mapped to a single addition_term on the IR,
#'   mirroring the asreml entry.
#' @param known_matrices Named list of matrices referenced by the
#'   model (mirrors `flexybayes()` for downstream compatibility;
#'   the five-shape corpus does not consume them, but the slot is
#'   carried through to the IR for traceability).
#' @param verbose Logical: print generated greta code to console
#'   (greta path only).
#' @param mcmc_verbose Logical: show MCMC progress bar.
#' @param return_code Logical: if `TRUE`, return the generated
#'   greta code string without fitting.
#' @param review_code Logical: if `TRUE`, return a
#'   `<flexybayes_review>` deferred-execution object carrying the
#'   generated code, IR, resolved prior, captured call, and RNG
#'   snapshot. Run the deferred fit with [proceed()]. Mutually
#'   exclusive with `return_code`. Supported under
#'   `backend = "greta"` (greta code via the codegen path) and
#'   `backend = "brms"` (Stan code via `brms::make_stancode()`);
#'   the INLA-side `code` slot for the review token is deferred to
#'   a later release. Default `FALSE` preserves the run-immediately
#'   semantics. Session-level override via
#'   `options(flexyBayes.review_code_default = TRUE)`.
#'
#' @return Under default `return_code = FALSE` and `review_code =
#'   FALSE`: an object of class `"flexybayes"` (greta or auto-fell-
#'   back-to-greta), `"flexybayes_inla"` (INLA accepted), or
#'   `"flexybayes_brms"` (Stan passthrough -- carries the live
#'   `brmsfit` on the `$brms` slot for direct access to brms's
#'   posterior tooling: `loo()`, `posterior_predict()`,
#'   `bayes_factor()`). The verb origin is recorded on
#'   `fit$extras$fb_terms$source = "brms"` and the captured call
#'   on `fit$extras$call_info$call`. With `review_code = TRUE`: a
#'   `<flexybayes_review>` object carrying the generated code
#'   (greta source on the greta path; Stan source via
#'   `brms::make_stancode()` on the brms path); advance to the fit
#'   via [proceed()]. With `return_code = TRUE`: the generated
#'   code string only.
#'
#' @seealso [flexybayes()] (asreml-style principal entry);
#'   [fb_greta()] (direct-greta entry); [triangulate()];
#'   [backend_decision()]; [prior_summary()].
#'
#' @examples
#' \donttest{
#' if (requireNamespace("greta", quietly = TRUE) &&
#'     requireNamespace("lme4", quietly = TRUE)) {
#'   data(sleepstudy, package = "lme4")
#'   fit <- fb_brms(Reaction ~ Days + (1 | Subject),
#'                  data = sleepstudy,
#'                  n_samples = 200, warmup = 200, chains = 1,
#'                  verbose = FALSE, mcmc_verbose = FALSE)
#'   coef(fit)
#'   backend_decision(fit)
#' }
#' }
#'
#' @export
fb_brms <- function(formula,
                    data,
                    family         = "gaussian",
                    link           = NULL,
                    backend        = c("greta", "inla", "brms",
                                       "auto"),
                    prior          = NULL,
                    n_samples      = 1000L,
                    warmup         = 500L,
                    chains         = 4L,
                    prior_fixed_sd = 100,
                    prior_vc_sd    = 1,
                    weights        = NULL,
                    known_matrices = list(),
                    verbose        = TRUE,
                    mcmc_verbose   = TRUE,
                    return_code    = FALSE,
                    review_code    = FALSE,
                    aggregate      = "auto") {

  # ----- 0. Validate ------------------------------------------------
  backend   <- match.arg(backend)
  aggregate <- .normalise_aggregate(aggregate)

  if (missing(formula))
    stop("`formula` is required: a brms-style two-sided formula.",
         call. = FALSE)
  if (missing(data) || !is.data.frame(data))
    stop("`data` must be a data.frame.", call. = FALSE)

  # Resolve session-level review-mode default BEFORE the unsupported-
  # backend guard, otherwise options(flexyBayes.review_code_default =
  # TRUE) would slip past the refusal on backend = "inla" / "auto"
  # (audit P1.1, 2026-05-24). Argument at call time wins.
  if (missing(review_code))
    review_code <- isTRUE(getOption("flexyBayes.review_code_default",
                                    FALSE))

  if (isTRUE(review_code) && !backend %in% c("greta", "brms"))
    stop("`review_code = TRUE` is currently supported with ",
         "backend = \"greta\" (greta code via the codegen path) ",
         "or backend = \"brms\" (Stan code via ",
         "brms::make_stancode()). Under backend = \"", backend,
         "\" the inspect-then-fit token would need an INLA-side ",
         "code slot, deferred to a future release. Pass ",
         "backend = \"greta\" or backend = \"brms\", or drop ",
         "review_code.", call. = FALSE)

  if (isTRUE(review_code) && isTRUE(return_code))
    stop("`return_code` and `review_code` are mutually exclusive. ",
         "Use `review_code = TRUE` for inspect-then-fit (returns a ",
         "<flexybayes_review> object); use `return_code = TRUE` for ",
         "the code string only.", call. = FALSE)

  the_call  <- match.call()
  data_name <- deparse(substitute(data))

  default_prior_active <- is.null(prior) && missing(prior_vc_sd)

  # ----- 1. Build the IR via fb_from_brms() -------------------------
  fb <- fb_from_brms(
    formula        = formula,
    data           = data,
    family         = family,
    link           = link,
    prior          = prior,
    weights        = weights,
    prior_fixed_sd = prior_fixed_sd,
    prior_vc_sd    = prior_vc_sd
  )

  # Synthesise the fixed / random / rcov forms downstream emitters
  # use for $extras$call_info display. Same shape the asreml entry
  # would have produced for the same model: `response ~ fixed-RHS`
  # for `fixed`; `~ g1 + g2 + ...` for `random` (NULL when no RI);
  # `~ units` for `rcov`. Preserves the v0.1 call_info convention so
  # `print()` / `summary()` look identical regardless of entry verb.
  response <- fb$response
  fixed_rhs_terms <- vapply(fb$fixed_terms, function(t) {
    if (!is.null(t$label)) t$label
    else if (!is.null(t$var))   t$var
    else if (!is.null(t$expr))  deparse(t$expr)
    else NA_character_
  }, character(1))
  fixed_rhs_terms <- fixed_rhs_terms[!is.na(fixed_rhs_terms)]
  fixed_rhs <- if (length(fixed_rhs_terms))
    paste(fixed_rhs_terms, collapse = " + ") else "1"
  if (!isTRUE(fb$intercept))
    fixed_rhs <- paste0(fixed_rhs, " - 1")
  fixed_form <- stats::as.formula(
    paste0(response, " ~ ", fixed_rhs),
    env = environment(formula)
  )

  random_form <- if (length(fb$random_terms)) {
    grp_names <- vapply(fb$random_terms, function(t) {
      if (!is.null(t$var)) t$var else NA_character_
    }, character(1))
    grp_names <- grp_names[!is.na(grp_names)]
    if (length(grp_names))
      stats::as.formula(paste("~", paste(grp_names, collapse = " + ")),
                        env = environment(formula))
    else NULL
  } else NULL

  rcov_form <- stats::as.formula("~ units", env = environment(formula))

  # ----- 2. Default-uniform prior expansion (ADR 0004 + §1.4) -------
  if (default_prior_active) {
    # ADR 0020: simple_slope_uncor contributes BOTH the standard
    # intercept-variance group name (term$var = the grouping factor)
    # AND a slope-variance group name (paste0(slope_var, "_", var))
    # so the existing per-group uniform-on-SD machinery covers the
    # new slope hyperparameter uniformly.
    grp_names <- character(0)
    for (t in fb$random_terms) {
      if (is.null(t$var)) next
      if (t$type %in% c("simple", "ide", "id"))
        grp_names <- c(grp_names, t$var)
      if (identical(t$type, "simple_slope_uncor")) {
        if (isTRUE(t$with_intercept))
          grp_names <- c(grp_names, t$var)
        if (!is.null(t$slope_var) && nzchar(t$slope_var))
          grp_names <- c(grp_names,
                         paste0(t$slope_var, "_", t$var))
      }
    }
    grp_names <- unique(grp_names)
    # AMBITION_STAGE.md §1.4: vm() + ped() structured-cov groups
    # also receive the uniform-on-SD default (extends ADR 0004).
    vm_ped_names <- vapply(fb$random_terms,
      function(t) {
        if (!is.null(t$var) && t$type %in% c("vm", "ped"))
          t$var else NA_character_
      }, character(1))
    vm_ped_names <- vm_ped_names[!is.na(vm_ped_names)]
    unif_default <- .default_uniform_prior(
      data           = data,
      response       = response,
      family         = family,
      link           = link,
      random_groups  = grp_names,
      vm_ped_groups  = vm_ped_names
    )
    fb$priors <- unif_default
    prior     <- unif_default
    .default_prior_note_once(
      scale = attr(unif_default, "fb_prior_default_scale"),
      basis = attr(unif_default, "fb_prior_default_basis")
    )
  }

  # ----- 3. Review-mode branch (ADR 0011 contract) ------------------
  if (isTRUE(review_code)) {
    review_emit_backend <- if (backend == "brms") "brms" else "greta"

    if (review_emit_backend == "greta" &&
        !requireNamespace("greta", quietly = TRUE))
      stop("Package 'greta' is required to generate the review-code ",
           "string. Install with:\n",
           "  install.packages('greta'); greta::install_greta_deps()",
           call. = FALSE)
    if (review_emit_backend == "brms" &&
        !requireNamespace("brms", quietly = TRUE))
      stop("Package 'brms' is required to generate Stan review code. ",
           "Install with: install.packages('brms'). A working C++ ",
           "toolchain (rstan or cmdstanr) is required for the ",
           "downstream fit.", call. = FALSE)

    if (!exists(".Random.seed", envir = globalenv(),
                inherits = FALSE)) {
      stats::runif(1)
    }
    seed_snapshot <- get(".Random.seed", envir = globalenv(),
                         inherits = FALSE)

    # Defensive scrub of the deferred-fit call (mirrors flexybayes()
    # review path): materialise symbol-form args so proceed() does
    # not depend on caller-frame bindings still being live.
    the_call_proceed <- the_call
    the_call_proceed$data <- data
    if (!is.null(weights))      the_call_proceed$weights        <- weights
    if (length(known_matrices)) the_call_proceed$known_matrices <- known_matrices
    if (!is.null(prior))        the_call_proceed$prior          <- prior

    # Stage 2 MVP -- preflight upstream of the code emit; refusal
    # short-circuits before any backend touches data. NULL below
    # the 1e5-row threshold.
    review_preflight <- .maybe_preflight(fb = fb, data = data,
                                          the_call = the_call)

    review_code_str <- if (review_emit_backend == "brms") {
      emit_brms(
        fb             = fb,
        data           = data,
        known_matrices = known_matrices,
        weights        = weights,
        n_samples      = n_samples,
        warmup         = warmup,
        chains         = chains,
        prior_fixed_sd = prior_fixed_sd,
        prior_vc_sd    = prior_vc_sd,
        verbose        = FALSE,
        mcmc_verbose   = mcmc_verbose,
        return_code    = TRUE,
        the_call       = the_call,
        fixed          = fixed_form,
        random         = random_form,
        rcov           = rcov_form,
        family         = family,
        link           = link,
        data_name      = data_name
      )
    } else {
      emit_greta(
        fb             = fb,
        data           = data,
        known_matrices = known_matrices,
        weights        = weights,
        n_samples      = n_samples,
        warmup         = warmup,
        chains         = chains,
        prior_fixed_sd = prior_fixed_sd,
        prior_vc_sd    = prior_vc_sd,
        verbose        = FALSE,
        mcmc_verbose   = mcmc_verbose,
        return_code    = TRUE,
        the_call       = the_call,
        fixed          = fixed_form,
        random         = random_form,
        rcov           = rcov_form,
        family         = family,
        link           = link,
        data_name      = data_name
      )
    }

    return(.new_flexybayes_review(
      code         = review_code_str,
      backend      = if (review_emit_backend == "brms")
                       "stan_via_brms" else "greta",
      ir           = fb,
      prior        = prior,
      data_name    = data_name,
      call         = the_call,
      seed         = seed_snapshot,
      preflight    = review_preflight,
      proceed_args = list(
        fb             = fb,
        data           = data,
        known_matrices = known_matrices,
        weights        = weights,
        n_samples      = n_samples,
        warmup         = warmup,
        chains         = chains,
        prior_fixed_sd = prior_fixed_sd,
        prior_vc_sd    = prior_vc_sd,
        verbose        = FALSE,
        mcmc_verbose   = mcmc_verbose,
        return_code    = FALSE,
        the_call       = the_call_proceed,
        fixed          = fixed_form,
        random         = random_form,
        rcov           = rcov_form,
        family         = family,
        link           = link,
        data_name      = data_name
      )
    ))
  }

  # ----- 4. Dispatch via the ADR 0006 helper ------------------------
  .dispatch_backend(
    fb             = fb,
    data           = data,
    backend        = backend,
    known_matrices = known_matrices,
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
    fixed          = fixed_form,
    random         = random_form,
    rcov           = rcov_form,
    family         = family,
    link           = link,
    data_name      = data_name,
    aggregate      = aggregate
  )
}
