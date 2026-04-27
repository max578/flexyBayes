# vignettes/_precompile.R
#
# Precompile every `flexyBayes-*.Rmd.orig` into its sibling
# `flexyBayes-*.Rmd` so that `R CMD build` and `R CMD check` render
# the static (already-evaluated) `.Rmd` in seconds rather than
# re-running the live MCMC chunks every time.
#
# Run interactively whenever a `.Rmd.orig` source is touched:
#
#   Rscript vignettes/_precompile.R
#
# Pre-requisites (the precompile is a one-time payment that must
# succeed in your interactive session, not in CI):
#
# - flexyBayes installed at the version matching DESCRIPTION
#   (`devtools::install()` or `R CMD INSTALL` of a recent tarball).
# - greta installed and `greta::install_greta_deps()` completed.
# - INLA installed (Additional_repositories binary path).
#
# Outputs:
#
# - `vignettes/<name>.Rmd` — static, ships in the package tarball.
# - `vignettes/<name>-figs/*.png` — figures, ship alongside the
#   static `.Rmd`. Per-vignette directory keeps figure namespaces
#   separate.
#
# `.Rbuildignore` excludes:
#
# - `^vignettes/_precompile\.R$` — this driver.
# - `^vignettes/.*\.Rmd\.orig$` — the live-MCMC sources.
#
# Audit recipe 09 (`/rpkg`).

vignettes_dir <- if (basename(getwd()) == "vignettes") {
  getwd()
} else if (dir.exists("vignettes")) {
  normalizePath("vignettes")
} else {
  stop("Run from the package root or from the vignettes/ directory.",
       call. = FALSE)
}

orig_files <- list.files(
  vignettes_dir,
  pattern    = "\\.Rmd\\.orig$",
  full.names = TRUE
)

if (length(orig_files) == 0L) {
  stop("No .Rmd.orig files found in ", vignettes_dir,
       ". Did you cp the .Rmd files first?", call. = FALSE)
}

cat(sprintf(
  "[precompile] %d vignette source(s) found in %s\n",
  length(orig_files), vignettes_dir
))

# Knit each .Rmd.orig in its own working directory so figure paths
# stay relative to vignettes/.
old_wd <- getwd()
on.exit(setwd(old_wd), add = TRUE)
setwd(vignettes_dir)

n_ok   <- 0L
n_fail <- 0L
failures <- character()

for (f in basename(orig_files)) {
  out  <- sub("\\.orig$", "", f)
  base <- sub("\\.Rmd\\.orig$", "", f)

  cat(sprintf("[precompile] %s -> %s\n", f, out))

  # Per-vignette fig.path keeps figure files namespaced.
  knitr::opts_chunk$set(fig.path = paste0(base, "-figs/"))

  t0 <- Sys.time()
  result <- tryCatch(
    knitr::knit(input = f, output = out, envir = new.env(),
                quiet = FALSE),
    error = function(e) {
      cat(sprintf(
        "[precompile] FAILED on %s: %s\n",
        f, conditionMessage(e)
      ))
      structure("error", condition_message = conditionMessage(e))
    }
  )
  dt <- Sys.time() - t0

  if (identical(unclass(result), "error")) {
    n_fail   <- n_fail + 1L
    failures <- c(failures, f)
  } else {
    n_ok <- n_ok + 1L
    cat(sprintf("[precompile] OK %s (%.1f s)\n", out, as.numeric(dt)))
  }
}

cat(sprintf(
  "\n[precompile] done: %d OK, %d FAILED\n",
  n_ok, n_fail
))

if (n_fail > 0L) {
  cat("[precompile] failures:\n")
  for (fl in failures) cat(sprintf("  - %s\n", fl))
  quit(status = 1L)
}
