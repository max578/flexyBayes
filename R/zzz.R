# Package load hooks

.onLoad <- function(libname, pkgname) {
  # Register emmeans methods if emmeans is available
  if (requireNamespace("emmeans", quietly = TRUE)) {
    emmeans::.emm_register("flexybayes", pkgname)
  }

  # Register broom S3 methods if generics is available
  if (requireNamespace("generics", quietly = TRUE)) {
    tryCatch({
      registerS3method("tidy", "flexybayes", tidy.flexybayes,
                        envir = asNamespace("generics"))
      registerS3method("glance", "flexybayes", glance.flexybayes,
                        envir = asNamespace("generics"))
      registerS3method("augment", "flexybayes", augment.flexybayes,
                        envir = asNamespace("generics"))
    }, error = function(e) NULL)
  }

  # Register greta S3 methods inside flexyBayes's namespace so the
  # Stage 3A `.emit_gaussian_aggregated_greta()` path can call into
  # greta from within a package-namespace context. Without this,
  # greta's internal `check_dims` -> `as.greta_array(...)` dispatch
  # routes greta_array operands to `as.greta_array.matrix` instead
  # of `as.greta_array.greta_array`, producing a spurious
  # missing/infinite-values error on otherwise-valid greta_arrays.
  if (requireNamespace("greta", quietly = TRUE)) {
    tryCatch({
      greta_ns <- asNamespace("greta")
      flx_ns   <- asNamespace(pkgname)
      for (cls in c("greta_array", "matrix", "numeric", "logical",
                     "integer", "data.frame", "array")) {
        m_name <- paste0("as.greta_array.", cls)
        if (exists(m_name, envir = greta_ns, inherits = FALSE)) {
          registerS3method("as.greta_array", cls,
                            get(m_name, envir = greta_ns,
                                inherits = FALSE),
                            envir = flx_ns)
        }
      }
    }, error = function(e) NULL)
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
  # 28 user-facing refusal codes, so the registry now holds the
  # complete 31-code user-facing vocabulary. Routing-decision reasons
  # (backend_decision trace) and internal aggregate-out-of-scope
  # control-flow signals are deliberately not registered --- they are
  # not refusals a user can hit. Every refusal site now routes through
  # .fb_refusal_condition(), which gates on this registry.
  .populate_refusal_registry_v0400()

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
}

.onAttach <- function(libname, pkgname) {
  packageStartupMessage(
    "flexyBayes ", utils::packageVersion(pkgname),
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
