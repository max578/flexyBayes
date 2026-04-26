# emit_greta -- flexyBayes greta backend emit shim.
#
# Phase 0.C: a no-semantic-change shim that takes an fb_terms IR
# (intermediate representation) object and runs the full greta
# backend pipeline that bayesreml() previously ran inline. This
# lifts greta dispatch out of bayesreml() and behind a single
# emit_*() function, mirroring what emit_brms (deliverable 1+) and
# emit_inla (deliverable 1+) will do.
#
# Behaviour invariant: for every input previously valid for
# bayesreml(), the migrated path bayesreml() -> fb_from_asreml() ->
# emit_greta() produces byte-identical generated greta code to the
# pre-0.C bayesreml() inline pipeline. Snapshot-tested in
# tests/testthat/test-emit-greta.R; transparency-tested in
# tests/testthat/test-fb-from-asreml.R.
#
# Internal -- not exported. Called from bayesreml() and (in
# deliverable 4) from triangulate() when greta is one of the
# requested backends.

emit_greta <- function(fb,
                       data,
                       known_matrices = list(),
                       weights        = NULL,
                       n_samples      = 1000,
                       warmup         = 500,
                       chains         = 4,
                       prior_fixed_sd = 10,
                       prior_vc_sd    = 1,
                       verbose        = TRUE,
                       mcmc_verbose   = TRUE,
                       return_code    = FALSE,
                       the_call       = NULL,
                       fixed          = NULL,
                       random         = NULL,
                       rcov           = NULL,
                       family         = NULL,
                       link           = NULL,
                       data_name      = NA_character_) {

  if (!is_fb_terms(fb))
    stop("`fb` must be an fb_terms object (see fb_from_asreml).",
         call. = FALSE)

  # ---------------------------------------------------------------- #
  # Unwrap the IR back into the shape the existing helpers expect.   #
  # No semantic change: fixed_info, random_terms, rcov_terms,        #
  # fam_link are byte-identical to what bayesreml() previously       #
  # produced inline via .parse_fixed / .parse_formula /              #
  # .resolve_family.                                                 #
  # ---------------------------------------------------------------- #

  fixed_info <- list(
    response  = fb$response,
    intercept = fb$intercept,
    terms     = fb$fixed_terms
  )
  random_terms <- fb$random_terms
  rcov_terms   <- fb$rcov_terms
  fam_link     <- list(family = fb$family, link = fb$link)

  # ---------------------------------------------------------------- #
  # Build evaluation environment (unchanged from pre-0.C bayesreml). #
  # ---------------------------------------------------------------- #

  greta_ns <- asNamespace("greta")
  ev <- new.env(parent = greta_ns)
  .setup_env(ev, fixed_info, random_terms, rcov_terms,
             data, known_matrices, weights)

  # ---------------------------------------------------------------- #
  # Generate code (unchanged).                                       #
  # ---------------------------------------------------------------- #

  ctx <- list(
    params    = character(0),
    predictor = character(0),
    code      = character(0),
    fam_link  = fam_link,
    prior_vc  = prior_vc_sd,
    prior_fx  = prior_fixed_sd
  )

  ctx <- .code_fixed(ctx, fixed_info)
  ctx <- .code_random(ctx, random_terms, data, known_matrices)
  ctx <- .code_rcov(ctx, rcov_terms, data)
  ctx <- .code_predictor(ctx, fixed_info)
  ctx <- .code_likelihood(ctx, fixed_info, rcov_terms, data, weights)
  ctx <- .code_model(ctx, n_samples, warmup, chains, mcmc_verbose)

  code_str <- paste(ctx$code, collapse = "\n")

  if (verbose) {
    cat("\n-- bayesreml: generated greta code ",
        paste(rep("-", 40), collapse = ""), "\n", sep = "")
    cat(code_str, "\n")
    cat(paste(rep("-", 60), collapse = ""), "\n\n")
  }

  if (return_code) return(invisible(code_str))

  # ---------------------------------------------------------------- #
  # Evaluate (unchanged).                                            #
  # ---------------------------------------------------------------- #

  t0 <- proc.time()
  tryCatch(
    eval(parse(text = code_str), envir = ev),
    error = function(e)
      stop("bayesreml evaluation error: ", conditionMessage(e))
  )
  elapsed <- unname((proc.time() - t0)["elapsed"])

  # ---------------------------------------------------------------- #
  # Post-processing (unchanged).                                     #
  # ---------------------------------------------------------------- #

  all_obj_names <- ls(ev)
  is_greta <- vapply(all_obj_names, function(nm) {
    tryCatch(inherits(get(nm, envir = ev, inherits = FALSE), "greta_array"),
             error = function(e) FALSE)
  }, logical(1))
  greta_arrays <- if (any(is_greta)) {
    nms <- all_obj_names[is_greta]
    setNames(lapply(nms, function(nm) get(nm, envir = ev, inherits = FALSE)),
             nms)
  } else {
    list()
  }

  post_summary <- tryCatch(summary(ev$atg_draws),
                           error = function(e) NULL)

  n_eff  <- tryCatch(coda::effectiveSize(ev$atg_draws),
                     error = function(e) NULL)
  gelman <- if (chains >= 2 && length(ev$atg_draws) >= 2) {
    tryCatch(coda::gelman.diag(ev$atg_draws, multivariate = FALSE),
             error = function(e) NULL)
  } else NULL
  conv_diag <- list(n_eff = n_eff, gelman = gelman)

  # Three-part output assembly
  glm_obj <- .build_glm(
    fixed_info  = fixed_info,
    data        = data,
    draws       = ev$atg_draws,
    ev          = ev,
    fam_link    = fam_link,
    the_call    = the_call,
    fixed       = fixed
  )

  greta_out <- structure(
    list(
      model        = ev$atg_model,
      draws        = ev$atg_draws,
      greta_arrays = greta_arrays,
      env          = ev
    ),
    class = "bayesreml_greta"
  )

  vc_table <- .build_variance_comps(post_summary, ctx$params)
  blups    <- .build_blups(post_summary, random_terms)
  preds    <- .build_predictions(data, fixed_info, post_summary,
                                 ev, fam_link)

  extras <- structure(
    list(
      summary        = post_summary,
      convergence    = conv_diag,
      variance_comps = vc_table,
      blups          = blups,
      predictions    = preds,
      code           = code_str,
      param_names    = unique(ctx$params),
      parse_info     = list(
        fixed  = fixed_info,
        random = random_terms,
        rcov   = rcov_terms,
        family = fam_link
      ),
      call_info      = list(
        fixed          = fixed,
        random         = random,
        rcov           = rcov,
        data_name      = data_name,
        family         = family,
        link           = link,
        known_matrices = known_matrices,
        weights        = weights,
        n_samples      = n_samples,
        warmup         = warmup,
        chains         = chains,
        prior_fixed_sd = prior_fixed_sd,
        prior_vc_sd    = prior_vc_sd
      ),
      run_time       = elapsed,
      model_info     = list(
        n_obs    = nrow(data),
        n_fixed  = length(fixed_info$terms) + fixed_info$intercept,
        n_random = length(random_terms),
        n_params = length(unique(ctx$params)),
        family   = fam_link$family,
        link     = fam_link$link
      )
    ),
    class = "bayesreml_extras"
  )

  result <- structure(
    list(
      glm    = glm_obj,
      greta  = greta_out,
      extras = extras
    ),
    class = "bayesreml"
  )

  invisible(result)
}
