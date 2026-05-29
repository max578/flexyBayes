# Approximation registry --- scaffold only at v0.4.0 Wave 1 Phase 1A
# substrate (ADR 0030 C5 + ADR 0027)
#
# Container + registration helper + lookup accessor + lock helper for
# the canonical approximation-scheme vocabulary. ADR 0027 makes every
# approximate route declare, at registration time, the four things a
# user needs to keep their own judgement: a bias bound, a validation
# procedure, a fallback hint, and ADR provenance. The registry is the
# single source of truth for "is this string a legitimate
# approximation scheme?", mirroring the v0.3.8 R/refusal_taxonomy.R
# (C7) and the v0.4.0 R/representation_registry.R (C4) scaffolds.
#
# Empty at this substrate step --- deliberately. The first scheme
# (`low_rank_smooth`) registers together with its emit path
# (R/emit_smooth_low_rank.R) and the exported validate_approximation()
# surface, because the scheme's validation_fn reads the truncated and
# full smooth-basis matrices off the fit object that only the emit
# path produces. Shipping the scheme's validation procedure before its
# producer would pin a fit-slot contract with no consumer to verify it
# against; the registry invariant ("every registered scheme carries a
# working validation procedure") is best honoured by landing scheme +
# validation + producer in one reviewed, end-to-end-verifiable change.
# This step ships the container so that landing is a population step,
# not an architecture step --- the same posture the C7 refusal
# scaffold took at v0.3.8 (container at v0.3.8, first population at
# v0.3.10).
#
# Rationale (v040-plan-2026-05-28 section 5.3):
#
#   "atomicity matters: a half-shipped scheme with a populated
#    registry but no validation procedure would violate the registry's
#    invariant."
#
# The registry is an environment (parent = emptyenv()) so symbol
# lookup cannot fall through to the package namespace and pick up an
# unrelated binding; populated by .register_approximation() at
# .onLoad() time (currently zero calls --- the scaffold-only posture)
# and locked immediately after via .lock_approximation_registry().

# --- container ---------------------------------------------------- #

# `.approximation_registry` is allocated at namespace load. Filled by
# .register_approximation() during .onLoad() (currently zero calls);
# locked immediately after by .lock_approximation_registry().
.approximation_registry <- new.env(parent = emptyenv())


# --- registration helper ------------------------------------------ #

# .register_approximation() --- the one-shot registration call.
# Idempotent only in the sense that a duplicate `scheme` raises rather
# than silently overwriting; the vocabulary is append-only at
# .onLoad() time and the registry then locks.
#
# Arguments (the five-field ADR 0027 Decision 2 schema)
#   scheme             canonical machine-readable identifier; the same
#                      string the exactness label "approximate_<scheme>"
#                      carries and the string validate_approximation()
#                      dispatches on. Must be a single non-empty string.
#   bias_bound         a list describing the analytical or empirical
#                      bias bound (e.g., type / expression / formula /
#                      reference / interpretation). Must be a list.
#   validation_fn      the per-scheme validation procedure, a function
#                      of (fit, ...) returning the realised bias
#                      measure + verdict; validate_approximation()
#                      dispatches here. Must be a function.
#   fallback_hint      one-string guidance on the exact-route fallback
#                      to offer when validation fails. Must be a single
#                      string.
#   registered_in_adr  the ADR number the scheme traces to (e.g.,
#                      "0027"). Free-form provenance; does not gate
#                      registration. Must be a single string.
#
# Returns invisible NULL. Side effect: assign to
# .approximation_registry.
.register_approximation <- function(scheme,
                                     bias_bound,
                                     validation_fn,
                                     fallback_hint,
                                     registered_in_adr) {

  if (!is.character(scheme) || length(scheme) != 1L || !nzchar(scheme))
    stop(".register_approximation(): `scheme` must be a non-empty ",
         "single string.", call. = FALSE)
  if (!is.list(bias_bound))
    stop(".register_approximation(): `bias_bound` must be a list.",
         call. = FALSE)
  if (!is.function(validation_fn))
    stop(".register_approximation(): `validation_fn` must be a ",
         "function of (fit, ...).", call. = FALSE)
  if (!is.character(fallback_hint) || length(fallback_hint) != 1L)
    stop(".register_approximation(): `fallback_hint` must be a single ",
         "string.", call. = FALSE)
  if (!is.character(registered_in_adr) ||
      length(registered_in_adr) != 1L)
    stop(".register_approximation(): `registered_in_adr` must be a ",
         "single string.", call. = FALSE)

  if (environmentIsLocked(.approximation_registry))
    stop(".register_approximation(): approximation registry is ",
         "locked; new schemes must be registered before ",
         ".lock_approximation_registry() fires at end of .onLoad().",
         call. = FALSE)

  if (exists(scheme, envir = .approximation_registry,
             inherits = FALSE))
    stop(".register_approximation(): scheme '", scheme, "' is already ",
         "registered. Approximation vocabulary is append-only; use a ",
         "distinct name for new schemes.", call. = FALSE)

  assign(scheme,
         list(
           scheme            = scheme,
           bias_bound        = bias_bound,
           validation_fn     = validation_fn,
           fallback_hint     = fallback_hint,
           registered_in_adr = registered_in_adr
         ),
         envir = .approximation_registry)

  invisible(NULL)
}


# --- accessor: full entry ----------------------------------------- #

# .lookup_approximation() --- internal accessor returning the full
# registered entry list. Refuses with a structured error if `scheme`
# is not registered; the known-schemes hint names the current
# vocabulary (empty at this substrate step). This is the refusal that
# validate_approximation.default() surfaces as
# `approximation_scheme_unknown` once the export lands.
.lookup_approximation <- function(scheme) {
  if (!is.character(scheme) || length(scheme) != 1L || !nzchar(scheme))
    stop(".lookup_approximation(): `scheme` must be a non-empty ",
         "single string.", call. = FALSE)
  if (!exists(scheme, envir = .approximation_registry,
              inherits = FALSE)) {
    known <- sort(ls(envir = .approximation_registry,
                     all.names = FALSE))
    stop(".lookup_approximation(): '", scheme, "' is not a registered ",
         "approximation scheme. Known schemes: ",
         if (length(known)) paste(known, collapse = ", ") else
           "(none registered yet)",
         ".", call. = FALSE)
  }
  get(scheme, envir = .approximation_registry, inherits = FALSE)
}


# --- accessor: validated scheme string ---------------------------- #

# .approximation_scheme() --- thin convenience returning the validated
# scheme name back. The edit-light replacement for inline scheme
# string literals at consumer sites, trading a single character of
# verbosity for vocabulary-lock enforcement (the same pattern as
# .representation_class()).
.approximation_scheme <- function(scheme) {
  .lookup_approximation(scheme)$scheme
}


# --- lock helper -------------------------------------------------- #

# .lock_approximation_registry() --- locks the environment so no
# further .register_approximation() calls or user-side assign()s can
# mutate it. Called once at the end of .onLoad(). The lock is enforced
# by R's environmentIsLocked() machinery; schemes registered before
# the lock remain readable indefinitely.
.lock_approximation_registry <- function() {
  if (!environmentIsLocked(.approximation_registry))
    lockEnvironment(.approximation_registry, bindings = TRUE)
  invisible(NULL)
}
