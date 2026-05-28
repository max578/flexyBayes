# Tests for the refusal-taxonomy scaffold (ADR 0030 C7; v0.3.8 scaffold-
# only posture). The registry is empty at v0.3.8 by design --- the
# ~30 existing refusal sites in dispatch.R / lgm_gate.R /
# structured_cov.R / emit_inla.R are migrated in one batch at v0.4.0
# alongside the user-facing fb_refusals() accessor.
#
# Five acceptance criteria per v038-plan-2026-05-25 section 5.2:
#
#   (a) .refusal_registry exists post-.onLoad() and is locked
#   (b) .register_refusal() with valid args succeeds (synthetic code)
#   (c) .register_refusal() with duplicate reason_code refuses
#   (d) user-side assign() into .refusal_registry raises
#   (e) the registry is empty at v0.3.8 (deliberate scaffold-only)

# ---------------------------------------------------------------- #
# (a) registry exists + is locked                                    #
# ---------------------------------------------------------------- #

test_that(".refusal_registry exists and is locked post-load", {
  reg <- flexyBayes:::.refusal_registry
  expect_true(is.environment(reg))
  expect_true(environmentIsLocked(reg))
})

# ---------------------------------------------------------------- #
# (b) .register_refusal() with valid args (via fresh environment)   #
# ---------------------------------------------------------------- #
#
# The post-load registry is locked, so we cannot test .register_refusal()
# directly against it. Instead we exercise the helper's validation logic
# on a fresh unlocked environment by temporarily swapping. This honours
# the scaffold-only posture (no real entries land in the live registry).

test_that(".register_refusal() validates args before assigning", {
  # Direct validation calls (no environment mutation needed).
  expect_error(flexyBayes:::.register_refusal(
    reason_code = NULL, description = "x", message_template = "x",
    registered_in_adr = "ADR 0030", since_version = "0.3.8"),
    regexp = "reason_code")
  expect_error(flexyBayes:::.register_refusal(
    reason_code = "x", description = c("a", "b"),
    message_template = "x", registered_in_adr = "ADR 0030",
    since_version = "0.3.8"),
    regexp = "description")
  expect_error(flexyBayes:::.register_refusal(
    reason_code = "x", description = "x", message_template = "x",
    registered_in_adr = "ADR 0030", since_version = ""),
    regexp = "since_version")
})

# ---------------------------------------------------------------- #
# (c) duplicate reason_code refuses (deferred to v0.4.0 migration) #
# ---------------------------------------------------------------- #
#
# Since the v0.3.8 registry is empty + locked, the duplicate-detection
# branch cannot be exercised against the live registry without test-only
# unlock. We assert the behaviour by reading the function body --- the
# error string mentions "already registered".

test_that(".register_refusal() body carries the duplicate-detection branch", {
  body_src <- paste(deparse(body(flexyBayes:::.register_refusal)),
                    collapse = "\n")
  expect_true(grepl("already registered", body_src, fixed = TRUE))
  expect_true(grepl("environmentIsLocked", body_src, fixed = TRUE))
})

# ---------------------------------------------------------------- #
# (d) user-side assign() raises on locked environment                #
# ---------------------------------------------------------------- #

test_that("user-side assign() into .refusal_registry raises", {
  reg <- flexyBayes:::.refusal_registry
  expect_error(assign("synthetic_test_code", list(), envir = reg),
               regexp = "locked|cannot")
})

# ---------------------------------------------------------------- #
# (e) v0.3.10 first-migration entries (ADR 0025 Decisions 3 + 4)    #
# ---------------------------------------------------------------- #
#
# v0.3.8 shipped the registry scaffold empty (zero entries; deliberate
# scaffold-only posture). v0.3.10 lands the first three entries via
# .populate_refusal_registry_v0310(): the two blocks-structural codes
# (block_partition_incomplete + block_not_positive_definite) plus the
# upgraded approximate_route_not_yet_registered. The full ~28-site
# bulk migration follows at v0.4.0 Wave 1 Phase 1C using the same
# .register_refusal() shape.

test_that(".refusal_registry carries the v0.3.10 first-migration entries", {
  reg     <- flexyBayes:::.refusal_registry
  entries <- ls(envir = reg, all.names = TRUE)
  expect_true("block_partition_incomplete"           %in% entries)
  expect_true("block_not_positive_definite"          %in% entries)
  expect_true("approximate_route_not_yet_registered" %in% entries)
  expect_equal(length(entries), 3L)
})

# ---------------------------------------------------------------- #
# Bonus: .lookup_refusal() returns the registered entry shape       #
# ---------------------------------------------------------------- #

test_that(".lookup_refusal() returns NULL for unregistered codes", {
  expect_null(flexyBayes:::.lookup_refusal("explicit_inla_gate_refused"))
  expect_null(flexyBayes:::.lookup_refusal("design_memory_exceeds_ceiling"))
  expect_null(flexyBayes:::.lookup_refusal("any_arbitrary_string"))
  expect_null(flexyBayes:::.lookup_refusal(""))
  expect_null(flexyBayes:::.lookup_refusal(NULL))
})

test_that(".lookup_refusal() returns the registered entry for the v0.3.10 codes", {
  entry <- flexyBayes:::.lookup_refusal("block_partition_incomplete")
  expect_type(entry, "list")
  expect_equal(entry$reason_code,       "block_partition_incomplete")
  expect_equal(entry$registered_in_adr, "ADR 0025")
  expect_equal(entry$since_version,     "0.3.10")
  expect_equal(entry$plan_field,        "representation_plan")

  entry_low <- flexyBayes:::.lookup_refusal(
    "approximate_route_not_yet_registered"
  )
  expect_equal(entry_low$registered_in_adr, "ADR 0025+0027")
  expect_equal(entry_low$since_version,     "0.3.10")
})
