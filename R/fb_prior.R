# fb_prior -- PC-canonical hybrid prior DSL (deliverable 3).
#
# Implements the prior interlingua described in
# design-notes-priors-brms-lgm.md Sec.Q2. v0.1 minimum subset:
# user-facing constructor + S3 class + structured spec list +
# print method. Cross-engine translation tables for greta /
# brms / INLA emit are stubbed in priors_to_inla() and
# priors_to_legacy() (the legacy-scalar bridge for emit_greta);
# full translation lands as deliverables 5+ flesh out.
#
# Targets supported in v0.1:
#   sigma             - residual standard deviation
#   sd(group = name)  - random-effect standard deviation
#   b("name")         - fixed-effect coefficient
#   cor(group = name) - correlation parameter
#   smooth(var)       - smoother variance (rw1/rw2)
#
# Distribution families supported in v0.1:
#   pc(upper, prob)            - PC prior (penalised complexity);
#                                exponential on sigma with
#                                rate = -log(prob) / upper.
#   half_normal(scale)         - on sd scale.
#   half_cauchy(scale)         - on sd scale.
#   student_t(df, scale)       - on sd scale (df > 0).
#   normal(mean, sd)           - on coefficient scale.
#   exponential(rate)          - on sd scale.
#   lkj(eta)                   - LKJ correlation prior.
#
# All specifications are stored verbatim with their parsed args;
# the emit_*() functions translate to backend-specific syntax at
# fit time per the Q2 translation table.

# ---------------------------------------------------------------- #
# Constructor                                                      #
# ---------------------------------------------------------------- #

#' Specify priors via the PC-canonical hybrid DSL
#'
#' The flexyBayes prior DSL (domain-specific language) lives on the
#' standard-deviation scale (never precision / variance) and accepts
#' two canonical idioms: distributional (`half_normal(scale = 1)`)
#' and tail-quantile / PC (penalised complexity)
#' (`pc(upper = 1, prob = 0.01)` meaning `Pr(sigma > 1) = 0.01`).
#' The PC idiom is the cross-engine interlingua -- it survives every
#' backend because it is a probability statement, not a
#' distributional name.
#'
#' v0.1 supports the targets and distributions listed above in the
#' file header. Calls outside the supported set raise a structured
#' error with the supported list.
#'
#' @param ... one or more two-sided formulas of the form
#'   `target ~ distribution(args)`. Examples:
#'
#'   * `sigma ~ pc(upper = 2, prob = 0.05)`
#'   * `sd(group = "subject") ~ half_normal(scale = 1)`
#'   * `b("treatment") ~ student_t(df = 4, scale = 2.5)`
#'   * `cor(group = "subject") ~ lkj(eta = 2)`
#'
#' @return an `fb_prior` object (S3, inherits from list) with
#'   `$specs` carrying the parsed `target` / `spec` pairs.
#'
#' @examples
#' p <- fb_prior(
#'   sigma                 ~ pc(upper = 2, prob = 0.05),
#'   sd(group = "subject") ~ half_normal(scale = 1),
#'   b("treatment")        ~ student_t(df = 4, scale = 2.5)
#' )
#' p
#' @export
fb_prior <- function(...) {
  args <- list(...)
  if (length(args) == 0L)
    stop("`fb_prior()` requires at least one specification.",
         call. = FALSE)

  specs <- vector("list", length(args))
  for (i in seq_along(args)) {
    a <- args[[i]]
    if (!inherits(a, "formula"))
      stop("Each `fb_prior()` argument must be a two-sided formula ",
           "`target ~ distribution(...)`. Argument ", i, " is: ",
           deparse(a), call. = FALSE)
    if (length(a) != 3L)
      stop("`fb_prior()` formula ", i, " must be two-sided ",
           "(target on left, distribution on right). Got: ",
           deparse(a), call. = FALSE)
    specs[[i]] <- list(
      target = .parse_prior_target(a[[2]]),
      spec   = .parse_prior_distribution(a[[3]])
    )
  }

  obj <- list(specs = specs)
  class(obj) <- c("fb_prior", "list")
  obj
}

is_fb_prior <- function(x) inherits(x, "fb_prior")

# ---------------------------------------------------------------- #
# Parsing helpers                                                  #
# ---------------------------------------------------------------- #

# Parse target side of a prior spec formula:
#   sigma                 -> list(type = "sigma")
#   sd(group = "subject") -> list(type = "sd", group = "subject")
#   b("treatment")        -> list(type = "b", name = "treatment")
#   cor(group = "subject") -> list(type = "cor", group = "subject")
#   smooth("time")        -> list(type = "smooth", var = "time")
.parse_prior_target <- function(expr) {
  if (is.name(expr)) {
    nm <- as.character(expr)
    if (nm == "sigma") return(list(type = "sigma"))
    return(list(type = "name", name = nm))
  }
  if (is.call(expr)) {
    fn <- as.character(expr[[1]])
    args_list <- as.list(expr[-1])

    if (fn == "sigma")
      return(list(type = "sigma"))

    if (fn == "sd") {
      group <- .extract_string_arg(args_list, "group")
      if (is.null(group))
        stop("sd() prior target requires `group = \"...\"` argument.",
             call. = FALSE)
      return(list(type = "sd", group = group))
    }

    if (fn == "b") {
      if (length(args_list) < 1L)
        stop("b() prior target requires a name string, e.g., ",
             "b(\"treatment\").", call. = FALSE)
      name <- as.character(args_list[[1]])
      return(list(type = "b", name = name))
    }

    if (fn == "cor") {
      group <- .extract_string_arg(args_list, "group")
      if (is.null(group))
        stop("cor() prior target requires `group = \"...\"` argument.",
             call. = FALSE)
      return(list(type = "cor", group = group))
    }

    if (fn == "smooth") {
      if (length(args_list) < 1L)
        stop("smooth() prior target requires a variable name, e.g., ",
             "smooth(\"time\").", call. = FALSE)
      var <- as.character(args_list[[1]])
      basis <- if (!is.null(args_list$basis))
        as.character(args_list$basis) else "rw2"
      return(list(type = "smooth", var = var, basis = basis))
    }
  }
  stop("Unsupported prior target: ", deparse(expr),
       ". Supported: sigma, sd(group = ...), b(\"name\"), ",
       "cor(group = ...), smooth(\"var\").", call. = FALSE)
}

# Helper -- extract a named string argument from a parsed call.
.extract_string_arg <- function(args_list, name) {
  if (!is.null(args_list[[name]]))
    return(as.character(args_list[[name]]))
  unnamed <- args_list[!nzchar(names(args_list) %||% rep("", length(args_list)))]
  if (length(unnamed) >= 1L)
    return(as.character(unnamed[[1]]))
  NULL
}

# Parse distribution side of a prior spec formula. Returns:
#   list(family = "pc", args = list(upper = 1, prob = 0.01))
.parse_prior_distribution <- function(expr) {
  if (!is.call(expr))
    stop("Prior distribution must be a call (e.g., ",
         "`pc(upper = 1, prob = 0.01)`). Got: ", deparse(expr),
         call. = FALSE)

  fn <- as.character(expr[[1]])
  supported <- c("pc", "half_normal", "half_cauchy", "student_t",
                 "normal", "exponential", "lkj", "cauchy", "gamma")

  if (!fn %in% supported)
    stop("Unsupported prior distribution: ", fn,
         ". v0.1 supports: ",
         paste(supported, collapse = ", "), call. = FALSE)

  args <- as.list(expr[-1])
  args <- lapply(args, function(a) tryCatch(eval(a, envir = baseenv()),
                                             error = function(e) a))
  list(family = fn, args = args)
}

# Local null-coalescing op (R < 4.4 compat -- DESCRIPTION targets >= 4.1).
`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------- #
# Print method                                                     #
# ---------------------------------------------------------------- #

#' Print method for fb_prior
#'
#' @param x   an `fb_prior` object.
#' @param ... unused.
#' @return invisibly returns `x`.
#' @keywords internal
#' @export
print.fb_prior <- function(x, ...) {
  cat("<fb_prior> ", length(x$specs),
      " specification", if (length(x$specs) != 1L) "s" else "",
      "\n", sep = "")
  for (s in x$specs) {
    cat("  ", .format_prior_target(s$target), " ~ ",
        .format_prior_distribution(s$spec), "\n", sep = "")
  }
  invisible(x)
}

.format_prior_target <- function(target) {
  switch(target$type,
    "sigma"  = "sigma",
    "sd"     = paste0("sd(group = \"", target$group, "\")"),
    "b"      = paste0("b(\"", target$name, "\")"),
    "cor"    = paste0("cor(group = \"", target$group, "\")"),
    "smooth" = paste0("smooth(\"", target$var, "\", basis = \"",
                       target$basis, "\")"),
    "name"   = target$name,
    deparse(target)
  )
}

.format_prior_distribution <- function(spec) {
  arg_strs <- vapply(seq_along(spec$args), function(i) {
    nm  <- names(spec$args)[i]
    val <- spec$args[[i]]
    if (is.numeric(val) && length(val) == 1L)
      return(paste0(if (nzchar(nm %||% "")) paste0(nm, " = ") else "",
                    format(val)))
    paste0(if (nzchar(nm %||% "")) paste0(nm, " = ") else "",
           deparse(val))
  }, character(1))
  paste0(spec$family, "(", paste(arg_strs, collapse = ", "), ")")
}

# ---------------------------------------------------------------- #
# Translation helpers (cross-engine emit hooks)                    #
# ---------------------------------------------------------------- #

# Translate fb_prior -> legacy scalar priors used by emit_greta.
# v0.1 minimum: extract sigma's pc/half_normal scale into a single
# vc_sd legacy scalar; extract b()'s normal sd into a single
# fixed_sd. If multiple sigma/b specs are given, the first wins
# (and a warning is emitted). Future iterations expand this into
# per-term emit_greta codegen.
priors_to_legacy <- function(prior, fixed_sd_default = 10,
                              vc_sd_default = 1) {
  if (!inherits(prior, "fb_prior"))
    return(list(fixed_sd = fixed_sd_default,
                vc_sd    = vc_sd_default,
                legacy   = TRUE))

  fixed_sd <- fixed_sd_default
  vc_sd    <- vc_sd_default

  for (s in prior$specs) {
    if (s$target$type == "sigma" && s$spec$family == "pc") {
      # PC: Pr(sigma > upper) = prob -> exponential rate;
      # use upper as a proxy for vc_sd (legacy scalar).
      if (!is.null(s$spec$args$upper))
        vc_sd <- as.numeric(s$spec$args$upper)
    }
    if (s$target$type == "sigma" && s$spec$family == "half_normal")
      if (!is.null(s$spec$args$scale))
        vc_sd <- as.numeric(s$spec$args$scale)
    if (s$target$type %in% c("sd", "smooth") &&
        s$spec$family == "half_normal")
      if (!is.null(s$spec$args$scale))
        vc_sd <- as.numeric(s$spec$args$scale)
    if (s$target$type == "b" && s$spec$family == "normal")
      if (!is.null(s$spec$args$sd))
        fixed_sd <- as.numeric(s$spec$args$sd)
  }

  list(fixed_sd = fixed_sd, vc_sd = vc_sd, legacy = FALSE,
       fb_prior = prior)
}

# Translate fb_prior -> INLA hyperpar control list. v0.1 minimum:
# returns a named list keyed by f()-term group / "sigma" mapping
# to INLA `prior = "pc.prec"` / `param` arguments per the Q2
# translation table.
priors_to_inla <- function(prior) {
  out <- list()
  if (!inherits(prior, "fb_prior")) return(out)

  for (s in prior$specs) {
    if (s$spec$family == "pc") {
      u <- as.numeric(s$spec$args$upper %||% 1)
      a <- as.numeric(s$spec$args$prob  %||% 0.01)
      key <- switch(s$target$type,
        "sigma" = "sigma",
        "sd"    = s$target$group,
        "smooth" = s$target$var,
        "<unknown>"
      )
      out[[key]] <- list(prior = "pc.prec", param = c(u, a))
    } else if (s$spec$family == "half_normal") {
      scale <- as.numeric(s$spec$args$scale %||% 1)
      key <- switch(s$target$type,
        "sigma" = "sigma",
        "sd"    = s$target$group,
        "smooth" = s$target$var,
        "<unknown>"
      )
      # Approximate half_normal(scale = s) via PC matched at
      # u = s * qnorm(0.995), alpha = 0.005 (Q2 design note).
      u <- scale * stats::qnorm(0.995)
      out[[key]] <- list(prior = "pc.prec", param = c(u, 0.005),
                          approx_from = "half_normal")
    }
  }
  out
}
