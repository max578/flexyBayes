# .dispatch_backend() -- shared ADR 0006 dispatch helper.
#
# Lifted from R/flexybayes.R lines 330--518 (pre-ADR-0014) so that
# both flexybayes() (asreml entry) and fb_brms() (brms entry) drive
# the same backend dispatch. Byte-equivalent under snapshot guard
# (test-emit-greta.md + test-backend-auto.R).
#
# Routes to emit_inla() or emit_greta() per backend = c("greta",
# "inla", "auto"), populates fit$extras$backend_decision with the
# uniform-shape trace, and attaches the fb_terms IR for downstream
# canonical_names() resolution. Per ADR 0006 (decision trace) and
# ADR 0014 (shared helper extraction).
#
# Internal -- not exported.

.dispatch_backend <- function(fb,
                              data,
                              backend,
                              known_matrices,
                              weights,
                              n_samples,
                              warmup,
                              chains,
                              prior_fixed_sd,
                              prior_vc_sd,
                              verbose,
                              mcmc_verbose,
                              return_code,
                              the_call,
                              fixed,
                              random,
                              rcov,
                              family,
                              link,
                              data_name,
                              aggregate = "auto") {

  aggregate <- .normalise_aggregate(aggregate)

  # gretaR slot: dormant in v0.2. The branch is unreachable from
  # user-facing entries (their match.arg excludes "gretaR") but
  # reachable from internal callers + the test suite. v0.3
  # activation replaces the refusal with the real emit_gretaR()
  # call; the branch structure stays.
  if (identical(backend, "gretaR")) {
    .gretaR_dormant_refusal(call = the_call)
  }

  # Stage 2 MVP design-memory preflight (ADR 0021). Runs only above
  # the 1e5-row threshold so the v0.2 user surface is unchanged at
  # small scales -- the existing test suite never trips this branch.
  # Above the threshold, .fb_preflight() reads only fb_dataset
  # metadata (n_rows, dictionaries, col_types) and refuses upstream
  # with a structured error if any term's design-memory estimate
  # exceeds the active ceiling. The refusal short-circuits dispatch
  # before any backend code runs.
  .maybe_preflight(fb = fb, data = data, the_call = the_call)

  # Stage 3A aggregated-gaussian gate (ADR 0022). Consumes the
  # `<fb_aggregation_plan>` if the user opted in (aggregate = "auto"
  # silently routes when the plan declares eligibility; aggregate =
  # TRUE refuses with the plan's reason_codes when ineligible;
  # aggregate = FALSE skips this gate entirely). When the gate
  # accepts, builds the `<fb_aggregated>` sufficient-statistics
  # object and dispatches to emit_gaussian_aggregated() on the
  # resolved backend, short-circuiting the per-row paths below.
  if (!isFALSE(aggregate) && !isTRUE(return_code)) {
    agg_fit <- .maybe_aggregate_gaussian(
      fb             = fb,
      data           = data,
      backend        = backend,
      aggregate      = aggregate,
      n_samples      = n_samples,
      warmup         = warmup,
      chains         = chains,
      prior_fixed_sd = prior_fixed_sd,
      prior_vc_sd    = prior_vc_sd,
      verbose        = verbose,
      mcmc_verbose   = mcmc_verbose,
      the_call       = the_call,
      fixed          = fixed,
      random         = random,
      rcov           = rcov,
      family         = family,
      link           = link,
      data_name      = data_name
    )
    if (!is.null(agg_fit)) return(agg_fit)
  }

  # Stan passthrough via brms. Opt-in only -- backend = "auto" never
  # routes to Stan because brms's first-call compile latency (30-60s)
  # would silently break the auto-dispatch transparent-fast-path
  # promise. Users wanting Stan triangulation set backend = "brms"
  # explicitly on fb_brms(); flexybayes() (the asreml entry) does
  # not advertise the value because asreml structured-covariance
  # terms (fa, us, ar1) do not translate losslessly to brms.
  if (identical(backend, "brms")) {
    fit <- emit_brms(
      fb             = fb,
      data           = data,
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
      data_name      = data_name
    )
    if (return_code) return(fit)
    if (!is.null(fit$extras)) {
      fit$extras$backend_decision <- list(
        backend     = "brms",
        path        = "explicit_brms",
        gate_checks = NULL,
        reason      = paste0("user requested brms explicitly ",
                              "(Stan passthrough; lgm_gate() not ",
                              "consulted on this path).")
      )
      fit$extras$fb_terms <- fb
    }
    fit$exactness <- "exact"
    return(fit)
  }

  decision <- NULL
  if (backend %in% c("inla", "auto")) {
    gated <- lgm_gate(fb)

    if (is_lgm_refusal(gated)) {
      if (backend == "inla") {
        msg <- paste(utils::capture.output(print(gated)),
                     collapse = "\n")
        stop("backend = \"inla\" refused by lgm_gate():\n", msg,
             call. = FALSE)
      }
      primary <- gated$failures[[1L]]
      if (!isTRUE(getOption(
            "flexyBayes.silence_auto_fallback_note", FALSE)))
        message("backend = \"auto\": lgm_gate() refused (",
                primary$rule_id, ": ", primary$reason,
                "); falling back to greta. Pass backend = ",
                "\"greta\" to silence, or backend = \"inla\" ",
                "to force the refusal as an error.")
      decision <- list(
        backend     = "greta",
        path        = "auto_lgm_refuse",
        gate_checks = gated$failures,
        reason      = paste0("lgm_gate() refused (",
                             primary$rule_id, "); auto fell back to greta.")
      )
    } else {
      if (!requireNamespace("INLA", quietly = TRUE)) {
        if (backend == "auto") {
          if (!isTRUE(getOption(
                "flexyBayes.silence_auto_inla_missing_note", FALSE)))
            message("backend = \"auto\": INLA is not installed; ",
                    "routing to greta. Install INLA from ",
                    "https://inla.r-inla-download.org for the LGM ",
                    "fast path. Silence via ",
                    "options(flexyBayes.silence_auto_inla_missing_note ",
                    "= TRUE).")
          decision <- list(
            backend     = "greta",
            path        = "auto_inla_unavailable",
            gate_checks = gated$capabilities,
            reason      = "lgm_gate() accepted; INLA not installed; routed to greta."
          )
        }
      }

      if (backend == "inla" ||
          (backend == "auto" &&
           requireNamespace("INLA", quietly = TRUE))) {
        # ADR 0017: with the gate folded around emit_inla()'s
        # structural refusals, lgm_gate(fb) == accept is a
        # sufficient condition for .build_inla_formula(gated) to
        # succeed structurally. We therefore no longer wrap the
        # emit_inla() call in a tryCatch / emit_inla_failure
        # fall-back: any error from this point is either (a) the
        # internal contract-violation assertion (gate / emit
        # drift bug -- a flexyBayes-side error that must surface,
        # not silently fall back to greta), or (b) an INLA-side
        # numerical / runtime failure independent of structural
        # feasibility (also surfaces directly so the user sees
        # the true diagnostic instead of a silent greta fit).
        fit <- emit_inla(
          fb        = gated,
          data      = data,
          verbose   = verbose,
          return_code = return_code,
          the_call  = the_call,
          fixed     = fixed,
          random    = random,
          rcov      = rcov,
          family    = family,
          link      = link,
          data_name = data_name
        )
        if (return_code) return(fit)
        if (!is.null(fit$extras)) {
          fit$extras$backend_decision <- list(
            backend     = "inla",
            path        = if (backend == "auto") "auto_accept" else "explicit_inla_accept",
            gate_checks = gated$capabilities,
            reason      = "lgm_gate() accepted; INLA dispatch."
          )
          fit$extras$fb_terms <- gated
        }
        fit$exactness <- "exact"
        return(fit)
      }
    }
  } else {
    decision <- list(
      backend     = "greta",
      path        = "explicit_greta",
      gate_checks = NULL,
      reason      = "user requested greta explicitly (no gate run)."
    )
  }

  if (!requireNamespace("greta", quietly = TRUE))
    stop("Package 'greta' is required for the greta backend. ",
         "Install with:\n",
         "  install.packages('greta')\n",
         "  greta::install_greta_deps()",
         call. = FALSE)

  fit <- emit_greta(
    fb             = fb,
    data           = data,
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
    data_name      = data_name
  )

  if (!isTRUE(return_code) && !is.null(fit$extras)) {
    if (!is.null(decision))
      fit$extras$backend_decision <- decision
    fit$extras$fb_terms <- fb
  }
  if (!isTRUE(return_code)) fit$exactness <- "exact"
  fit
}


# Normalise the user-facing `aggregate` argument. Accepts:
#   TRUE        -- force aggregation; refuse if plan ineligible.
#   FALSE       -- skip aggregation; always per-row.
#   "auto"      -- aggregate when plan eligible; silently fall through
#                  to per-row otherwise (the v0.3.2 default).
.normalise_aggregate <- function(x) {
  if (is.logical(x) && length(x) == 1L && !is.na(x))
    return(x)
  if (is.character(x) && length(x) == 1L && identical(x, "auto"))
    return("auto")
  stop("`aggregate` must be TRUE, FALSE, or \"auto\"; got: ",
       paste(deparse(x), collapse = " "), call. = FALSE)
}


# Stage 3A aggregated-gaussian gate (ADR 0022). Returns either a
# fitted <flexybayes_aggregated> object (gate accepted; aggregated
# emit ran) or NULL (gate declined; caller falls through to per-row).
# Refuses (raises a typed condition) when aggregate = TRUE but the
# plan declares ineligibility, or when aggregate = TRUE on a backend
# that does not support the aggregated path (brms, gretaR, stan).
.maybe_aggregate_gaussian <- function(fb, data, backend, aggregate,
                                       n_samples, warmup, chains,
                                       prior_fixed_sd, prior_vc_sd,
                                       verbose, mcmc_verbose, the_call,
                                       fixed, random, rcov, family,
                                       link, data_name) {

  # Aggregation only defined for backends with a flexyBayes-side
  # aggregated emit path. v0.3.2 supports greta + inla; brms / gretaR
  # / stan have no aggregated path in scope at v0.3.2.
  agg_capable_backend <- backend %in% c("greta", "inla", "auto")
  if (!agg_capable_backend) {
    if (isTRUE(aggregate))
      stop("`aggregate = TRUE` is not supported on backend = \"",
           backend, "\" at v0.3.2 (the aggregated path is wired for ",
           "greta and inla only). Pass aggregate = FALSE or switch ",
           "backend.", call. = FALSE)
    return(NULL)
  }

  # Run the model-level plan against the fb_dataset metadata. Reads
  # only IR + dictionaries; no design matrix is materialised.
  fb_dataset_meta <- .fb_dataset(data)
  plan <- .fb_aggregation_plan(fb, fb_dataset_meta)

  # Resolve the effective backend for the aggregated emit. v0.3.2
  # supports only INLA on the aggregated path (greta deferred to
  # v0.3.3; see emit_gaussian_aggregated() header for the dispatch
  # rationale). Force INLA when backend = "auto" or "greta" if the
  # plan would otherwise route to aggregation; refuse explicitly when
  # backend = "greta" with aggregate = TRUE.
  eff_backend <- .agg_resolve_backend(backend, fb)
  if (identical(eff_backend, "greta")) {
    if (isTRUE(aggregate))
      stop("`aggregate = TRUE` on backend = \"greta\" is deferred ",
           "at v0.3.2. Pass backend = \"inla\" (or \"auto\") for ",
           "the aggregated path, or aggregate = FALSE for per-row ",
           "greta.", call. = FALSE)
    return(NULL)
  }

  # at_units on INLA at v0.3.2: the multi-likelihood INLA stack is
  # deferred. If we'd otherwise route to INLA AND the rcov uses
  # at_units, force the eff_backend down to greta (which supports the
  # heterogeneous-residual aggregated path) or fall through to per-row
  # when greta isn't an option.
  uses_at_units <- length(fb$rcov_terms) > 0L &&
    any(vapply(fb$rcov_terms,
               function(t) identical(t$type %||% "", "at_units"),
               logical(1L)))
  if (identical(eff_backend, "inla") && uses_at_units) {
    if (identical(backend, "inla") && isTRUE(aggregate))
      stop("`aggregate = TRUE` with backend = \"inla\" refused: ",
           "heterogeneous residual at_units on INLA is deferred at ",
           "v0.3.2 (requires the multi-likelihood INLA stack). Pass ",
           "backend = \"greta\" with aggregate = TRUE, or aggregate ",
           "= FALSE for per-row INLA.", call. = FALSE)
    if (identical(backend, "auto"))
      eff_backend <- "greta"
    else
      return(NULL)
  }

  if (!isTRUE(plan$eligible)) {
    if (isTRUE(aggregate)) {
      cond <- structure(
        class = c("flexybayes_aggregate_refusal", "error", "condition"),
        list(
          message     = paste0(
            "`aggregate = TRUE` refused by .fb_aggregation_plan(): ",
            paste(plan$reason_codes, collapse = ", "),
            ". Pass aggregate = FALSE for the per-row path."),
          call         = the_call,
          reason_codes = plan$reason_codes,
          plan         = plan
        )
      )
      stop(cond)
    }
    return(NULL)
  }

  fb_aggregated <- .fb_aggregate_gaussian(fb, fb_dataset_meta)

  fit <- emit_gaussian_aggregated(
    fb             = fb,
    fb_aggregated  = fb_aggregated,
    data           = data,
    backend        = eff_backend,
    n_samples      = n_samples,
    warmup         = warmup,
    chains         = chains,
    prior_fixed_sd = prior_fixed_sd,
    prior_vc_sd    = prior_vc_sd,
    verbose        = verbose,
    mcmc_verbose   = mcmc_verbose,
    return_code    = FALSE,
    the_call       = the_call,
    fixed          = fixed,
    random         = random,
    rcov           = rcov,
    family         = family,
    link           = link,
    data_name      = data_name
  )

  fit$exactness <- "aggregated_exact"
  if (!is.null(fit$extras)) {
    fit$extras$backend_decision <- list(
      backend     = eff_backend,
      path        = "aggregated_gaussian",
      gate_checks = NULL,
      reason      = sprintf(
        "aggregation plan eligible (N = %d, K = %d, ratio = %.2f:1)",
        plan$N, plan$K_est, plan$N / plan$K_est)
    )
    fit$extras$fb_terms <- fb
  }
  fit
}


# Choose the effective aggregated-emit backend. greta / inla pass
# through verbatim. auto consults lgm_gate -- if the model is LGM-
# compatible and INLA is installed, prefer INLA (faster deterministic
# on the aggregated path); else greta.
.agg_resolve_backend <- function(backend, fb) {
  if (backend %in% c("greta", "inla")) return(backend)
  if (identical(backend, "auto")) {
    gated <- tryCatch(lgm_gate(fb), error = function(e) NULL)
    if (!is.null(gated) && !is_lgm_refusal(gated) &&
        requireNamespace("INLA", quietly = TRUE))
      return("inla")
    return("greta")
  }
  # Unknown backend -- caller already filtered, defensive default.
  "greta"
}


# Stage 2 MVP -- shared preflight call. Runs IFF the IR carries
# n_rows >= 1e5; below that threshold the v0.2 user surface is
# unchanged. Returns the <fb_preflight> result (or NULL when below
# the threshold); on refusal raises the typed condition via
# .stop_preflight_refusal(). Used by both .dispatch_backend()'s
# entry block and the review_code branches in flexybayes() /
# fb_brms() so the gate fires identically across both paths.
.maybe_preflight <- function(fb, data, the_call,
                              threshold = 1e5L) {
  if (!isTRUE(!is.null(fb$data_summary$n) &&
              fb$data_summary$n >= threshold))
    return(NULL)
  # Optional global ceiling override -- lets the user set a stricter
  # cap than the default 60% x RAM (e.g. on a shared host) without
  # passing an argument through every dispatch entry. NULL falls back
  # to the default RAM-probe resolution inside .fb_preflight(). The
  # related option `flexyBayes.preflight_ram_fraction` adjusts the
  # default fraction multiplicatively (audit P2.3, 2026-05-23).
  pf_ceiling_gb <- getOption("flexyBayes.preflight_ceiling_gb", NULL)
  pf_dataset <- .fb_dataset(data)
  pf_result  <- .fb_preflight(fb, pf_dataset,
                               memory_ceiling_gb = pf_ceiling_gb)
  if (inherits(pf_result$refusal, "fb_preflight_refusal"))
    .stop_preflight_refusal(pf_result$refusal, call = the_call)
  pf_result
}


# Stage 2 MVP -- raise a typed preflight refusal as a structured
# condition. The custom class `flexybayes_preflight_refusal` carries
# the refusal object verbatim so downstream tooling can pattern-match
# on the slots without parsing free text.
#
# Audit P1.3 (2026-05-24): the headline is branched on
# refusal$reason_code so that an unknown-representation refusal does
# not falsely suggest raising the memory ceiling. The detailed body
# already prints correctly via print.fb_preflight_refusal().
.stop_preflight_refusal <- function(refusal, call) {
  msg <- paste(utils::capture.output(print(refusal)), collapse = "\n")
  headline <- switch(
    refusal$reason_code,
    design_memory_exceeds_ceiling =
      paste0("flexyBayes preflight refused: the design exceeds the ",
             "active memory ceiling. The dispatch was short-circuited ",
             "before any backend code ran."),
    representation_unknown_for_preflight =
      paste0("flexyBayes preflight refused: the design representation ",
             "is not characterised by the preflight estimator. The ",
             "dispatch was short-circuited before any backend code ",
             "ran -- raising the memory ceiling will not help."),
    # default: neutral wording carrying the reason code so any future
    # refusal class lands honestly even before its headline is added.
    paste0("flexyBayes preflight refused (reason_code = ",
           refusal$reason_code, "). The dispatch was short-circuited ",
           "before any backend code ran.")
  )
  cond <- structure(
    class = c("flexybayes_preflight_refusal", "error", "condition"),
    list(
      message       = paste0(headline, "\n", msg),
      call          = call,
      refusal       = refusal,
      reason_code   = refusal$reason_code,
      binding_term  = refusal$binding_term,
      ceiling_bytes = refusal$ceiling_bytes
    )
  )
  stop(cond)
}
