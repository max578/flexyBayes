# =============================================================================
# fb_pesto.R -- the first consumer on the C5 ensemble-source ingest floor.
#
# Turns a calibrated simulation ensemble (a PESTO manifest, or any C5-conforming
# source) into flexyBayes-ready artefacts -- principally an INFORMATIVE PRIOR
# derived from the ensemble, the "generalise" seam of the
# inverse -> validation -> generalisation pipeline: PESTO calibrates a forward
# model; flexyBayes carries that calibrated knowledge forward as a prior for a
# subsequent Bayesian fit (MET / GxE / prediction to unseen environments).
#
# It consumes the C5 contract (as_fb_ensemble), never apsimx / PESTO internals.
# `fb_prior_from_ensemble()` is the reusable engine (fb_apsim_prior in ADR 0009
# will route through it); `fb_pesto()` is the PESTO-facing headline verb.
# =============================================================================

# ---- the reusable prior-construction engine ---------------------------------

#' Derive an informative flexyBayes prior from a simulation ensemble
#'
#' Constructs an `fb_prior` from a calibrated parameter ensemble -- the
#' "generalise" step that carries a process-model calibration forward into a
#' flexyBayes fit. The ensemble is ingested through the C5 contract
#' ([as_fb_ensemble()]), so any conforming producer works (a PESTO manifest, a
#' raw `apsimx` ensemble, a file).
#'
#' The `"moments"` method (the default, self-contained) fits an independent
#' `normal(mean, sd)` prior to each parameter from its ensemble marginal mean
#' and standard deviation, emitted as `b("<param>") ~ normal(mean, sd)`
#' fixed-effect priors. **Cross-parameter correlation is discarded** -- the
#' moment-only path keeps the marginals, not the joint. The richer joint method
#' (`"pesto"`, the PESTO-native prior preserving covariance + positive-orthant
#' structure) and the kernel-density method (`"kde"`, via kernR) are specified
#' but not yet wired;
#' they raise a structured error naming their gate and the available fallback.
#'
#' @param ensemble A C5 ensemble source: an `fb_ensemble`, a PESTO
#'   `pesto_ensemble_manifest`, a `list(params, outputs, ...)`, or a file path.
#' @param method One of `"moments"` (default), `"pesto"`, `"kde"`.
#' @param parameters Optional character vector selecting a subset of the
#'   ensemble's parameter columns. `NULL` (default) uses all of them.
#'
#' @return An `fb_prior` object (see [fb_prior()]), ready to pass to
#'   `flexybayes(..., prior = )`.
#' @seealso [fb_pesto()], [as_fb_ensemble()], [fb_prior()].
#' @examples
#' e <- fb_ensemble(
#'   params = data.frame(k = stats::rnorm(50, 2, 0.3),
#'                       r = stats::rnorm(50, 0.5, 0.1)),
#'   outputs = data.frame(yield = stats::rnorm(50))
#' )
#' p <- fb_prior_from_ensemble(e)
#' p
#' @export
fb_prior_from_ensemble <- function(
  ensemble,
  method = c("moments", "pesto", "kde"),
  parameters = NULL
) {
  method <- match.arg(method)
  e <- as_fb_ensemble(ensemble)

  if (method == "pesto") {
    stop(
      "fb_prior_from_ensemble(method = \"pesto\"): the joint PESTO-native ",
      "prior (covariance + positive-orthant structure, Contract E / ADR 0008) ",
      "is not yet wired. Use method = \"moments\" for the marginal ",
      "(mean + sd) prior, or wait for the ADR 0008 release.",
      call. = FALSE
    )
  }
  if (method == "kde") {
    stop(
      "fb_prior_from_ensemble(method = \"kde\"): the kernel-density prior ",
      "(via kernR) is not yet wired, and requires a backend supporting ",
      "custom-density priors (greta; not INLA). Use method = \"moments\".",
      call. = FALSE
    )
  }

  params <- e$params
  if (!is.null(parameters)) {
    miss <- setdiff(parameters, colnames(params))
    if (length(miss) > 0L) {
      stop(
        "fb_prior_from_ensemble(): parameters not in the ensemble: ",
        paste(miss, collapse = ", "),
        ".",
        call. = FALSE
      )
    }
    params <- params[, parameters, drop = FALSE]
  }

  num <- vapply(params, is.numeric, logical(1L))
  if (!all(num)) {
    params <- params[, num, drop = FALSE]
  }
  if (ncol(params) == 0L) {
    stop(
      "fb_prior_from_ensemble(): the ensemble has no numeric parameter ",
      "columns to build a prior from.",
      call. = FALSE
    )
  }

  nm <- colnames(params)
  mean_j <- vapply(params, mean, numeric(1L), na.rm = TRUE)
  sd_j <- vapply(params, stats::sd, numeric(1L), na.rm = TRUE)

  ok <- is.finite(mean_j) & is.finite(sd_j) & sd_j > 0
  if (!any(ok)) {
    stop(
      "fb_prior_from_ensemble(): no parameter has a finite, positive ",
      "ensemble standard deviation; cannot build a normal prior.",
      call. = FALSE
    )
  }
  if (!all(ok)) {
    message(
      "flexyBayes: dropping degenerate (zero / non-finite SD) parameter(s) ",
      "from the moments prior: ",
      paste(nm[!ok], collapse = ", "),
      ". They carry no spread for a normal prior."
    )
  }

  forms <- lapply(which(ok), function(j) {
    stats::as.formula(
      bquote(b(.(nm[j])) ~ normal(.(unname(mean_j[j])), .(unname(sd_j[j])))),
      env = baseenv()
    )
  })
  do.call(fb_prior, forms)
}

# ---- the PESTO-facing headline verb -----------------------------------------

#' Carry a PESTO calibration into flexyBayes
#'
#' Ingests a calibrated simulation ensemble (a PESTO
#' `pesto_ensemble_manifest`, or any C5-conforming source via
#' [as_fb_ensemble()]) and returns the flexyBayes-ready artefacts for the
#' "generalise" step of the
#' calibration -> validation -> generalisation pipeline: the canonical
#' [fb_ensemble()], an informative prior derived from the calibrated parameters
#' ([fb_prior_from_ensemble()]), and the per-parameter moment summary. The
#' resulting `$prior` is passed straight to `flexybayes(..., prior = )`.
#'
#' flexyBayes never executes the simulator (APSIM is run upstream by `apsimx`);
#' this verb consumes the calibration result through the contract.
#'
#' @param x A C5 ensemble source (PESTO manifest, `fb_ensemble`, list, or path).
#' @param method Prior-construction method passed to
#'   [fb_prior_from_ensemble()]; `"moments"` (default), `"pesto"`, `"kde"`.
#' @param parameters Optional subset of parameter columns for the prior.
#'
#' @return An object of class `c("fb_pesto", "list")` with components
#'   `ensemble` (the [fb_ensemble()]), `prior` (the derived [fb_prior()]),
#'   `moments` (a `data.frame` of `parameter`, `mean`, `sd`), `method`, and
#'   `provenance`.
#' @seealso [fb_prior_from_ensemble()], [as_fb_ensemble()].
#' @examples
#' e <- fb_ensemble(
#'   params = data.frame(k = stats::rnorm(50, 2, 0.3)),
#'   outputs = data.frame(yield = stats::rnorm(50))
#' )
#' res <- fb_pesto(e)
#' res$prior
#' @export
fb_pesto <- function(
  x,
  method = c("moments", "pesto", "kde"),
  parameters = NULL
) {
  method <- match.arg(method)
  e <- as_fb_ensemble(x)
  prior <- fb_prior_from_ensemble(e, method = method, parameters = parameters)

  params <- e$params
  if (!is.null(parameters)) {
    params <- params[, intersect(parameters, colnames(params)), drop = FALSE]
  }
  num <- vapply(params, is.numeric, logical(1L))
  params <- params[, num, drop = FALSE]
  moments <- data.frame(
    parameter = colnames(params),
    mean = vapply(params, mean, numeric(1L), na.rm = TRUE),
    sd = vapply(params, stats::sd, numeric(1L), na.rm = TRUE),
    row.names = NULL,
    stringsAsFactors = FALSE
  )

  structure(
    list(
      ensemble = e,
      prior = prior,
      moments = moments,
      method = method,
      provenance = e$provenance
    ),
    class = c("fb_pesto", "list")
  )
}

# ---- display ----------------------------------------------------------------

#' @export
print.fb_pesto <- function(x, ...) {
  cat("-- fb_pesto (calibration -> flexyBayes prior, C5 consumer) -\n")
  cat(
    "  source : ",
    x$provenance$source %||% "?",
    " | sets: ",
    nrow(x$ensemble$params),
    " | method: ",
    x$method,
    "\n",
    sep = ""
  )
  cat(
    "  prior  : ",
    length(x$prior$specs %||% x$prior),
    " parameter prior(s)\n",
    sep = ""
  )
  cat("  moments:\n")
  print(utils::head(x$moments, 10L))
  if (nrow(x$moments) > 10L) {
    cat("  ... ", nrow(x$moments) - 10L, " more\n", sep = "")
  }
  cat("------------------------------------------------------------\n")
  invisible(x)
}
