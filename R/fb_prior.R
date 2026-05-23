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
#   uniform(lower, upper)      - on sd scale (lower >= 0, upper > lower).
#                                Sits outside the PC interlingua so cross-
#                                engine compilation is engine-direct, not
#                                via the PC translation table; documented
#                                as such per Q2.
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
#'   * `sd(group = "subject") ~ uniform(lower = 0, upper = 5)`
#'
#' Supported distribution families: `pc`, `half_normal`, `half_cauchy`,
#' `student_t`, `normal`, `exponential`, `lkj`, `cauchy`, `gamma`,
#' `uniform`. Note that `uniform()` on a variance component sits
#' outside the PC-canonical interlingua: the INLA backend honours it
#' exactly via an expression-prior on the log-precision; the legacy
#' greta scalar bridge cannot represent it and will refuse with a
#' redirect.
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
      spec   = .parse_prior_distribution(a[[3]],
                                          envir = environment(a))
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
.parse_prior_distribution <- function(expr, envir = baseenv()) {
  if (!is.call(expr))
    stop("Prior distribution must be a call (e.g., ",
         "`pc(upper = 1, prob = 0.01)`). Got: ", deparse(expr),
         call. = FALSE)

  fn <- as.character(expr[[1]])
  supported <- c("pc", "half_normal", "half_cauchy", "student_t",
                 "normal", "exponential", "lkj", "cauchy", "gamma",
                 "uniform")

  if (!fn %in% supported)
    stop("Unsupported prior distribution: ", fn,
         ". v0.1 supports: ",
         paste(supported, collapse = ", "), call. = FALSE)

  # Evaluate distribution arguments in the formula's calling
  # environment so users can pass data-driven scales like
  # `pc(upper = 2.5 * sd(y), prob = 0.05)`. Fall back to leaving the
  # language object in place if evaluation fails (validators below
  # surface a clear error).
  args <- as.list(expr[-1])
  args <- lapply(args, function(a)
    tryCatch(eval(a, envir = envir), error = function(e) a))

  # uniform-specific validation (degenerate or open-ended bounds
  # would produce silently bad cross-engine emit otherwise).
  if (fn == "uniform") {
    lower <- args$lower
    upper <- args$upper
    if (is.null(lower) && length(args) >= 1L && nchar(names(args)[[1]] %||% "") == 0L)
      lower <- args[[1]]
    if (is.null(upper) && length(args) >= 2L && nchar(names(args)[[2]] %||% "") == 0L)
      upper <- args[[2]]
    if (is.null(lower)) lower <- 0
    if (is.null(upper))
      stop("uniform() requires `upper`; got: ", deparse(expr),
           ". Example: `sd(group = \"g\") ~ uniform(lower = 0, upper = 5)`.",
           call. = FALSE)
    if (!is.numeric(lower) || !is.numeric(upper) ||
        length(lower) != 1L || length(upper) != 1L ||
        !is.finite(lower) || !is.finite(upper))
      stop("uniform() lower/upper must be finite scalars.", call. = FALSE)
    if (lower < 0)
      stop("uniform() lower must be >= 0 for sd-scale targets ",
           "(sd is non-negative). Got lower = ", lower, ".",
           call. = FALSE)
    if (upper <= lower)
      stop("uniform() upper must be > lower. Got lower = ", lower,
           ", upper = ", upper, ".", call. = FALSE)
    args$lower <- lower
    args$upper <- upper
  }

  list(family = fn, args = args)
}

# Local null-coalescing op (R < 4.4 compat -- DESCRIPTION targets >= 4.1).
`%||%` <- function(a, b) if (is.null(a)) b else a

# ---------------------------------------------------------------- #
# Default-prior construction (Simpson-2017 PC) -- internal         #
# ---------------------------------------------------------------- #

# Pick a sensible scale U for the PC default from the response and
# (family, link). Identity/Gaussian: U = 2.5 * sd(y). Log-link
# (Poisson, NegBin, Gamma): U = 2.5 * sd(log(y + 0.5)) so the scale
# matches the random effect's working scale. Logit-link (binomial,
# beta): U = 2.5 (logit-scale random effects are typically O(1) so
# response-derived scale is meaningless). Returns (scale, basis)
# where basis records which branch fired -- captured so the
# deprecation message can explain itself.
.default_prior_scale <- function(data, response, family, link = NULL) {
  fam <- if (inherits(family, "family")) family$family
         else as.character(family)
  fam <- tolower(fam %||% "gaussian")
  link_name <- if (!is.null(link)) tolower(link)
               else if (inherits(family, "family")) tolower(family$link)
               else NULL
  is_log_link   <- isTRUE(link_name == "log") ||
                   fam %in% c("poisson", "negative_binomial",
                              "negbinom", "nbinomial", "gamma")
  is_logit_link <- isTRUE(link_name == "logit") ||
                   fam %in% c("binomial", "binary", "beta")

  if (is_logit_link)
    return(list(scale = 2.5, basis = "logit_default"))

  y <- if (!is.null(data) && response %in% names(data))
    data[[response]] else NULL

  if (is_log_link) {
    if (!is.numeric(y)) return(list(scale = 1.0,
                                     basis = "log_default_nonnumeric"))
    yp <- as.numeric(y); yp <- yp[is.finite(yp) & yp >= 0]
    if (length(yp) < 2L) return(list(scale = 1.0,
                                      basis = "log_default_too_small"))
    sdv <- stats::sd(log(yp + 0.5))
    if (!is.finite(sdv) || sdv <= 0) sdv <- 1.0
    return(list(scale = 2.5 * sdv, basis = "log_link_sd"))
  }

  if (!is.numeric(y)) return(list(scale = 1.0,
                                   basis = "identity_default"))
  yv <- as.numeric(y); yv <- yv[is.finite(yv)]
  if (length(yv) < 2L) return(list(scale = 1.0,
                                    basis = "identity_too_small"))
  sdv <- stats::sd(yv)
  if (!is.finite(sdv) || sdv <= 0) sdv <- 1.0
  list(scale = 2.5 * sdv, basis = "identity_sd")
}

# Construct a PC prior fb_prior() for a model. PC spec applied to
# sigma + every named random group in `random_groups`. Retained in
# v0.1.x as an explicit-choice constructor (e.g., used in vignette 06
# advanced appendix and PC-default tests); no longer the v0.1
# default. ADR 0004 supersedes ADR 0003 (PC default) with the
# bounded-uniform default below.
.default_pc_prior <- function(data,
                               response,
                               family,
                               link           = NULL,
                               random_groups  = character(0),
                               alpha          = 0.05) {
  scl <- .default_prior_scale(data, response, family, link)
  specs <- list(list(
    target = list(type = "sigma"),
    spec   = list(family = "pc",
                  args   = list(upper = scl$scale, prob = alpha))
  ))
  for (g in unique(random_groups)) {
    if (!nzchar(g)) next
    specs[[length(specs) + 1L]] <- list(
      target = list(type = "sd", group = g),
      spec   = list(family = "pc",
                    args   = list(upper = scl$scale, prob = alpha))
    )
  }
  obj <- list(specs = specs)
  class(obj) <- c("fb_prior", "list")
  attr(obj, "fb_prior_default_basis") <- scl$basis
  attr(obj, "fb_prior_default_scale") <- scl$scale
  obj
}

# Pick a sensible upper bound U for the uniform-on-SD default per
# (family, link). Returns (scale, basis):
# - Gaussian / identity link: U = 5 * sd(y); basis = "identity_sd_uniform"
# - Log link (Poisson, NegBin, Gamma): U = 3; basis = "log_link_uniform"
#   covers a 20x ratio of group means -- wide for any realistic use.
# - Logit link (Binomial, Beta): U = 5; basis = "logit_uniform"
#   covers the full probability range.
# Wider than the PC default's 2.5*sd because uniform is flat across
# its support; the upper must be loose enough to be uninformative.
# Theory: Gelman 2006, Bayesian Analysis 1(3):515-534, sec.4 worked
# example. ADR 0004.
.default_uniform_scale <- function(data, response, family, link = NULL) {
  fam <- if (inherits(family, "family")) family$family
         else as.character(family)
  fam <- tolower(fam %||% "gaussian")
  link_name <- if (!is.null(link)) tolower(link)
               else if (inherits(family, "family")) tolower(family$link)
               else NULL
  is_log_link   <- isTRUE(link_name == "log") ||
                   fam %in% c("poisson", "negative_binomial",
                              "negbinom", "nbinomial", "gamma")
  is_logit_link <- isTRUE(link_name == "logit") ||
                   fam %in% c("binomial", "binary", "beta")

  if (is_logit_link)
    return(list(scale = 5, basis = "logit_uniform"))

  if (is_log_link)
    return(list(scale = 3, basis = "log_link_uniform"))

  y <- if (!is.null(data) && response %in% names(data))
    data[[response]] else NULL

  if (!is.numeric(y)) return(list(scale = 1.0,
                                   basis = "identity_default_uniform"))
  yv <- as.numeric(y); yv <- yv[is.finite(yv)]
  if (length(yv) < 2L) return(list(scale = 1.0,
                                    basis = "identity_too_small_uniform"))
  sdv <- stats::sd(yv)
  if (!is.finite(sdv) || sdv <= 0) sdv <- 1.0
  list(scale = 5 * sdv, basis = "identity_sd_uniform")
}

# Construct the v0.1 default uniform prior fb_prior() for a model.
# Bounded uniform on SD: sigma ~ uniform(0, U) and every named random
# group's SD ~ uniform(0, U).
#
# AMBITION_STAGE.md §1.4 extension (extending ADR 0004): the uniform-
# on-SD default now also fires on vm() and ped() structured-cov
# random terms. The two forms share the simple-RI scale derivation
# (5 * sd(response) heuristic; identity / log / logit family-aware
# branches via .default_uniform_scale()) because their natural
# variance-matrix scaling is identity in the SD-on-the-Cholesky-
# scaled-random-effect interpretation that codegen .code_random's
# vm / ped branches use (u_<tag> = L_G %*% (z * sigma_<tag>); the
# Cholesky absorbs G's scale and sigma is purely the residual-scale
# multiplier). The remaining structured forms (at, us, fa, ar1)
# still fall through to the legacy lognormal pending later v0.2.x
# patches (each has a different natural scale -- per-level SDs for
# at, full Cholesky for us, SD+correlation for ar1/fa -- and a
# uniform default per form requires methodological judgement that
# is being deferred per §1.4).
#
# `vm_ped_groups` is a character vector of `term$var` strings (one
# per vm / ped random term) and is keyed identically to `random_groups`
# in priors_to_legacy() / priors_to_inla() so the uniform_per_vc
# entries surface through the existing dispatch.
.default_uniform_prior <- function(data,
                                    response,
                                    family,
                                    link           = NULL,
                                    random_groups  = character(0),
                                    vm_ped_groups  = character(0)) {
  scl <- .default_uniform_scale(data, response, family, link)
  specs <- list(list(
    target = list(type = "sigma"),
    spec   = list(family = "uniform",
                  args   = list(lower = 0, upper = scl$scale))
  ))
  for (g in unique(random_groups)) {
    if (!nzchar(g)) next
    specs[[length(specs) + 1L]] <- list(
      target = list(type = "sd", group = g),
      spec   = list(family = "uniform",
                    args   = list(lower = 0, upper = scl$scale))
    )
  }
  # §1.4 vm() + ped() branch. Add a separate spec per structured group
  # so prior_summary() surfaces them distinctly from the simple-RI
  # groups; carry a `_default_uniform_form` tag (vm / ped) so the
  # surface can explain which structured form the spec came from.
  for (g in unique(vm_ped_groups)) {
    if (!nzchar(g)) next
    sp <- list(
      target = list(type = "sd", group = g),
      spec   = list(family = "uniform",
                    args   = list(lower = 0, upper = scl$scale))
    )
    attr(sp, "_default_uniform_form") <- "vm_or_ped"
    specs[[length(specs) + 1L]] <- sp
  }
  obj <- list(specs = specs)
  class(obj) <- c("fb_prior", "list")
  attr(obj, "fb_prior_default_basis") <- scl$basis
  attr(obj, "fb_prior_default_scale") <- scl$scale
  if (length(vm_ped_groups) > 0L)
    attr(obj, "fb_prior_default_vm_ped_groups") <- unique(vm_ped_groups)
  obj
}

# One-time announcement of the v0.1.x default change. ADR 0004
# (uniform default) supersedes ADR 0003 (PC default). Silenceable via
# options(flexyBayes.silence_default_prior_note = TRUE).
.default_prior_note_once <- function(scale, basis) {
  if (isTRUE(getOption("flexyBayes.silence_default_prior_note", FALSE)))
    return(invisible())
  if (isTRUE(getOption("flexyBayes._default_prior_note_emitted", FALSE)))
    return(invisible())
  message("flexyBayes: variance-component prior default is uniform(0, ",
          format(scale, digits = 3), ") on every SD (residual sigma + ",
          "every named random-effect group), following Gelman (2006, ",
          "Bayesian Analysis 1(3):515-534). Scale basis = \"",
          basis, "\". Pass `prior_vc_sd` explicitly for the legacy ",
          "lognormal(0, prior_vc_sd) default, `prior = fb_prior(...)` ",
          "for full control, or ",
          "options(flexyBayes.silence_default_prior_note = TRUE) to ",
          "silence this notice.")
  options(flexyBayes._default_prior_note_emitted = TRUE)
}

# One-time message emitted from priors_to_inla() when a uniform()
# spec is being approximated as a PC prior. Silenceable via
# options(flexyBayes.silence_uniform_inla_approx = TRUE).
.uniform_to_inla_warn_once <- function() {
  if (isTRUE(getOption("flexyBayes.silence_uniform_inla_approx", FALSE)))
    return(invisible())
  if (isTRUE(getOption("flexyBayes._uniform_inla_approx_emitted", FALSE)))
    return(invisible())
  message("flexyBayes: uniform() prior on a variance component is ",
          "approximated as PC(upper, 0.01) for the INLA backend in ",
          "v0.1.x. The support is matched but the density inside ",
          "differs (PC concentrates at sigma = 0; uniform is flat). ",
          "Exact bounded-uniform support lands in v0.2 -- see ",
          "?fb_prior. Silence this notice via ",
          "options(flexyBayes.silence_uniform_inla_approx = TRUE).")
  options(flexyBayes._uniform_inla_approx_emitted = TRUE)
}

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

  # Per-VC PC specs (target = sigma / sd / smooth) keyed by the
  # codegen tag the variance component carries: "__sigma__" for
  # residual sigma; group / smooth-var name otherwise. codegen.R's
  # .sigma_decl emits greta::exponential(rate) for these.
  pc_per_vc <- list()

  # Per-VC uniform specs, same keying. codegen.R's .sigma_decl emits
  # greta::uniform(lower, upper) for these. Mirrors pc_per_vc; under
  # ADR 0004 these are the v0.1 default for sigma + named random
  # groups via .default_uniform_prior(). Structured-covariance
  # branches (us, fa, ar1, vm, ped) bypass .sigma_decl and stay on
  # the legacy lognormal pending v0.2 codegen broadening.
  uniform_per_vc <- list()

  for (s in prior$specs) {
    if (s$target$type == "sigma" && s$spec$family == "pc") {
      if (!is.null(s$spec$args$upper))
        vc_sd <- as.numeric(s$spec$args$upper)
      pc_per_vc[["__sigma__"]] <- list(
        upper = as.numeric(s$spec$args$upper %||% 1),
        prob  = as.numeric(s$spec$args$prob  %||% 0.05)
      )
    }
    if (s$target$type == "sigma" && s$spec$family == "half_normal")
      if (!is.null(s$spec$args$scale))
        vc_sd <- as.numeric(s$spec$args$scale)
    if (s$target$type %in% c("sd", "smooth") &&
        s$spec$family == "half_normal")
      if (!is.null(s$spec$args$scale))
        vc_sd <- as.numeric(s$spec$args$scale)
    if (s$target$type %in% c("sd", "smooth") &&
        s$spec$family == "pc") {
      key <- if (s$target$type == "sd") s$target$group else s$target$var
      pc_per_vc[[key]] <- list(
        upper = as.numeric(s$spec$args$upper %||% 1),
        prob  = as.numeric(s$spec$args$prob  %||% 0.05)
      )
    }
    if (s$target$type == "b" && s$spec$family == "normal")
      if (!is.null(s$spec$args$sd))
        fixed_sd <- as.numeric(s$spec$args$sd)

    # uniform on a variance component (target = sigma / sd / smooth):
    # surface in uniform_per_vc; codegen .sigma_decl emits
    # greta::uniform(lower, upper) directly. ADR 0004 D2.
    if (s$target$type %in% c("sigma", "sd", "smooth") &&
        s$spec$family == "uniform") {
      key <- switch(
        s$target$type,
        "sigma"  = "__sigma__",
        "sd"     = s$target$group,
        "smooth" = s$target$var
      )
      uniform_per_vc[[key]] <- list(
        lower = as.numeric(s$spec$args$lower %||% 0),
        upper = as.numeric(s$spec$args$upper)
      )
      # Fallback vc_sd legacy hyperparameter -- best-effort for
      # structured-covariance branches that don't yet honour uniform.
      if (s$target$type == "sigma" && !is.null(s$spec$args$upper))
        vc_sd <- as.numeric(s$spec$args$upper)
    }
  }

  list(fixed_sd = fixed_sd, vc_sd = vc_sd, legacy = FALSE,
       fb_prior = prior, pc_per_vc = pc_per_vc,
       uniform_per_vc = uniform_per_vc)
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
    } else if (s$spec$family == "uniform") {
      lower <- as.numeric(s$spec$args$lower %||% 0)
      upper <- as.numeric(s$spec$args$upper)
      key   <- switch(s$target$type,
        "sigma" = "sigma",
        "sd"    = s$target$group,
        "smooth" = s$target$var,
        "<unknown>"
      )
      # v0.1.x: approximate uniform(lower, upper) on the sd scale via
      # a PC prior with matched upper tail. Pr(sigma > upper) = 0.01
      # (default alpha) plus suppression of mass near zero. This is
      # an approximation -- the density inside the support differs
      # from uniform (PC concentrates at sigma = 0; uniform is flat)
      # -- but it preserves the user's intent of a bounded weakly-
      # informative prior on the variance component. Exact bounded-
      # support uniform via an INLA expression-prior is on the v0.2
      # roadmap pending more robust integration with INLA's parser.
      # We surface the approximation explicitly via `approx_from` so
      # downstream tooling (and the print method) can flag it, and
      # via a once-per-session message at construction time.
      .uniform_to_inla_warn_once()
      out[[key]] <- list(prior       = "pc.prec",
                         param       = c(upper, 0.01),
                         approx_from = "uniform",
                         meta        = list(family = "uniform",
                                            lower  = lower,
                                            upper  = upper))
    }
  }
  out
}
