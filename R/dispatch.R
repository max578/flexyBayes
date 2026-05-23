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
                              data_name) {

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
  preflight_threshold <- 1e5L
  if (isTRUE(!is.null(fb$data_summary$n) &&
             fb$data_summary$n >= preflight_threshold)) {
    # Optional global ceiling override -- lets the user set a stricter
    # cap than 0.8 x RAM (e.g. on a shared host) without passing an
    # argument through every dispatch entry. NULL falls back to the
    # default RAM-probe resolution inside .fb_preflight().
    pf_ceiling_gb <- getOption("flexyBayes.preflight_ceiling_gb", NULL)
    pf_dataset <- .fb_dataset(data)
    pf_result  <- .fb_preflight(fb, pf_dataset,
                                 memory_ceiling_gb = pf_ceiling_gb)
    if (inherits(pf_result$refusal, "fb_preflight_refusal"))
      .stop_preflight_refusal(pf_result$refusal, call = the_call)
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
  fit
}


# Stage 2 MVP -- raise a typed preflight refusal as a structured
# condition. The custom class `flexybayes_preflight_refusal` carries
# the refusal object verbatim so downstream tooling can pattern-match
# on the slots without parsing free text.
.stop_preflight_refusal <- function(refusal, call) {
  msg <- paste(utils::capture.output(print(refusal)), collapse = "\n")
  cond <- structure(
    class = c("flexybayes_preflight_refusal", "error", "condition"),
    list(
      message       = paste0(
        "flexyBayes preflight refused: the design exceeds the ",
        "active memory ceiling. The dispatch was short-circuited ",
        "before any backend code ran.\n",
        msg
      ),
      call          = call,
      refusal       = refusal,
      reason_code   = refusal$reason_code,
      binding_term  = refusal$binding_term,
      ceiling_bytes = refusal$ceiling_bytes
    )
  )
  stop(cond)
}
