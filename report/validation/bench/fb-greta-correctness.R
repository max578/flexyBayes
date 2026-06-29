## bench/fb-greta-correctness.R -- real benchmark for the `fb_greta` card.
## The sleepstudy random-intercept LMM via the greta (TensorFlow MCMC) backend:
##   flexyBayes(backend="greta")  vs  lme4::lmer()  (the independent REML oracle).
## This is the SLOW card -- greta initialises TensorFlow and runs HMC, so a full
## run is minutes, not seconds. It is authored runnable; execute with:
##   cd report/validation && Rscript bench/fb-greta-correctness.R
## Numbers are computed and cached; the card never hand-types them. A TF
## non-finite draw (known non-determinism) is recorded, never silently dropped.
## Run from report/validation/.

RESDIR <- "bench/results"
dir.create(RESDIR, showWarnings = FALSE, recursive = TRUE)
res <- list(card = "fb-greta-correctness",
            model = "Reaction ~ Days + (1 | Subject)",
            dataset = "sleepstudy (lme4)", oracle = "lme4::lmer REML",
            backend_under_test = "flexyBayes backend='greta' (TensorFlow HMC)")

pkg <- normalizePath(file.path("..", "..", "flexyBayes"), mustWork = FALSE)
ok_pkg <- tryCatch({
  suppressMessages(devtools::load_all(pkg, quiet = TRUE)); TRUE
}, error = function(e) { res$load_error <<- conditionMessage(e); FALSE })
set.seed(20260629L)
utils::data(sleepstudy, package = "lme4")

res$lme4 <- tryCatch({
  fit_l <- lme4::lmer(Reaction ~ Days + (1 | Subject), data = sleepstudy, REML = TRUE)
  list(fixef = lme4::fixef(fit_l),
       se = sqrt(diag(as.matrix(stats::vcov(fit_l)))))
}, error = function(e) list(error = conditionMessage(e)))

res$fb_greta <- if (!ok_pkg) list(error = "package failed to load") else tryCatch({
  t <- system.time(
    fit_b <- flexybayes(fixed = Reaction ~ Days, random = ~Subject,
                        data = sleepstudy, family = "gaussian", backend = "greta",
                        n_samples = 1000, warmup = 1000, chains = 2,
                        verbose = FALSE, mcmc_verbose = FALSE)
  )[["elapsed"]]
  b <- coef(fit_b)
  list(coef = b, seconds = t, all_finite = all(is.finite(b)),
       class = paste(class(fit_b), collapse = ","))
}, error = function(e) list(error = conditionMessage(e)))

res$agreement <- tryCatch({
  b <- res$fb_greta$coef; l <- res$lme4$fixef
  if (is.null(b) || is.null(l)) stop("a required fit did not produce coefficients")
  if (!all(is.finite(b))) stop("greta/TF produced a non-finite coefficient (TF non-determinism)")
  common <- intersect(names(b), names(l))
  data.frame(
    term = common, fb_greta = unname(b[common]), lme4 = unname(l[common]),
    reml_se = unname(res$lme4$se[common]),
    abs_delta_vs_lme4 = unname(abs(b[common] - l[common])),
    within_1.5_reml_se = unname(abs(b[common] - l[common]) < 1.5 * res$lme4$se[common]),
    row.names = NULL
  )
}, error = function(e) list(error = conditionMessage(e)))

res$pass <- isTRUE(is.data.frame(res$agreement)) && all(res$agreement$within_1.5_reml_se)
res$generated_on <- as.character(Sys.Date())
saveRDS(res, file.path(RESDIR, "fb-greta-correctness.rds"))
cat("fb-greta-correctness:", if (isTRUE(res$pass)) "PASS" else "see result", "\n")
