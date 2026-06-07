# Report inference-backend readiness

Checks which inference backends flexyBayes can route to are installed
and usable in the current session, returning a small table you can
inspect before fitting. The check is read-only: it probes package
availability and, for greta, the reachability of its Python / TensorFlow
stack, without building a model or starting a fit.

## Usage

``` r
fb_backend_status()
```

## Value

A data frame of class `fb_backend_status` with one row per backend and
the columns `backend`, `installed` (logical), `usable` (logical), and
`note` (a human-readable status, including the install command when a
backend is absent). A `print` method renders it as a readiness table.

## Details

`installed` records whether the backend's R package is present. `usable`
records whether the backend can actually run a fit now – for greta this
additionally requires a working Python / TensorFlow stack, so a greta
that is `installed` but not `usable` needs
[`greta::install_greta_deps()`](https://rdrr.io/pkg/greta/man/install_greta_deps.html).
The dormant opt-in `gretaR` engine is reported separately by
[`gretaR_status()`](https://aagi-aus.github.io/flexyBayes/dev/reference/gretaR_status.md).

## See also

[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/dev/reference/flexybayes.md)
for the universal entry, the
[`fb_greta()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_greta.md)
/
[`fb_inla()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_inla.md)
/
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/dev/reference/fb_brms.md)
single-engine pins, and
[`gretaR_status()`](https://aagi-aus.github.io/flexyBayes/dev/reference/gretaR_status.md)
for the dormant gretaR slot.

## Examples

``` r
# \donttest{
# Probing greta initialises its Python / TensorFlow stack, so the first
# call can be slow; wrapped in \donttest{} for that reason.
fb_backend_status()
#> Downloading uv...
#> Done!
#> flexyBayes backend readiness
#> ----------------------------------------------------------------
#>   [ok] greta   ready (MCMC)
#>   [ok] INLA    ready (approximate inference: integrated nested Laplace)
#>   [--] brms    not installed: install.packages('brms')
# }
```
