# Contributing to bayesreml

Thanks for your interest in contributing. The package is an
`AAGI-AUS` collective effort; we welcome bug reports, fixes,
documentation improvements, and discussion of new features.

## Bug reports and feature requests

Please use the GitHub issue tracker:
<https://github.com/AAGI-AUS/bayesreml/issues>.

Useful information to include:

- a minimal reproducible example;
- the output of `sessionInfo()`;
- the output of `packageVersion("bayesreml")` and, if relevant,
  `packageVersion("greta")` and `packageVersion("INLA")`;
- whether the issue reproduces on a fresh R session.

## Pull requests

Small fixes (typos, doc clarifications, minor bug fixes) are welcome
as direct PRs against `main`. For non-trivial changes, please open
an issue first to discuss the approach.

### Development setup

```r
# clone the repo, then in R:
install.packages(c("devtools", "testthat", "roxygen2"))
devtools::load_all()
devtools::test()
devtools::check()
```

The package depends on `greta` (default MCMC backend) and `INLA`
(Laplace backend). `greta` requires a working Python + TensorFlow
install — see `greta::install_greta_deps()`. `INLA` is hosted at
<https://inla.r-inla-download.org/R/stable>.

### Code style

- snake_case for function and argument names.
- Australian / British English in user-facing prose (`optimise`,
  `behaviour`, `parameterise`, `centred`).
- ISO-8601 dates (`YYYY-MM-DD`).
- Two-space indentation; line width ≤ 80 chars where practicable.

### Tests

Add tests under `tests/testthat/`. Tests that depend on `greta` or
`INLA` should `skip_if_not_installed("greta")` /
`skip_if_not_installed("INLA")`. The test suite uses testthat
edition 3.

### Documentation

Roxygen2 (`@param`, `@return`, `@examples`, `@family`) is the source
of truth for `man/`; do not hand-edit `.Rd` files. Long-running
examples should use `\donttest{}`, not `\dontrun{}`.

### Vignettes

Vignettes follow the brms / tidymodels register: motivation →
theory → implementation → interpretation → pitfalls → extensions.
See `vignettes-stage1-plan.md` (workspace-level) for the deck-wide
conventions.

## Community

The project follows the [Contributor Covenant Code of
Conduct](CODE_OF_CONDUCT.md). By participating, you agree to abide
by its terms.

For security-relevant disclosures, please follow [SECURITY.md](SECURITY.md)
rather than the public issue tracker.
