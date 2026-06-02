# Package load hooks

.onLoad <- function(libname, pkgname) {
  # Register emmeans methods if emmeans is available -- for both the
  # greta (`flexybayes`) and INLA (`flexybayes_inla`) fit classes.
  if (requireNamespace("emmeans", quietly = TRUE)) {
    emmeans::.emm_register(c("flexybayes", "flexybayes_inla"), pkgname)
  }

  # marginaleffects gates on a class allow-list before dispatching its
  # get_predict / get_coef / get_vcov methods, but exposes a custom-class
  # hook via this option (see
  # marginaleffects:::sanity_model_supported_class). Append the flexyBayes
  # classes without clobbering a user's existing setting.
  if (requireNamespace("marginaleffects", quietly = TRUE)) {
    cur <- getOption("marginaleffects_model_classes", default = NULL)
    options(
      marginaleffects_model_classes = union(
        as.character(cur),
        c("flexybayes", "flexybayes_inla")
      )
    )
  }

  # Register broom S3 methods if generics is available
  if (requireNamespace("generics", quietly = TRUE)) {
    tryCatch(
      {
        registerS3method(
          "tidy",
          "flexybayes",
          tidy.flexybayes,
          envir = asNamespace("generics")
        )
        registerS3method(
          "glance",
          "flexybayes",
          glance.flexybayes,
          envir = asNamespace("generics")
        )
        registerS3method(
          "augment",
          "flexybayes",
          augment.flexybayes,
          envir = asNamespace("generics")
        )
      },
      error = function(e) NULL
    )
  }

  # Register greta S3 methods inside flexyBayes's namespace so the
  # Stage 3A `.emit_gaussian_aggregated_greta()` path can call into
  # greta from within a package-namespace context. Without this,
  # greta's internal `check_dims` -> `as.greta_array(...)` dispatch
  # routes greta_array operands to `as.greta_array.matrix` instead
  # of `as.greta_array.greta_array`, producing a spurious
  # missing/infinite-values error on otherwise-valid greta_arrays.
  if (requireNamespace("greta", quietly = TRUE)) {
    tryCatch(
      {
        greta_ns <- asNamespace("greta")
        flx_ns <- asNamespace(pkgname)
        for (cls in c(
          "greta_array",
          "matrix",
          "numeric",
          "logical",
          "integer",
          "data.frame",
          "array"
        )) {
          m_name <- paste0("as.greta_array.", cls)
          if (exists(m_name, envir = greta_ns, inherits = FALSE)) {
            registerS3method(
              "as.greta_array",
              cls,
              get(m_name, envir = greta_ns, inherits = FALSE),
              envir = flx_ns
            )
          }
        }
      },
      error = function(e) NULL
    )
  }

  # Initialise the emit-once message latches into their fresh state.
  # The store lives in R/emit_state.R inside a package-private env so
  # it cannot be read or mutated via getOption() / options(); test
  # code reaches it through .reset_emit_state_for_test() exposed via
  # helper-emit-state.R.
  .init_emit_state()

  # ADR 0030 C4 (v0.4.0 Wave 1 Phase 1A): populate the representation
  # registry with the fifteen v0.4.0-open classes (the ten plan-named
  # entries plus indexed_random_intercept + dense_baseline discovered
  # in the v0.3.10 source plus indexed_fixed_numeric /
  # indexed_fixed_factor / indexed_fixed_factor_numeric discovered
  # during the Phase 1A .preflight_fixed_term() producer-site sweep).
  # The registry is the single source of truth for legitimate
  # representation_class strings at preflight / planning / display
  # sites; .lookup_representation() / .representation_class() refuse
  # unknown names so typos cannot silently propagate. low_rank
  # registers in Phase 1B alongside the approximation registry.
  .populate_representation_registry_v0400()

  # Lock the representation registry. Bindings remain readable
  # indefinitely; further .register_representation() calls after
  # this point raise rather than mutate the locked environment.
  .lock_representation_registry()

  # ADR 0025 Decisions 3 + 4 (v0.3.10): register the first three
  # canonical refusal-reason codes into the v0.3.8 C7 scaffold ---
  # block_partition_incomplete, block_not_positive_definite, and the
  # upgraded approximate_route_not_yet_registered. This is the first
  # migration; the v0.4.0 Wave 1 Phase 1C bulk migration follows the
  # same .register_refusal() shape for the ~28 remaining sites.
  .populate_refusal_registry_v0310()

  # ADR 0030 C7 (v0.4.0 Wave 1 Phase 1C): bulk-register the remaining
  # user-facing refusal codes (the v0.3.10 scaffold above seeds the
  # first three). With the family gate and the parse-time spec
  # refusals and the entry-point argument guards folded in during the
  # 2026-05-30 audit remediation, the registry held 39 user-facing
  # codes; Wave 2 Phase 2A (ADR 0030 C3 fb_cov()) adds three
  # (fb_cov_type_unknown, fb_cov_missing_matrix, cov_arg_not_fb_cov)
  # for a v0.4.0 total of 42. Routing-
  # decision reasons (backend_decision trace) and internal aggregate-
  # out-of-scope control-flow signals are deliberately not registered
  # --- they are not refusals a user can hit. Every refusal site now
  # routes through .fb_refusal_condition(), which gates on this
  # registry.
  .populate_refusal_registry_v0400()

  # gretaR backend activation (ADR 0013/0031): the gretaR-specific refusal codes.
  .populate_refusal_registry_gretaR()

  # Lock the refusal-reason registry (ADR 0030 C7 scaffold; v0.3.8).
  # The lock makes the registry immutable to user code once the
  # package is loaded; .register_refusal() calls beyond this point
  # raise rather than mutate the locked environment.
  .lock_refusal_registry()

  # ADR 0030 C5 + ADR 0027 (v0.4.0 Wave 1 Phase 1B): register the
  # first approximation scheme, low_rank_smooth, with its full
  # five-field schema and its validation_fn (.validate_low_rank_smooth,
  # R/emit_smooth_low_rank.R). The scheme lands together with its emit
  # path (R/codegen.R low-rank branch), its predict-side projection
  # (R/predict_kernel.R), and the exported validate_approximation()
  # surface --- the registry invariant ("every registered scheme
  # carries a working validation procedure") is honoured because the
  # validation_fn reads the truncation metadata a real low-rank fit
  # records on fit$extras$parse_info$approx.
  .populate_approximation_registry_v0400()

  # Lock the approximation-scheme registry. Further
  # .register_approximation() calls beyond this point raise rather
  # than mutate the locked environment; further schemes (inla_laplace,
  # predictive_process, vb) register here in subsequent releases.
  .lock_approximation_registry()

  # ADR 0029 (v0.4.0 Wave 2 Phase 2B): populate the backend-independence
  # registry with the three pairs among the v0.3.x triangulatable
  # backends (greta, inla, brms). triangulate() consumes this to label
  # each cross-engine comparison with its independence axis
  # (algorithmic / implementation / specification). The stan_brms
  # backend (ADR 0028) registers its own pairs when it lands at v0.4.1.
  .populate_backend_independence_registry_v0400()

  # Lock the backend-independence registry. The closed axis vocabulary
  # and the per-pair records are immutable to user code once loaded.
  .lock_backend_independence_registry()

  # ADR 0031 (v0.5.0 backend-axis recovery): populate the backend
  # registry --- the fifth closed-vocabulary registry, modelling backend
  # as a first-class axis (the one concept ADR 0030 left hard-coded).
  # Registers the three active backends (greta, inla, brms) plus the
  # dormant gretaR slot. By Phase 3 the registry is the single source of
  # truth for backend facts and dispatch CONSUMES them: availability via
  # .available_backend_names(), capability via .backend_can_fit(), the
  # emit entry-point via .backend_emit_fn(). The per-paradigm routing
  # order / fallback policy stays explicit in dispatch by design
  # (Option A, 2026-05-31). test-backend-registry.R guards consistency
  # against the match.arg vocabularies and .routing_policy_table().
  .populate_backend_registry_v050()

  # Lock the backend registry. Further .register_backend() calls beyond
  # this point raise rather than mutate the locked environment; future
  # engines (gretaR activation, NIMBLE) register here in later releases.
  .lock_backend_registry()
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage(
    "flexyBayes ",
    utils::packageVersion(pkgname),
    " -- Bayesian mixed models with ASReml syntax"
  )

  # Check greta availability
  if (!requireNamespace("greta", quietly = TRUE)) {
    packageStartupMessage(
      "  Note: greta is not installed. Install with:\n",
      "    install.packages('greta')\n",
      "    greta::install_greta_deps()"
    )
  }
}
