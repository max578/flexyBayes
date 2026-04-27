## Submission

This is the first submission of `flexyBayes` to CRAN.

## Test environments

- local macOS Tahoe 26.3.1 (Apple Silicon), R 4.5.2 — `R CMD check
  --as-cran` clean (1 NOTE, see below).
- GitHub Actions matrix (committed locally — `.github/workflows/`;
  activates on first push after AAGI-AUS collective rename approval):
  ubuntu-latest × {R-devel, R-release, R-oldrel-1} plus R-release ×
  {windows-latest, macos-latest, macos-14 (Apple Silicon)}. INLA is
  installed on the Linux release leg only via the
  `Additional_repositories` binary path. greta is intentionally not
  installed on the standard CI matrix (Python / TF setup is a separate
  slow workflow); greta-dependent tests gate via `skip_if_no_greta()`
  and skip cleanly.

## R CMD check results — itemised per NOTE

```
Status: 1 NOTE
```

**NOTE 1 — `checking CRAN incoming feasibility`** (`Status: Error`).

- **Category.** Intrinsic to first submission.
- **Justification.** This NOTE fires the network-side CRAN-status query
  during the local check; it cannot be suppressed by any package change
  before submission. The same NOTE will appear on every first-submission
  package and resolves automatically once CRAN's incoming-checks accept
  the upload.

## Downstream impact

`flexyBayes` has zero reverse dependencies on CRAN. `revdep_check()` is
N/A for this submission.

## Suggests-only dependencies

`INLA` is not on CRAN; it is hosted at the URL declared in
`Additional_repositories:`. The package degrades gracefully when INLA
is not installed: every code path that calls `INLA::*` is guarded by
`requireNamespace("INLA", quietly = TRUE)`, and tests that exercise
the live INLA backend skip via `skip_if_not_installed("INLA")`.

`greta` (the default backend) requires Python and TensorFlow. The
greta entry-point checks for greta's availability and emits a clear
install hint (`greta::install_greta_deps()`) if absent.

## Vignette compute

Twelve vignettes ship with the package. Heavy MCMC fits inside
vignettes use small `n_samples` budgets and conditional evaluation
(`requireNamespace("greta")`, `requireNamespace("INLA")`); failures of
the live INLA + greta integration during CRAN's clean re-render are
caught by `tryCatch()` so a single chunk failure does not crash the
vignette render.
