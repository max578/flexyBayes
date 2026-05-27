# Truth-display helpers --- ADR 0030 Decision 4 (v0.3.8)
#
# Shared helpers for print.flexybayes() / summary.flexybayes() /
# print.flexybayes_aggregated() / summary.flexybayes_aggregated() that
# render the two adjacent "Representation:" and "Engine:" lines. The
# split disambiguates representation regime (exact vs aggregated_exact)
# from inference engine (greta MCMC vs INLA Laplace vs brms / Stan
# HMC) --- closes 2026-05-25 audit Critical Fix #4.
#
# These helpers also back fb_plan()'s engine_label / representation_label
# slots (see R/fb_plan.R for the plan-side equivalents .engine_label_for()
# and .representation_label_for() --- the fit-side helpers below take a
# materialised fit object plus its $extras$backend_decision trace).

# .repr_label_for_fit() --- the Representation: line content.
# Reads $exactness directly (the canonical slot since ADR 0022) and
# attaches the compression ratio for aggregated_exact when N/K >= 2.
.repr_label_for_fit <- function(fit, bd) {
  exact <- fit$exactness %||% "exact"
  if (identical(exact, "aggregated_exact")) {
    am <- fit$extras$aggregation_meta
    if (!is.null(am) && !is.null(am$N) && !is.null(am$K) &&
        am$K > 0L && am$N / am$K >= 2)
      return(sprintf("aggregated_exact (compression %.0f:1)",
                     am$N / am$K))
    return("aggregated_exact")
  }
  exact
}

# .engine_label_for_fit() --- the Engine: line content. Maps the
# backend_decision trace's $backend + $path tuple to a human-readable
# inference-engine + approximation-regime phrase.
.engine_label_for_fit <- function(fit, bd) {
  backend <- bd$backend %||% NA_character_
  path    <- bd$path    %||% NA_character_
  if (is.na(backend)) return("(unknown engine)")
  if (identical(backend, "greta"))  return("greta MCMC")
  if (identical(backend, "brms"))   return("brms / Stan HMC")
  if (identical(backend, "inla")) {
    if (identical(path, "aggregated_inla"))
      return("INLA Laplace (aggregated)")
    return("INLA Laplace")
  }
  if (identical(backend, "gretaR"))
    return("gretaR (R-native; dormant at v0.3.x)")
  backend
}
