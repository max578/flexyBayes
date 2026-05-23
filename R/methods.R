# S3 methods for the flexybayes class

#' Print a flexybayes object
#' @param x A flexybayes object
#' @param ... Additional arguments (ignored)
#' @export
print.flexybayes <- function(x, ...) {
  ci <- x$extras$call_info
  mi <- x$extras$model_info

  cat("Bayesian mixed model  [flexyBayes]\n")
  cat(strrep("-", 55), "\n")

  cat("  Fixed  :", deparse(ci$fixed), "\n")
  if (!is.null(ci$random)) cat("  Random :", deparse(ci$random), "\n")
  if (!is.null(ci$rcov) && !identical(deparse(ci$rcov), "~units"))
    cat("  Rcov   :", deparse(ci$rcov), "\n")
  cat("  Family :", mi$family, "(", mi$link, "link )\n")

  nch <- ci$chains
  ns  <- ci$n_samples
  cat("  MCMC   :", nch, "chain(s) x", ns, "samples",
      "(warmup =", ci$warmup, ") --",
      round(x$extras$run_time, 1), "sec\n")

  cat("  Params :", mi$n_params, "monitored;",
      mi$n_fixed, "fixed,", mi$n_random, "random terms\n")

  # Quick convergence
  if (!is.null(x$extras$convergence$gelman)) {
    rhat <- x$extras$convergence$gelman$psrf[, "Point est."]
    max_rhat <- max(rhat, na.rm = TRUE)
    flag <- if (max_rhat < 1.05) " [OK]" else
            if (max_rhat < 1.10) " [borderline]" else " [!]"
    cat("  Max Rhat:", round(max_rhat, 3), flag, "\n")
  }
  min_eff <- if (!is.null(x$extras$convergence$n_eff))
               min(x$extras$convergence$n_eff, na.rm = TRUE) else NA
  if (!is.na(min_eff))
    cat("  Min ESS:", round(min_eff, 0), "\n")

  cat(strrep("-", 55), "\n")
  cat("  $glm    -- GLM-compatible (summary, emmeans, etc.)\n")
  cat("  $greta  -- native greta (draws, model, calculate)\n")
  cat("  $extras -- diagnostics, BLUPs, variance components\n")

  invisible(x)
}

#' Summarise a flexybayes object
#'
#' @param object A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return Invisibly returns the posterior summary
#' @export
summary.flexybayes <- function(object, ...) {
  ci <- object$extras$call_info
  mi <- object$extras$model_info

  cat("Bayesian mixed model summary  [flexyBayes]\n")
  cat(strrep("=", 60), "\n")
  cat("  Fixed  :", deparse(ci$fixed), "\n")
  if (!is.null(ci$random)) cat("  Random :", deparse(ci$random), "\n")
  cat("  Family :", mi$family, "/", mi$link, "\n")
  cat("  N =", mi$n_obs, ", chains =", ci$chains,
      ", samples =", ci$n_samples, "\n\n")

  # Fixed effects
  cat("-- Fixed effects (posterior) ", strrep("-", 33), "\n")
  beta <- coef(object)
  if (length(beta) > 0) {
    ci_mat <- confint(object)
    fx_df <- data.frame(
      Estimate   = beta,
      Post.SD    = sqrt(diag(vcov(object))),
      `2.5%`     = ci_mat[, 1],
      `97.5%`    = ci_mat[, 2],
      check.names = FALSE
    )
    print(round(fx_df, 4))
  } else {
    cat("  (none)\n")
  }

  # Variance components
  cat("\n-- Variance components ", strrep("-", 38), "\n")
  vc <- object$extras$variance_comps
  if (!is.null(vc) && nrow(vc) > 0) {
    print(data.frame(
      Component = vc$component,
      Estimate  = round(vc$estimate, 4),
      SD        = round(vc$sd, 4),
      `2.5%`    = round(vc$q2.5, 4),
      `97.5%`   = round(vc$q97.5, 4),
      check.names = FALSE,
      row.names = NULL
    ))
  } else {
    cat("  (none available)\n")
  }

  # Convergence
  cat("\n-- Convergence ", strrep("-", 45), "\n")
  conv <- object$extras$convergence
  if (!is.null(conv$gelman)) {
    rhat <- conv$gelman$psrf[, "Point est."]
    cat("  Rhat range:", round(min(rhat, na.rm = TRUE), 3), "-",
        round(max(rhat, na.rm = TRUE), 3), "\n")
  }
  if (!is.null(conv$n_eff)) {
    cat("  ESS  range:", round(min(conv$n_eff, na.rm = TRUE), 0), "-",
        round(max(conv$n_eff, na.rm = TRUE), 0), "\n")
  }
  cat("  Run time  :", round(object$extras$run_time, 1), "sec\n")

  invisible(object$extras$summary)
}

#' Extract fixed effect coefficients
#' @param object A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return Named numeric vector of posterior mean fixed effects
#' @export
coef.flexybayes <- function(object, ...) {
  object$glm$coefficients
}

#' Extract variance-covariance matrix of fixed effects
#' @param object A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return Posterior covariance matrix of fixed effect coefficients
#' @export
vcov.flexybayes <- function(object, ...) {
  attr(object$glm, "posterior_vcov")
}

#' Credible intervals for fixed effects
#'
#' Returns posterior quantile-based credible intervals, not
#' frequentist confidence intervals.
#'
#' @param object A flexybayes object
#' @param parm Parameter names (NULL for all fixed effects)
#' @param level Credible level (default 0.95)
#' @param ... Additional arguments (ignored)
#' @return Matrix with lower and upper credible bounds
#' @export
confint.flexybayes <- function(object, parm = NULL, level = 0.95, ...) {
  draws <- object$greta$draws
  all_draws <- do.call(rbind, lapply(draws, as.matrix))

  # Get fixed effect column names
  beta_names <- names(coef(object))
  if (length(beta_names) == 0) return(matrix(nrow = 0, ncol = 2))

  # Map coefficient names back to draw column names
  coef_info <- .extract_fixed_coefs(object$extras$parse_info$fixed, draws)
  # Use the raw draw columns
  col_names <- colnames(all_draws)

  # Find the draws columns for fixed effects
  fixed_info <- object$extras$parse_info$fixed
  fixed_draw_cols <- .get_fixed_draw_columns(fixed_info, col_names)

  if (length(fixed_draw_cols) == 0)
    return(matrix(nrow = 0, ncol = 2))

  alpha <- 1 - level
  probs <- c(alpha / 2, 1 - alpha / 2)

  avail <- fixed_draw_cols[fixed_draw_cols %in% col_names]
  ci_mat <- t(apply(all_draws[, avail, drop = FALSE], 2, quantile,
                    probs = probs))
  rownames(ci_mat) <- beta_names[seq_along(avail)]
  colnames(ci_mat) <- paste0(round(probs * 100, 1), "%")

  if (!is.null(parm)) {
    ci_mat <- ci_mat[parm, , drop = FALSE]
  }

  ci_mat
}

# Helper: get draw column names for fixed effects
.get_fixed_draw_columns <- function(fixed_info, col_names) {
  result <- character(0)
  if (fixed_info$intercept && "mu_atg" %in% col_names) {
    result <- c(result, "mu_atg")
  }
  for (term in fixed_info$terms) {
    if (term$type == "factor") {
      prefix <- if (fixed_info$intercept) paste0("tau_", term$var) else
                paste0("alpha_", term$var)
      matches <- grep(paste0("^", prefix), col_names, value = TRUE)
      result <- c(result, matches)
    } else if (term$type == "continuous") {
      nm <- paste0("beta_", term$var)
      if (nm %in% col_names) result <- c(result, nm)
    } else if (term$type == "factor_interaction") {
      tag <- paste(term$vars, collapse = "_x_")
      prefix <- if (fixed_info$intercept) paste0("tau_", tag) else
                paste0("alpha_", tag)
      matches <- grep(paste0("^", prefix), col_names, value = TRUE)
      result <- c(result, matches)
    } else if (term$type %in% c("interaction", "expression")) {
      tag <- if (term$type == "interaction") {
        paste0(term$vars[1], "_x_", term$vars[2])
      } else {
        gsub("[^A-Za-z0-9_]", "_", term$label)
      }
      nm <- paste0("beta_", tag)
      if (nm %in% col_names) result <- c(result, nm)
    }
  }
  result
}

#' Extract fitted values
#' @param object A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return Numeric vector of posterior mean fitted values
#' @export
fitted.flexybayes <- function(object, ...) {
  object$glm$fitted.values
}

#' Extract residuals
#' @param object A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return Numeric vector of residuals (observed - fitted)
#' @export
residuals.flexybayes <- function(object, ...) {
  object$glm$residuals
}

#' Predict from a flexybayes model
#'
#' @param object A flexybayes object
#' @param newdata Optional new data frame for prediction. If NULL, returns
#'   fitted values from the original data.
#' @param type `"link"` for linear predictor, `"response"` for response scale.
#' @param se.fit Logical: return standard errors?
#' @param ... Additional arguments (ignored)
#' @return If `se.fit = FALSE`, a numeric vector. If `se.fit = TRUE`, a list
#'   with `fit` and `se.fit`.
#' @export
predict.flexybayes <- function(object, newdata = NULL,
                               type = c("response", "link"),
                               se.fit = FALSE, ...) {
  type <- match.arg(type)

  if (is.null(newdata)) {
    if (type == "link") {
      pred <- object$glm$linear.predictors
    } else {
      pred <- object$glm$fitted.values
    }
    if (se.fit) {
      return(list(fit = pred, se.fit = rep(NA_real_, length(pred))))
    }
    return(pred)
  }

  # ADR 0018: smooth-aware prediction on newdata. The smooth terms
  # live on the IR's random_terms slot (asreml-style fits put s() in
  # `random`, not in the fixed formula). The truth source is the
  # IR's parse_info$random list plus the parse_info$smooths slot
  # populated at codegen time. If the IR carries smooth_mgcv random
  # terms but the smooths slot is empty/missing (legacy fits saved
  # before ADR 0018), refuse cleanly. If the smooths slot is
  # populated, use mgcv::PredictMat() per smooth and column-bind to
  # the linear-only design matrix.
  fixed_formula <- object$glm$formula
  random_terms  <- object$extras$parse_info$random
  smooths_slot  <- object$extras$parse_info$smooths
  has_smooth_in_ir <- !is.null(random_terms) &&
    any(vapply(random_terms,
               function(t) !is.null(t$type) && t$type == "smooth_mgcv",
               logical(1)))

  if (has_smooth_in_ir &&
      (is.null(smooths_slot) || length(smooths_slot) == 0L))
    stop("predict.flexybayes(): the fit was produced before smooth-",
         "basis retention shipped (or via fb_greta() where smooth ",
         "basis is user-managed). Refusing to use stats::model.matrix() ",
         "on smooth terms -- it would produce silently wrong ",
         "predictions on newdata. Re-fit via flexybayes() / fb_brms() ",
         "on the current package version to enable predict() with ",
         "newdata.", call. = FALSE)

  tryCatch({
    if (has_smooth_in_ir && length(smooths_slot) > 0L) {
      # Linear-only model matrix (s() terms stripped from rhs). The
      # smooth terms in asreml-style fits live on the random formula,
      # not on the fixed formula, so the fixed formula is already
      # linear-only. We use the rhs-only variant of model.matrix so
      # newdata does not need to carry the response variable.
      X_linear <- stats::model.matrix(
        stats::delete.response(
          stats::terms(.linear_formula(fixed_formula))),
        data = newdata
      )
      beta <- coef(object)
      common <- intersect(colnames(X_linear), names(beta))
      lin_part <- if (length(common) > 0L)
        as.numeric(X_linear[, common, drop = FALSE] %*% beta[common])
      else rep(0, nrow(newdata))

      # Per-smooth basis on newdata via mgcv's reference implementation
      # plus per-smooth posterior-mean basis coefficients from the
      # draws matrix. The draws columns for s(x) are named
      # `s_x_raw[i]` (scaled by `sigma_s_x` in the codegen via
      # `f_s_x <- B_g_s_x %*% (s_x_raw * sigma_s_x)`). We compute the
      # posterior-mean of the *product* (basis-coefficient vector)
      # which matches the codegen contract on the linear predictor.
      draws_mat <- do.call(rbind,
        lapply(object$greta$draws, as.matrix))
      smooth_part <- rep(0, nrow(newdata))
      for (v in names(smooths_slot)) {
        sm <- smooths_slot[[v]]
        # Basis at newdata.
        Bnew <- mgcv::PredictMat(sm, data = newdata)
        # Posterior-mean basis-coefficient vector. Match the codegen
        # naming: `s_<v>_raw[1]` ... `s_<v>_raw[k]` and `sigma_s_<v>`.
        raw_pat   <- paste0("^s_", v, "_raw(\\[|$)")
        raw_cols  <- grep(raw_pat, colnames(draws_mat), value = TRUE)
        sigma_col <- paste0("sigma_s_", v)
        if (length(raw_cols) == 0L || !sigma_col %in% colnames(draws_mat))
          next
        # Each draw: raw[k] * sigma -> per-draw basis-coef vector;
        # average over draws -> posterior-mean basis-coef vector.
        raw_draws   <- draws_mat[, raw_cols, drop = FALSE]
        sigma_draws <- draws_mat[, sigma_col]
        coef_draws  <- sweep(raw_draws, 1L, sigma_draws, `*`)
        coef_mean   <- colMeans(coef_draws)
        # The basis from PredictMat is k columns (the absorbed-cons
        # basis matches the training-time basis dim).
        if (ncol(Bnew) != length(coef_mean)) next
        smooth_part <- smooth_part + as.numeric(Bnew %*% coef_mean)
      }
      pred <- lin_part + smooth_part
      # `mm` carried forward to the se.fit branch below; for the
      # smooth path we set it to the linear part only (se.fit not
      # computed on smooths in this iteration).
      mm <- X_linear
    } else {
      # rhs-only model matrix so newdata does not need to carry the
      # response variable (the prior path required `y` in newdata,
      # which was unnecessarily restrictive).
      mm <- stats::model.matrix(
        stats::delete.response(stats::terms(fixed_formula)),
        data = newdata
      )
      beta <- coef(object)

      common <- intersect(colnames(mm), names(beta))
      if (length(common) == 0) {
        warning("No matching coefficients for newdata prediction.")
        pred <- rep(NA_real_, nrow(newdata))
      } else {
        pred <- as.numeric(mm[, common, drop = FALSE] %*% beta[common])
      }
    }

    if (type == "response") {
      fam_link <- object$extras$parse_info$family
      pred <- switch(fam_link$link,
        "identity" = pred,
        "log"      = exp(pred),
        "logit"    = 1 / (1 + exp(-pred)),
        "probit"   = pnorm(pred),
        pred
      )
    }

    if (se.fit) {
      V <- vcov(object)
      if (has_smooth_in_ir && length(smooths_slot) > 0L) {
        # Smooth-path se.fit not computed -- the smooth-basis vcov is
        # not yet on the IR (only the fixed-effect vcov is). Return NA
        # rather than a wrong number; v0.3 candidate.
        se <- rep(NA_real_, nrow(newdata))
      } else {
        common <- intersect(colnames(mm), names(beta))
        if (length(common) > 0 && nrow(V) > 0) {
          se <- sqrt(rowSums(
            (mm[, common, drop = FALSE] %*% V[common, common]) *
             mm[, common, drop = FALSE]
          ))
        } else {
          se <- rep(NA_real_, nrow(newdata))
        }
      }
      return(list(fit = pred, se.fit = se))
    }

    pred
  }, error = function(e) {
    # ADR 0018: the legacy-fit correctness refusal above is a
    # deliberate stop() with a structured message; re-raise it
    # rather than swallow into a warning + NA vector.
    msg <- conditionMessage(e)
    if (grepl("smooth-basis retention", msg, fixed = TRUE))
      stop(msg, call. = FALSE)
    warning("Prediction with newdata failed: ", msg)
    rep(NA_real_, nrow(newdata))
  })
}

# ADR 0018 internal helper: TRUE when the rhs of `f` contains at
# least one s() smooth specification. Used by predict.flexybayes()
# to drive the smooth-aware branch + the legacy-fit refusal.
.formula_has_smooth <- function(f) {
  if (!inherits(f, "formula")) return(FALSE)
  rhs <- f[[length(f)]]
  any(grepl("\\bs\\(", deparse(rhs)))
}

# ADR 0018 internal helper: strip s() terms from the rhs of `f` and
# return the linear-only formula. Preserves the lhs, the intercept
# convention, and any non-s() terms (factor / continuous /
# interaction / I() expressions). Used by predict.flexybayes() to
# build the linear-only design matrix before column-binding the
# per-smooth basis from mgcv::PredictMat().
.linear_formula <- function(f) {
  if (!inherits(f, "formula")) return(f)
  tt <- stats::terms(f)
  labs <- attr(tt, "term.labels")
  keep <- !grepl("^s\\(", labs)
  # Preserve intercept presence (attr(tt, "intercept") is 0 or 1).
  intercept_str <- if (isTRUE(attr(tt, "intercept") == 1)) "1" else "0"
  rhs_terms <- c(intercept_str, labs[keep])
  rhs <- paste(rhs_terms, collapse = " + ")
  lhs <- if (length(f) == 3L) deparse(f[[2]]) else NULL
  stats::as.formula(
    if (!is.null(lhs)) paste(lhs, "~", rhs) else paste("~", rhs),
    env = environment(f)
  )
}

#' Log-likelihood (approximate)
#' @param object A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return logLik object
#' @export
logLik.flexybayes <- function(object, ...) {
  y <- object$glm$y
  fitted <- fitted(object)
  fam_link <- object$extras$parse_info$family

  ll <- tryCatch({
    if (fam_link$family == "gaussian") {
      # Get residual SD from posterior
      all_draws <- do.call(rbind, lapply(object$greta$draws, as.matrix))
      sigma_cols <- grep("^sigma_e_atg", colnames(all_draws), value = TRUE)
      if (length(sigma_cols) > 0) {
        sigma_e <- mean(all_draws[, sigma_cols[1]])
      } else {
        sigma_e <- sqrt(mean((y - fitted)^2))
      }
      sum(dnorm(y, mean = fitted, sd = sigma_e, log = TRUE))
    } else if (fam_link$family %in% c("binomial", "binary")) {
      p <- pmax(pmin(fitted, 1 - 1e-10), 1e-10)
      sum(dbinom(y, size = 1, prob = p, log = TRUE))
    } else if (fam_link$family == "poisson") {
      sum(dpois(y, lambda = pmax(fitted, 1e-10), log = TRUE))
    } else {
      NA_real_
    }
  }, error = function(e) NA_real_)

  structure(ll,
    df = object$extras$model_info$n_params,
    nobs = object$extras$model_info$n_obs,
    class = "logLik"
  )
}

#' Number of observations
#' @param object A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return Integer
#' @export
nobs.flexybayes <- function(object, ...) {
  object$extras$model_info$n_obs
}

#' Extract model family
#' @param object A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return A family object
#' @export
family.flexybayes <- function(object, ...) {
  object$glm$family
}

#' Extract model formula
#' @param x A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return The fixed formula
#' @export
formula.flexybayes <- function(x, ...) {
  x$glm$formula
}

#' Extract model matrix
#' @param object A flexybayes object
#' @param ... Additional arguments (ignored)
#' @return The fixed effects model matrix
#' @export
model.matrix.flexybayes <- function(object, ...) {
  model.matrix(object$glm$formula, data = object$glm$data)
}

#' Update a flexybayes model
#'
#' Re-fit the model with modified arguments.
#'
#' @param object A flexybayes object
#' @param ... Arguments to override (e.g., `n_samples = 2000`)
#' @return A new flexybayes object
#' @export
update.flexybayes <- function(object, ...) {
  cl <- object$extras$call_info
  dots <- list(...)

  args <- list(
    fixed          = cl$fixed,
    random         = cl$random,
    rcov           = cl$rcov,
    data           = object$glm$data,
    family         = cl$family,
    link           = cl$link,
    known_matrices = cl$known_matrices,
    weights        = cl$weights,
    n_samples      = cl$n_samples,
    warmup         = cl$warmup,
    chains         = cl$chains,
    prior_fixed_sd = cl$prior_fixed_sd,
    prior_vc_sd    = cl$prior_vc_sd
  )

  # Override with user-supplied arguments
  for (nm in names(dots)) {
    args[[nm]] <- dots[[nm]]
  }

  do.call(flexybayes, args)
}

#' Compare flexybayes models
#'
#' Bayesian model comparison using WAIC or DIC.
#'
#' @param object A flexybayes object
#' @param ... Additional flexybayes objects to compare
#' @return A data frame with model comparison statistics
#' @export
anova.flexybayes <- function(object, ...) {
  models <- c(list(object), list(...))
  n_models <- length(models)

  # Compute log-likelihoods
  lls <- vapply(models, function(m) {
    ll <- logLik(m)
    as.numeric(ll)
  }, numeric(1))

  n_params <- vapply(models, function(m) {
    m$extras$model_info$n_params
  }, integer(1))

  # Approximate DIC-like comparison
  dic <- -2 * lls + 2 * n_params

  model_names <- paste0("Model ", seq_len(n_models))

  result <- data.frame(
    Model   = model_names,
    logLik  = round(lls, 2),
    npar    = n_params,
    DIC     = round(dic, 2),
    delta   = round(dic - min(dic), 2),
    row.names = NULL,
    stringsAsFactors = FALSE
  )

  cat("Bayesian model comparison\n")
  cat(strrep("-", 50), "\n")
  print(result)
  cat("\nNote: DIC is approximate. For rigorous comparison,\n",
      "use loo::loo() on the greta draws.\n")

  invisible(result)
}


# ---------------------------------------------------------------- #
# flexybayes_direct_greta -- subclass method overrides              #
# ---------------------------------------------------------------- #
# fb_greta() returns objects of class
#   c("flexybayes_direct_greta", "flexybayes", "list")
# (subclass first so S3 dispatch finds the direct-greta overrides
# before the parent flexybayes methods). Three methods dispatch to
# greta-direct-aware overrides; everything else (summary, vcov,
# confint, prior_summary, posterior_samples) inherits verbatim from
# the parent "flexybayes" class.

#' Print a flexybayes object built via fb_greta() (direct greta entry)
#'
#' Distinguishes the direct-greta entry from the asreml-style /
#' brms-style formula entries by listing target parameters and the
#' inferred likelihood family.
#'
#' @param x A `flexybayes_direct_greta` object.
#' @param ... Additional arguments (ignored).
#' @return Invisibly returns `x`.
#' @export
print.flexybayes_direct_greta <- function(x, ...) {
  ci  <- x$extras$call_info
  mi  <- x$extras$model_info
  cm  <- mi$canonical_map

  cat("Bayesian model  [flexyBayes / direct-greta entry]\n")
  cat(strrep("-", 55), "\n")
  cat("  Entry  : fb_greta() (user-built greta model)\n")
  cat("  Family :", mi$family, "(likelihood:", mi$likelihood, ")\n")
  cat("  MCMC   :", ci$chains, "chain(s) x", ci$n_samples, "samples",
      "(warmup =", ci$warmup, ") --",
      round(x$extras$run_time, 1), "sec\n")
  cat("  Params :", mi$n_params, "monitored",
      "(", length(cm), "target greta_arrays)\n")

  if (length(cm) > 0L) {
    cat("  Targets:", paste(names(cm), collapse = ", "), "\n")
    has_renames <- any(names(cm) != unname(cm))
    if (has_renames) {
      cat("  Canonical map:\n")
      for (i in seq_along(cm)) {
        if (names(cm)[i] != cm[i])
          cat("    ", names(cm)[i], " -> ", cm[i], "\n", sep = "")
      }
    }
  }

  if (!is.null(x$extras$convergence$gelman)) {
    rhat <- x$extras$convergence$gelman$psrf[, "Point est."]
    max_rhat <- max(rhat, na.rm = TRUE)
    flag <- if (max_rhat < 1.05) " [OK]" else
            if (max_rhat < 1.10) " [borderline]" else " [!]"
    cat("  Max Rhat:", round(max_rhat, 3), flag, "\n")
  }
  min_eff <- if (!is.null(x$extras$convergence$n_eff))
               min(x$extras$convergence$n_eff, na.rm = TRUE) else NA
  if (!is.na(min_eff))
    cat("  Min ESS:", round(min_eff, 0), "\n")

  cat(strrep("-", 55), "\n")
  cat("  $glm    -- minimal GLM-compatible shim ",
      "(posterior means of target params)\n", sep = "")
  cat("  $greta  -- native greta (model, draws, greta_arrays)\n")
  cat("  $extras -- diagnostics, canonical_map, backend_decision\n")

  invisible(x)
}

#' Extract canonical-named posterior means from an fb_greta() fit
#'
#' Returns the posterior means of the target greta_arrays under
#' their canonical names. Differs from `coef.flexybayes()` only in
#' the source of the names (canonical map rather than fixed-effect
#' formula terms).
#'
#' @param object A `flexybayes_direct_greta` object.
#' @param ... Additional arguments (ignored).
#' @return Named numeric vector of posterior mean target parameters.
#' @export
coef.flexybayes_direct_greta <- function(object, ...) {
  # The parent class stores posterior means on object$glm$coefficients
  # already keyed by canonical names (renamed at fit time in
  # fb_greta()). Return that verbatim.
  object$glm$coefficients
}

#' Predict from a flexybayes_direct_greta fit
#'
#' Direct-greta fits do not encode a Wilkinson-Rogers formula on the
#' IR, so `predict()` cannot mechanically apply the model matrix to
#' `newdata`. The user must supply an explicit predictor function
#' `f(theta, newdata)` mapping a length-`p` named parameter vector
#' and a data frame to a length-`nrow(newdata)` vector of predicted
#' values. Posterior-mean prediction is computed by applying `f()`
#' to each posterior draw and averaging.
#'
#' @param object A `flexybayes_direct_greta` object.
#' @param newdata A data frame.
#' @param predictor A function `function(theta, newdata) -> numeric`
#'   where `theta` is a named vector of canonical-named target
#'   parameters and `newdata` is the data frame passed in.
#' @param type Character; `"response"` (default; on the response
#'   scale) or `"link"` (on the linear-predictor scale). Currently
#'   identity link only; non-Gaussian families queued for v0.3.
#' @param n_draws Integer; number of posterior draws to use (default
#'   500). The predictor function is applied to each draw and the
#'   mean is returned.
#' @param ... Additional arguments (ignored).
#' @return Numeric vector of length `nrow(newdata)`.
#' @export
predict.flexybayes_direct_greta <- function(object,
                                            newdata,
                                            predictor,
                                            type = c("response", "link"),
                                            n_draws = 500L,
                                            ...) {
  type <- match.arg(type)
  if (missing(newdata) || is.null(newdata))
    stop("`newdata` must be supplied to predict() on an fb_greta() ",
         "fit (the IR does not encode a Wilkinson-Rogers formula ",
         "that predict() can mechanically apply).", call. = FALSE)
  if (missing(predictor) || !is.function(predictor))
    stop("`predictor` must be a function `function(theta, newdata) ",
         "-> numeric` mapping a named parameter vector and newdata to ",
         "a vector of predictions. See ?predict.flexybayes_direct_greta ",
         "for the contract.", call. = FALSE)

  draws <- object$greta$draws
  all_draws <- do.call(rbind, lapply(draws, as.matrix))

  # Apply the canonical-name rename to the draw matrix so the
  # predictor sees the canonical names (consistent with coef()).
  cm <- object$extras$model_info$canonical_map
  greta_names <- names(cm)
  canon       <- unname(cm)
  for (i in seq_along(greta_names)) {
    if (identical(greta_names[i], canon[i])) next
    pat <- paste0("^", greta_names[i], "(\\[|$)")
    repl <- paste0(canon[i], "\\1")
    colnames(all_draws) <- sub(pat, repl, colnames(all_draws))
  }

  n_total <- nrow(all_draws)
  if (n_draws >= n_total) {
    idx <- seq_len(n_total)
  } else {
    idx <- sort(sample.int(n_total, n_draws, replace = FALSE))
  }

  preds_mat <- vapply(idx, function(k) {
    theta <- setNames(as.numeric(all_draws[k, ]), colnames(all_draws))
    out <- predictor(theta, newdata)
    if (!is.numeric(out) || length(out) != nrow(newdata))
      stop("`predictor(theta, newdata)` must return a numeric vector ",
           "of length nrow(newdata) = ", nrow(newdata),
           "; got length ", length(out), ".", call. = FALSE)
    out
  }, numeric(nrow(newdata)))

  if (is.null(dim(preds_mat))) preds_mat <- matrix(preds_mat, nrow = 1L)
  rowMeans(preds_mat)
}
