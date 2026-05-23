# .fb_dataset() -- Stage 2 MVP internal dataset wrapper (v0.3.0).
#
# Wraps a data.frame / data.table in a list-shaped S3 object
# `<fb_dataset>` carrying:
#   $data         the underlying data.table (in-place if input was a
#                 data.table; converted via as.data.table() if input
#                 was a data.frame; NULL for the metadata-only path)
#   $dictionaries named list of stable factor-level dictionaries (per
#                 factor / character column, ordered character vector
#                 of levels frozen at wrap time; chunked-prediction
#                 and aggregation paths read this slot to guarantee
#                 levels do not drift on row-wise recoding)
#   $n_rows       cached integer row count
#   $col_types    named character vector: one entry per column,
#                 storage class ("double", "integer", "factor",
#                 "character", "logical", or fall-through class[1])
#   $origin       "data.frame" | "data.table" | "metadata-only"
#
# Internal-only at v0.3.0: no `@export` tag on the constructor; no
# man page generated. Export is gated on at least two downstream
# workflows (Stage 3A aggregation + Stage 3B chunked predict)
# stabilising the contract.
#
# Metadata-only path (`data = NULL`): caller supplies n_rows,
# col_types, dictionaries directly. Lets the preflight layer reason
# about 1e8-row designs without materialising the 1e8-row table.

.fb_dataset <- function(data = NULL,
                        n_rows = NULL,
                        col_types = NULL,
                        dictionaries = NULL,
                        ...) {

  # ----------------------- metadata-only path ----------------------- #
  if (is.null(data)) {
    if (is.null(n_rows))
      stop(".fb_dataset(data = NULL, ...) requires `n_rows`.",
           call. = FALSE)
    if (!is.numeric(n_rows) || length(n_rows) != 1L || n_rows < 0)
      stop("`n_rows` must be a non-negative numeric scalar; got: ",
           deparse(n_rows), call. = FALSE)
    if (is.null(col_types))
      stop(".fb_dataset(data = NULL, ...) requires `col_types`.",
           call. = FALSE)
    if (!is.list(col_types) && !is.character(col_types))
      stop("`col_types` must be a named list or named character ",
           "vector of column-class strings.", call. = FALSE)
    ct <- if (is.list(col_types)) unlist(col_types) else col_types
    if (is.null(names(ct)) || any(!nzchar(names(ct))))
      stop("`col_types` entries must be named (one entry per column).",
           call. = FALSE)
    if (is.null(dictionaries)) {
      dictionaries <- list()
    } else if (!is.list(dictionaries)) {
      stop("`dictionaries` must be a named list of character vectors.",
           call. = FALSE)
    } else if (length(dictionaries) > 0L &&
               (is.null(names(dictionaries)) ||
                any(!nzchar(names(dictionaries))))) {
      stop("`dictionaries` entries must be named (one per factor / ",
           "character column).", call. = FALSE)
    }

    return(structure(
      list(
        data         = NULL,
        dictionaries = dictionaries,
        n_rows       = as.integer(n_rows),
        col_types    = ct,
        origin       = "metadata-only"
      ),
      class = c("fb_dataset", "list")
    ))
  }

  # ----------------------- data-backed path ------------------------- #
  if (!inherits(data, "data.frame"))
    stop("`data` must be a data.frame, data.table, or NULL ",
         "(metadata-only path).", call. = FALSE)

  was_dt <- inherits(data, "data.table")
  dt <- if (was_dt) data.table::copy(data)
        else        data.table::as.data.table(data)

  cols <- names(dt)
  ct   <- vapply(cols, function(nm) {
    col <- dt[[nm]]
    if      (is.factor(col))    "factor"
    else if (is.character(col)) "character"
    else if (is.logical(col))   "logical"
    else if (is.integer(col))   "integer"
    else if (is.numeric(col))   "double"
    else                        class(col)[[1L]]
  }, character(1L))
  names(ct) <- cols

  dict <- list()
  for (nm in cols) {
    col <- dt[[nm]]
    if (is.factor(col)) {
      dict[[nm]] <- levels(col)
    } else if (is.character(col)) {
      dict[[nm]] <- sort(unique(col))
    }
  }

  structure(
    list(
      data         = dt,
      dictionaries = dict,
      n_rows       = nrow(dt),
      col_types    = ct,
      origin       = if (was_dt) "data.table" else "data.frame"
    ),
    class = c("fb_dataset", "list")
  )
}


# ---------------------------------------------------------------- #
# S3 print + format methods                                        #
# ---------------------------------------------------------------- #

#' Format method for an internal `<fb_dataset>` wrapper
#'
#' One-line summary of the internal dataset wrapper used by the
#' Stage 2 preflight layer.
#'
#' @param x   an `<fb_dataset>` object.
#' @param ... unused.
#' @return a length-1 character string.
#' @keywords internal
#' @export
format.fb_dataset <- function(x, ...) {
  meta <- if (identical(x$origin, "metadata-only"))
            " (metadata-only)" else ""
  sprintf(
    "<fb_dataset%s>: n_rows = %s; n_cols = %d; n_dicts = %d; origin = %s",
    meta,
    format(x$n_rows, big.mark = " ", scientific = FALSE),
    length(x$col_types),
    length(x$dictionaries),
    x$origin
  )
}

#' Print method for an internal `<fb_dataset>` wrapper
#'
#' Diagnostic print: one-line header from [format.fb_dataset()],
#' then a per-column types row and a per-dictionary level-count row.
#'
#' @param x   an `<fb_dataset>` object.
#' @param ... unused.
#' @return invisibly returns `x`.
#' @keywords internal
#' @export
print.fb_dataset <- function(x, ...) {
  cat(format(x, ...), "\n", sep = "")
  if (length(x$col_types)) {
    cat("  col_types: ",
        paste0(names(x$col_types), ":", x$col_types,
               collapse = "; "),
        "\n", sep = "")
  }
  if (length(x$dictionaries)) {
    levels_str <- paste0(
      names(x$dictionaries), "(",
      vapply(x$dictionaries, length, integer(1L)), ")"
    )
    cat("  dicts: ", paste(levels_str, collapse = "; "), "\n",
        sep = "")
  }
  invisible(x)
}


# ---------------------------------------------------------------- #
# Helpers (internal-only)                                          #
# ---------------------------------------------------------------- #

# Lookup the level-count of a column. Reads `<fb_dataset>$dictionaries`
# first (the source of truth for the frozen-level contract); falls
# back to NA_integer_ if no dictionary is present. Used by the
# preflight per-term estimators to size random-intercept / random-
# slope blocks without re-scanning the underlying data.table.
.fb_dataset_levels <- function(ds, col) {
  if (col %in% names(ds$dictionaries))
    return(length(ds$dictionaries[[col]]))
  NA_integer_
}

# Column-type lookup -- returns NA_character_ if the column is not
# tracked. Internal helper used by preflight to gate factor-vs-numeric
# emit paths without re-reading $data.
.fb_dataset_type <- function(ds, col) {
  if (col %in% names(ds$col_types))
    return(unname(ds$col_types[[col]]))
  NA_character_
}

# Predicate -- is the dataset wrapper a metadata-only descriptor?
# Used by the preflight stress test to assert no row-wise read
# happens on the 1e8-row descriptor path.
.fb_dataset_is_metadata <- function(ds) {
  identical(ds$origin, "metadata-only")
}
