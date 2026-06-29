## bench/fb-correctness.R -- real benchmark for the `fb`/`flexybayes` card.
## A fixed-effects Gaussian linear regression with KNOWN coefficients: recover
## (beta0, beta1, beta2) from simulated data via flexyBayes (INLA backend, exact)
## against two independent oracles -- `lm()` (the exact OLS/MLE solution) and the
## known data-generating truth. Fast (no MCMC). Numbers cached; never hand-typed.
## Run from report/validation/.

RESDIR <- "bench/results"
dir.create(RESDIR, showWarnings = FALSE, recursive = TRUE)
res <- list(card = "fb-correctness",
            model = "y ~ x1 + x2 (Gaussian, fixed effects)",
            oracle = "lm() exact OLS + known DGP truth",
            backend_under_test = "flexyBayes backend='inla'")

pkg <- normalizePath(file.path("..", "..", "flexyBayes"), mustWork = FALSE)
ok_pkg <- tryCatch({
  suppressMessages(devtools::load_all(pkg, quiet = TRUE)); TRUE
}, error = function(e) { res$load_error <<- conditionMessage(e); FALSE })
set.seed(20260629L)

## known ground truth
truth <- c(`(Intercept)` = 2.0, x1 = -1.5, x2 = 0.8)
n <- 400L
dat <- data.frame(x1 = stats::rnorm(n), x2 = stats::rnorm(n))
dat$y <- truth[["(Intercept)"]] + truth[["x1"]] * dat$x1 +
  truth[["x2"]] * dat$x2 + stats::rnorm(n, sd = 1)
res$truth <- truth

## oracle: lm (exact)
res$lm <- tryCatch({
  t <- system.time(fit_o <- stats::lm(y ~ x1 + x2, data = dat))[["elapsed"]]
  list(coef = stats::coef(fit_o),
       se = summary(fit_o)$coefficients[, "Std. Error"], seconds = t)
}, error = function(e) list(error = conditionMessage(e)))

## backend under test: flexyBayes (INLA, fixed-effects only -> exact)
res$fb <- if (!ok_pkg) list(error = "package failed to load") else tryCatch({
  t <- system.time(
    fit_b <- flexybayes(fixed = y ~ x1 + x2, data = dat, family = "gaussian",
                        backend = "inla", verbose = FALSE, mcmc_verbose = FALSE)
  )[["elapsed"]]
  list(coef = coef(fit_b), seconds = t, class = paste(class(fit_b), collapse = ","))
}, error = function(e) list(error = conditionMessage(e)))

res$agreement <- tryCatch({
  b <- res$fb$coef; o <- res$lm$coef
  if (is.null(b) || is.null(o)) stop("a required fit did not produce coefficients")
  common <- intersect(names(b), names(o))
  data.frame(
    term = common,
    truth = unname(truth[common]),
    fb_inla = unname(b[common]),
    lm = unname(o[common]),
    lm_se = unname(res$lm$se[common]),
    abs_delta_vs_lm = unname(abs(b[common] - o[common])),
    within_2_lm_se = unname(abs(b[common] - o[common]) < 2 * res$lm$se[common]),
    row.names = NULL
  )
}, error = function(e) list(error = conditionMessage(e)))

res$pass <- isTRUE(is.data.frame(res$agreement)) && all(res$agreement$within_2_lm_se)
res$generated_on <- as.character(Sys.Date())
saveRDS(res, file.path(RESDIR, "fb-correctness.rds"))
cat("fb-correctness:", if (isTRUE(res$pass)) "PASS" else "see result", "\n")
