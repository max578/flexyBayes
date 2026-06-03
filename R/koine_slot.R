# koine_slot.R -- the dormant 4th-backend slot for koine, the synthesised
# fourth opinion on the orthogonal lens axis (CONSTELLATION.md contracts C1 +
# C3; the constellation's Leader direction item 2).
#
# This is the constellation's "dormant-but-correct activation" pattern
# (CONSTELLATION.md invariant 6), mirroring what R/gretaR_slot.R was before the
# 2026-06-02 gretaR activation: koine is registered in the backend registry
# (`R/backend_registry.R`, status = "dormant") and the canonical-name registry
# (`R/canonical_names.R`), but is NOT advertised on any user-facing `backend`
# argument. Every internal path that would dispatch to koine raises a structured
# `koine_dormant_refusal` naming the dormancy reason + the activation procedure.
#
# Unlike gretaR (an engine-axis HMC backend), koine's value is ORTHOGONAL-LENS
# diversity -- it is the synthesised fourth opinion `triangulate()` consumes,
# graded on the lens axis (ADR 0029), and it owns the Stage-0 koine_pass /
# koine_result data contract (C3). The slot here is its C1 backend seam: a
# draws-producing engine flexyBayes can triangulate against once koine's
# programmatic, re-entrant builder is confirmed against backend_contract.md
# clause 1 (the C1 conformance battery -- add a koine descriptor to
# .conformance_backends() in tests/testthat/test-backend-conformance.R).
#
# Activation is a small deliberate edit, the gretaR flip in reverse-engineered
# form: register koine's real emit + capability predicate, swap the mapper stub
# below for the real mapper, replace the dispatch refusal branch
# (R/dispatch.R) with a live emit branch, and move the registry entry
# dormant -> active. The single source of truth for activation state is the
# option `flexyBayes.koine_activated`, queried here only.

# Minimum koine version carrying a programmatic, re-entrant builder confirmed
# against backend_contract.md clause 1 + the Stage-0 koine_pass/koine_result
# contract. koine is 0.0.0.9000 today; this floor is the activation gate, not a
# claim it is met.
.KOINE_VERSION_FLOOR <- "0.1.0"

# ---------------------------------------------------------------- #
# Activation state introspection                                    #
# ---------------------------------------------------------------- #

# Resolve the current dormancy reason for the koine slot. Returns one of the
# documented sentinels; consumed by the dispatch refusal, the canonical-name
# mapper stub, and koine_status().
.koine_dormancy_reason <- function() {
  activated <- isTRUE(getOption("flexyBayes.koine_activated", FALSE))
  installed <- nzchar(system.file(package = "koine"))
  if (!installed) {
    return("koine_not_installed")
  }
  if (!activated) {
    return("slot_provisioned_not_activated")
  }
  # Reachable only when the activation boolean is TRUE but no C1 clause-1
  # confirmation mechanism has been wired yet (mirrors gretaR's pre-activation
  # not_audit_clean state): the builder has not been confirmed against the
  # conformance battery, so the slot stays dormant.
  "koine_builder_unconfirmed"
}

# Capability flag appended by lgm_gate() to an LGM-compatible IR. Always the
# dormant flag until activation flips the registry entry + a clause-1
# confirmation mechanism agrees.
.koine_slot_capability <- function() {
  if (identical(.koine_dormancy_reason(), "koine_dispatch_eligible")) {
    "koine_dispatch_eligible"
  } else {
    "koine_slot_dormant"
  }
}

# Standard activation procedure -- documented in one place so the dispatch
# refusal, the canonical-name stub, and koine_status() surface the same steps.
.koine_activation_procedure <- function() {
  c(
    paste0(
      "Confirm koine's programmatic, re-entrant model builder against ",
      "backend_contract.md clause 1 -- add a koine descriptor to ",
      ".conformance_backends() in test-backend-conformance.R and pass clauses ",
      "1-5."
    ),
    paste0(
      "Install the koine package (>= ",
      .KOINE_VERSION_FLOOR,
      ", the version ",
      "carrying that builder + the Stage-0 koine_pass/koine_result contract)."
    ),
    "Run options(flexyBayes.koine_activated = TRUE) in the session."
  )
}


# ---------------------------------------------------------------- #
# Canonical-name mapper stub                                        #
# ---------------------------------------------------------------- #
# Registered into .canonical_mappers under the key "koine" at package load.
# Returns the scaffold-dormant sentinel so triangulate() short-circuits cleanly
# against a (currently impossible) koine fit.

.mapper_koine_stub <- function(fit, fb_terms) {
  list(
    map = character(0),
    transform = list(),
    source = "scaffold_dormant",
    dormancy_reason = .koine_dormancy_reason()
  )
}


# ---------------------------------------------------------------- #
# Registry capability predicate (dormant)                           #
# ---------------------------------------------------------------- #
# The backend registry stores this as koine's capability_predicate. While the
# slot is dormant it refuses every model with the dormancy flag, so a stray
# dispatch can never silently produce a wrong fit -- it is caught by the
# capability gate before the dispatch refusal even fires.

.capability_koine_dormant <- function(fb) {
  .koine_slot_capability()
}


# ---------------------------------------------------------------- #
# Exported helper                                                   #
# ---------------------------------------------------------------- #

#' Introspect the koine backend slot
#'
#' Returns the activation state of the koine backend slot plus the procedure to
#' activate it. koine is the synthesised fourth opinion on flexyBayes's
#' orthogonal lens axis (the constellation's C1 + C3 contracts); its slot is
#' provisioned but dormant until koine ships a programmatic, re-entrant model
#' builder confirmed against the backend contract. Until then this helper is the
#' canonical discoverability surface -- users who see "koine" referenced in the
#' constellation charter or the backend contract can call `koine_status()` to
#' inspect why the slot is dormant and how to wake it.
#'
#' @return A list with components:
#'   \describe{
#'     \item{`activated`}{Logical: `TRUE` only when
#'       `options(flexyBayes.koine_activated)` is set AND a clause-1
#'       confirmation mechanism has cleared. Currently always `FALSE`.}
#'     \item{`koine_installed`}{Logical: result of
#'       `nzchar(system.file(package = "koine"))`.}
#'     \item{`builder_confirmed`}{Logical or `NA`: whether koine's builder has
#'       been confirmed against backend-contract clause 1. Currently always
#'       `NA` (no confirmation mechanism shipped).}
#'     \item{`dormancy_reason`}{Character: one of
#'       `"koine_not_installed"`, `"slot_provisioned_not_activated"`,
#'       `"koine_builder_unconfirmed"`, or `"koine_dispatch_eligible"` (the
#'       last meaning the slot is fully active).}
#'     \item{`activation_procedure`}{Character vector: numbered steps to
#'       activate the slot, in order.}
#'   }
#'
#' @examples
#' ks <- koine_status()
#' ks$activated         # FALSE
#' ks$dormancy_reason   # "koine_not_installed" or
#'                      # "slot_provisioned_not_activated"
#' cat(ks$activation_procedure, sep = "\n")
#'
#' @seealso [gretaR_status()] for the engine-axis sibling slot.
#' @export
koine_status <- function() {
  installed <- nzchar(system.file(package = "koine"))
  reason <- .koine_dormancy_reason()
  fully_active <- identical(reason, "koine_dispatch_eligible")
  list(
    activated = fully_active,
    koine_installed = installed,
    builder_confirmed = NA,
    dormancy_reason = reason,
    activation_procedure = .koine_activation_procedure()
  )
}


# ---------------------------------------------------------------- #
# Dispatch refusal constructor                                      #
# ---------------------------------------------------------------- #
# Called from .dispatch_backend() (R/dispatch.R) when the internal value
# backend = "koine" reaches the dispatch branch. The branch is unreachable from
# user-facing entries (match.arg rejects "koine"); reachable only from internal
# callers + tests. Activation replaces the branch body with the real
# emit_koine() call; this helper is removed at that time.

.koine_dormant_refusal <- function(call = NULL) {
  reason <- .koine_dormancy_reason()
  proc <- .koine_activation_procedure()
  msg <- paste0(
    "The koine backend slot is currently dormant (reason: ",
    reason,
    "). koine is the synthesised fourth opinion on the orthogonal lens axis; ",
    "its slot is provisioned but not yet activated. Recommended fallback: use ",
    "an active engine (backend = \"greta\" / \"inla\" / \"brms\" / ",
    "\"gretaR\"). Activation procedure:\n",
    paste0("  ", seq_along(proc), ". ", proc, collapse = "\n")
  )
  cond <- structure(
    class = c("koine_dormant_refusal", "error", "condition"),
    list(
      message = msg,
      call = call,
      dormancy_reason = reason,
      activation_procedure = proc
    )
  )
  stop(cond)
}


# ---------------------------------------------------------------- #
# Package-load registration                                         #
# ---------------------------------------------------------------- #
# Sourced after R/canonical_names.R (alphabetic 'k' > 'c'), so the
# .canonical_mappers registry + register_canonical_mapper() are defined by the
# time this line runs. Activation: replace .mapper_koine_stub with the real
# .mapper_koine in one place here.

register_canonical_mapper("koine", .mapper_koine_stub)
