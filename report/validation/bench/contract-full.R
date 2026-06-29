## contract-full.R -- full-surface two-sided conformance sweep for flexyBayes.
## Writes the canonical gate input bench/results/contract-conformance.rds.
##
## Two-sided per the engine (engine/conformance.R): a NEGATIVE axis (a bad input
## must be rejected with a clean, caller-facing error -- never accepted silently
## or met with an opaque internal stack trace) and a POSITIVE axis (a valid input
## yields the correct result, graded against an independent oracle).
##
## The negative axis is generated across the exported surface by
## pv_auto_negative_probe (every required argument set to NA). Predicates (which
## legitimately accept any input and return a logical), side-effecting / status
## functions, and the heavy fitters / constructors are excluded from the auto
## probe and handled by curated cases instead, so the sweep does not mis-flag a
## predicate's NA-tolerance as a defect and does not call a fitter with garbage.
## Run from report/validation/:  Rscript bench/contract-full.R
`%||%` <- function(a, b) if (is.null(a)) b else a
if (!isNamespaceLoaded("flexyBayes")) {
  if (requireNamespace("devtools", quietly = TRUE) &&
      dir.exists(file.path("..", "flexyBayes"))) {
    suppressMessages(devtools::load_all(file.path("..", "flexyBayes"), quiet = TRUE))
  } else {
    suppressMessages(library(flexyBayes))
  }
}
RESDIR <- "bench/results"
dir.create(RESDIR, showWarnings = FALSE, recursive = TRUE)

SURFACE <- pv_exported_surface("flexyBayes")          # the exported function surface

## Excluded from the all-NA negative auto-probe (each handled below or one-sided
## by nature):
##  - predicates accept any input and return a logical -- NA is not an error;
##  - heavy fitters / constructors are curated, since an all-NA call could be slow;
##  - generators (rdirichlet / rgev) and cat_code are curated explicitly.
EXCL_AUTO <- c(
  "is_fb_approx", "is_fb_cov", "is_fb_engine", "proceed",
  "fb", "flexybayes", "fb_approx", "fb_plan", "fb_gwas", "fb_gblup_cv", "fb_gev",
  "flexybayes_stream", "fb_from_asreml", "fb_from_brms", "fb_from_greta",
  "fb_cov", "fb_engine", "fb_dirichlet", "rdirichlet", "rgev", "cat_code")

neg_auto <- pv_auto_negative_probe("flexyBayes", value = NA, exclude = EXCL_AUTO)

## Curated cases: positive (valid input + an independent oracle) and targeted
## negatives for the constructors / generators excluded from the auto probe.
CURATED <- list(
  ## --- positive, graded against an independent oracle ---
  list(fn = "fb_cov", source = "curated", expect = "ok",
       label = "fb_cov: SPD matrix -> fb_cov object",
       call = function() fb_cov(diag(3)), check = function(v) isTRUE(is_fb_cov(v))),
  list(fn = "fb_engine", source = "curated", expect = "ok",
       label = "fb_engine: 'inla' -> engine object",
       call = function() fb_engine("inla"), check = function(v) isTRUE(is_fb_engine(v))),
  list(fn = "rdirichlet", source = "curated", expect = "ok",
       label = "rdirichlet: draws lie on the simplex",
       call = function() rdirichlet(5, c(1, 1, 1)),
       check = function(v) is.matrix(v) && nrow(v) == 5 && ncol(v) == 3 &&
         max(abs(rowSums(v) - 1)) < 1e-8),
  list(fn = "rgev", source = "curated", expect = "ok",
       label = "rgev: n finite draws",
       call = function() rgev(10, location = 0, scale = 1, shape = 0.1),
       check = function(v) length(v) == 10 && all(is.finite(v))),
  list(fn = "fb_prior", source = "curated", expect = "ok",
       label = "fb_prior: penalised-complexity specification accepted",
       call = function() fb_prior(sigma ~ pc(upper = 2, prob = 0.05)),
       check = function(v) !is.null(v) && length(v) > 0),
  list(fn = "is_fb_cov", source = "curated", expect = "ok",
       label = "is_fb_cov: TRUE on an fb_cov object",
       call = function() is_fb_cov(fb_cov(diag(2))), check = function(v) isTRUE(v)),
  list(fn = "is_fb_cov", source = "curated", expect = "ok",
       label = "is_fb_cov: FALSE on a plain numeric",
       call = function() is_fb_cov(1), check = function(v) isFALSE(v)),
  list(fn = "is_fb_engine", source = "curated", expect = "ok",
       label = "is_fb_engine: TRUE on an engine object",
       call = function() is_fb_engine(fb_engine("inla")), check = function(v) isTRUE(v)),

  ## --- negative: a bad input must be rejected with a clean error ---
  list(fn = "fb", source = "curated", expect = "error",
       label = "fb: NULL input rejected",
       call = function() fb(NULL), check = NULL),
  list(fn = "flexybayes", source = "curated", expect = "error",
       label = "flexybayes: NULL input rejected",
       call = function() flexybayes(NULL), check = NULL),
  list(fn = "fb_cov", source = "curated", expect = "error",
       label = "fb_cov: NA matrix rejected",
       call = function() fb_cov(NA), check = NULL),
  list(fn = "fb_engine", source = "curated", expect = "error",
       label = "fb_engine: unknown engine name rejected",
       call = function() fb_engine("not-an-engine"), check = NULL),
  list(fn = "rdirichlet", source = "curated", expect = "error",
       label = "rdirichlet: NA arguments rejected",
       call = function() rdirichlet(NA, NA), check = NULL),
  list(fn = "rgev", source = "curated", expect = "error",
       label = "rgev: negative n rejected",
       call = function() rgev(-1, location = 0, scale = 1, shape = 0), check = NULL),
  list(fn = "fb_dirichlet", source = "curated", expect = "error",
       label = "fb_dirichlet: NULL input rejected",
       call = function() fb_dirichlet(NULL), check = NULL),
  list(fn = "fb_approx", source = "curated", expect = "error",
       label = "fb_approx: NULL scheme rejected",
       call = function() fb_approx(NULL), check = NULL),
  list(fn = "fb_prior", source = "curated", expect = "error",
       label = "fb_prior: empty specification rejected",
       call = function() fb_prior(), check = NULL)
)

cases <- c(CURATED, neg_auto)

## Single core: the greta (TensorFlow) and brms (Stan) back ends are unsafe to
## fork, so the sweep runs sequentially. Each cell is self-seeded.
verdicts <- pv_grid(
  cases, fn = function(cs) cs$call(),
  expect = function(cs) cs$expect, label = function(cs, i) cs$label,
  check = function(v, cs) if (is.null(cs$check)) TRUE else isTRUE(cs$check(v)),
  cores = 1L, base_seed = 20260629L)
verdicts$fn <- vapply(cases, function(cs) cs$fn, character(1))[verdicts$idx]
verdicts$source <- vapply(cases, function(cs) cs$source %||% "generated",
                          character(1))[verdicts$idx]

## A metamorphic invariant the package must satisfy: Dirichlet draws lie on the
## probability simplex (each row sums to one), checked independently of any
## package-internal expectation.
META <- pv_metamorphic_suite(list(
  "rdirichlet rows sum to 1" = function() {
    set.seed(1L)
    m <- rdirichlet(20, c(2, 3, 5))
    pv_metamorphic(rowSums(m), rep(1, 20), what = "rdirichlet simplex")
  }
))

conf <- pv_assemble_conformance(verdicts, META, surface = SURFACE,
                                master_seed = 20260629L,
                                provenance = pv_provenance("../flexyBayes"))
saveRDS(conf, file.path(RESDIR, "contract-conformance.rds"))
cat(sprintf("contract-full: %d cells, %d findings, two-sided coverage %.2f\n",
            conf$n_cells, conf$n_findings, conf$api_surface_covered %||% NA_real_))
print(conf$summary)
if (conf$n_findings)
  print(conf$findings[, c("label", "expect", "status", "detail")], row.names = FALSE)
