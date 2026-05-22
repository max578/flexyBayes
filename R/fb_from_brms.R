# fb_from_brms -- flexyBayes brms-format ingest path (deliverable 1).
#
# v0.1 MINIMUM SUBSET -- parses a brms-style formula
#   `response ~ fixed_effects + (1 | g1) + (1 | g2) + ...`
# via R's formula abstract syntax tree (AST). No runtime brms
# dependency for this minimum subset; brmsformula objects (built via
# brms::bf()) are accepted by unwrapping `formula$formula` when brms
# is loaded.
#
# Supported (v0.1):
# - Gaussian / binomial / poisson / Gamma / lognormal / beta family
#   names; default link or explicit override.
# - Linear fixed effects (factor / continuous / interaction /
#   I() expressions) -- re-parsed via the existing .parse_fixed
#   helper for byte-identity with the asreml ingest path.
# - Random intercepts via `(1 | g)` and `(1 || g)`.
# - Optional `weights` argument mapped to addition_terms with
#   type = "weights" (mirrors fb_from_asreml).
#
# Refused (v0.1) -- fail-fast at ingest with a clear message:
# - Random slopes `(x | g)` and uncorrelated slopes `(x || g)`.
# - Smoothers `s()`, `t2()`.
# - Gaussian processes `gp()`.
# - Autocorrelation `ar()`, `ma()`, `arma()`, `cosy()`, `car()`.
# - Distributional regression and addition terms (`cens`, `trunc`,
#   `trials`, `se`, `mi`, `weights()` inside formula; the
#   `weights` argument is supported instead).
# - Multivariate / hurdle / mixture / categorical families (caught
#   by lgm_gate post-construction or by the family-name check
#   here).
#
# Future iterations will use brms::brmsterms() for the full Q4
# v0.1 ingest set and add full random-slope translation,
# smoothers via INLA's rw1/rw2, GP via SPDE, distributional
# regression refusal hooks, and the addition-form family.

# ---------------------------------------------------------------- #
# Public-style entry -- internal in v0.1                            #
# ---------------------------------------------------------------- #

# Construct an fb_terms object from a brms-style formula.
#
# @param formula a base-R formula (recommended) or a `brmsformula`
#   object. brmsformula support requires `brms` to be installed.
# @param data data.frame containing all referenced variables.
# @param family character family name or a base-R `family()` object.
# @param link character link override or NULL.
# @param prior an fb_prior object (deliverable 3) or NULL.
# @param weights optional numeric weights vector of length
#   nrow(data). Mapped to a single addition_term with
#   type = "weights".
# @param ... currently unused; reserved for v0.2+ brms-ingest
#   options (e.g., specials, autocor handling).
# @return an fb_terms object with source = "brms".
fb_from_brms <- function(formula,
                         data,
                         family         = "gaussian",
                         link           = NULL,
                         prior          = NULL,
                         weights        = NULL,
                         prior_fixed_sd = 100,
                         prior_vc_sd    = 1,
                         ...) {

  if (inherits(formula, "brmsformula")) {
    if (!requireNamespace("brms", quietly = TRUE))
      stop("Package 'brms' is required to ingest brmsformula objects. ",
           "Install via: install.packages(\"brms\")",
           call. = FALSE)
    formula <- formula$formula
  }
  if (!inherits(formula, "formula"))
    stop("`formula` must be a formula or a brmsformula object.",
         call. = FALSE)
  if (length(formula) < 3L)
    stop("`formula` must be two-sided: response ~ predictors.",
         call. = FALSE)

  # LHS-pipe brms addition forms (`y | trials(n) ~ ...`,
  # `y | cens(c) ~ ...`, `y | weights(w) ~ ...`, `y | se(s) ~ ...`).
  # The hand-rolled v0.1 walker does not parse the addition-form
  # surface; refuse at ingest with a corpus-naming message rather
  # than fall through to the cryptic "Response variable not found
  # in data" error from the later names(data) lookup.
  if (is.call(formula[[2L]]) &&
      identical(formula[[2L]][[1L]], as.name("|")))
    stop("v0.2 brms ingest does not yet support LHS addition forms ",
         "(`y | trials(n) ~ ...`, `y | cens(c) ~ ...`, etc.). The ",
         "supported brms corpus is single-column responses only ",
         "(use `family = \"binomial\"` for Bernoulli with a 0/1 ",
         "response). Addition forms are queued for a future ",
         "expansion of the brms ingest layer. Got: ",
         deparse(formula[[2L]]), call. = FALSE)

  # ------------------------- Family + link ----------------------- #
  if (inherits(family, "family")) {
    fam_name  <- family$family
    link_name <- if (!is.null(link)) link else family$link
  } else if (is.character(family) && length(family) == 1L) {
    fl <- .resolve_family(family, link)
    fam_name  <- fl$family
    link_name <- fl$link
  } else {
    stop("`family` must be a character(1) name or a `family()` object.",
         call. = FALSE)
  }

  # ------------------------- Response --------------------------- #
  response <- deparse(formula[[2]])
  if (!response %in% names(data))
    stop("Response variable '", response, "' not found in data.",
         call. = FALSE)

  # ------------------------- Walk RHS --------------------------- #
  walked <- .brms_walk_rhs(formula[[3]])

  # Reject unsupported features fail-fast (per v0.1 minimum scope)
  if (length(walked$ext_terms) > 0L) {
    classes <- vapply(walked$ext_terms, function(t) {
      paste0(t$type, " (", t$deparse, ")")
    }, character(1))
    stop("v0.1 brms ingest does not yet support: ",
         paste(classes, collapse = ", "),
         ". These features will be added in subsequent iterations.",
         call. = FALSE)
  }

  # Build a fixed-only formula and re-parse via .parse_fixed (gives
  # us byte-identical fixed_terms output to the asreml ingest path)
  fixed_only_rhs <- if (length(walked$fixed_labels))
    paste(walked$fixed_labels, collapse = " + ") else "1"
  fixed_form <- stats::as.formula(
    paste0(response, " ~ ", fixed_only_rhs)
  )
  fixed_info <- .parse_fixed(fixed_form, data)

  # Translate each (1 | g) RE pair to a parse_formula.R-style
  # term descriptor, refusing random slopes
  random_terms <- list()
  for (pair in walked$re_pairs) {
    rt <- .brms_re_to_fb(pair, data)
    if (rt$type == "brms_re_unsupported")
      stop("v0.1 brms ingest only supports random intercepts ",
           "(1 | g) or (1 || g). Found: ", rt$deparse,
           ". Random slopes will be added in subsequent iterations.",
           call. = FALSE)
    random_terms[[length(random_terms) + 1L]] <- rt
  }

  # ------------------------- Weights --------------------------- #
  addition_terms <- if (!is.null(weights)) {
    if (!is.numeric(weights) || length(weights) != nrow(data))
      stop("`weights` must be a numeric vector of length nrow(data).",
           call. = FALSE)
    list(list(type = "weights", values = weights))
  } else {
    list()
  }

  # ------------------------- Priors ---------------------------- #
  priors <- if (!is.null(prior)) {
    prior
  } else {
    list(fixed_sd = prior_fixed_sd, vc_sd = prior_vc_sd,
         legacy = TRUE)
  }

  data_summary <- list(
    n              = nrow(data),
    known_matrices = character(0)
  )

  new_fb_terms(
    response       = response,
    family         = fam_name,
    link           = link_name,
    intercept      = fixed_info$intercept,
    fixed_terms    = fixed_info$terms,
    random_terms   = random_terms,
    rcov_terms     = list(),                # brms folds rcov into family
    addition_terms = addition_terms,
    priors         = priors,
    data_summary   = data_summary,
    capabilities   = character(),
    source         = "brms"
  )
}

# ---------------------------------------------------------------- #
# AST walking helpers                                              #
# ---------------------------------------------------------------- #

# Walk a brms-style formula RHS and bucket terms.
#
# Returns:
#   list(
#     fixed_labels = character vector of deparsed top-level terms,
#     re_pairs     = list of (lhs, rhs, cor) triplets for `(... | ...)`,
#     ext_terms    = list of fb_term descriptors for unsupported
#                    features (smoothers, GP, autocorrelation)
#   )
.brms_walk_rhs <- function(expr) {
  fixed_labels <- character(0)
  re_pairs     <- list()
  ext_terms    <- list()

  visit <- function(e) {
    # Strip parentheses around `(... | ...)` patterns first
    if (is.call(e) && identical(e[[1]], as.name("("))) {
      inner <- e[[2]]
      if (is.call(inner)) {
        op <- as.character(inner[[1]])
        if (op == "|") {
          re_pairs[[length(re_pairs) + 1L]] <<- list(
            lhs = inner[[2]], rhs = inner[[3]], cor = TRUE
          )
          return(invisible())
        }
        if (op == "||") {
          re_pairs[[length(re_pairs) + 1L]] <<- list(
            lhs = inner[[2]], rhs = inner[[3]], cor = FALSE
          )
          return(invisible())
        }
      }
      # Bare parentheses around a non-RE expression -- descend
      visit(e[[2]])
      return(invisible())
    }

    # Recurse on `+` and `-` operators
    if (is.call(e)) {
      op <- as.character(e[[1]])
      if (op %in% c("+", "-")) {
        visit(e[[2]])
        if (length(e) >= 3L) visit(e[[3]])
        return(invisible())
      }

      # Unsupported brms specials -- bucket into ext_terms
      if (op %in% c("s", "t2")) {
        ext_terms[[length(ext_terms) + 1L]] <<- list(
          type = "smoother", fn = op, deparse = deparse(e)
        )
        return(invisible())
      }
      if (op == "gp") {
        ext_terms[[length(ext_terms) + 1L]] <<- list(
          type = "gp", deparse = deparse(e)
        )
        return(invisible())
      }
      if (op %in% c("ar", "ma", "arma", "cosy", "car")) {
        ext_terms[[length(ext_terms) + 1L]] <<- list(
          type = "autocorrelation", fn = op, deparse = deparse(e)
        )
        return(invisible())
      }
      if (op %in% c("cens", "trunc", "trials", "se", "mi",
                    "weights", "subset", "rate")) {
        ext_terms[[length(ext_terms) + 1L]] <<- list(
          type = "addition_form", fn = op, deparse = deparse(e)
        )
        return(invisible())
      }
    }

    # Default: a fixed-effect term -- record its deparse for later
    # re-parsing through .parse_fixed
    fixed_labels <<- c(fixed_labels, deparse(e))
    invisible()
  }

  visit(expr)

  list(
    fixed_labels = fixed_labels,
    re_pairs     = re_pairs,
    ext_terms    = ext_terms
  )
}

# Translate a single brms RE pair (lhs | rhs) to a parse_formula.R
# term descriptor.
#
# v0.1: only `(1 | g)` and `(1 || g)` are supported.
# Anything else returns a marker descriptor whose type =
# "brms_re_unsupported" so the caller can reject with a clear
# message.
.brms_re_to_fb <- function(pair, data) {
  lhs <- pair$lhs
  rhs <- pair$rhs
  cor <- pair$cor

  group_name <- deparse(rhs)
  lhs_str    <- deparse(lhs)
  is_one     <- (is.numeric(lhs) && length(lhs) == 1L &&
                 isTRUE(all.equal(as.numeric(lhs), 1))) ||
                (is.name(lhs) && as.character(lhs) == "1") ||
                identical(lhs_str, "1")

  if (is_one) {
    out <- list(type = "simple", var = group_name)
    if (group_name %in% names(data)) {
      f <- factor(data[[group_name]])
      out$var_n      <- nlevels(f)
      out$var_levels <- levels(f)
    }
    return(out)
  }

  list(
    type    = "brms_re_unsupported",
    lhs     = lhs_str,
    rhs     = group_name,
    cor     = cor,
    deparse = paste0("(", lhs_str,
                     if (isTRUE(cor)) " | " else " || ",
                     group_name, ")")
  )
}
