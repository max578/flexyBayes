# Tests for the approximation registry --- ADR 0030 C5 + ADR 0027
# (v0.4.0 Wave 1 Phase 1A substrate). The registry formalises the
# approximation-scheme vocabulary into a single locked
# .approximation_registry container at .onLoad(). Scaffold-only at
# this step: the container, the .register_approximation() /
# .lookup_approximation() / .approximation_scheme() helpers, and the
# lock helper ship empty; the first scheme (low_rank_smooth) populates
# together with its emit path + validate_approximation() export. All
# helpers are internal.
#
# Nine acceptance criteria:
#
#   (a) .approximation_registry exists post-.onLoad() and is locked
#   (b) the registry is empty at the scaffold step
#   (c) .register_approximation() validates its five-field schema
#   (d) .register_approximation() refuses when the registry is locked
#   (e) .lookup_approximation() refuses an unknown scheme
#   (f) .lookup_approximation() refuses non-string input
#   (g) .approximation_scheme() refuses an unknown scheme
#   (h) user-side assign() into the locked registry raises
#   (i) snapshot test on the (empty) registered vocabulary

# ---------------------------------------------------------------- #
# (a) registry exists + is locked                                   #
# ---------------------------------------------------------------- #

test_that(".approximation_registry exists and is locked post-load", {
  reg <- flexyBayes:::.approximation_registry
  expect_true(is.environment(reg))
  expect_true(environmentIsLocked(reg))
})

# ---------------------------------------------------------------- #
# (b) registry is empty at the scaffold step                        #
# ---------------------------------------------------------------- #

test_that("the approximation registry is empty at the scaffold step", {
  reg <- flexyBayes:::.approximation_registry
  expect_length(ls(envir = reg, all.names = FALSE), 0L)
})

# ---------------------------------------------------------------- #
# (c) .register_approximation() validates the five-field schema     #
# ---------------------------------------------------------------- #
#
# The post-load registry is locked, so we exercise the validation
# logic by passing bad arguments. Validation fires before the lock
# check, so these errors surface even with a locked registry.

test_that(".register_approximation() validates inputs", {
  ok_bias <- list(type = "analytical")
  ok_fn   <- function(fit, ...) TRUE
  expect_error(flexyBayes:::.register_approximation(
    scheme = "", bias_bound = ok_bias, validation_fn = ok_fn,
    fallback_hint = "x", registered_in_adr = "0027"),
    regexp = "`scheme` must be a non-empty single string")
  expect_error(flexyBayes:::.register_approximation(
    scheme = "s", bias_bound = "not a list", validation_fn = ok_fn,
    fallback_hint = "x", registered_in_adr = "0027"),
    regexp = "`bias_bound` must be a list")
  expect_error(flexyBayes:::.register_approximation(
    scheme = "s", bias_bound = ok_bias, validation_fn = 42L,
    fallback_hint = "x", registered_in_adr = "0027"),
    regexp = "`validation_fn` must be a function")
  expect_error(flexyBayes:::.register_approximation(
    scheme = "s", bias_bound = ok_bias, validation_fn = ok_fn,
    fallback_hint = c("a", "b"), registered_in_adr = "0027"),
    regexp = "`fallback_hint` must be a single string")
  expect_error(flexyBayes:::.register_approximation(
    scheme = "s", bias_bound = ok_bias, validation_fn = ok_fn,
    fallback_hint = "x", registered_in_adr = 27L),
    regexp = "`registered_in_adr` must be a single string")
})

# ---------------------------------------------------------------- #
# (d) .register_approximation() refuses on locked registry          #
# ---------------------------------------------------------------- #

test_that(".register_approximation() refuses on locked registry", {
  expect_error(flexyBayes:::.register_approximation(
    scheme = "brand_new_scheme",
    bias_bound = list(type = "analytical"),
    validation_fn = function(fit, ...) TRUE,
    fallback_hint = "would never land",
    registered_in_adr = "9999"),
    regexp = "registry is locked"
  )
})

# ---------------------------------------------------------------- #
# (e) .lookup_approximation() refuses unknown scheme                #
# ---------------------------------------------------------------- #

test_that(".lookup_approximation() refuses unknown scheme", {
  err <- tryCatch(
    flexyBayes:::.lookup_approximation("definitely_not_a_scheme"),
    error = function(e) e)
  expect_s3_class(err, "error")
  expect_match(conditionMessage(err),
               "not a registered approximation scheme")
  # the empty-vocabulary hint is load-bearing at the scaffold step
  expect_match(conditionMessage(err), "none registered yet")
})

# ---------------------------------------------------------------- #
# (f) .lookup_approximation() refuses non-string input              #
# ---------------------------------------------------------------- #

test_that(".lookup_approximation() refuses non-string input", {
  expect_error(flexyBayes:::.lookup_approximation(NULL),
               regexp = "non-empty single string")
  expect_error(flexyBayes:::.lookup_approximation(""),
               regexp = "non-empty single string")
  expect_error(flexyBayes:::.lookup_approximation(c("a", "b")),
               regexp = "non-empty single string")
  expect_error(flexyBayes:::.lookup_approximation(1L),
               regexp = "non-empty single string")
})

# ---------------------------------------------------------------- #
# (g) .approximation_scheme() refuses an unknown scheme             #
# ---------------------------------------------------------------- #
#
# The round-trip success path is exercised once low_rank_smooth
# registers (with its emit path); at the scaffold step only the
# refusal delegation is reachable.

test_that(".approximation_scheme() refuses an unknown scheme", {
  expect_error(
    flexyBayes:::.approximation_scheme("not_a_scheme"),
    regexp = "not a registered approximation scheme"
  )
})

# ---------------------------------------------------------------- #
# (h) user-side assign() into the locked registry raises            #
# ---------------------------------------------------------------- #

test_that("user-side assign() into the registry raises", {
  reg <- flexyBayes:::.approximation_registry
  expect_error(
    assign("user_injected_scheme", list(scheme = "x"), envir = reg),
    regexp = "locked|cannot add bindings"
  )
})

# ---------------------------------------------------------------- #
# (i) snapshot test on the (empty) registered vocabulary            #
# ---------------------------------------------------------------- #
#
# The vocabulary is empty at the scaffold step; the snapshot pins that
# emptiness so the first population (low_rank_smooth) surfaces as a
# conscious snapshot diff the maintainer must accept.

test_that("registered approximation vocabulary snapshot", {
  reg <- flexyBayes:::.approximation_registry
  vocab <- sort(ls(envir = reg, all.names = FALSE))
  expect_snapshot(vocab)
})
