## bench/fb-brms-correctness.R -- real benchmark for the `fb_brms` card.
## The sleepstudy random-intercept LMM via the brms (Stan HMC) backend:
##   flexyBayes(backend="brms")  vs  standalone brms::brm()  vs  lme4::lmer().
## lme4 (REML) is the independent oracle; standalone brms tests flexyBayes's
## translation fidelity. SLOW: brms compiles a Stan model (~30-60s) then runs
## HMC. Authored runnable; numbers cached, never hand-typed. Run from report/validation/.

RESDIR <- "bench/results"
dir.create(RESDIR, showWarnings = FALSE, recursive = TRUE)
res <- list(card = "fb-brms-correctness",
            model = "Reaction ~ Days + (1 | Subject)",
            dataset = "sleepstudy (lme4)", oracle = "lme4::lmer REML",
            backend_under_test = "flexyBayes backend='brms' (Stan HMC)",
            independent_backend = "standalone brms::brm()")

pkg <- normalizePath(file.path("..", "..", "flexyBayes"), mustWork = FALSE)
ok_pkg <- tryCatch({
  suppressMessages(devtools::load_all(pkg, quiet = TRUE)); TRUE
}, error = function(e) { res$load_error <<- conditionMessage(e); FALSE })
set.seed(20260629L)
utils::data(sleepstudy, package = "lme4")

res$lme4 <- tryCatch({
  fit_l <- lme4::lmer(Reaction ~ Days + (1 | Subject), data = sleepstudy, REML = TRUE)
  list(fixef = lme4::fixef(fit_l), se = sqrt(diag(as.matrix(stats::vcov(fit_l)))))
}, error = function(e) list(error = conditionMessage(e)))

res$brms_standalone <- tryCatch({
  if (!requireNamespace("brms", quietly = TRUE)) stop("brms not installed")
  t <- system.time(
    fit_s <- brms::brm(Reaction ~ Days + (1 | Subject), data = sleepstudy,
                       chains = 2, iter = 2000, refresh = 0, silent = 2,
                       seed = 20260629L)
  )[["elapsed"]]
  fx <- brms::fixef(fit_s)
  list(fixef = stats::setNames(fx[, "Estimate"], rownames(fx)), seconds = t)
}, error = function(e) list(error = conditionMessage(e)))

res$fb_brms <- if (!ok_pkg) list(error = "package failed to load") else tryCatch({
  t <- system.time(
    fit_b <- flexybayes(fixed = Reaction ~ Days, random = ~Subject,
                        data = sleepstudy, family = "gaussian", backend = "brms",
                        n_samples = 1000, warmup = 1000, chains = 2,
                        verbose = FALSE, mcmc_verbose = FALSE)
  )[["elapsed"]]
  b <- coef(fit_b)
  list(coef = b, seconds = t, all_finite = all(is.finite(b)),
       class = paste(class(fit_b), collapse = ","))
}, error = function(e) list(error = conditionMessage(e)))

res$agreement <- tryCatch({
  b <- res$fb_brms$coef; l <- res$lme4$fixef; s <- res$brms_standalone$fixef
  if (is.null(b) || is.null(l)) stop("a required fit did not produce coefficients")
  common <- Reduce(intersect, list(names(b), names(l),
                                   if (!is.null(s)) names(s) else names(l)))
  data.frame(
    term = common, fb_brms = unname(b[common]), lme4 = unname(l[common]),
    brms_standalone = if (!is.null(s)) unname(s[common]) else NA_real_,
    reml_se = unname(res$lme4$se[common]),
    abs_delta_vs_lme4 = unname(abs(b[common] - l[common])),
    within_1.5_reml_se = unname(abs(b[common] - l[common]) < 1.5 * res$lme4$se[common]),
    row.names = NULL
  )
}, error = function(e) list(error = conditionMessage(e)))

res$pass <- isTRUE(is.data.frame(res$agreement)) && all(res$agreement$within_1.5_reml_se)
res$generated_on <- as.character(Sys.Date())
saveRDS(res, file.path(RESDIR, "fb-brms-correctness.rds"))
cat("fb-brms-correctness:", if (isTRUE(res$pass)) "PASS" else "see result", "\n")
