# fb_greta() -- direct-greta-model entry to flexyBayes.
#
# The third entry to the package, alongside `flexybayes()` (asreml-
# style, principal) and `fb_brms()` (brms-style, Ship-lane weeks
# 3--4). `fb_greta()` accepts a user-built `greta_model` directly and
# lowers it into the same `fb_terms` IR scaffold used by the formula
# entries, so the rest of the post-fit surface (summary, coef, vcov,
# prior_summary) works uniformly across the three entries.
#
# Per ADR 0012 in design-notes-priors-brms-lgm.md. Never a fallback
# path: `flexybayes()` does not silently switch into direct-greta
# mode under any condition (plan-final Sec.6 principle 9). Selected
# explicitly by name.

#' Fit a user-built greta model under the flexyBayes post-fit surface
#'
#' Lower a user-supplied `greta_model` into the same `fb_terms`
#' intermediate representation (IR) used by [flexybayes()] and the
#' brms entry, run MCMC via [greta::mcmc()], and return a classed
#' result that works with [summary()], [coef()], [vcov()],
#' [prior_summary()], and the wider flexyBayes diagnostic surface.
#'
#' `fb_greta()` is the expert / power-user entry. Use it when the
#' model is already expressed in native greta primitives
#' (`as_data()`, `normal()`, `uniform()`, `distribution()<-`,
#' `model()`) and you want the flexyBayes triangulation / prior
#' introspection / canonical-name surface without rewriting in
#' asreml or brms formula grammar. [flexybayes()] remains the
#' principal entry for asreml-style formulas; `fb_greta()` is an
#' explicit alternative, never a silent fallback.
#'
#' @param model A `greta_model` object built by [greta::model()].
#' @param data Optional data.frame the user's `as_data()` calls were
#'   issued against. Recorded on the IR for downstream methods
#'   (`predict()`, `posterior_samples()` with `newdata`,
#'   triangulation reporting). `NULL` accepted; downstream methods
#'   that need the original frame raise structured refusals.
#' @param known_matrices Named list of pre-computed matrices
#'   referenced by the model graph. Recorded on the IR for
#'   traceability. Empty list by default.
#' @param prior Optional `fb_prior()` object. When supplied, this is
#'   a *declaration* of the priors the model encodes (used by
#'   [prior_summary()] and [triangulate()] for cross-backend prior
#'   matching); `fb_greta()` does not modify the model's priors. A
#'   semantic mismatch between the declared prior and the model
#'   graph raises a structural refusal -- `fb_greta()` will not
#'   silently re-prior an already-built greta model.
#' @param n_samples Integer: number of posterior samples per chain.
#' @param warmup Integer: number of warmup (burn-in) iterations per
#'   chain.
#' @param chains Integer: number of MCMC chains.
#' @param canonical_names Optional named character vector mapping
#'   greta-side parameter names (the names of
#'   `model$target_greta_arrays`) to canonical names used by
#'   [triangulate()]. `NULL` falls back to the verbatim greta names
#'   with a one-time structured note (silenceable via
#'   `options(flexyBayes.silence_canonical_names_note = TRUE)`).
#' @param verbose Logical: print progress messages.
#' @param mcmc_verbose Logical: show MCMC progress bar from greta.
#' @param return_code Logical: deferred -- raises a structured
#'   refusal under the current contract (the user's model is already
#'   greta-side; there is no generated code to return). Reserved for
#'   a future v0.3 reconstruction surface.
#' @param review_code Logical: deferred -- raises a structured
#'   refusal under the current contract. The model-graph pretty-
#'   printer for the `<flexybayes_review>` `code` slot on the
#'   greta-direct entry is queued for a subsequent release (it
#'   requires a topological walk over `model$dag$node_list` with
#'   operation-node arithmetic). The formula-entry [flexybayes()] /
#'   [fb_brms()] paths still support `review_code = TRUE`, because
#'   `flexyBayes` is the code author on those paths.
#'
#' @return An object of class
#'   `c("flexybayes_direct_greta", "flexybayes", "list")` (subclass
#'   first so S3 dispatch finds the direct-greta overrides before
#'   the parent flexybayes methods). The `"flexybayes"` parent
#'   class makes the standard post-fit methods ([summary()],
#'   [vcov()], [confint()], [prior_summary()]) dispatch correctly;
#'   the `"flexybayes_direct_greta"` subclass routes three methods
#'   ([print()], [coef()], [predict()]) to greta-direct-aware
#'   overrides. Structure: `$glm` (minimal GLM-compatible shim built
#'   from posterior summary of target parameters), `$greta` (the
#'   real MCMC fit), `$extras` (diagnostics, code, call_info,
#'   model_info, canonical_map).
#'
#' @seealso [flexybayes()] (asreml-style principal entry);
#'   [prior_summary()]; [triangulate()].
#'
#' @examples
#' \donttest{
#' if (requireNamespace("greta", quietly = TRUE)) {
#'   data(sleepstudy, package = "lme4")
#'   library(greta)
#'   y     <- as_data(sleepstudy$Reaction)
#'   x     <- as_data(sleepstudy$Days)
#'   b0    <- normal(0, 100)
#'   b1    <- normal(0, 100)
#'   sigma <- uniform(0, 5 * sd(sleepstudy$Reaction))
#'   mu    <- b0 + b1 * x
#'   distribution(y) <- normal(mu, sigma)
#'   m <- model(b0, b1, sigma)
#'   fit <- fb_greta(m, data = sleepstudy,
#'                   canonical_names = c(b0 = "(Intercept)",
#'                                       b1 = "Days",
#'                                       sigma = "sigma"),
#'                   n_samples = 200, warmup = 200, chains = 1,
#'                   verbose = FALSE, mcmc_verbose = FALSE)
#'   coef(fit)
#' }
#' }
#'
#' @export
fb_greta <- function(model,
                     data            = NULL,
                     known_matrices  = list(),
                     prior           = NULL,
                     n_samples       = 1000L,
                     warmup          = 500L,
                     chains          = 4L,
                     canonical_names = NULL,
                     verbose         = TRUE,
                     mcmc_verbose    = TRUE,
                     return_code     = FALSE,
                     review_code     = FALSE) {

  # ADR 0031 Phase 3 (two-step-clean migration). fb_greta()'s native
  # greta_model fitting signature is deprecated at v0.4.1. At v0.5.0
  # fb_greta() becomes the greta engine pin (a formula verb, equivalent
  # to fb(backend = "greta")); native graphs are then fit through fb()
  # directly, and fb_from_greta() builds the IR from one. Warns now so
  # the meaning-change has a deprecation window. Deduped once per session
  # by id; the dedicated deprecation test forces it via
  # lifecycle_verbosity = "warning".
  lifecycle::deprecate_warn(
    when    = "0.4.1",
    what    = I("fb_greta(model = <greta_model>), the native-graph fitting signature"),
    details = c(
      i = "Build the flexyBayes IR from a native greta model with fb_from_greta().",
      i = paste0("At v0.5.0, fb_greta() becomes the greta engine pin and ",
                 "native greta_model graphs are fit through fb() directly.")),
    id      = "flexybayes_fb_greta_native_signature"
  )

  # ------- 0. Validation. ----------------------------------------- #

  if (!requireNamespace("greta", quietly = TRUE))
    stop("Package 'greta' is required by fb_greta(). Install with:\n",
         "  install.packages('greta')", call. = FALSE)

  if (!inherits(model, "greta_model"))
    stop("`model` must be a `greta_model` object built by ",
         "`greta::model(...)`. Got class: ",
         paste(class(model), collapse = "/"),
         ". For asreml-style formulas use flexybayes(); for ",
         "brms-style formulas use fb_brms() (v0.2 weeks 3--4).",
         call. = FALSE)

  # Mutual exclusion (mirrors ADR 0011 contract for the formula
  # entries; here both flags are deferred under the v0.2 contract).
  if (isTRUE(return_code) && isTRUE(review_code))
    stop("`return_code` and `review_code` are mutually exclusive. ",
         "On the fb_greta() path both flags are currently deferred; ",
         "see ?fb_greta.", call. = FALSE)

  if (isTRUE(return_code))
    stop("`return_code = TRUE` is deferred on fb_greta(): the user's ",
         "model is already greta-side, so there is no flexyBayes-",
         "generated code string to return. Reserved for a future ",
         "reconstruction surface.", call. = FALSE)

  if (isTRUE(review_code))
    stop("`review_code = TRUE` is deferred on fb_greta(): the model-",
         "graph pretty-printer for the `<flexybayes_review>` `code` ",
         "slot is queued for a subsequent release (it requires a ",
         "topological walk over `model$dag$node_list` with ",
         "operation-node arithmetic). The formula-entry flexybayes() ",
         "/ fb_brms() paths still support review_code.",
         call. = FALSE)

  # ------- 1. IR ingest via fb_from_greta(). ---------------------- #
  the_call <- match.call()

  fb <- fb_from_greta(
    model           = model,
    data            = data,
    prior           = prior,
    canonical_names = canonical_names,
    known_matrices  = known_matrices
  )

  # ------- 2. Direct greta::mcmc() call (no emit_greta lowering). - #
  run_time_start <- proc.time()[["elapsed"]]
  draws <- greta::mcmc(
    model    = model,
    n_samples = n_samples,
    warmup   = warmup,
    chains   = chains,
    verbose  = mcmc_verbose
  )
  run_time <- proc.time()[["elapsed"]] - run_time_start

  if (isTRUE(verbose))
    message("fb_greta(): fit complete in ", round(run_time, 1), " sec; ",
            chains, " chain(s) x ", n_samples, " samples; ",
            length(fb$greta_meta$arrays), " target parameter(s).")

  # ------- 3. Posterior summary on canonical-named axes. ---------- #

  all_draws <- do.call(rbind, lapply(draws, as.matrix))
  if (is.null(colnames(all_draws)))
    stop("greta MCMC returned draws without column names; ",
         "fb_greta() requires named target parameters.",
         call. = FALSE)

  # Rename draw columns to canonical where mapped (greta uses
  # canonical-array-name plus an element index for vector-valued
  # targets, e.g., `b[1,1]`). We only rename the scalar columns; the
  # element-suffixed columns retain the original greta name with the
  # canonical-prefix substitution. This keeps the canonical-name
  # registry compatible with both scalar and vector targets.
  greta_names <- names(fb$greta_meta$canonical_map)
  canon       <- unname(fb$greta_meta$canonical_map)
  for (i in seq_along(greta_names)) {
    if (identical(greta_names[i], canon[i])) next
    pat <- paste0("^", greta_names[i], "(\\[|$)")
    repl <- paste0(canon[i], "\\1")
    colnames(all_draws) <- sub(pat, repl, colnames(all_draws))
  }

  post_mean <- colMeans(all_draws)
  post_vcov <- if (ncol(all_draws) > 0L) cov(all_draws) else matrix(0, 0, 0)
  post_sd   <- sqrt(diag(post_vcov))
  post_q025 <- apply(all_draws, 2L, quantile, probs = 0.025, na.rm = TRUE)
  post_q975 <- apply(all_draws, 2L, quantile, probs = 0.975, na.rm = TRUE)

  # ------- 4. Convergence diagnostics. ---------------------------- #
  conv <- tryCatch({
    list(
      gelman = if (length(draws) >= 2L)
        coda::gelman.diag(draws, autoburnin = FALSE,
                          multivariate = FALSE) else NULL,
      n_eff  = tryCatch(coda::effectiveSize(draws),
                        error = function(e) NULL)
    )
  }, error = function(e) list(gelman = NULL, n_eff = NULL))

  # ------- 5. Minimal $glm shim. ---------------------------------- #
  # ADR 0012 Sec.5: a minimal GLM-shaped shim built from the posterior
  # summary so that emmeans / marginaleffects see *something*. The
  # shim carries posterior means under canonical names as
  # `coefficients`; the family is the inferred likelihood family.
  fam_obj <- tryCatch(
    eval(call(fb$family))(),
    error = function(e) gaussian()
  )
  glm_shim <- list(
    coefficients = post_mean,
    residuals    = numeric(0),
    fitted.values = numeric(0),
    rank         = length(post_mean),
    family       = fam_obj,
    linear.predictors = numeric(0),
    deviance     = NA_real_,
    aic          = NA_real_,
    null.deviance = NA_real_,
    iter         = NA_integer_,
    df.residual  = NA_integer_,
    df.null      = NA_integer_,
    converged    = TRUE,
    boundary     = FALSE,
    call         = the_call
  )
  attr(glm_shim, "posterior_vcov") <- post_vcov
  attr(glm_shim, "posterior_sd")   <- post_sd
  attr(glm_shim, "posterior_q025") <- post_q025
  attr(glm_shim, "posterior_q975") <- post_q975
  class(glm_shim) <- c("flexybayes_glm", "glm", "lm")

  # ------- 6. Assemble the classed result. ------------------------ #
  param_names <- colnames(all_draws)
  result <- list(
    glm    = glm_shim,
    greta  = list(
      model         = model,
      draws         = draws,
      greta_arrays  = fb$greta_meta$arrays,
      env           = new.env(parent = emptyenv())
    ),
    extras = list(
      summary       = data.frame(
        param = param_names,
        mean  = post_mean,
        sd    = post_sd,
        q025  = post_q025,
        q975  = post_q975,
        stringsAsFactors = FALSE,
        row.names = NULL
      ),
      convergence   = conv,
      variance_comps = NULL,
      blups         = NULL,
      predictions   = NULL,
      code          = NA_character_,  # no flexyBayes-generated code
      param_names   = param_names,
      parse_info    = list(source = "greta",
                          canonical_map = fb$greta_meta$canonical_map),
      call_info     = list(
        fixed    = quote(`<greta-direct entry>`),
        random   = NULL,
        rcov     = NULL,
        chains   = chains,
        n_samples = n_samples,
        warmup   = warmup,
        call     = the_call
      ),
      run_time      = run_time,
      model_info    = list(
        family   = fb$family,
        link     = "identity",
        n_params = length(post_mean),
        n_fixed  = length(post_mean),
        n_random = 0L,
        n_obs    = fb$greta_meta$n_data %||% NA_integer_,
        likelihood = fb$greta_meta$likelihood,
        canonical_map = fb$greta_meta$canonical_map
      ),
      fb_terms      = fb,
      backend_decision = list(
        backend     = "greta",
        path        = "direct_entry",
        gate_checks = NULL,
        reason      = paste0("fb_greta() bypasses lgm_gate(); ",
                             "user-built model accepted as-is.")
      )
    )
  )
  # S3 dispatch order: subclass first (most-specific), then parent.
  # ADR 0012 Sec.5 specified the reverse, but that breaks R's S3 dispatch
  # (the leftmost match wins): `print.flexybayes` would always shadow
  # `print.flexybayes_direct_greta`. The implementation uses the
  # R-correct order; ADR 0012 Sec.5 amended in the 2026-05-22 PROJECT_LOG
  # entry.
  class(result) <- c("flexybayes_direct_greta", "flexybayes", "list")
  result
}


# ---------------------------------------------------------------- #
# backend_decision() -- trivial-trace helper (ADR 0012 Sec.6)         #
# ---------------------------------------------------------------- #

#' Backend dispatch trace for a flexyBayes fit
#'
#' Returns the dispatch trace recorded at fit time: which backend
#' was selected, which gate checks ran, and why. On fb_greta() fits
#' the trace is trivial (the user bypassed the gate by entering on
#' the greta-direct path).
#'
#' @param fit A `flexybayes` object.
#' @return A list with the following components. The first four
#'   are present on every fit; the four routing-trace
#'   fields are present on v0.3.6+ fits and NULL
#'   on earlier fits for backward compatibility.
#'   \describe{
#'     \item{`backend`}{Character; one of `"greta"`, `"inla"`,
#'       `"brms"`, `"gretaR"`.}
#'     \item{`path`}{Character; the dispatch path token.}
#'     \item{`gate_checks`}{List or NULL; the `lgm_gate()` check
#'       trail (failures on refusal; capabilities on accept).}
#'     \item{`reason`}{Character; the dispatch-decision rationale.}
#'     \item{`preflight_summary`}{An `<fb_preflight>` object or
#'       NULL. Populated when `.fb_preflight()` ran (>1e5-row
#'       path); NULL on the small-data fast path.}
#'     \item{`representation_plan`}{Named list of slim per-term
#'       entries `(term_id, representation_class, justification)`
#'       derived from `preflight_summary`; NULL when no preflight.}
#'     \item{`rejected_routes`}{List of `(backend, reason)` pairs
#'       for the backends considered but not chosen. Empty for
#'       explicit user requests (the routing policy is bypassed
#'       when the backend is named directly).}
#'     \item{`routing_policy_version`}{Character; e.g.
#'       `"stage5a_v1"`. The audit-anchor for reproducibility -- a
#'       policy change bumps this string.}
#'   }
#' @export
backend_decision <- function(fit) {
  if (!inherits(fit, "flexybayes") && !inherits(fit, "flexybayes_inla"))
    stop("`fit` must be a `flexybayes` (or `flexybayes_inla`) object.",
         call. = FALSE)
  decision <- fit$extras$backend_decision
  if (is.null(decision))
    # Pre-ADR-0006 fit (no recorded decision): synthesise a minimal
    # legacy trace so downstream tooling never sees NULL.
    return(list(
      backend                = if (inherits(fit, "flexybayes_inla")) "inla" else "greta",
      path                   = "legacy_no_recorded_decision",
      gate_checks            = NULL,
      reason                 = paste0("fit predates dispatch-trace recording; ",
                                       "backend inferred from class."),
      preflight_summary      = NULL,
      representation_plan    = NULL,
      rejected_routes        = list(),
      routing_policy_version = NA_character_
    ))
  # Stage 4 (ADR 0024) v0.3.6+: surface the four new fields with
  # NULL defaults so pre-Stage-4 fits (those that recorded the
  # 4-field ADR-0006 trace before v0.3.6 landed) read out with the
  # same shape downstream tooling sees on v0.3.6+ fits. Construct
  # a fresh canonical 8-field list with explicit NULL values --
  # `decision[["x"]] <- NULL` removes the slot rather than setting
  # it to NULL, which would silently drop the field on every read.
  rejected <- decision$rejected_routes
  if (is.null(rejected)) rejected <- list()
  version <- decision$routing_policy_version
  if (is.null(version)) version <- NA_character_
  list(
    backend                = decision$backend,
    path                   = decision$path,
    gate_checks            = decision$gate_checks,
    reason                 = decision$reason,
    preflight_summary      = decision$preflight_summary,
    representation_plan    = decision$representation_plan,
    rejected_routes        = rejected,
    routing_policy_version = version
  )
}
