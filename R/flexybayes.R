#' Bayesian Mixed Models with ASReml Syntax
#'
#' Specify mixed models using ASReml formula syntax and estimate them via
#' Bayesian MCMC using greta. Returns a three-part result: a GLM-compatible
#' object for use with standard R packages (emmeans, marginaleffects, etc.),
#' native greta output for Bayesian diagnostics, and extras for secondary
#' analyses.
#'
#' @param fixed Two-sided formula: `response ~ fixed_effects`.
#' @param random One-sided formula: `~ random_terms` using ASReml syntax.
#'   Supports `vm()`, `at()`, `us()`, `fa()`, `ar1()`, `spl()`, `ped()`,
#'   `dsum()`, `id()`, and nested colon terms.
#' @param rcov One-sided formula: `~ residual_structure`. Default `~ units`
#'   (iid residuals). Use `~ at(env):units` for heterogeneous variance.
#' @param data A data.frame containing all variables referenced in the formulas.
#' @param family Character: `"gaussian"`, `"binomial"`, `"poisson"`,
#'   `"negative_binomial"`, `"gamma"`, or `"beta"`.
#' @param link Character or NULL: override the default link function
#'   (e.g., `"probit"` for binomial).
#' @param known_matrices Named list of matrices referred to in the random
#'   formula (e.g., `list(Gmat = G_mat, Amat = A_mat)`). As of v0.3.7,
#'   each matrix may be supplied either as a dense base-R `matrix`
#'   (passed via `vm(group, V = ...)` or `ped(group, A = ...)`, the
#'   legacy default), a user-supplied lower-triangular Cholesky
#'   factor (`vm(group, chol = L)`; greta backend only), or a sparse
#'   precision matrix `Matrix::dgCMatrix` (`vm(group, precision = Q)`
#'   or `ped(group, A_inv, use_sparse_precision = TRUE)`; greta and
#'   INLA backends). See the structured-covariance vignette for
#'   per-format worked examples.
#' @param weights Optional numeric weight vector (length N); sets
#'   Var = sigma^2 / w.
#' @param n_samples Integer: number of posterior samples per chain.
#' @param warmup Integer: number of warmup (burn-in) iterations per chain.
#' @param chains Integer: number of MCMC chains.
#' @param prior An optional `fb_prior()` object specifying priors via the
#'   PC-canonical hybrid DSL (preferred). When supplied it overrides
#'   `prior_vc_sd` for the variance components it covers. See
#'   [fb_prior()].
#' @param prior_fixed_sd Numeric: SD for fixed-effect normal priors,
#'   applied uniformly to the intercept, factor contrasts, continuous
#'   slopes, factor x continuous interactions, and `I()`-expression
#'   terms. Default `100` — weakly informative on the natural response
#'   scale for the vast majority of agricultural / clinical responses
#'   (covers responses with central tendency up to several hundred
#'   without crushing the posterior toward zero), while still
#'   regularising at sample sizes below ~ 30 per coefficient. Set
#'   wider (e.g. `1000`) for responses on a larger natural scale, or
#'   narrower for explicit shrinkage. Rationale follows Gelman (2006)
#'   *Bayesian Analysis* 1(3):515-534 on weakly-informative priors for
#'   regression coefficients on the data scale.
#' @param prior_vc_sd Numeric: hyperparameter for the legacy
#'   `lognormal(0, prior_vc_sd)` variance-component prior. **Note:**
#'   when both `prior` and `prior_vc_sd` are left at their defaults,
#'   v0.1 activates a bounded-uniform default on the SD scale
#'   (`uniform(0, U)` with family-aware `U`: `5 * sd(y)` for Gaussian;
#'   `5` on the logit scale for binomial / beta; `3` on the log scale
#'   for Poisson / negative-binomial / gamma) for `sigma` and every
#'   named random-effect group. Theory: Gelman (2006), *Bayesian
#'   Analysis* 1(3):515-534. The legacy `lognormal(0, 1)` default
#'   fires only when `prior_vc_sd` is passed explicitly. Silence the
#'   one-time announcement message via
#'   `options(flexyBayes.silence_default_prior_note = TRUE)`.
#' @param verbose Logical: print generated greta code to console.
#' @param mcmc_verbose Logical: show MCMC progress bar from greta.
#' @param return_code Logical: if TRUE, return the generated code string
#'   without fitting the model.
#' @param review_code Logical: if TRUE, do not fit the model immediately;
#'   instead return a `<flexybayes_review>` deferred-execution object
#'   carrying the generated backend code, the resolved prior, the
#'   parsed intermediate representation (IR), the captured call, and
#'   a snapshot of `.Random.seed`. Inspect the code with [cat_code()];
#'   run the deferred fit with [proceed()]; a second [proceed()] call
#'   returns the cached fit. Useful as a teaching / auditing surface
#'   before a long MCMC run. Default `FALSE` preserves the existing
#'   run-immediately semantics. A session-level override is available
#'   via `options(flexyBayes.review_code_default = TRUE)`; the
#'   argument value at call time always wins. Closest published
#'   precedent: [brms::make_stancode()] plus the `chains = 0` idiom
#'   for "do everything except sampling". `review_code = TRUE` and
#'   `return_code = TRUE` are mutually exclusive.
#' @param backend Character: one of `"greta"` (default; existing
#'   behaviour --- emit to greta and fit via MCMC), `"inla"`
#'   (explicit INLA; calls `lgm_gate()` and raises a structured
#'   refusal if the model is not LGM-feasible), or `"auto"` (calls
#'   `lgm_gate()` and routes to INLA on accept, greta on refuse).
#'   Under `"auto"`, falling back to greta emits a one-time
#'   silenceable note carrying the gate's primary failure rule;
#'   `options(flexyBayes.silence_auto_fallback_note = TRUE)`
#'   silences it. When INLA is not installed under `"auto"`, the
#'   call routes to greta with the note
#'   `auto_inla_unavailable` (silenceable via
#'   `options(flexyBayes.silence_auto_inla_missing_note = TRUE)`).
#'   [backend_decision()] surfaces the dispatch trace post-fit.
#'   `review_code = TRUE` is currently scoped to `backend = "greta"`
#'   only; combining with `backend = "inla"` / `"auto"` raises a
#'   structured refusal until INLA-side `code`-slot support lands.
#'
#' @param aggregate One of `"auto"` (default), `TRUE`, or `FALSE`.
#'   Aggregated-gaussian sufficient-statistics gate. `"auto"`
#'   consults the aggregation plan and routes through the per-cell
#'   emit path when the IR is in scope (gaussian-identity, fixed +
#'   random-intercept, productive compression) **on `backend = "inla"`**;
#'   on `backend = "greta"`, `"auto"` falls through to the per-row
#'   path even when the plan is eligible (`TRUE` is required to
#'   activate the greta aggregated emit explicitly). `TRUE` forces
#'   aggregation on either backend -- raises a structured refusal
#'   when the plan declares ineligibility. `FALSE` skips the gate
#'   entirely. Aggregated fits carry `$exactness == "aggregated_exact"`
#'   and the dispatch trace's `path` slot reads `"aggregated_gaussian"`.
#'   The asymmetry is documented behaviour rather than a bug: greta
#'   uses dense-matrix per-row emit by default for predictable RAM,
#'   and switching to the aggregated path silently would change the
#'   posterior numerical profile without an explicit opt-in.
#'
#' @return An object of class `"flexybayes"` — a list with three components:
#' \describe{
#'   \item{`$glm`}{A GLM-compatible object (class `c("flexybayes_glm", "glm",
#'     "lm")`) with posterior mean coefficients, vcov, residuals, fitted values,
#'     etc. Works with `summary()`, `emmeans()`, `marginaleffects()`,
#'     `effectsize()`.}
#'   \item{`$greta`}{Native greta output: `model`, `draws` (mcmc.list),
#'     `greta_arrays`, and `env`. Use with `bayesplot`, `greta::calculate()`,
#'     `posterior::as_draws()`.}
#'   \item{`$extras`}{Additional outputs: posterior `summary`, `convergence`
#'     diagnostics, `variance_comps`, `blups`, `predictions`, generated `code`,
#'     `param_names`, `parse_info`, `call_info`, `run_time`, `model_info`.}
#' }
#'
#' If `return_code = TRUE`, returns a character string of greta code instead.
#'
#' @examples
#' \donttest{
#' if (requireNamespace("greta", quietly = TRUE)) {
#'   data(met_example, package = "flexyBayes")
#'   # Simple random intercept model (small budget for example purposes)
#'   fit <- flexybayes(
#'     fixed  = yield ~ env,
#'     random = ~ geno,
#'     data   = met_example$dat,
#'     n_samples = 100, warmup = 100, chains = 1, verbose = FALSE
#'   )
#'   summary(fit)
#'   coef(fit)
#' }
#' }
#'
#' @importFrom stats terms model.frame model.matrix model.response
#'   formula family gaussian binomial poisson Gamma
#'   fitted residuals predict confint coef vcov logLik
#'   nobs update anova na.omit var cov quantile median
#'   qnorm pnorm dnorm setNames df.residual deviance
#'   .getXlevels dbinom density dpois lowess
#'   printCoefmat qqline qqnorm runif
#' @importFrom graphics abline axis hist legend lines par segments
#' @importFrom methods is
#' @importFrom coda effectiveSize gelman.diag
#' @importFrom splines bs
#' @export
flexybayes <- function(
    fixed,
    random           = NULL,
    rcov             = NULL,
    data,
    family           = "gaussian",
    link             = NULL,
    known_matrices   = list(),
    weights          = NULL,
    n_samples        = 1000,
    warmup           = 500,
    chains           = 4,
    prior            = NULL,
    prior_fixed_sd   = 100,
    prior_vc_sd      = 1,
    verbose          = TRUE,
    mcmc_verbose     = TRUE,
    return_code      = FALSE,
    review_code      = FALSE,
    backend          = c("greta", "inla", "auto"),
    aggregate        = "auto",
    plan             = FALSE
) {
  # Stage 4 (ADR 0024 §6(h)): refuse approximate-scheme requests
  # before match.arg fires its generic "should be one of" error.
  # The structured refusal points to ADR 0027 (the future
  # approximation registry) and the available exact-route
  # alternatives. Runs first so the user sees the architectural
  # rationale rather than match.arg's surface message.
  .check_approximate_scheme(backend)
  backend   <- match.arg(backend)
  aggregate <- .normalise_aggregate(aggregate)

  # Defer the greta package check to the emit-greta branch. For
  # backend = "inla" we don't need greta installed; for backend =
  # "auto" we only require greta if the gate refuses (or INLA is
  # unavailable) and we fall through to the greta emit.

  # Resolve session-level review-mode default BEFORE the unsupported-
  # backend guard, otherwise options(flexyBayes.review_code_default =
  # TRUE) would slip past the refusal on backend = "inla" / "auto"
  # (audit P1.1, 2026-05-24). Argument at call time wins.
  if (missing(review_code))
    review_code <- isTRUE(getOption("flexyBayes.review_code_default",
                                    FALSE))

  # review_code = TRUE is currently scoped to the greta-emit path
  # (ADR 0011). Under backend = "inla" / "auto" with INLA accepted,
  # review_code is deferred to a future ADR -- the deferred-execution
  # token would need an INLA-side `code` slot (the inla() formula +
  # family + hyper list) and a different proceed() target. Refuse
  # cleanly for now rather than silently emitting greta code for an
  # INLA fit.
  if (isTRUE(review_code) && backend != "greta")
    stop("`review_code = TRUE` is currently supported only with ",
         "backend = \"greta\". Under backend = \"", backend, "\" ",
         "the inspect-then-fit token would need an INLA-side code ",
         "slot, queued for a subsequent release. Pass ",
         "backend = \"greta\" or drop review_code.",
         call. = FALSE)

  if (isTRUE(review_code) && isTRUE(return_code))
    stop("`return_code` and `review_code` are mutually exclusive. ",
         "Use `review_code = TRUE` for inspect-then-fit (returns a ",
         "<flexybayes_review> object); use `return_code = TRUE` for ",
         "the code string only.", call. = FALSE)

  the_call  <- match.call()
  data_name <- deparse(substitute(data))

  # Detect "all defaults" -- user supplied neither an fb_prior() nor
  # an explicit prior_vc_sd. In that case the v0.1 default fires:
  # build a bounded-uniform default keyed to the response scale (per
  # family / link) for sigma + every random group surfaced by the IR,
  # and emit the one-time announcement message. ADR 0004 (uniform)
  # supersedes ADR 0003 (PC).
  default_prior_active <- is.null(prior) && missing(prior_vc_sd)

  # Build the flexyBayes intermediate representation (IR) via the
  # asreml-format ingest path. See R/fb.R.
  fb <- fb_from_asreml(
    fixed          = fixed,
    random         = random,
    rcov           = rcov,
    data           = data,
    family         = family,
    link           = link,
    weights        = weights,
    known_matrices = known_matrices,
    prior          = prior,
    prior_fixed_sd = prior_fixed_sd,
    prior_vc_sd    = prior_vc_sd
  )

  if (default_prior_active) {
    # ADR 0020: simple_slope_uncor contributes BOTH the standard
    # intercept-variance group name AND a slope-variance group name
    # (paste0(slope_var, "_", grouping_factor)) so the existing
    # per-group uniform-on-SD machinery covers both hyperparameters.
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
      response       = fb$response,
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

  # plan = TRUE: short-circuit after IR build (ADR 0030 C1). The plan
  # surface lives in fb_plan(); flexybayes(plan = TRUE) is the
  # courtesy alternative invocation that lets asreml-style callers
  # reach the same planning object without re-typing the formula in
  # brms shape.
  if (isTRUE(plan))
    return(.fb_plan_from_ir(
      fb                = fb,
      data              = data,
      backend           = backend,
      known_matrices    = known_matrices,
      aggregate         = aggregate,
      memory_ceiling_gb = NULL,
      predict_plan      = NULL,
      the_call          = the_call,
      data_name         = data_name
    ))

  # Review-mode branch. Build the deferred-execution token instead
  # of firing the backend. Code generation does not consume RNG; the
  # .Random.seed snapshot is captured before any RNG-touching step so
  # that proceed(rev) reproduces the chain a direct call would have
  # produced at the same outer seed. verbose printing is suppressed
  # because the review object owns the code surface (cat_code(rev)).
  if (isTRUE(review_code)) {
    if (!requireNamespace("greta", quietly = TRUE))
      stop("Package 'greta' is required to generate the review-code ",
           "string. Install with:\n",
           "  install.packages('greta'); greta::install_greta_deps()",
           call. = FALSE)
    if (!exists(".Random.seed", envir = globalenv(),
                inherits = FALSE)) {
      runif(1)  # initialise RNG so the snapshot is reproducible
    }
    seed_snapshot <- get(".Random.seed", envir = globalenv(),
                         inherits = FALSE)

    # Build a `the_call` for the deferred fit that does not reach
    # back into the caller's frame for symbol resolution. `match.call()`
    # captured `data = <symbol>` (and similarly for any other
    # non-literal argument such as `weights`, `known_matrices`,
    # `prior`); when proceed(rev) fires later, those caller-frame
    # bindings may have gone out of scope. R's standard fit-object
    # pipeline (model.frame / terms / class dispatch on the glm
    # surface inside .build_glm) lazily evaluates the stored call in
    # certain paths, which raises "object '<symbol>' not found" if
    # the binding is gone. Replace the symbol slots with their
    # current values so the proceed-side call is self-contained.
    # The user-side captured call (stored on the review object as
    # `$call`) keeps the original symbol form for diagnostic clarity.
    the_call_proceed <- the_call
    the_call_proceed$data <- data
    if (!is.null(weights))        the_call_proceed$weights        <- weights
    if (length(known_matrices))   the_call_proceed$known_matrices <- known_matrices
    if (!is.null(prior))          the_call_proceed$prior          <- prior

    # Stage 2 MVP -- run preflight upstream of the code emit so the
    # review token carries the design-memory summary and a refusal
    # short-circuits before any code generation happens. Below the
    # 1e5-row threshold .maybe_preflight() returns NULL and the
    # review object's $preflight slot stays NULL (v0.2 behaviour).
    review_preflight <- .maybe_preflight(fb = fb, data = data,
                                          the_call = the_call)

    review_code_str <- emit_greta(
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
      fixed          = fixed,
      random         = random,
      rcov           = rcov,
      family         = family,
      link           = link,
      data_name      = data_name
    )

    return(.new_flexybayes_review(
      code         = review_code_str,
      backend      = "greta",
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
        fixed          = fixed,
        random         = random,
        rcov           = rcov,
        family         = family,
        link           = link,
        data_name      = data_name
      )
    ))
  }

  # Backend dispatch lives in R/dispatch.R as the shared helper
  # `.dispatch_backend()` (lifted per ADR 0014 so fb_brms() drives
  # the same routing). Semantics per ADR 0006: backend = "greta"
  # skips the gate; backend = "inla" calls lgm_gate() and raises
  # the refusal on non-LGM; backend = "auto" gate-then-route with
  # silenceable fall-back notes.
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
    fixed          = fixed,
    random         = random,
    rcov           = rcov,
    family         = family,
    link           = link,
    data_name      = data_name,
    aggregate      = aggregate
  )
}


# ----------------------------------------------------------------- #
# fb -- alias for flexybayes() (ADR 0004 D1)                        #
# ----------------------------------------------------------------- #
#
# `fb` is a literal alias for `flexybayes()`. One canonical
# asreml-format implementation; two exported names for typing
# economy. The brms-format ingest path (former fb() body) is
# deferred to v0.2 as `fb_brms()`; the internal helper
# `fb_from_brms()` in R/fb_from_brms.R remains unexported as v0.2
# work-continuity code.
#
# Rationale: ADR 0004 in design-notes-priors-brms-lgm.md.

#' @rdname flexybayes
#' @export
fb <- flexybayes
