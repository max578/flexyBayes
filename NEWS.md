# flexyBayes 0.3.0.9000

## Stage 3A foundation -- exact Gaussian aggregation via sufficient statistics

Internal `.fb_aggregate_gaussian()` collapses a per-row Gaussian-identity
mixed model into one row per cell, where a cell is the maximal subset of
observations sharing the same linear-predictor value. Three sufficient
statistics per cell (`n_k`, `S1_k = sum(y)`, `S2_k = sum(y^2)`) carry
all the information the Gaussian-identity log-likelihood needs.

The implementation is foundation-only at this release: the algebraic
correctness gate landed, the backend emit path is not yet wired. A
property-based test draws twenty random in-scope intermediate
representations across three N scales (100, 500, 2000) with random
coefficients and confirms that the aggregated log-likelihood matches the
raw per-row form to relative error below `1e-12` in every case. The
biased cell-mean shortcut is exposed only so the same test can confirm
a regression would be caught.

The scope envelope refuses (typed condition
`flexybayes_aggregate_out_of_scope`) on: non-Gaussian family,
non-identity link, smooth fixed-effect term, or any random slope --
all of which break the cell-constant linear predictor.

Internal-only at v0.3.0.9000; surfaces user-facing in v0.3.2 alongside
the greta / INLA aggregated emit path and the `$exactness` slot.

## Stage 3A foundation -- memory shape correction + model-level plan

Two follow-up changes to the Stage 3A foundation surfaced by the
2026-05-23 audit:

- `<fb_aggregated>$design_matrix` (the full `N x p` per-row design
  matrix) is replaced by `$cell_design` (the `K x p` per-cell form).
  The aggregated emit path only needs the per-cell linear predictor;
  carrying the per-row matrix defeated the compression contract at
  large `N` and was not an implementation shape compatible with the
  10M-100M-row roadmap. Per-row equivalence verification (the
  bit-exact log-likelihood gate) now rebuilds the per-row design
  locally via `stats::model.matrix()`.

- New internal `.fb_aggregation_plan()` returning a model-level
  `<fb_aggregation_plan>` with seven slots: `eligible`,
  `reason_codes`, `cell_key_terms`, `requires_materialisation`,
  `K_est`, `N`, `compression_est`. The plan reads only IR + dataset
  metadata; no design materialised. `.fb_preflight()` attaches the
  plan to its result for diagnostic visibility. The plan is
  informational at v0.3.0.9000: the per-term
  `aggregated_likelihood_candidate` flag remains the dispatcher
  contract through v0.3.1. In v0.3.2 the plan supersedes per-term
  flags as the dispatch input when the aggregated emit path lands.

  Productivity threshold: `K_est / N <= 0.5` (at least 2:1 compression
  expected from metadata). Below the threshold the plan reports
  `eligible = TRUE`; above it reports
  `reason_codes = "compression_unproductive"`. Continuous fixed
  terms make the cell count data-dependent (cannot estimate from
  metadata) and the plan reports
  `reason_codes = "compression_data_dependent"`.

## Preflight hardening -- smooth/spline estimators + unknown-term refusal

The Stage 2 preflight layer now characterises every term class the
asreml and brms parsers can emit. Five new branches:

- Mgcv smooth terms (`s(x)`, `smooth_mgcv` in the IR) on either side
  of the formula: dense `N x k` basis estimate using the resolved
  `term$k` from `mgcv::smoothCon()`. Previously parser-emitted smooths
  fell through to a single-column estimate -- a factor-of-`k`
  under-estimate that could let a large smooth model pass preflight
  when the actual basis exceeded the ceiling.
- P-spline terms (`spl(x)`): dense `N x df` basis with `df = 8`
  matching the codegen default.
- Factor:factor interactions: dense treatment-coded `N x (prod(L) - 1)`
  estimate; the audit-named high-cardinality scary case.
- Factor:continuous interactions (ADR 0019 indexed slope): integer
  index column + continuous column + `(L - 1)` per-level slope
  coefficients.
- Polynomial terms (`pol(x, d)`): dense `N x d` basis.

The fixed and random fallthrough branches no longer record a
single-dense-column estimate framed as "conservative lower bound" --
a lower bound is the opposite of conservative for a refusal gate.
Unrecognised term classes now flag the per-term entry with
`unknown_representation = TRUE` and the top-level preflight returns a
typed `flexybayes_preflight_refusal` with
`reason_code = "representation_unknown_for_preflight"` carrying the
binding term label. Structured-covariance random terms (`vm`, `ped`,
`fa`, `us`, `at`, `ar1`, `nested`, etc.) remain estimated via the
indexed-representation heuristic and are now labelled
`representation_class = "indexed_structured_estimate"` with a header
note that production fits at large `N` should set `memory_ceiling_gb`
explicitly rather than relying on the default.

## Behaviour change -- default RAM fraction lowered from 80% to 60%

The default design-memory ceiling is now `60%` of system RAM (was
`80%`). This is conservative for shared workstations, CI runners, and
interactive laptops where the user expects the rest of the machine to
remain responsive under load. A new global option
`flexyBayes.preflight_ram_fraction` exposes the fraction for per-host
tuning:

```r
options(flexyBayes.preflight_ram_fraction = 0.5)   # tighter
options(flexyBayes.preflight_ram_fraction = 0.9)   # looser, single-user host
```

The fraction is validated as `(0, 1]`. The 8 GiB fallback (used when
neither the `benchmarkme` nor the `memuse` RAM probe is installed)
is unaffected -- the fallback is already a conservative absolute
floor.

# flexyBayes 0.3.0

## Stage 2 design-memory preflight

flexyBayes now estimates the design-representation memory of a model
upstream of the backend dispatch and refuses with a structured
diagnostic when the estimate exceeds an active ceiling. The aim is to
replace the v0.2 silent-allocation antipattern (`Error: cannot
allocate vector of size 3.2 Gb` from `model.matrix()` mid-fit) with an
explicit, per-term refusal that names the binding term and a numeric
override.

The default ceiling is 80% of system RAM, probed via `benchmarkme` or
`memuse` when either is installed; otherwise an 8 GiB fallback applies.
Users can set a stricter cap via the global option
`flexyBayes.preflight_ceiling_gb` (e.g. on shared hosts where the full
RAM should not be claimed for a single fit).

The check runs only on fits with `n_rows >= 1e5` so the v0.2 user
surface is unchanged at small scales. On larger fits the check reads
only `n_rows`, factor-level counts, and column types -- no row-wise
data scan -- so the runtime is `O(terms)` regardless of `n_rows`.
A 1e8-row metadata-only check completes in milliseconds on the
development laptop.

The refusal is a typed condition `flexybayes_preflight_refusal`
carrying the binding term name, its byte estimate, the active
ceiling, and a suggested override. On `flexybayes(..., review_code
= TRUE)` and `fb_brms(..., review_code = TRUE)` the resulting
`<flexybayes_review>` token now carries a `$preflight` slot; the
preflight summary appears in `print(rev)` above the `cat_code()`
prompt.

The `aggregated_likelihood_candidate` flag on each per-term entry is
a forward-looking promise to the gaussian-identity aggregated
backend path; the flag has no runtime effect at v0.3.0 (no
aggregation runs yet) but is consumed by later stages.

# flexyBayes 0.2.6

## Correctness fix -- factor:continuous interaction (ADR 0019)

`flexybayes(y ~ x * f, data = ...)` where `f` is a factor and `x`
is numeric previously emitted the interaction term using a
coefficient broadcast that did not match base R's treatment-coded
model matrix -- producing posterior estimates that disagreed with
`lme4::lmer` by more than three standard deviations on simulated
data. The fix emits the interaction as a treatment-coded indexed
slope: the reference level's slope is fixed to zero; the L-1 non-
reference levels carry their own slope deviations sampled from the
prior, indexed back to the observation vector via the factor's
level codes. Posterior estimates now match `lme4::lmer` within MCMC
tolerance and the linear-predictor equality
`eta_flexybayes == model.matrix(~ f * x) %*% beta` holds at
tolerance `1e-10` for any compatible coefficient vector.

The new term class `factor_numeric_interaction` registers the
canonical-name family `slope_<f>_<x>[<level>]` per non-reference
level for both the greta and brms backends. The dispatch trace
records which emit branch fired via
`fit$extras$parse_info$factor_continuous_emit` (`"option_c"` for
the greta-native concatenation idiom; `"option_d"` for the per-
observation lookup-vector fallback gated on
`options(flexyBayes.force_option_d = TRUE)`).

Unsupported contrast types (`contr.helmert`, `contr.sdif`,
`contr.sum`, ordered factors, user-supplied custom contrast
matrices) refuse at ingest with a structured
`flexybayes_contrast_unsupported` condition carrying `contrast`,
`factor_name`, and `deferral_target` slots; the message points at
the v0.3 representation IR for general contrast support.

The INLA mapper for the new term class registers only after a
three-arbitrator verification test (INLA vs greta vs `lme4::lmer`)
passes on the host; on hosts where INLA verification cannot
complete the gate refuses INLA dispatch with a v0.3 deferral
message rather than silently shipping an unverified translation.

## Feature -- uncorrelated random slopes (x || g) (ADR 0020)

`fb_brms(y ~ x + (x || g), ...)` now parses and emits the
uncorrelated random-effect form -- in lme4 / brms semantics each
level of `g` carries an independent intercept deviation AND an
independent slope deviation, both drawn from their own univariate-
normal priors (no correlation parameter shared between intercept
and slope). The explicit `(1 + x || g)` shape is equivalent;
`(0 + x || g)` suppresses the intercept block, yielding a slope-
only random effect. The correlated form `(x | g)` continues to
refuse with a v0.3 deferral message pointing to ADR 0025
(Stage 5A known-covariance inputs), which will admit the user-
supplied Cholesky factor that makes the correlated form
tractable; the refusal raises a typed condition
(`flexybayes_correlated_slope_unsupported`) carrying
`grouping_factor`, `slope_variable`, `deferral_target`, and
`workaround` slots so downstream tooling can pattern-match.

Canonical-name family `sd_<x>_<g>` registered on the greta + brms
backends -- the brms-side `sd_<g>__<x>` parameter (brms's
double-underscore Stan convention) maps to the canonical
`sd_<x>_<g>`. INLA mapping is gated by a three-arbitrator
verification test (INLA vs greta vs lme4) on a simple fixture
following the §3.4 verification policy in
`plan-indexing-bigdata-merged-2026-05-23-v2.md`; until the
verification artefact records pass, the INLA backend refuses
`(x || g)` with a v0.3 deferral message naming `backend = "greta"`
as the workaround. Triangulation between greta and brms on
`(x || g)` fits agrees on slope-variance posteriors within
`W_1 <= 0.20 * tau_true` (the loosened envelope per merged-v2
§5.6 risk 3 -- slope-variance posteriors are intrinsically less
identified than intercept-variance ones at modest J).

## Representation benchmarks (Stage 1C per merged-v2 plan section 4.2.3)

The benchmark harness gains three new rows per term class:
`generated_code_size_bytes`, `pre_fit_object_size_bytes`, and
`code_generation_time_sec`. Snapshot tests assert that the greta
fit-time codegen path does not call `model.matrix()` for supported
indexed term classes -- the indexed-emit path replaces the dense
matrix at any `n`, so generated code size stays nearly constant in
`n`.

Benchmark filename rename: `tools/benchmark_flexyBayes_0.2.5.R` ->
`tools/benchmark_flexyBayes.R` (version stamp dropped; the harness
runs against whichever version is installed, and names its output
directory accordingly at run time).

# flexyBayes 0.2.5.9000

## Correctness fix -- predict(newdata) on smooths (ADR 0018)

`predict.flexybayes(..., newdata = ...)` on fits containing one or
more `s()` smooth terms now uses retained `mgcv` `Smooth` objects via
`mgcv::PredictMat()`, restoring correctness on `newdata` containing
`x` values inside or near the training range. Previously the basis
was implicitly re-derived from `newdata` via `stats::model.matrix()`,
producing correct-by-coincidence values inside the training range
and silently wrong values near or beyond. The fix retains the
`mgcv::smoothCon()` output on the IR (internal slot
`random_terms[[i]]$smooth_obj`) and threads it via
`extras$parse_info$smooths`. `fb_brms(backend = "brms")` and
`fb_greta()` are exempt -- both already correct.

A correctness refusal fires on legacy fits saved before this fix:
re-fit on the current version to enable `predict(newdata)`.

## Code-size fix -- smooth emit literal-matrix storage

The `greta` emit path for `s()` smooths no longer inlines the n-row
basis matrix as a literal in the generated code. The basis is bound
into the model environment as `B_s_<varname>` and the emitted code
references `as_data(B_s_<varname>)` instead.
`nchar(return_code(fit))` for `s(x)` at `n = 10000` dropped from
~10 MB to under 10 kB.

## Gate truth = emit truth (ADR 0017)

`lgm_gate(fb) == accept` is now a sufficient condition for the
INLA emit path to succeed structurally. Three new gate rules
(`fixed_term_type_inla`, `random_term_type_inla`,
`rcov_term_type_inla`) fold the prior emit-time refusal sites into
`lgm_gate()` so users see refusals before the INLA machinery is
invoked. `backend = "auto"` no longer carries a separate emit-time
fall-back path; dispatch trace's auto-non-LGM path is uniformly
`"auto_lgm_refuse"`.

## Visual-regression test tier upgraded (AMBITION_STAGE §1.1)

The `vdiffr` SVG-snapshot tests in `test-plot-vdiffr.R` (which had
been skipped unconditionally due to MCMC-float-drift fragility) are
replaced with numerical snapshots on the plotted data structure.
Equivalent coverage for "did the plot get built correctly" without
the SVG-diff fragility.

## Structured-cov default priors -- vm() + ped() now uniform-on-SD

`.default_uniform_prior()` (extending ADR 0004) now fires on `vm()`
and `ped()` random-term inputs, closing the documented inconsistency
where `simple`/`ide`/`id` RE SDs defaulted to uniform-on-SD while
`vm`/`ped` fell back to legacy lognormal. The other structured forms
(`at`, `us`, `fa`, `ar1`) remain on the legacy default for now.

# flexyBayes 0.2.0 (development)

## Four-verb API

`flexyBayes` exposes four user-facing entry points covering the
formula-grammar × backend-ambition cross-product:

| Verb | Grammar | Backend choices | Use when |
|---|---|---|---|
| `flexybayes()` | ASReml (`fixed` / `random` / `rcov`) | `greta`, `inla`, `auto` | ASReml syntax; agricultural / variance-component workflows. |
| `fb_brms()` | brms / lme4 (`y ~ x + (1 | g)`) | `greta`, `inla`, `brms`, `auto` | brms or lme4 syntax; Stan passthrough on `backend = "brms"`. |
| `fb_greta()` | direct greta model graph | `greta` | Expert escape hatch; supplies a pre-built greta model. |
| `triangulate()` | n/a | n/a | Pairwise cross-engine posterior comparison. |

`fb()` remains as a literal alias for `flexybayes()`.

## Dispatch trace

Every fit records a structured `backend_decision()` describing which
backend ran and why:

```r
fit <- flexybayes(yield ~ env, random = ~ geno, data = trial)
backend_decision(fit)
#> $backend     "greta"
#> $path        "auto_inla_refuse"
#> $gate_checks <list of lgm_gate rules + pass/fail>
#> $reason      "lgm_gate refused at check `hyperparam_budget`."
```

`backend = "auto"` runs `lgm_gate()` and routes to INLA on acceptance,
otherwise to greta. `auto` never routes to Stan — brms's first-call
Stan compile (typically 30–60 s) is incompatible with the auto-fast-
path promise; Stan is opt-in only via explicit `backend = "brms"` on
`fb_brms()`.

## Stan passthrough on `fb_brms(backend = "brms")`

`fb_brms()` builds the flexyBayes intermediate representation (IR),
translates the prior, hands off to `brms::brm()`, and wraps the
returned `brmsfit` in a `c("flexybayes_brms", "flexybayes")` subclass.
The live `brmsfit` is exposed on the `$brms` slot so brms's own
posterior tooling (`loo()`, `posterior_predict()`, `bayes_factor()`)
remains directly available.

```r
fit_s <- fb_brms(Reaction ~ Days + (1 | Subject),
                 data = sleepstudy, backend = "brms")
fit_g <- fb_brms(Reaction ~ Days + (1 | Subject),
                 data = sleepstudy, backend = "greta")
triangulate(fit_s, fit_g)
```

`review_code = TRUE` on the Stan path returns Stan source via
`brms::make_stancode()` — compile-free inspection before any Stan
compilation fires.

## Cross-engine triangulation

`triangulate(fit_a, fit_b)` computes mean difference, SD ratio, tail
drift, Wasserstein-1, and R-hat-on-means on every parameter the two
fits have in common. Canonical-name resolution (see below) means the
caller usually does not need to pass a `name_map`.

```r
fit_g <- flexybayes(yield ~ env, random = ~ geno, data = trial,
                    backend = "greta")
fit_i <- flexybayes(yield ~ env, random = ~ geno, data = trial,
                    backend = "inla")
triangulate(fit_g, fit_i)
#> Common parameters: 5
#> # A tibble: 5 × 6
#>   parameter        mean_diff sd_ratio tail_drift wasserstein_1 rhat_means
#>   <chr>                <dbl>    <dbl>      <dbl>         <dbl>      <dbl>
#> 1 (Intercept)        -0.041   0.997      0.012         0.041     1.002
#> ...
```

## `canonical_names()` registry

Each backend names parameters differently (greta's `sigma_g`, INLA's
`Precision for g` on the precision scale, brms's `sd_g__Intercept`,
etc.). `canonical_names()` resolves backend-native names to a single
canonical name and applies the appropriate scale transform — most
visibly, INLA's precision draws are flipped to the SD scale before
comparison.

```r
canonical_names(fit_i)
#>   native                canonical    transform
#>   "(Intercept)"         "(Intercept)" identity
#>   "Precision for g"     "sd_g"        1/sqrt(.)
#>   "Precision for the Gaussian observations" "sigma" 1/sqrt(.)
```

`triangulate()` uses the registry to align parameters before
computing metrics.

## `prior_summary()` accessor

A new exported S3 generic surfaces the resolved priors used to fit
the model. The summary distinguishes three resolution paths:

- **auto-default** — bounded uniform on SD per Gelman (2006); fires
  when neither a user `fb_prior()` nor a legacy `prior_vc_sd` scalar
  is supplied.
- **user-supplied** — the `fb_prior()` object the caller passed via
  the `prior` argument.
- **legacy-scalar** — the `prior_fixed_sd` / `prior_vc_sd` bridge,
  preserved verbatim when `prior_vc_sd` is passed explicitly.

```r
fit <- flexybayes(Reaction ~ Days, random = ~ Subject,
                  data = sleepstudy)
prior_summary(fit)
#> <prior_summary>  backend = greta
#>   Source: auto-default bounded uniform on SD (Gelman 2006)
#>     Upper bound U = 282.7
#>     Scale basis    = 5 * sd(Reaction)
```

On `fb_greta()` fits the summary is flagged `declaration_only = TRUE`
because flexyBayes does not re-prior the user-built greta graph; the
prior records what the user declared the model encodes.

## `review_code = TRUE` workflow

A new optional argument on `flexybayes()`, `fb_brms()`, and
`fb_greta()` lets users inspect the generated backend code before any
sampling fires, then advance into the fit when ready:

```r
rev <- flexybayes(yield ~ env, random = ~ geno, data = trial,
                  review_code = TRUE)
rev                  # two-line summary: backend + IR dimensions
cat_code(rev)        # emit the generated greta (or Stan) code
fit <- proceed(rev)  # fit; a second proceed(rev) returns the cache
```

The returned `<flexybayes_review>` object carries the generated code,
the parsed IR, the resolved prior, the captured call, and a snapshot
of `.Random.seed`. The seed snapshot is restored on `proceed()` entry
so a direct call and a review-then-proceed pair reproduce the same
R-RNG state.

`review_code = TRUE` and `return_code = TRUE` (the older
code-string-only option) are mutually exclusive. Default is `FALSE`;
session-level override via
`options(flexyBayes.review_code_default = TRUE)`.

## Prior contract

Auto-default (no `prior` and no `prior_vc_sd` supplied):

| Target | Default | Notes |
|---|---|---|
| Residual `sigma` (Gaussian / identity link) | `uniform(0, 5 * sd(y))` | Gelman 2006 |
| Residual `sigma` (log link) | `uniform(0, 5 * sd(log(y + 0.5)))` | Gelman 2006 |
| Residual `sigma` (logit link) | `uniform(0, 5)` | Gelman 2006 |
| `sd(group)` for `simple` / `ide` / `id` terms | matched to residual by family | Gelman 2006 |
| Fixed-effect coefficients | `normal(0, prior_fixed_sd)`, `prior_fixed_sd = 100` | Gelman 2006 |

Structured-covariance random terms (`vm`, `ped`, `at`, `us`, `fa`,
`ar1`) currently fall back to the legacy `lognormal(0, prior_vc_sd)`
default; per-form uniform defaults are scheduled for v0.2.5.

The PC prior remains a first-class explicit option via
`fb_prior(sigma ~ pc(upper = U, prob = p))` and is the cross-engine
interlingua (Simpson et al. 2017) for translation across greta / INLA
/ brms.

The `prior_fixed_sd` default was raised from 10 to 100 in this cycle;
the previous value was too tight for responses on the natural data
scale (e.g., `sleepstudy$Reaction` with mean ≈ 298 ms) and induced a
substantial intercept bias against the REML reference.

`fb_prior()` accepts the targets `sigma`, `sd(group)`, `b(name)`,
`cor(group)`, `smooth(var)`, and the families `pc`, `normal`,
`student_t`, `half_normal`, `half_cauchy`, `cauchy`, `gamma`,
`exponential`, `lkj`, `uniform`.

## LGM feasibility filter

`lgm_gate(fb)` runs a structural feasibility check on the parsed IR
before INLA dispatch. The filter returns either an acceptance or an
`lgm_refusal` object carrying every rule that failed, the diagnostic,
the suggested re-route (`backend = "brms"` via `fb_brms()` for the
Stan passthrough; greta for the broader flexyBayes formula path), and
a two-key-armed override path.

The structural refusals currently live in two places (the gate plus
`emit_inla()`); folding the emit-time refusals into the gate is the
ADR 0017 v0.2.5 work.

## `gretaR` slot

A dormant scaffold for the `gretaR` backend is registered:
`gretaR_status()` reports `activated = FALSE` and explains the
activation procedure. The four touch-points (`match.arg` extension,
canonical-name mapper, dispatch branch, status helper) are in place
so v0.3 activation reduces to a single short patch plus the
`emit_gretaR.R` body — once the gretaR package goes public and
audit-clean.

## Vignettes

Twelve numbered vignettes ship with the package:

1. Getting started · 2. ASReml-shaped formulas · 3. Foundational
regression · 4. Hierarchical models · 5. Structured covariance ·
6. Priors and regularisation · 7. METs and genomic selection ·
8. Downstream analysis · 9. Spatio-temporal models · 10. Cross-
engine triangulation · 11. LGM feasibility filter · 12. Backend
internals.

Heavy MCMC vignettes use a `.Rmd.orig` precompile pattern
(`vignettes/_precompile.R`); the `.Rmd` that ships in the package
tarball is the pre-evaluated static output.

## References

- Gelman, A. (2006). Prior distributions for variance parameters in
  hierarchical models. *Bayesian Analysis* 1(3): 515–534.
- Simpson, D., Rue, H., Riebler, A., Martins, T. G., & Sørbye, S. H.
  (2017). Penalising model component complexity: a principled,
  practical approach to constructing priors. *Statistical Science*
  32(1): 1–28.
- Rue, H., Martino, S., & Chopin, N. (2009). Approximate Bayesian
  inference for latent Gaussian models by using integrated nested
  Laplace approximations. *JRSS: Series B* 71(2): 319–392.
