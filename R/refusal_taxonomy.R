# Refusal registry --- scaffold only at v0.3.8 (ADR 0030 C7)
#
# Container + registration helper for the canonical refusal-reason
# vocabulary. Empty at v0.3.8: this release ships the registry
# infrastructure without converting the ~30 existing refusal sites
# scattered through dispatch.R, lgm_gate.R, structured_cov.R, and
# emit_inla.R. Full population (one .register_refusal() call per
# existing site) + the user-facing fb_refusals() accessor land at
# v0.4.0.
#
# Rationale (v038-plan-2026-05-25 section 5.2):
#
#   "The deliberate choice here is to ship the container without the
#    migration risk of touching ~30 existing refusal sites in one
#    release."
#
# The registry is an environment (not a list) so .register_refusal()
# can write idempotently without copy-on-modify cost; locked at the
# end of .onLoad() so user-side assign() raises a contract violation.

# --- container ---------------------------------------------------- #

# `.refusal_registry` is allocated at namespace load. The parent
# environment is `emptyenv()` so symbol lookup cannot accidentally
# fall through to the package namespace and pick up an unrelated
# binding. Filled by .register_refusal() during .onLoad() (currently
# zero calls --- the scaffold-only posture); locked immediately
# after by .lock_refusal_registry().
.refusal_registry <- new.env(parent = emptyenv())


# --- registration helper ------------------------------------------ #

# .register_refusal() --- the one-shot registration call. Idempotent
# only in the sense that a duplicate reason_code raises rather than
# silently overwriting; intentional refusals (the v0.4.0 migration)
# fire once per reason at .onLoad() time and the registry then
# locks.
#
# Arguments
#   reason_code        canonical machine-readable identifier; the
#                      same string that appears on the structured
#                      condition object thrown by the refusal site.
#                      Must be a single non-empty string.
#   description        one-line human-readable description; what the
#                      refusal means in plain language.
#   message_template   the template string used to render the
#                      message; conventionally uses base::sprintf()
#                      placeholders so the refusal site can fill in
#                      the data-specific slots.
#   registered_in_adr  the ADR number the refusal traces to (e.g.,
#                      "ADR 0024" for the routing-policy refusals,
#                      "ADR 0025" for the structured-cov refusals).
#                      Free-form; this field documents provenance,
#                      it does not gate registration.
#   plan_field         optional name of the <fb_plan> slot that
#                      surfaces this refusal at plan time (e.g.,
#                      "rejected_routes"). NA_character_ if the
#                      refusal is not surfaced by fb_plan() (e.g.,
#                      runtime-only refusals).
#   since_version      the flexyBayes version the refusal was
#                      introduced; useful for backward-compat
#                      audits.
#
# Returns invisible NULL. Side effect: assign to .refusal_registry.
.register_refusal <- function(reason_code,
                              description,
                              message_template,
                              registered_in_adr,
                              plan_field    = NA_character_,
                              since_version) {

  if (!is.character(reason_code) || length(reason_code) != 1L ||
      !nzchar(reason_code))
    stop(".register_refusal(): `reason_code` must be a non-empty ",
         "single string.", call. = FALSE)
  if (!is.character(description) || length(description) != 1L)
    stop(".register_refusal(): `description` must be a single ",
         "string.", call. = FALSE)
  if (!is.character(message_template) || length(message_template) != 1L)
    stop(".register_refusal(): `message_template` must be a single ",
         "string.", call. = FALSE)
  if (!is.character(registered_in_adr) || length(registered_in_adr) != 1L)
    stop(".register_refusal(): `registered_in_adr` must be a single ",
         "string.", call. = FALSE)
  if (!is.character(plan_field) || length(plan_field) != 1L)
    stop(".register_refusal(): `plan_field` must be a single string ",
         "(use NA_character_ for unsurfaced refusals).", call. = FALSE)
  if (!is.character(since_version) || length(since_version) != 1L ||
      !nzchar(since_version))
    stop(".register_refusal(): `since_version` must be a non-empty ",
         "single string.", call. = FALSE)

  if (environmentIsLocked(.refusal_registry))
    stop(".register_refusal(): refusal registry is locked; new ",
         "entries must be registered before .lock_refusal_registry() ",
         "fires at end of .onLoad().", call. = FALSE)

  if (exists(reason_code, envir = .refusal_registry, inherits = FALSE))
    stop(".register_refusal(): reason_code '", reason_code, "' is ",
         "already registered. Refusal vocabulary is append-only; ",
         "use a distinct reason_code for new refusals.", call. = FALSE)

  assign(reason_code,
         list(
           reason_code        = reason_code,
           description        = description,
           message_template   = message_template,
           registered_in_adr  = registered_in_adr,
           plan_field         = plan_field,
           since_version      = since_version
         ),
         envir = .refusal_registry)

  invisible(NULL)
}


# --- accessor ----------------------------------------------------- #

# .lookup_refusal() --- internal accessor for refusal sites that
# want to consult the registry for a description or message template.
# Returns the registered entry list, or NULL if the reason_code is
# not yet registered (the v0.3.8 scaffold-only state returns NULL
# for every code). Callers must tolerate NULL --- the legacy
# inline-message refusal sites continue to function untouched.
.lookup_refusal <- function(reason_code) {
  if (!is.character(reason_code) || length(reason_code) != 1L ||
      !nzchar(reason_code))
    return(NULL)
  if (!exists(reason_code, envir = .refusal_registry, inherits = FALSE))
    return(NULL)
  get(reason_code, envir = .refusal_registry, inherits = FALSE)
}


# --- v0.3.10 registry population (ADR 0025 Decisions 3 + 4) ------ #

# .populate_refusal_registry_v0310() --- the first migration of
# existing refusal sites into the v0.3.8 C7 scaffold. Called from
# .onLoad() *before* .lock_refusal_registry() so the entries are
# in place when user code first observes the registry.
#
# Three reason codes register at v0.3.10:
#
#   block_partition_incomplete         --- ADR 0025 D3 (blocks
#                                          structural refusal: sum of
#                                          block sizes != grouping
#                                          factor level count).
#   block_not_positive_definite        --- ADR 0025 D3 (blocks
#                                          structural refusal: at
#                                          least one V_k fails the
#                                          PD probe; the offending
#                                          block index is named in
#                                          the message text).
#   approximate_route_not_yet_registered --- ADR 0025 D4 + ADR 0027
#                                            (low-rank refusal-stub
#                                            upgrade naming
#                                            validate_approximation()
#                                            as the v0.4.0 Wave 1
#                                            Phase 1B forward export).
#
# Forward pattern: the v0.4.0 Wave 1 Phase 1C bulk migration moves
# the ~28 remaining inline-message refusal sites into this scaffold
# using the same .register_refusal() call shape.
.populate_refusal_registry_v0310 <- function() {
  .register_refusal(
    reason_code        = "block_partition_incomplete",
    description        = paste0(
      "Block-diagonal vm/ped: the block sizes do not partition ",
      "the grouping factor's level count."),
    message_template   = paste0(
      "vm(%s, blocks = %s): block sizes (%s = %d) do not match ",
      "levels(`%s`) (%d levels)."),
    registered_in_adr  = "ADR 0025",
    plan_field         = "representation_plan",
    since_version      = "0.3.10"
  )
  .register_refusal(
    reason_code        = "block_not_positive_definite",
    description        = paste0(
      "Block-diagonal vm/ped: at least one V_k failed the ",
      "positive-definite probe."),
    message_template   = paste0(
      "vm(%s, blocks = %s): block %d failed the PD probe (size ",
      "%d x %d)."),
    registered_in_adr  = "ADR 0025",
    plan_field         = "representation_plan",
    since_version      = "0.3.10"
  )
  .register_refusal(
    reason_code        = "approximate_route_not_yet_registered",
    description        = paste0(
      "Approximate covariance / dispatch carriers refuse until the ",
      "ADR 0027 approximation registry ships at v0.4.0 ",
      "(validate_approximation())."),
    message_template   = paste0(
      "vm(%s, low_rank_factor = %s, low_rank_scheme = '%s'): ",
      "low-rank carriers require validate_approximation() (v0.4.0)."),
    registered_in_adr  = "ADR 0025+0027",
    plan_field         = "representation_plan",
    since_version      = "0.3.10"
  )
  invisible(NULL)
}


# --- lock helper -------------------------------------------------- #

# .lock_refusal_registry() --- locks the environment so no further
# .register_refusal() calls or user-side assign()s can mutate it.
# Called once at the end of .onLoad(). The lock is enforced by R's
# environmentIsLocked() machinery; bindings registered before the
# lock remain readable indefinitely.
.lock_refusal_registry <- function() {
  if (!environmentIsLocked(.refusal_registry))
    lockEnvironment(.refusal_registry, bindings = TRUE)
  invisible(NULL)
}
