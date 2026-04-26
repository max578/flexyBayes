# triangulate -- cross-engine posterior comparison (deliverable 4).
#
# The signature feature of flexyBayes. Takes two model fits produced
# via different backends (greta / INLA / brms passthrough) and
# computes per-parameter posterior comparison metrics: Wasserstein-1
# distance (1D), R-hat-on-means, tail drift (0.025 / 0.975 quantile
# difference), and SD ratio.
#
# Backends use different internal parameter naming conventions:
#   - greta: e.g., "mu_atg", "beta_x", "tau_env[1]", "sigma_geno"
#   - INLA: e.g., "(Intercept):1", "x:1", "g:1", "Precision for g"
# Users supply a `name_map` (named character vector or list) to
# align fit_b's parameter names to fit_a's canonical names. Without
# alignment, only literal-match parameters are compared.
#
# Internal posterior extraction is via the fb_as_draws_simple()
# generic with methods for `bayesreml` (greta backend) and
# `bayesreml_inla` (INLA backend). Both return a named list whose
# values are numeric vectors of posterior draws.

# ---------------------------------------------------------------- #
# Public-facing entry                                              #
# ---------------------------------------------------------------- #

#' Cross-engine posterior triangulation
#'
#' Compute per-parameter posterior comparison metrics across two
#' Bayesian fits produced via different backends (greta / INLA /
#' brms passthrough). The signature feature of flexyBayes.
#'
#' For each parameter present in both fits (post `name_map`), the
#' returned table reports: posterior means, posterior SDs, Q2.5 /
#' Q97.5 differences (tail drift), Wasserstein-1 distance (1D
#' empirical), the SD ratio, and an R-hat-on-means scalar that
#' compares between-engine vs within-engine variance. Parameters
#' present in only one fit are reported in `only_a` / `only_b`.
#'
#' Backends use different parameter naming conventions; supply
#' `name_map = c(<fit_b name> = <canonical name>, ...)` to align
#' them. Without alignment, only literal-match parameter names are
#' compared.
#'
#' @param fit_a a fit object with a `fb_as_draws_simple` method
#'   (e.g., `bayesreml` from greta, `bayesreml_inla` from INLA).
#' @param fit_b a second fit object, typically from a different
#'   backend.
#' @param name_map named character vector or list mapping fit_b's
#'   parameter names (left) to canonical names matching fit_a
#'   (right). Optional.
#' @param n_samples integer: number of posterior samples to draw
#'   for fits whose extractor needs sampling (e.g., INLA via
#'   `INLA::inla.posterior.sample`).
#' @return a `triangulate_result` S3 object (list). Key fields:
#'   `metrics` (data.frame, one row per common parameter),
#'   `common` (character), `only_a`, `only_b`, `n_common`,
#'   `source_a`, `source_b`.
#' @examples
#' \dontrun{
#' library(bayesreml)
#' d <- data.frame(y = rnorm(40), x = rnorm(40), g = factor(rep(1:5, 8)))
#' fit_g <- fb(y ~ x + (1 | g), data = d, backend = "greta",
#'             n_samples = 200, warmup = 200, chains = 2)
#' fit_i <- fb(y ~ x + (1 | g), data = d, backend = "inla")
#' tri <- triangulate(
#'   fit_g, fit_i,
#'   name_map = c("(Intercept):1" = "mu_atg", "x:1" = "beta_x")
#' )
#' print(tri)
#' }
#' @export
triangulate <- function(fit_a, fit_b, name_map = NULL, n_samples = 1000L) {

  draws_a <- fb_as_draws_simple(fit_a, n_samples = n_samples)
  draws_b <- fb_as_draws_simple(fit_b, n_samples = n_samples)

  if (!is.list(draws_a) || is.null(names(draws_a)))
    stop("`fb_as_draws_simple(fit_a)` must return a named list of ",
         "numeric vectors.", call. = FALSE)
  if (!is.list(draws_b) || is.null(names(draws_b)))
    stop("`fb_as_draws_simple(fit_b)` must return a named list of ",
         "numeric vectors.", call. = FALSE)

  if (!is.null(name_map)) {
    if (!(is.list(name_map) || is.character(name_map)) ||
        is.null(names(name_map)))
      stop("`name_map` must be a named character vector or list ",
           "mapping fit_b's parameter names to canonical names.",
           call. = FALSE)
    new_names <- names(draws_b)
    for (i in seq_along(new_names)) {
      if (new_names[i] %in% names(name_map))
        new_names[i] <- as.character(name_map[[new_names[i]]])
    }
    names(draws_b) <- new_names
  }

  common <- intersect(names(draws_a), names(draws_b))
  only_a <- setdiff(names(draws_a), common)
  only_b <- setdiff(names(draws_b), common)

  metrics <- if (length(common) > 0L) {
    rows <- lapply(common, function(p) {
      .triangulate_one(p, draws_a[[p]], draws_b[[p]])
    })
    do.call(rbind, lapply(rows, as.data.frame, stringsAsFactors = FALSE))
  } else {
    .triangulate_empty_table()
  }

  structure(
    list(
      metrics  = metrics,
      common   = common,
      only_a   = only_a,
      only_b   = only_b,
      n_common = length(common),
      source_a = .triangulate_source(fit_a),
      source_b = .triangulate_source(fit_b)
    ),
    class = c("triangulate_result", "list")
  )
}

is_triangulate_result <- function(x) inherits(x, "triangulate_result")

# ---------------------------------------------------------------- #
# Per-parameter metrics                                            #
# ---------------------------------------------------------------- #

.triangulate_one <- function(name, a, b) {
  a <- as.numeric(a); b <- as.numeric(b)
  m_a <- mean(a, na.rm = TRUE)
  m_b <- mean(b, na.rm = TRUE)
  s_a <- stats::sd(a, na.rm = TRUE)
  s_b <- stats::sd(b, na.rm = TRUE)
  q025_a <- stats::quantile(a, 0.025, names = FALSE, na.rm = TRUE)
  q025_b <- stats::quantile(b, 0.025, names = FALSE, na.rm = TRUE)
  q975_a <- stats::quantile(a, 0.975, names = FALSE, na.rm = TRUE)
  q975_b <- stats::quantile(b, 0.975, names = FALSE, na.rm = TRUE)

  list(
    param         = name,
    mean_a        = m_a,
    mean_b        = m_b,
    mean_diff     = m_a - m_b,
    sd_a          = s_a,
    sd_b          = s_b,
    sd_ratio      = if (is.finite(s_b) && s_b > 0) s_a / s_b else NA_real_,
    q025_diff     = q025_a - q025_b,
    q975_diff     = q975_a - q975_b,
    wasserstein_1 = .wasserstein1_1d(a, b),
    rhat_means    = .rhat_means_2(a, b)
  )
}

.triangulate_empty_table <- function() {
  data.frame(
    param         = character(0),
    mean_a        = numeric(0),
    mean_b        = numeric(0),
    mean_diff     = numeric(0),
    sd_a          = numeric(0),
    sd_b          = numeric(0),
    sd_ratio      = numeric(0),
    q025_diff     = numeric(0),
    q975_diff     = numeric(0),
    wasserstein_1 = numeric(0),
    rhat_means    = numeric(0),
    stringsAsFactors = FALSE
  )
}

# Empirical 1D Wasserstein-1 distance via quantile interpolation:
# W1 = integral over u in [0, 1] of |F_a^-1(u) - F_b^-1(u)| du.
# Approximated by a 99-point quantile grid (u in 0.01..0.99).
.wasserstein1_1d <- function(a, b) {
  if (length(a) == 0L || length(b) == 0L) return(NA_real_)
  qs <- seq(0.01, 0.99, by = 0.01)
  qa <- stats::quantile(a, qs, names = FALSE, na.rm = TRUE)
  qb <- stats::quantile(b, qs, names = FALSE, na.rm = TRUE)
  mean(abs(qa - qb))
}

# R-hat-on-means: with two backends, treat each backend's posterior
# as a single "chain". Compute sqrt((W + B) / W) where W is the
# average within-engine variance and B is the squared between-
# engine mean spread. Returns ~1 when posteriors agree and grows
# with disagreement.
.rhat_means_2 <- function(a, b) {
  m_a <- mean(a, na.rm = TRUE)
  m_b <- mean(b, na.rm = TRUE)
  v_a <- stats::var(a, na.rm = TRUE)
  v_b <- stats::var(b, na.rm = TRUE)

  W <- mean(c(v_a, v_b), na.rm = TRUE)
  if (!is.finite(W) || W <= 0) return(NA_real_)
  B <- (m_a - m_b)^2 / 2
  sqrt((W + B) / W)
}

.triangulate_source <- function(fit) {
  if (inherits(fit, "bayesreml_inla")) return("inla")
  if (inherits(fit, "bayesreml"))      return("greta")
  paste(class(fit), collapse = "/")
}

# ---------------------------------------------------------------- #
# Per-fit posterior extraction (S3 generic)                        #
# ---------------------------------------------------------------- #

#' Extract per-parameter posterior draws from a model fit
#'
#' S3 generic used by `triangulate()` to extract a named list of
#' numeric posterior-draw vectors from each fit. Methods exist for
#' the `bayesreml` (greta backend) and `bayesreml_inla` (INLA
#' backend) classes; user-defined methods can extend the generic.
#'
#' @param fit a model fit object.
#' @param ... method-specific arguments (e.g., `n_samples` for INLA).
#' @return a named list of numeric vectors.
#' @export
fb_as_draws_simple <- function(fit, ...) UseMethod("fb_as_draws_simple")

#' @rdname fb_as_draws_simple
#' @keywords internal
#' @export
fb_as_draws_simple.bayesreml <- function(fit, ...) {
  if (is.null(fit$greta) || is.null(fit$greta$draws))
    stop("Cannot extract draws: fit$greta$draws is missing. ",
         "Did the fit complete (return_code = FALSE) and use ",
         "backend = \"greta\"?", call. = FALSE)
  m <- as.matrix(fit$greta$draws)
  cols <- colnames(m)
  if (is.null(cols)) cols <- paste0("V", seq_len(ncol(m)))
  setNames(lapply(seq_len(ncol(m)), function(j) as.numeric(m[, j])),
           cols)
}

#' @rdname fb_as_draws_simple
#' @keywords internal
#' @export
fb_as_draws_simple.bayesreml_inla <- function(fit, n_samples = 1000L, ...) {
  if (!requireNamespace("INLA", quietly = TRUE))
    stop("Package 'INLA' is required to extract draws from a ",
         "bayesreml_inla object.", call. = FALSE)
  if (is.null(fit$inla))
    stop("Cannot extract draws: fit$inla is missing.", call. = FALSE)

  n_samples <- as.integer(n_samples)
  samples <- tryCatch(
    INLA::inla.posterior.sample(n_samples, fit$inla),
    error = function(e)
      stop("INLA::inla.posterior.sample() failed: ",
           conditionMessage(e),
           ". Re-fit with control.compute = list(config = TRUE).",
           call. = FALSE)
  )

  if (length(samples) == 0L)
    stop("INLA::inla.posterior.sample() returned an empty list.",
         call. = FALSE)

  latent_names   <- rownames(samples[[1]]$latent)
  hyperpar_names <- names(samples[[1]]$hyperpar)

  out <- list()
  for (pn in latent_names) {
    out[[pn]] <- vapply(samples,
      function(s) as.numeric(s$latent[pn, 1]), numeric(1))
  }
  for (pn in hyperpar_names) {
    out[[pn]] <- vapply(samples,
      function(s) as.numeric(s$hyperpar[pn]), numeric(1))
  }
  out
}

#' @rdname fb_as_draws_simple
#' @keywords internal
#' @export
fb_as_draws_simple.default <- function(fit, ...) {
  stop("triangulate() / fb_as_draws_simple() does not know how to ",
       "extract draws from an object of class ",
       paste(class(fit), collapse = "/"),
       ". Define an `fb_as_draws_simple.<class>` method.",
       call. = FALSE)
}

# ---------------------------------------------------------------- #
# Print method                                                     #
# ---------------------------------------------------------------- #

#' Print method for triangulate_result
#'
#' Internal S3 method. Brief summary header followed by the per-
#' parameter metrics table.
#'
#' @param x   a `triangulate_result` object.
#' @param ... unused.
#' @return invisibly returns `x`.
#' @keywords internal
#' @export
print.triangulate_result <- function(x, ...) {
  cat("<triangulate_result>\n")
  cat("  source_a: ", x$source_a, "\n", sep = "")
  cat("  source_b: ", x$source_b, "\n", sep = "")
  cat("  n_common: ", x$n_common, "\n", sep = "")
  .print_only(x$only_a, "only_a")
  .print_only(x$only_b, "only_b")

  if (x$n_common > 0L) {
    cat("\nMetrics (per common parameter):\n")
    print(.round_metrics(x$metrics, 4))
  } else {
    cat("\n  No common parameters. Supply `name_map` to align ",
        "fit_b's parameter names to fit_a's canonical names.\n",
        sep = "")
  }
  invisible(x)
}

.print_only <- function(names_vec, label) {
  n <- length(names_vec)
  cat("  ", label, ":   ", n, " parameter",
      if (n != 1L) "s" else "",
      if (n > 0L) paste0(" (",
        paste(utils::head(names_vec, 5), collapse = ", "),
        if (n > 5L) ", ..." else "",
        ")") else "",
      "\n", sep = "")
}

.round_metrics <- function(df, digits = 4L) {
  num_cols <- vapply(df, is.numeric, logical(1))
  df[num_cols] <- lapply(df[num_cols], round, digits = digits)
  df
}
