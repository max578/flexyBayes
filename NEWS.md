# flexyBayes 0.3.6

## Stage 4 -- backend routing trace + preflight metadata consumption

Two architectural additions complete the v0.2.6 -> v0.3.x dispatch
story. The existing four-backend surface (`greta` / `inla` /
`brms`-passthrough / `gretaR`-scaffold) now routes deliberately
and reports its decisions reproducibly.

**`backend_decision(fit)` gains four new fields.** Every fit
produced under v0.3.6 carries the existing four fields (`backend`
/ `path` / `gate_checks` / `reason`, per ADR 0006) plus:

- `preflight_summary` -- the `.fb_preflight()` return value when
  preflight ran (>1e5-row path); NULL on the small-data fast path
  by design.
- `representation_plan` -- a slim list of one entry per IR term:
  `(term_id, representation_class, justification)`. Derived from
  `preflight_summary`; NULL when no preflight ran.
- `rejected_routes` -- a list of `(backend, reason)` pairs for
  the backends considered but not chosen. Empty for explicit user
  requests (policy bypassed). For `backend = "auto"`, the list
  enumerates the non-chosen candidates from `{greta, inla,
  gretaR}` with per-backend reason codes.
- `routing_policy_version` -- the policy version that decided
  this fit's dispatch (e.g., `"stage4_v1"`). Bumping this string
  is the audit-anchor for reproducibility -- a fit produced under
  an older policy carries the older string.

Legacy fits (those that recorded the v0.2 / v0.3.5 four-field
trace before v0.3.6 landed) read out via the accessor with NULL
defaults on the four new fields; downstream code reading
`backend_decision(fit)$chosen_backend` is unaffected.

**`lgm_gate(fb, preflight = NULL)`.** The gate signature gains an
optional second argument. When `preflight` is NULL (the v0.3.5
calling convention), the gate behaves exactly as today -- 10
structural rules. When `preflight` is supplied, the gate runs an
11th rule, `.lgm_check_memory_feasibility_inla(fb, preflight)`,
that refuses when the INLA path's projected memory exceeds the
active ceiling. The Stage 4 ship is a single-multiplier
approximation: INLA memory ~= 3x the indexed preflight total (the
INLA dense intermediate inflation rule of thumb; per-term
estimators land at v0.3.7). The multiplier is configurable via
`options(flexyBayes.inla_memory_multiplier = <value>)`. **The new
refusal reason code is `memory_infeasibility_inla`** -- distinct
from the existing structural reason codes (`fixed_term_type_inla`
/ `random_term_type_inla` / `rcov_term_type_inla` from ADR 0017,
the six original family / predictor / distributional / re_prior
/ latent_class / hyperparam_budget). The structural-vs-memory
distinction is the central new piece of dispatch information --
distinguishable from `rejected_routes` alone, without re-running
the gate.

**Routing-policy registry.** The policy lives in
`.routing_policy_table()`, a small data.frame in `R/dispatch.R`
that encodes the (`user_request`, `gate_outcome`,
`preflight_outcome`, `inla_installed`) tuple -> `(chosen_backend,
reason_code)` mapping. This is the single source of truth: the
dispatch logic queries the table via `.resolve_routing()` rather
than re-deriving the decision from nested ifs. Changing the
policy is a table-edit, not a control-flow surgery.

**Approximate-scheme guard.** Backend names carrying an
approximate-scheme exactness label (e.g.,
`"inla_pardiso_approximate"`, `"variational_advi"`) now refuse at
the entry function with `approximate_route_not_yet_registered`,
pointing to ADR 0027 (the future approximation registry). The
package's identity rests on exactness labelling (per Stage 3A /
ADR 0022); silently routing an approximate request would violate
that contract.

Worked example -- a memory-infeasible model on `backend = "auto"`
now produces a trace like:

```r
bd <- backend_decision(fit)
bd$backend                # "greta"
bd$path                   # "auto_lgm_refuse_memory"
bd$rejected_routes
# list(
#   list(backend = "inla",   reason = "memory_infeasibility_inla"),
#   list(backend = "gretaR", reason = "backend_not_activated")
# )
bd$routing_policy_version # "stage4_v1"
```

The decision is now reproducible from `backend_decision(fit)`
alone, plus the policy version string. The reproducibility
posture mirrors `targets::tar_metadata()` (Landau 2021), which
captures the chosen execution plan plus the rejected alternatives
+ reasons on every pipeline run.

The vignette companion (`flexyBayes-11-lgm-feasibility.Rmd.orig`
extension for the structural-vs-memory refusal distinction) is
staged for v0.3.7 alongside the per-term INLA memory estimator.

# flexyBayes 0.3.5

## Stage 3B (file-output) -- file-backed prediction + sample activation

Two additions to `predict.flexybayes(newdata, ...)` complete the
Stage 3B scope opened at 0.3.4.

**File-backed prediction output.** Three new arguments --
`output_file`, `format`, `interop` -- route `predict()` to a
disk-backed tabular output when `output_file` is supplied. The
file carries `point`, `lower`, `upper` (95% posterior credible
bounds) plus optional `se.fit`, plus the columns of `newdata`,
under the format resolved by:

```
format = "auto" (default):
  if (interop)                        return "csv"
  if (N >= 1e6 && fst_available)      return "fst"
  if (N >= 1e6 && !fst_available)     return "rds"
  if (N <  1e6)                       return "rds"

format = "csv": always "csv" (no fst dependency)
format = "rds": always "rds" (no fst dependency)
format = "fst":
  if (fst_available)                  return "fst"
  else                                stop(structured_refusal_with_install_hint)
```

The fst path is 30-40x faster than rds at N >= 1e6 for
essentially the same on-disk size (single-platform benchmark
under `benchmark_results/fst_stage3b_2026-05-23`). `fst` is
declared in `Suggests` with a `>= 0.9.0` floor; `predict(...,
format = "fst")` with `fst` not installed raises a structured
refusal naming the install command and the `format = "rds"`
override line. Refusing rather than silently falling back is
consistent with the package's broader no-silent-refusal posture.
Pre-existing prediction grids are not overwritten: if
`output_file` already exists, `predict()` raises a structured
stop suggesting `unlink()` rather than overwriting silently.

The posterior intervals follow standard posterior-predictive
quantile semantics (Gelman et al. 2013, Bayesian Data Analysis,
section 15): the linear predictor is evaluated under each
retained posterior draw, the link inverse is applied per draw,
and `point` / `lower` / `upper` are read off the rowwise mean
and 2.5% / 97.5% quantiles. Chunked vs unchunked file output is
equivalent at floating-point precision; BLAS non-associativity
at the matrix-size boundary introduces ULP-level differences
(~2e-16) but no numerically meaningful drift.

**`allow_new_levels = "sample"` is now active.** The label was
stable at 0.3.4; the implementation ships here. Unknown factor
levels in `newdata` get a fresh `Normal(0, tau_group)`
random-effect realisation layered onto the linear predictor per
posterior draw (mirrors `brms::posterior_epred(...,
sample_new_levels = "gaussian")`). Caller's `set.seed()`
controls reproducibility.
The in-memory return reports the posterior-mean point estimate;
the sampled-RE contribution averages toward zero across draws so
the in-memory point estimate sits close to the population
baseline -- the file-backed return captures the proper per-row
posterior interval reflecting sampled-RE uncertainty. INLA fits
do not currently expose per-draw access and route to a
structured refusal; an INLA draws adapter is queued for a future
release.

## Internals

- New `R/predict_file_output.R` (`.fst_available`,
  `.resolve_format`, `.predict_write_file`, `.predict_to_file`).
- New `R/predict_posterior.R` (`.predict_per_draw`,
  `.predict_intervals`, `.predict_sample_re_for_unknowns`,
  `.predict_in_memory_sample`).
- `R/predict_chunked.R` -- `.predict_resolve_factors()` drops the
  0.3.4 deferred-stop on `"sample"`; the new branch tags
  unknown rows via `attr(newdata, "sample_re_summary")` for
  downstream per-draw consumption.
- `R/methods.R` -- `predict.flexybayes()` gains `output_file`,
  `format`, `interop` arguments and two new dispatch branches.

## Test coverage

- New `tests/testthat/test-predict-file-output.R` (16 blocks)
  covering the pure-path resolution table, the structured
  fst refusal, csv/rds/fst round-trip with factor preservation,
  chunked invariance, format = "auto" end-to-end with mocked
  fst availability, the interop branch, and overwrite refusal.
- New `tests/testthat/test-predict-sample-new-levels.R` (7
  blocks) covering active success on mixed known+unknown rows,
  caller-seed-driven non-determinism, posterior-interval
  variance scaling, backward-compat with legacy fits,
  deferred-stop removal confirmation, and the no-draws fit
  refusal.

Total test counts: PASS 1317 / FAIL 0 / SKIP 73 (0.3.4 baseline
was 1262/0/73; +55 expectations across 22 new blocks).

# flexyBayes 0.3.4

## Stage 3B (core) -- chunked indexed prediction + factor-dictionary handling

Three new pieces on the `predict.flexybayes(newdata, ...)` surface
for prediction grids large enough to warrant chunked iteration and
for cases where `newdata` carries factor levels not seen at fit
time.

**Dictionary-backed factor handling.** Fits now carry a metadata-
only `<fb_dataset>` descriptor (frozen factor-level dictionaries
plus column-type cache) on `fit$extras$fb_dataset`. At
`predict(newdata)` time, factor columns in `newdata` resolve
against this dictionary instead of being re-derived from
`newdata`. The change closes a latent silent-re-levelling
bug where the v0.3.3 prediction path could permute a random-effect
contribution under specific `newdata` orderings.

**`allow_new_levels = c("population", "sample", "refuse")`.**
Policy for factor values in `newdata` that are not in the fit-
time dictionary. `"population"` (default) coerces unknown-level
rows to NA on the affected column and emits a warning naming the
count; downstream prediction returns the population-level
prediction for those rows. `"refuse"` raises a structured stop on
the first unknown level, naming the column and (up to five) unknown
values. `"sample"` (fresh random-effect draw per unknown level) is
reserved at 0.3.4 -- the label is stable but the implementation
ships at 0.3.5 alongside the file-backed prediction output.

**`chunk_size` argument.** When supplied and `nrow(newdata) >
chunk_size`, prediction iterates over chunks of the requested size
and concatenates the per-chunk results. Default `NULL` preserves
the single-pass behaviour. `chunk_size` is a wall-time / peak-
memory knob -- the numerical output is identical to the single-
pass call. A typical setting at large `newdata` is `chunk_size =
10000L`.

The file-backed prediction output formats (`format = c("auto",
"csv", "rds", "fst")` + `output_file` argument) ship together at
0.3.5; this release covers the in-memory prediction surface only.

---

# flexyBayes 0.3.3

## Stage 3A -- Gaussian aggregated emit (greta path)

Completes the aggregated-gaussian path by activating the greta
backend alongside INLA. `fb_brms(..., backend = "greta", aggregate
= TRUE)` and `flexybayes(..., backend = "greta", aggregate = TRUE)`
now route through the same sufficient-statistics emit as the INLA
path. The greta implementation factorises the cell-mean weighted
gaussian observation against a gamma observation on the within-cell
sum of squares; together these recover the per-row gaussian log-
likelihood exactly (the algebraic identity proof is in Searle,
Casella & McCulloch (1992) *Variance Components* §3). On a fixed-
seed synthetic dataset with N = 800, J = 20, the aggregated greta
posterior recovers a known (beta, sigma, tau) triple within MC
tolerance; the backend-fidelity check is shipped as a stress-gated
test (`FLEXYBAYES_RUN_STRESS=true`).

**Known caveat.** The aggregated INLA path still uses an explicit
`loggamma(1, 5e-5)` precision prior on random-intercept terms when
the user has not supplied a prior via `prior = fb_prior(...)`, for
the data-scale-stability reason in the 0.3.2 caveat. Unifying the
default-prior behaviour across per-row and aggregated paths remains
queued. The greta aggregated path follows the same default prior
shape (sd-scale) as the per-row greta path; matched-prior
comparisons within greta are therefore consistent without extra
configuration.

**Heterogeneous residual.** `at(f):units` on greta now flows through
the aggregated path end-to-end (when `f` is in the cell key). The
multi-likelihood INLA stack required for the same on the INLA
aggregated path remains queued.

---

# flexyBayes 0.3.2

## Stage 3A -- Gaussian aggregated emit (INLA path)

Wires the sufficient-statistics aggregation foundation (introduced
in 0.3.0 as `<fb_aggregated>` + `<fb_aggregation_plan>`) into the
live dispatch path. Gaussian-identity LMMs whose linear predictor
is cell-constant -- fixed numeric / factor effects plus random
intercepts on factor groupings -- now have an aggregated emit path
that fits the same posterior on per-cell sufficient statistics
rather than per-observation likelihood contributions. The aggregated
log-likelihood is the algebraic identity of the per-row form (no
approximation; see Searle, Casella & McCulloch (1992) *Variance
Components* §3 and Bates et al. (2015) §3 on the profiled-deviance
shortcut); the bit-exact equivalence is gated by a property-based
test in `tests/testthat/test-aggregate-gaussian.R`.

**API.** A new `aggregate = c("auto", TRUE, FALSE)` argument joins
`flexybayes()` and `fb_brms()`. The default `"auto"` consults the
plan and silently routes through the aggregated emit when the IR
is in scope and compression is productive (`K/N <= 0.5`); falls
through to the per-row path when out of scope. `TRUE` forces
aggregation -- raises a structured refusal naming the plan's
reason code when ineligible. `FALSE` skips the gate entirely.

**Exactness field.** Every flexybayes fit now carries an
`$exactness` slot. Per-row paths populate it as `"exact"`;
aggregated paths populate it as `"aggregated_exact"`. The dispatch
trace's `path` slot reads `"aggregated_gaussian"` on aggregated
fits. `summary()` and a new `print.flexybayes_aggregated()` /
`summary.flexybayes_aggregated()` surface the field plus a
compression-ratio line when N/K >= 2 (suppressed on smaller
datasets to avoid misleading claims).

**Backend coverage at 0.3.2.** INLA-backed aggregation is shipped
end-to-end (cell-mean weighted gaussian + a custom precision-prior
expression that absorbs the within-cell sum-of-squares correction;
the algebra is documented in the file header). Greta-backed
aggregation is deferred to a follow-on -- the algebraic pattern
(cell-mean weighted gaussian plus a gamma observation on the
within-cell SS) is viable, but the package wiring needs a
codegen-without-runtime-parse workaround for an R S3 dispatch
context-sensitivity that surfaces only inside the package
namespace. `aggregate = TRUE` on `backend = "greta"` refuses
cleanly with a deferred-feature message; `aggregate = "auto"` on
greta silently falls through to the per-row path.

**Heterogeneous residual.** `at(f):units` is supported on the
aggregated path when `f` is a cell-key term (so each cell has a
single residual variance). When the residual factor is not a cell
key the per-row / per-cell algebraic identity breaks and the emit
refuses with a structured `heterogeneous_residual_factor_not_in_-
cell_key` reason code.

**Known caveat.** The aggregated INLA path uses an explicit
`loggamma(1, 5e-5)` precision prior on random-intercept terms when
the user has not supplied a prior via `prior = fb_prior(...)`,
because INLA's data-scale-dependent default would otherwise
produce different effective priors on the per-row and aggregated
data scales. Matched-prior comparisons between per-row and
aggregated paths therefore require either passing an explicit
`fb_prior()` or accepting that the residual / random-intercept
posteriors will differ on tail behaviour. The fixed-effect
posteriors remain bit-exactly equivalent under the algebraic
identity. Unifying the per-row default-prior behaviour with the
aggregated path is queued for a follow-on.

---

# flexyBayes 0.3.1

## Trust Pass -- preflight + aggregation honesty hardening

A focused three-phase pass on the public API's honesty contract,
spanning the preflight layer, the aggregation taxonomy, and the
public-facing metadata. Closes a deep review of the v0.3.0.9000
development tip end-to-end. No user-facing API signature changes;
every revision tightens behaviour the package already promised.

**Trust bugs.** A session-level `options(flexyBayes.review_code_default
= TRUE)` no longer slips past the unsupported-backend refusal on
`backend = "inla"` / `"auto"` for either `flexybayes()` or `fb_brms()`
-- option resolution now runs before the backend guard. The preflight
refusal headline no longer claims "the design exceeds the active
memory ceiling" when the refusal is actually
`representation_unknown_for_preflight`; the headline now branches on
the reason code so an unknown-representation refusal does not falsely
send the user down the ceiling-override path.

**Preflight taxonomy.** Structured-covariance random terms are split
into known-indexed forms (`vm`, `ped`, `ar1`, `ar1_spatial`) that
keep the tested heuristic estimator, and everything else (`at`,
`us`, `fa`, `at_simple`, `us_gxe`, `fa_gxe`, `vm_gxe`, ...) that
now routes to `representation_unknown_for_preflight` rather than
silently under-estimating the design memory at large N. The previous
"single level" fallback in `.preflight_term_level_count()` was
replaced with `NA_integer_`; every consumer branch (structured-cov,
random intercept, uncorrelated random slope, fixed factor, factor
:numeric interaction) now treats an unresolvable level count as the
signal to escalate to an unknown-representation refusal.

**Aggregation refusal codes.** The Stage 3A out-of-scope taxonomy was
renamed and aligned across the two emitters that report it:
`.assert_aggregate_in_scope()` (the runtime gate) and
`.fb_aggregation_plan()` (the model-level planner) now produce the
same reason code for the same model. The previous catch-all
`random_slope_in_scope` is replaced by three positively-named codes
(`random_slope_not_aggregatable`, `structured_random_not_aggregatable`,
`smooth_term_not_aggregatable`); the planner's
`compression_data_dependent` is renamed
`continuous_cell_key_data_dependent` for clarity.

**Public-facing metadata.** The `codemeta.json` version field, the
`cran-comments.md` build description, `SECURITY.md`, `SUPPORT.md`,
and the README's `review_code` support row are all refreshed for
the 0.3.x line. `API_STABILITY.md` splits the structured-covariance
default-priors row by actual implemented behaviour (`vm`/`ped` on
the uniform-on-SD default; `at`/`us`/`fa`/`ar1`/`spl` on the legacy
lognormal). `CONTRIBUTING.md` documents the source-directory
`R CMD check` footgun and recommends the build-then-check workflow.

The AAGI-AUS GitHub URL declared in `DESCRIPTION` is the agreed
forward destination; until the upstream repository rename ships,
the CRAN-incoming feasibility check raises a sub-NOTE for the URL.
`cran-comments.md` itemises this and the other structural NOTE
sub-items in full.

## Test coverage

`PASS 1187 / FAIL 0 / SKIP 72` on `tools/tally.R` (was 1151/0/72 at
the deep-review baseline; +36 expectations across the Trust Pass).
9 new `test_that` blocks pin the structured-covariance preflight
split and the renamed aggregation taxonomy; 8 ordered cases pin the
`review_code` option-default ordering across both formula verbs.


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
