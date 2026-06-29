## bench/fb-inla-correctness.R -- real benchmark for the `fb_inla` card.
## Three-way agreement on sleepstudy (lme4), a random-intercept Gaussian LMM:
##   flexyBayes(backend="inla")  vs  standalone INLA::inla()  vs  lme4::lmer().
## lme4 (REML) is the independent oracle; standalone INLA tests flexyBayes's
## translation fidelity (does fb-via-INLA reproduce a hand-written INLA fit?).
## Numbers are computed here and cached; the card never hand-types them.
## Run from report/validation/.

RESDIR <- "bench/results"
dir.create(RESDIR, showWarnings = FALSE, recursive = TRUE)

res <- list(card = "fb-inla-correctness", model = "Reaction ~ Days + (1 | Subject)",
            dataset = "sleepstudy (lme4)", oracle = "lme4::lmer REML",
            backend_under_test = "flexyBayes backend='inla'",
            independent_backend = "standalone INLA::inla()")

## load_all FIRST, then seed (load_all consumes the RNG stream).
pkg <- normalizePath(file.path("..", "..", "flexyBayes"), mustWork = FALSE)
ok_pkg <- tryCatch({
  suppressMessages(devtools::load_all(pkg, quiet = TRUE)); TRUE
}, error = function(e) { res$load_error <<- conditionMessage(e); FALSE })
set.seed(20260629L)

utils::data(sleepstudy, package = "lme4")

## -- oracle: lme4 REML -------------------------------------------------------
res$lme4 <- tryCatch({
  t <- system.time(fit_l <- lme4::lmer(Reaction ~ Days + (1 | Subject),
                                       data = sleepstudy, REML = TRUE))[["elapsed"]]
  vc <- as.data.frame(lme4::VarCorr(fit_l))
  list(fixef = lme4::fixef(fit_l),
       se = sqrt(diag(as.matrix(stats::vcov(fit_l)))),
       sd_subject = vc$sdcor[vc$grp == "Subject"],
       sigma = vc$sdcor[vc$grp == "Residual"], seconds = t)
}, error = function(e) list(error = conditionMessage(e)))

## -- independent backend: standalone INLA -----------------------------------
res$inla_standalone <- tryCatch({
  if (!requireNamespace("INLA", quietly = TRUE)) stop("INLA not installed")
  t <- system.time(
    fit_i <- INLA::inla(Reaction ~ Days + f(Subject, model = "iid"),
                        family = "gaussian", data = sleepstudy,
                        control.compute = list(config = FALSE))
  )[["elapsed"]]
  fx <- fit_i$summary.fixed
  list(fixef = stats::setNames(fx[, "mean"], rownames(fx)), seconds = t)
}, error = function(e) list(error = conditionMessage(e)))

## -- backend under test: flexyBayes via INLA --------------------------------
res$fb_inla <- if (!ok_pkg) list(error = "package failed to load") else tryCatch({
  t <- system.time(
    fit_b <- flexybayes(fixed = Reaction ~ Days, random = ~Subject,
                        data = sleepstudy, family = "gaussian", backend = "inla",
                        verbose = FALSE, mcmc_verbose = FALSE)
  )[["elapsed"]]
  list(coef = coef(fit_b), seconds = t,
       class = paste(class(fit_b), collapse = ","))
}, error = function(e) list(error = conditionMessage(e)))

## -- agreement (only when both fb and the oracle produced fixed effects) -----
res$agreement <- tryCatch({
  b <- res$fb_inla$coef; l <- res$lme4$fixef; s <- res$inla_standalone$fixef
  if (is.null(b) || is.null(l)) stop("a required fit did not produce coefficients")
  common <- Reduce(intersect, list(names(b), names(l),
                                   if (!is.null(s)) names(s) else names(l)))
  data.frame(
    term = common,
    fb_inla = unname(b[common]),
    lme4 = unname(l[common]),
    inla_standalone = if (!is.null(s)) unname(s[common]) else NA_real_,
    reml_se = unname(res$lme4$se[common]),
    abs_delta_vs_lme4 = unname(abs(b[common] - l[common])),
    within_1.5_reml_se = unname(abs(b[common] - l[common]) < 1.5 * res$lme4$se[common]),
    row.names = NULL
  )
}, error = function(e) list(error = conditionMessage(e)))

res$pass <- isTRUE(is.data.frame(res$agreement)) &&
  all(res$agreement$within_1.5_reml_se)
res$generated_on <- as.character(Sys.Date())
saveRDS(res, file.path(RESDIR, "fb-inla-correctness.rds"))
cat("fb-inla-correctness:",
    if (isTRUE(res$pass)) "PASS" else "see result (error or out-of-tolerance)", "\n")
