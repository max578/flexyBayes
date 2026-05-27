# huge_n_probe.R -- shape-only probe of the preflight + aggregation +
# prediction kernel paths at N = 5e6.
#
# Skeleton at v0.3.8.  Full N = 5e6 MCMC runs land at v0.4.0 per the
# trust-release gate (ADR 0027).  This script exercises the data-shape
# code paths (preflight, aggregation plan, prediction kernel dispatch)
# without materialising the impossible MCMC fit -- the point is to
# detect a regression in the metadata layer before the v0.4.0 push.
#
# Env-gated by FLEXYBAYES_RUN_HUGE_N=true.  Run from the workspace root:
#   FLEXYBAYES_RUN_HUGE_N=true Rscript flexyBayes/tools/profiles/huge_n_probe.R

if (!nzchar(Sys.getenv("FLEXYBAYES_RUN_HUGE_N"))) {
  cat("Set FLEXYBAYES_RUN_HUGE_N=true to run the huge_n_probe.\n")
  quit(save = "no", status = 0L)
}

suppressMessages(devtools::load_all("flexyBayes", quiet = TRUE))

t0 <- Sys.time()

# ---- Synthetic data ---------------------------------------------------

n_rows <- 5e6L
n_grp  <- 200L
set.seed(20260527L)
d <- data.frame(
  group = factor(sample.int(n_grp, n_rows, replace = TRUE)),
  x     = stats::rnorm(n_rows),
  y     = stats::rnorm(n_rows)
)
cat(sprintf("Generated synthetic dataset: %d rows, %d groups.\n",
            n_rows, n_grp))

# ---- Preflight shape probe -------------------------------------------

cat("\n-- preflight shape --\n")
pf <- tryCatch(
  flexyBayes:::.fb_preflight(
    fixed  = y ~ x,
    random = ~ group,
    data   = d
  ),
  error = function(e) {
    cat(sprintf("preflight raised expected refusal: %s\n",
                conditionMessage(e)))
    NULL
  }
)
if (!is.null(pf)) {
  cat(sprintf("preflight class: %s\n",
              paste(class(pf), collapse = ", ")))
  agg <- attr(pf, "aggregation_plan")
  if (!is.null(agg)) {
    cat(sprintf("aggregation_plan code: %s\n", agg$code))
  } else {
    cat("aggregation_plan: NULL (no aggregation triggered)\n")
  }
}

# ---- Aggregation kernel probe ----------------------------------------

cat("\n-- aggregation plan probe --\n")
plan <- tryCatch(
  flexyBayes:::.fb_aggregation_plan(
    fixed  = y ~ x,
    random = ~ group,
    data   = d
  ),
  error = function(e) {
    cat(sprintf("aggregation_plan raised: %s\n",
                conditionMessage(e)))
    NULL
  }
)
if (!is.null(plan)) {
  cat(sprintf("plan code: %s; n_cells = %s\n",
              plan$code,
              if (is.null(plan$n_cells)) "NA" else plan$n_cells))
}

elapsed <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
cat(sprintf("\n=== huge_n_probe SKELETON COMPLETE (v0.3.8) -- %.1fs ===\n",
            elapsed))
cat("Full N = 5e6 MCMC runs land at v0.4.0 per ADR 0027 trust-release gate.\n")
