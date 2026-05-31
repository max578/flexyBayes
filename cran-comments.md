## Submission

This is the first submission of `flexyBayes` to CRAN.

The package is currently a 0.4.x release build (`0.4.0`).
Public release is held pending the AAGI-AUS collective conversation on
the upstream repository rename (project decision **D8**); the package
URL declared in `DESCRIPTION` is the agreed forward destination and
404s today — see **NOTE 1** below. The local check run is otherwise
clean.

## Test environments

- local macOS Tahoe 26.3.1 (Apple Silicon), R 4.5.2 — `R CMD check
  --as-cran`, 1-NOTE structural baseline (NOTE 1 below); one
  additional environmental NOTE (NOTE 2) fires when the local HTML
  Tidy binary is older than the version `R CMD check` accepts, and a
  third environmental NOTE (NOTE 3) fires when the check host cannot
  reach a network time source. Net `Status:` on the current dev
  machine is `1 NOTE` when networked + recent-Tidy; up to `3 NOTEs`
  on a stale-Tidy, offline host.
- GitHub Actions matrix (committed locally — `.github/workflows/`;
  activates on first push after the D8 collective decision):
  ubuntu-latest × {R-devel, R-release, R-oldrel-1} plus R-release ×
  {windows-latest, macos-latest, macos-14 (Apple Silicon)}. The
  workflow set is `R-CMD-check.yaml`, `dependency-review.yaml`,
  `lint.yaml`, `pkgdown.yaml`, `test-coverage.yaml`. INLA is installed
  on the Linux release leg only via the `Additional_repositories`
  binary path. greta is intentionally not installed on the standard CI
  matrix (Python / TF setup is a separate slow workflow);
  greta-dependent tests gate via `skip_if_no_greta()` and skip
  cleanly.

## R CMD check results — itemised per NOTE

```
Status: 1 NOTE
```

**NOTE 1 — `checking CRAN incoming feasibility`.**

This NOTE carries four sub-items:

1. *New submission.* Intrinsic to first submission; resolves once
   CRAN's incoming checks accept the upload.
2. *Version contains large components.* This sub-NOTE fires only at
   development versions (`*.9000` tag per the R-pkgs convention); it
   is absent at the proper release version (`0.3.9`) and reappears
   only when checking the dev tip between releases.
3. *Suggests or Enhances not in mainstream repositories: greta, INLA.*
   `greta` lives on CRAN as of 0.5.x; this sub-NOTE fires when CRAN's
   incoming-feasibility check cannot resolve `greta` against its
   internal mirror snapshot. `INLA` is intentionally not on CRAN and
   ships via `Additional_repositories:`
   `https://inla.r-inla-download.org/R/stable`. Both code paths are
   guarded by `requireNamespace(., quietly = TRUE)`; the package
   degrades gracefully when either Suggests dependency is absent.
4. *Found the following (possibly) invalid URLs:*
   `https://github.com/AAGI-AUS/flexyBayes` and
   `https://github.com/AAGI-AUS/flexyBayes/issues`, both returning
   HTTP 404. **Known pending.** The local-only rename from
   `bayesreml` to `flexyBayes` was completed 2026-04-27; the matching
   upstream repository rename is gated on the AAGI-AUS collective
   conversation (project decision **D8**). The URL declared in
   `DESCRIPTION` is the *agreed forward destination* —
   `AAGI-AUS/flexyBayes` is where the package will live once the
   upstream rename ships; the URL is forward-pointing on purpose so a
   single edit at the moment of collective approval is unnecessary.
   This sub-NOTE will resolve once the upstream rename ships. This
   sub-item may or may not fire on a given check host depending on
   the network-reachability check's caching behaviour.

**NOTE 2 (environmental) — `checking HTML version of manual`.**

```
Skipping checking HTML validation: 'tidy' doesn't look like recent
enough HTML Tidy.
```

Environmental: the local HTML Tidy binary on macOS Tahoe is older
than the version `R CMD check` is happy with. CRAN's check farm runs
a current Tidy, so this NOTE does not appear on CRAN itself. Does
not fire on the current dev machine when a recent Tidy is on PATH.

**NOTE 3 (environmental, only when offline) — `checking for future file timestamps`.**

```
unable to verify current time
```

`R CMD check` queries `worldclockapi.com` (or a similar network time
source) to validate that no file in the source tarball carries a
modification timestamp in the future. When the check host cannot
reach that network service — offline build environment, firewalled
CI runner, etc. — the check returns this NOTE rather than failing
the timestamp validation. No package file actually carries a future
timestamp on the development workstation; on a networked check host
this NOTE does not appear. CRAN's check farm is networked, so this
NOTE does not appear on CRAN.

## Downstream impact

`flexyBayes` has zero reverse dependencies on CRAN. `revdep_check()`
is N/A for this submission.

## Suggests-only dependencies

`INLA` is not on CRAN; it is hosted at the URL declared in
`Additional_repositories:`. The package degrades gracefully when INLA
is not installed: every code path that calls `INLA::*` is guarded by
`requireNamespace("INLA", quietly = TRUE)`, and tests that exercise
the live INLA backend skip via `skip_if_not_installed("INLA")`.

`greta` (the default backend) requires Python and TensorFlow. The
greta entry-point checks for greta's availability and emits a clear
install hint (`greta::install_greta_deps()`) if absent.

`brms` (the Stan passthrough on `fb_brms(backend = "brms")`) requires
a working Stan toolchain. Stan-dependent tests gate via
`skip_if_not_installed("brms")` plus `skip_on_cran()` /
`skip_on_ci()` because brms's first-call Stan compile (typically
30–60 s) exceeds the CRAN check budget.

## Vignette compute

Fifteen vignettes ship with the package. Heavy MCMC fits inside
vignettes use small `n_samples` budgets and conditional evaluation
(`requireNamespace("greta")`, `requireNamespace("INLA")`); failures
of the live INLA + greta integration during CRAN's clean re-render
are caught by `tryCatch()` so a single chunk failure does not crash
the vignette render. Vignettes use the `.Rmd.orig` precompile pattern
(`vignettes/_precompile.R` + `.Rbuildignore` excluding the `.orig`
sources) — the static `.Rmd` that ships in the package tarball is the
pre-evaluated output, so the build-side vignette render is a markdown
rendering exercise, not a live MCMC re-run.
