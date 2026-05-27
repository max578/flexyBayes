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

  # Lock the refusal-reason registry (ADR 0030 C7 scaffold; v0.3.8).
  # v0.3.8 ships zero .register_refusal() calls; v0.4.0 will populate
  # the registry from ~30 existing refusal sites, with the registration
  # block sitting above this lock call. The lock makes the registry
  # immutable to user code once the package is loaded.
  .lock_refusal_registry()
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
