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
        emit_attempt <- tryCatch(
          emit_inla(
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
          ),
          error = function(e) structure(
            list(.emit_failed = TRUE,
                 .emit_error = conditionMessage(e)),
            class = "emit_inla_failure"
          )
        )

        if (inherits(emit_attempt, "emit_inla_failure")) {
          if (backend == "inla")
            stop("backend = \"inla\": emit_inla() refused this ",
                 "model: ", emit_attempt$.emit_error, call. = FALSE)
          if (!isTRUE(getOption(
                "flexyBayes.silence_auto_fallback_note", FALSE)))
            message("backend = \"auto\": lgm_gate() accepted but ",
                    "emit_inla() refused at emit time (",
                    sub("\\..*$", "", emit_attempt$.emit_error),
                    "); falling back to greta.")
          decision <- list(
            backend     = "greta",
            path        = "auto_inla_emit_refuse",
            gate_checks = gated$capabilities,
            reason      = paste0("lgm_gate() accepted; emit_inla() ",
                                 "refused at emit time; auto fell ",
                                 "back to greta.")
          )
        } else {
          fit <- emit_attempt
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
