# =============================================================================
# ensemble_source.R -- the C5 "ensemble source" ingest contract.
#
# Coerces a simulation ensemble from any conforming producer -- a PESTO
# calibration manifest, a raw apsimx run extracted to data.frames, a saved file,
# or a future registered producer -- into ONE canonical `fb_ensemble` object the
# methods-intense consumers (fb_pesto(), the surrogate seam, fb_apsim()) build
# on. flexyBayes depends on the CONTRACT (inst/ensemble_source_contract.md),
# never on apsimx / PESTO internals. APSIM is executed upstream by apsimx; no
# code here runs APSIM.
#
# Canonical object: a list of class c("fb_ensemble", "list") with
#   params       data.frame, one row per parameter set (the ensemble key order).
#   outputs      data.frame, row-aligned to params (row i = response to set i).
#   output_dims  data.frame or NULL -- one row per outputs column, labelling it
#                (site, season, day, variable); the long view of ADR 0009.
#   observed     named numeric or NULL -- target obs (subset of outputs cols).
#   provenance   list -- at least $source; plus apsim_version / seed / n_sets /
#                simulator / created_via where known.
# =============================================================================

# ---- constructor (the canonical / "raw" path) -------------------------------

#' Construct a canonical simulation-ensemble object
#'
#' Builds an `fb_ensemble` -- flexyBayes's canonical container for a
#' parameter-to-output simulation ensemble (contract C5,
#' `inst/ensemble_source_contract.md`). `params` and `outputs` are the `(X, Y)`
#' an emulator or surrogate trains on; `output_dims` and `observed` add the
#' calibration framing when present. flexyBayes never executes the simulator
#' (APSIM is run upstream by `apsimx`); this is the ingest floor the
#' methods-intense consumers share.
#'
#' @param params A `data.frame`, one row per parameter set, columns the
#'   simulator's input parameters. Row order is the ensemble key.
#' @param outputs A `data.frame` row-aligned to `params`
#'   (`nrow(outputs) == nrow(params)`), columns the output dimensions.
#' @param observed Optional named numeric of target observations; names a
#'   subset of `colnames(outputs)`. `NULL` for a pure forward ensemble.
#' @param output_dims Optional `data.frame`, one row per `outputs` column,
#'   labelling it (e.g. `site`, `season`, `day`, `variable`). `NULL` when
#'   outputs are unlabelled.
#' @param provenance A named list of provenance fields; `source` is filled with
#'   `"raw"` when absent.
#'
#' @return An object of class `c("fb_ensemble", "list")`.
#' @seealso [as_fb_ensemble()], [verify_fb_ensemble()], [read_fb_ensemble()].
#' @examples
#' e <- fb_ensemble(
#'   params = data.frame(k = c(0.1, 0.2, 0.3)),
#'   outputs = data.frame(yield = c(4.1, 4.6, 5.0))
#' )
#' verify_fb_ensemble(e)$ok
#' @export
fb_ensemble <- function(
  params,
  outputs,
  observed = NULL,
  output_dims = NULL,
  provenance = list()
) {
  params <- as.data.frame(params)
  outputs <- as.data.frame(outputs)
  if (is.null(provenance$source)) {
    provenance$source <- "raw"
  }
  provenance$n_sets <- nrow(params)
  e <- structure(
    list(
      params = params,
      outputs = outputs,
      output_dims = output_dims,
      observed = observed,
      provenance = provenance
    ),
    class = c("fb_ensemble", "list")
  )
  chk <- verify_fb_ensemble(e)
  if (!isTRUE(chk$ok)) {
    stop("fb_ensemble(): ", chk$message, call. = FALSE)
  }
  e
}

# ---- conformance verifier ---------------------------------------------------

#' Verify a simulation ensemble against the C5 contract
#'
#' Checks that `e` honours the ensemble-source contract
#' (`inst/ensemble_source_contract.md`): row-aligned positive-length
#' `params` / `outputs`, any `observed` names a subset of the outputs, any
#' `output_dims` one row per output column, and a `provenance$source`. Returns a
#' verdict rather than erroring, so callers can branch (the `fb_ensemble()`
#' constructor turns a failure into an error; an interactive check can inspect
#' the message).
#'
#' @param e An object to check (an `fb_ensemble`, or any list with the same
#'   components).
#' @return A list `list(ok = <logical>, message = <character>)`. `ok = TRUE` and
#'   an empty message on conformance; `ok = FALSE` and the first violation
#'   otherwise.
#' @export
verify_fb_ensemble <- function(e) {
  fail <- function(msg) list(ok = FALSE, message = msg)
  if (!is.list(e) || is.null(e$params) || is.null(e$outputs)) {
    return(fail("not an ensemble: missing `params` and/or `outputs`."))
  }
  if (!is.data.frame(e$params) || !is.data.frame(e$outputs)) {
    return(fail("`params` and `outputs` must both be data.frames."))
  }
  if (nrow(e$params) == 0L) {
    return(fail("`params` has zero rows (empty ensemble)."))
  }
  if (nrow(e$params) != nrow(e$outputs)) {
    return(fail(sprintf(
      "`params` (%d rows) and `outputs` (%d rows) are not row-aligned.",
      nrow(e$params),
      nrow(e$outputs)
    )))
  }
  if (!is.null(e$observed)) {
    onm <- names(e$observed)
    if (is.null(onm) || !all(onm %in% colnames(e$outputs))) {
      return(fail(paste0(
        "`observed` names must be a subset of `colnames(outputs)`; ",
        "unmatched: ",
        paste(setdiff(onm, colnames(e$outputs)), collapse = ", ")
      )))
    }
  }
  if (!is.null(e$output_dims)) {
    if (
      !is.data.frame(e$output_dims) ||
        nrow(e$output_dims) != ncol(e$outputs)
    ) {
      return(fail(paste0(
        "`output_dims` must be a data.frame with one row per `outputs` ",
        "column (",
        ncol(e$outputs),
        ")."
      )))
    }
  }
  if (is.null(e$provenance) || is.null(e$provenance$source)) {
    return(fail("`provenance$source` is required (the producer kind)."))
  }
  list(ok = TRUE, message = "")
}

# ---- the producer registry (extensibility seam) -----------------------------
# A registry of (producer S3 class -> coercer) so a NEW producer (koine, a
# surrogate, an apsimx-specific adapter) becomes ingestible by registering a
# coercer here, with no edit to as_fb_ensemble() or this file. Mirrors the
# canonical-name mapper registry's source-time registration pattern.

.ensemble_source_registry <- new.env(parent = emptyenv())

#' Register an ensemble-source coercer for a producer class
#'
#' Extends [as_fb_ensemble()] so a new producer of simulation ensembles becomes
#' ingestible without modifying flexyBayes. The coercer takes a producer object
#' and returns an `fb_ensemble`. This is the constellation extensibility seam
#' for contract C5: a member registers its coercer rather than flexyBayes
#' hard-coding the member.
#'
#' @param producer_class A single string -- the S3 class of the producer object.
#' @param coercer A function `function(x, ...) -> fb_ensemble`.
#' @return Invisibly `NULL`.
#' @export
register_ensemble_source <- function(producer_class, coercer) {
  if (
    !is.character(producer_class) ||
      length(producer_class) != 1L ||
      !nzchar(producer_class)
  ) {
    stop(
      "register_ensemble_source(): `producer_class` must be a single ",
      "non-empty string.",
      call. = FALSE
    )
  }
  if (!is.function(coercer)) {
    stop(
      "register_ensemble_source(): `coercer` must be a function.",
      call. = FALSE
    )
  }
  assign(producer_class, coercer, envir = .ensemble_source_registry)
  invisible(NULL)
}

.lookup_ensemble_source <- function(producer_class) {
  for (cls in producer_class) {
    if (exists(cls, envir = .ensemble_source_registry, inherits = FALSE)) {
      return(get(cls, envir = .ensemble_source_registry, inherits = FALSE))
    }
  }
  NULL
}

# ---- the ingest generic -----------------------------------------------------

#' Coerce a conforming producer to a canonical `fb_ensemble`
#'
#' The single ingest entry point for contract C5. Dispatches on the producer:
#' an `fb_ensemble` is returned unchanged; a `pesto_ensemble_manifest` (PESTO's
#' S7 calibration manifest) is mapped via the C2 → C5 bridge; a `list` carrying
#' `params` / `outputs` is wrapped; a length-1 character path is read from disk.
#' Any other class is looked up in the producer registry
#' ([register_ensemble_source()]) before erroring.
#'
#' @param x A conforming producer object (see Details / the contract).
#' @param ... Passed to the matched coercer.
#' @return An `fb_ensemble`.
#' @seealso `inst/ensemble_source_contract.md`.
#' @export
as_fb_ensemble <- function(x, ...) {
  UseMethod("as_fb_ensemble")
}

#' @export
as_fb_ensemble.fb_ensemble <- function(x, ...) {
  x
}

#' @export
as_fb_ensemble.list <- function(x, ...) {
  if (is.null(x$params) || is.null(x$outputs)) {
    stop(
      "as_fb_ensemble(): a list source must carry `params` and `outputs`.",
      call. = FALSE
    )
  }
  prov <- x$provenance %||% list()
  if (is.null(prov$source)) {
    prov$source <- "raw"
  }
  fb_ensemble(
    params = x$params,
    outputs = x$outputs,
    observed = x$observed,
    output_dims = x$output_dims,
    provenance = prov
  )
}

#' @export
as_fb_ensemble.character <- function(x, ...) {
  if (length(x) != 1L) {
    stop(
      "as_fb_ensemble(): a character source must be a single path.",
      call. = FALSE
    )
  }
  read_fb_ensemble(x, ...)
}

#' @export
as_fb_ensemble.default <- function(x, ...) {
  coercer <- .lookup_ensemble_source(class(x))
  if (!is.null(coercer)) {
    return(coercer(x, ...))
  }
  # A PESTO manifest is an S7 object whose S3 class is the *namespaced* name
  # (e.g. "PESTO::pesto_ensemble_manifest"), so match by suffix rather than an
  # S3 method on the bare name (which S7 dispatch never reaches).
  if (any(grepl("(^|::)pesto_ensemble_manifest$", class(x)))) {
    return(.coerce_pesto_manifest(x, ...))
  }
  stop(
    "as_fb_ensemble(): no coercer for class ",
    paste0("'", class(x), "'", collapse = "/"),
    ". Supply an `fb_ensemble`, a `pesto_ensemble_manifest`, a list with ",
    "`params`/`outputs`, a file path, or register one via ",
    "register_ensemble_source().",
    call. = FALSE
  )
}

# ---- the PESTO manifest bridge (C2 -> C5), capability-gated ------------------
# PESTO's pesto_ensemble_manifest (S7) carries params + outputs (row-aligned) +
# obs_target + apsim_version -- a superset of C5. Coerced WITHOUT importing
# PESTO: the S7 properties are read via S7::prop(), guarded by S7 availability
# and a class check, so flexyBayes stays standalone-functional when PESTO is
# absent (dormant-correct).

.coerce_pesto_manifest <- function(x, ...) {
  if (!requireNamespace("S7", quietly = TRUE)) {
    stop(
      "as_fb_ensemble(): reading a PESTO manifest needs the S7 package.",
      call. = FALSE
    )
  }
  prop <- function(nm) tryCatch(S7::prop(x, nm), error = function(e) NULL)
  params <- as.data.frame(prop("params"))
  outputs <- as.data.frame(prop("outputs"))
  obs <- prop("obs_target")
  observed <- if (is.numeric(obs) && length(obs) > 0L && !is.null(names(obs))) {
    obs[names(obs) %in% colnames(outputs)]
  } else {
    NULL
  }
  if (!is.null(observed) && length(observed) == 0L) {
    observed <- NULL
  }
  av <- prop("apsim_version")
  fb_ensemble(
    params = params,
    outputs = outputs,
    observed = observed,
    provenance = list(
      source = "pesto",
      apsim_version = if (is.character(av) && length(av) == 1L) av else NA,
      schema_version = prop("schema_version"),
      created_via = "as_fb_ensemble.pesto_ensemble_manifest"
    )
  )
}

# ---- file reader ------------------------------------------------------------

#' Read a simulation ensemble from a file
#'
#' Reads a saved `fb_ensemble` (or a `list(params, outputs, ...)`) from an
#' `.rds` file and returns a verified `fb_ensemble`. The file path's provenance
#' is recorded. (Delimited / `.fst` readers can be added as the methods work
#' needs them; `.rds` is the lossless round-trip used now.)
#'
#' @param path A single `.rds` file path.
#' @param ... Unused; for generic compatibility.
#' @return An `fb_ensemble`.
#' @export
read_fb_ensemble <- function(path, ...) {
  if (!is.character(path) || length(path) != 1L || !file.exists(path)) {
    stop(
      "read_fb_ensemble(): `path` must be a single existing file.",
      call. = FALSE
    )
  }
  if (!grepl("\\.rds$", path, ignore.case = TRUE)) {
    stop(
      "read_fb_ensemble(): only .rds is supported currently; got '",
      path,
      "'.",
      call. = FALSE
    )
  }
  obj <- readRDS(path)
  e <- if (inherits(obj, "fb_ensemble")) obj else as_fb_ensemble.list(obj)
  e$provenance$source <- e$provenance$source %||% "file"
  e$provenance$created_via <- paste0("read_fb_ensemble('", basename(path), "')")
  chk <- verify_fb_ensemble(e)
  if (!isTRUE(chk$ok)) {
    stop(
      "read_fb_ensemble(): file does not conform -- ",
      chk$message,
      call. = FALSE
    )
  }
  e
}

# ---- display ----------------------------------------------------------------

#' @export
print.fb_ensemble <- function(x, ...) {
  cat("-- fb_ensemble (simulation ensemble, contract C5) ----------\n")
  cat("  source : ", x$provenance$source %||% "?", "\n", sep = "")
  cat("  sets   : ", nrow(x$params), "\n", sep = "")
  cat(
    "  params : ",
    ncol(x$params),
    " (",
    paste(utils::head(colnames(x$params), 6L), collapse = ", "),
    if (ncol(x$params) > 6L) ", ..." else "",
    ")\n",
    sep = ""
  )
  cat("  outputs: ", ncol(x$outputs), "\n", sep = "")
  cat(
    "  labelled: ",
    !is.null(x$output_dims),
    " | observed: ",
    !is.null(x$observed),
    "\n",
    sep = ""
  )
  av <- x$provenance$apsim_version
  if (!is.null(av) && !is.na(av)) {
    cat("  apsim  : ", av, "\n", sep = "")
  }
  cat("------------------------------------------------------------\n")
  invisible(x)
}
