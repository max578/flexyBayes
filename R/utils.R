# Internal utility helpers for flexyBayes
# Not exported

# Add a line of code to the code generation context
.add <- function(ctx, ...) {
  ctx$code <- c(ctx$code, paste0(...))
  ctx
}

# Register a parameter name in the context
.add_param <- function(ctx, ...) {
  ctx$params <- c(ctx$params, c(...))
  ctx
}

# Add a term to the linear predictor
.add_pred <- function(ctx, term_str) {
  ctx$predictor <- c(ctx$predictor, term_str)
  ctx
}

# Safe deparse of formula sub-expression
.dep <- function(expr, i) {
  if (length(expr) >= i) deparse(expr[[i]]) else NA_character_
}

# Safe deparse of a named argument inside a call expression. Returns
# NA_character_ when the argument is absent. Used by the formula parser
# to extract structured-covariance named arguments (chol, precision,
# ...) from vm() / ped() special-term calls without disturbing the
# existing
# positional-V backward-compat path.
.dep_named <- function(expr, name) {
  nms <- names(expr)
  if (is.null(nms)) {
    return(NA_character_)
  }
  idx <- which(nms == name)
  if (length(idx) == 0L) {
    return(NA_character_)
  }
  deparse(expr[[idx[[1L]]]])
}

# Resolve family and link function
#
# @param family Character: gaussian, binomial, poisson, negative_binomial,
#   gamma, beta
# @param link Character or NULL: override default link
# @return List with family and link
.resolve_family <- function(family, link) {
  defaults <- list(
    gaussian = "identity",
    binomial = "logit",
    binary = "logit",
    poisson = "log",
    negative_binomial = "log",
    negbinom = "log",
    gamma = "log",
    beta = "logit"
  )
  fam <- tolower(family)
  if (!fam %in% names(defaults)) {
    stop(.fb_refusal_condition(
      reason_code = "unsupported_family",
      message = paste0(
        "Unsupported family \"",
        family,
        "\". flexyBayes supports: ",
        paste(names(defaults), collapse = ", "),
        ". Other families (including survival / time-to-event and ",
        "multivariate responses) are planned future work; see ",
        "fb_refusals()."
      ),
      family_class = "flexybayes_unsupported_family"
    ))
  }
  lnk <- if (!is.null(link)) tolower(link) else defaults[[fam]]
  list(family = fam, link = lnk)
}

# Map flexyBayes family string to stats::family object
.get_stats_family <- function(fam_link) {
  switch(
    fam_link$family,
    "gaussian" = gaussian(link = fam_link$link),
    "binomial" = ,
    "binary" = binomial(link = fam_link$link),
    "poisson" = poisson(link = fam_link$link),
    "negative_binomial" = ,
    "negbinom" = poisson(link = "log"),
    "gamma" = Gamma(link = fam_link$link),
    "beta" = gaussian(link = "identity"),
    gaussian()
  )
}
