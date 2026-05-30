# Backend registry (ADR 0031; v0.5.0 backend-axis recovery, Phase 1).
#
# The fifth closed-vocabulary registry, alongside representation
# (R/representation_registry.R), approximation (R/approximation_registry.R),
# backend-independence (R/backend_independence_registry.R), and refusal
# (R/refusal_taxonomy.R). It models *backend* as a first-class axis
# rather than a value hard-coded into each verb's match.arg vocabulary
# and into .routing_policy_table(). ADR 0030 built the package's whole
# architecture on "extend by registration, not by API growth" but left
# backend the one concept still hard-coded (ADR 0030 SS7 deferred the
# backend roster to per-backend ADRs); ADR 0031 supplies the registry
# that philosophy always implied.
#
# Same shape as the other four registries: an environment allocated at
# namespace load, filled by .register_backend() during .onLoad(), locked
# immediately after by .lock_backend_registry(). parent = emptyenv() so a
# key miss cannot fall through to the package namespace.
#
# PHASE BOUNDARY (honest scoping). This Phase-1 registry is *additive and
# behaviour-neutral*: it is the single source of truth for legitimate
# backend names and their metadata, and a consistency test (test-backend-
# registry.R) proves the existing hard-coded routing references no
# unregistered engine. It does NOT yet drive dispatch. Two fields named in
# ADR 0031 are deliberately deferred to later phases, openly (not silently):
#   - `capability_predicate` -- the per-backend "can this engine represent
#     this model?" function that REPLACES the current special-cased gates
#     (low_rank_requires_greta, at_units, the lgm_gate rules) lands in
#     Phase 2, where dispatch switches to consume it.
#   - the user-facing "brms" -> "stan" engine rename lands in Phase 3 with
#     a lifecycle deprecation window. Phase 1 registers the engine under
#     its CURRENT dispatch label "brms" so routing is byte-for-byte
#     unchanged; `rename_to` records the Phase-3 target for traceability.
#
# Internal -- not exported.

# --- closed status vocabulary ------------------------------------- #

# A backend entry is one of three lifecycle states. `active` backends are
# reachable today; `dormant` backends have a provisioned but inactive
# slot (gretaR per ADR 0013 -- see R/gretaR_slot.R) and refuse at
# dispatch until activated; `reserved` is documentation-only and not
# registered here (NIMBLE is the reserved next slot; it has no slot yet,
# so registering it would be a stub -- it is named in this comment
# instead). The vocabulary is closed; a new state requires an ADR 0031
# amendment.
.BACKEND_STATUS_VOCABULARY <- c("active", "dormant")

# The grammars a backend can ingest-and-fit. A formula model (asreml or
# brms/lme4 dialect) lowers to the shared fb_terms IR and can target any
# formula-capable engine subject to capability; a native greta model
# graph (the "greta" grammar) is greta-only by construction. Closed
# vocabulary mirrored from the ingest-adapter family (fb_from_asreml /
# fb_from_brms / fb_from_greta).
.BACKEND_GRAMMAR_VOCABULARY <- c("asreml", "brms", "greta")

# --- container ---------------------------------------------------- #

.backend_registry <- new.env(parent = emptyenv())

# --- registration helper ------------------------------------------ #

# .register_backend() --- the one-shot registration call. Validates the
# status + grammar vocabularies (an unknown value is a hard error naming
# the offender), refuses a duplicate, refuses once the registry is
# locked. Field schema:
#   name            chr(1)  canonical backend name (the routing label).
#   status          chr(1)  one of .BACKEND_STATUS_VOCABULARY.
#   engine          chr(1)  emit entry-point function name, or NA for a
#                           dormant backend (resolved lazily at dispatch;
#                           stored as a name string, not a closure, so a
#                           load-time reference cannot fail).
#   grammars        chr     subset of .BACKEND_GRAMMAR_VOCABULARY.
#   paradigm        chr(1)  inference-paradigm label (aligns with the
#                           backend-independence registry's paradigms).
#   available_pkg   chr(1)  the R package whose presence makes the
#                           backend usable, or NA (dormant / always-on).
#   default_in_auto lgl(1)  whether `auto` considers it by default.
#   rename_to       chr(1)  Phase-3 user-facing rename target, or NA.
#   registered_in_adr chr(1)
.register_backend <- function(name, status, engine, grammars, paradigm,
                              available_pkg, default_in_auto,
                              rename_to = NA_character_,
                              registered_in_adr = "0031") {
  # Validate inputs before checking mutability, so a caller passing an
  # unknown status / grammar sees the actionable vocabulary error rather
  # than a lock error even on a loaded (locked) package.
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !nzchar(name))
    stop(".register_backend(): `name` must be a single non-empty string.",
         call. = FALSE)
  if (!identical(length(status), 1L) ||
      !status %in% .BACKEND_STATUS_VOCABULARY)
    stop(".register_backend(): unknown status '", status,
         "'. The closed vocabulary is ",
         paste(.BACKEND_STATUS_VOCABULARY, collapse = ", "),
         "; expanding it requires an ADR 0031 amendment.", call. = FALSE)
  unknown_g <- setdiff(grammars, .BACKEND_GRAMMAR_VOCABULARY)
  if (length(unknown_g) > 0L)
    stop(".register_backend(): unknown grammar ",
         paste0("'", unknown_g, "'", collapse = ", "),
         ". The closed vocabulary is ",
         paste(.BACKEND_GRAMMAR_VOCABULARY, collapse = ", "), ".",
         call. = FALSE)
  if (!is.logical(default_in_auto) || length(default_in_auto) != 1L ||
      is.na(default_in_auto))
    stop(".register_backend(): `default_in_auto` must be TRUE or FALSE.",
         call. = FALSE)

  if (environmentIsLocked(.backend_registry))
    stop(".register_backend(): the backend registry is locked; ",
         "backends must be registered before .lock_backend_registry() ",
         "fires at end of .onLoad().", call. = FALSE)

  if (exists(name, envir = .backend_registry, inherits = FALSE))
    stop(".register_backend(): backend '", name, "' is already ",
         "registered. Backend vocabulary is append-only.", call. = FALSE)

  assign(name,
         list(
           name              = name,
           status            = status,
           engine            = engine,
           grammars          = grammars,
           paradigm          = paradigm,
           available_pkg     = available_pkg,
           default_in_auto   = default_in_auto,
           rename_to         = rename_to,
           registered_in_adr = registered_in_adr
         ),
         envir = .backend_registry)

  invisible(NULL)
}

# --- accessors ---------------------------------------------------- #

# .lookup_backend() --- internal accessor returning the full entry, or
# NULL when the name is not registered.
.lookup_backend <- function(name) {
  if (!is.character(name) || length(name) != 1L || is.na(name) ||
      !exists(name, envir = .backend_registry, inherits = FALSE))
    return(NULL)
  get(name, envir = .backend_registry, inherits = FALSE)
}

# .registered_backend_names() --- every registered backend name (any
# status), sorted for determinism.
.registered_backend_names <- function() {
  sort(ls(envir = .backend_registry, all.names = FALSE))
}

# .available_backend_names() --- the active backends whose required
# package is installed (NA available_pkg means always-on). Dormant
# backends are excluded. This is the candidate set the universal entry
# will default to in Phase 2; in Phase 1 it is read only by the
# consistency test.
.available_backend_names <- function() {
  out <- character(0)
  for (nm in .registered_backend_names()) {
    e <- .lookup_backend(nm)
    if (!identical(e$status, "active")) next
    ok <- is.na(e$available_pkg) ||
      requireNamespace(e$available_pkg, quietly = TRUE)
    if (ok) out <- c(out, nm)
  }
  out
}

# .auto_default_backend_names() --- registered backends flagged for
# auto's default candidate set (any status; dormant ones are filtered by
# availability at dispatch). Mirrors the current dispatch candidate list.
.auto_default_backend_names <- function() {
  out <- character(0)
  for (nm in .registered_backend_names()) {
    e <- .lookup_backend(nm)
    if (isTRUE(e$default_in_auto)) out <- c(out, nm)
  }
  sort(out)
}

# --- lock --------------------------------------------------------- #

.lock_backend_registry <- function() {
  if (!environmentIsLocked(.backend_registry))
    lockEnvironment(.backend_registry, bindings = TRUE)
  invisible(NULL)
}

# --- v0.5.0 population --------------------------------------------- #

# .populate_backend_registry_v050() --- registers the three active
# backends reachable today plus the dormant gretaR slot. Names + labels
# mirror the CURRENT dispatch reality (engine "brms" not yet renamed to
# "stan"; rename lands Phase 3) so this phase is byte-for-byte behaviour-
# neutral. `default_in_auto` encodes the current candidate list
# c("inla", "greta", "gretaR") from .resolve_routing(): greta + inla +
# gretaR are auto-considered, brms is opt-in only (its 30--60 s Stan
# compile would break the auto fast-path promise -- ADR 0024).
.populate_backend_registry_v050 <- function() {
  .register_backend(
    name = "greta", status = "active", engine = "emit_greta",
    grammars = c("asreml", "brms", "greta"), paradigm = "hmc_nuts",
    available_pkg = "greta", default_in_auto = TRUE)
  .register_backend(
    name = "inla", status = "active", engine = "emit_inla",
    grammars = c("asreml", "brms"), paradigm = "laplace_approximation",
    available_pkg = "INLA", default_in_auto = TRUE)
  .register_backend(
    name = "brms", status = "active", engine = "emit_brms",
    grammars = c("asreml", "brms"), paradigm = "hmc_nuts",
    available_pkg = "brms", default_in_auto = FALSE,
    rename_to = "stan")
  .register_backend(
    name = "gretaR", status = "dormant", engine = NA_character_,
    grammars = "greta", paradigm = "hmc_nuts",
    available_pkg = NA_character_, default_in_auto = TRUE,
    registered_in_adr = "0013/0031")
  invisible(NULL)
}
