# Changelog

## flexyBayes 0.5.0

### The verb surface, finalised (breaking change)

The fitting surface now has one consistent shape: a universal entry that
spans every backend, single-engine pins, and exported ingest adapters.
The deprecation windows opened at 0.4.1 are now closed.

- **Engine pins are single-engine, by name.**
  [`fb_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_greta.md),
  [`fb_inla()`](https://aagi-aus.github.io/flexyBayes/reference/fb_inla.md),
  and
  [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
  each fit via exactly one engine — `fb_<engine>(...)` is sugar for
  `fb(..., backend = "<engine>")`. Passing a conflicting `backend` to a
  pin is now a clear error rather than being silently overridden.
  `fb_brms(backend = "brms")` (the redundant self-pin) is still
  accepted.
- **[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
  no longer takes a non-brms backend.** The multi-backend role moved to
  [`fb()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
  /
  [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
  at 0.4.1; at 0.5.0
  [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
  is the brms engine pin. Pass the same formula to
  [`fb()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
  to reach `greta`, `inla`, or `auto`.
- **[`fb()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
  /
  [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
  fit a native greta model directly.** Pass a `greta::model()` object
  (or a
  [`fb_from_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_from_greta.md)
  intermediate representation) straight to
  [`fb()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md);
  it is fit via greta and returned with the full post-fit surface. To
  keep a canonical-name map for cross-engine
  [`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md),
  build the representation once and reuse it:
  `fb(fb_from_greta(model, canonical_names = c(...)))`.
- **`fb_greta(model = )` is no longer a separate native-graph verb.**
  The `model =` argument still works (it is mapped to the universal
  model slot), so existing native-graph calls keep fitting; the
  recommended form is `fb_greta(model)` or, with a canonical map,
  `fb_greta(fb_from_greta(model, canonical_names = c(...)))`.

### Backend selection has one home

Backend availability, per-engine capability, and the `auto` candidate
set are all sourced from a single locked registry, so an unsupported
(model x engine) pair always yields a registered, structured refusal
naming the offending construct.

### Bug fixes

- **[`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md)
  now compares INLA variance components on the standard- deviation
  scale.** The automatic precision-to-standard-deviation conversion for
  an INLA fit was keyed so that it silently did not fire, so a
  cross-engine comparison (for example greta versus INLA) reported the
  INLA precision against the other engine’s standard deviation on the
  `sigma` and `sd_<group>` rows. The conversion now fires by default,
  with no need to pass `transform_b` by hand.
- **[`plot()`](https://rdrr.io/r/graphics/plot.default.html) works on
  every backend fit.** Previously only a greta fit had a
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) method, so
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html) on an INLA,
  brms, aggregated, or native-greta fit fell through to
  [`graphics::plot.default()`](https://rdrr.io/r/graphics/plot.default.html)
  and errored. `plot(fit, type = "effects")` now works on any backend,
  and plot types that need quantities a backend does not expose (trace
  plots without MCMC draws, residual plots without fitted values) report
  that clearly instead of erroring.
- **Positional and named prior arguments behave identically.** A prior
  written positionally (for example `normal(0, 50)`) is now read the
  same as the named form (`normal(0, sd = 50)`) on every emit path;
  previously a positional scale could be silently dropped to the default
  on the greta and INLA paths.
- **[`predict()`](https://rdrr.io/r/stats/predict.html), `emmeans()`,
  and `marginaleffects` work on an INLA fit of a brms-grammar mixed
  model.** A model written as `y ~ x + (1 | g)` and fitted via INLA
  previously refused these downstream calls, because the random-effect
  bar term leaked into the fixed-effect design matrix.
  [`formula()`](https://rdrr.io/r/stats/formula.html) on an INLA fit now
  returns the fixed-effect formula only, as documented, so the design
  matrix matches the fitted coefficients. Aggregated INLA fits are
  covered too.
- **A non-binary binomial response is refused on the greta backend**
  rather than being silently fitted as a Bernoulli model.
- **Internal faults are no longer swallowed.** A genuine fault in the
  latent-Gaussian gate during aggregated `auto` routing, and a failure
  to compute [`logLik()`](https://rdrr.io/r/stats/logLik.html), now
  surface rather than being silently turned into a fallback or `NA`.

## flexyBayes 0.4.1

### One universal entry across every grammar and backend

[`fb()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
/
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
becomes the single entry for any input grammar and any backend, with
single-engine pins alongside it.

- **Grammar polymorphism.**
  [`fb()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
  /
  [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
  now accept a brms / lme4-style bar-grouped formula
  (`response ~ x + (1 | g)`) in addition to the ASReml `fixed` /
  `random` / `rcov` form. The grammar is detected from the call shape;
  the new `syntax` argument forces it. A brms-style model now reaches
  every available backend through the universal entry, not just one.
- **Engine pins.**
  [`fb_inla()`](https://aagi-aus.github.io/flexyBayes/reference/fb_inla.md)
  joins
  [`fb_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_greta.md)
  as a single-engine fitting verb: `fb_inla(...)` is exactly
  `fb(..., backend = "inla")`, and accepts the same grammars.
- **Exported ingest adapters.**
  [`fb_from_asreml()`](https://aagi-aus.github.io/flexyBayes/reference/fb_from_asreml.md),
  [`fb_from_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_from_brms.md)
  and
  [`fb_from_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_from_greta.md)
  are now exported. They turn a model specification into the
  backend-agnostic intermediate representation, for inspection, caching,
  or hand-off to a fitting verb.
- **Registry-driven backend selection.** Backend availability,
  capability, and the `auto` candidate set are sourced from a single
  locked backend registry, so the dispatch facts have one home.

### Deprecations

- **[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
  with a non-brms backend is deprecated.** Pass the same formula to
  [`fb()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
  /
  [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md),
  which now detects brms grammar and reaches every backend (including
  the same `auto` / `greta` / `inla` routing).
  `fb_brms(backend = "brms")` is unaffected. The multi-backend form is
  removed at 0.5.0, when
  [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
  becomes the brms engine pin.
- **The `fb_greta(model = )` native-graph signature is deprecated.**
  Build the intermediate representation from a native greta model with
  [`fb_from_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_from_greta.md).
  The signature is removed at 0.5.0, when
  [`fb_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_greta.md)
  becomes the greta engine pin.

## flexyBayes 0.4.0

### Covariance carriers: the `fb_cov()` constructor (breaking change)

Structured covariance is now declared with the
[`fb_cov()`](https://aagi-aus.github.io/flexyBayes/reference/fb_cov.md)
constructor noun inside a random term, completing the four-constructor
surface
([`fb_prior()`](https://aagi-aus.github.io/flexyBayes/reference/fb_prior.md),
[`fb_engine()`](https://aagi-aus.github.io/flexyBayes/reference/fb_engine.md),
[`fb_approx()`](https://aagi-aus.github.io/flexyBayes/reference/fb_approx.md),
[`fb_cov()`](https://aagi-aus.github.io/flexyBayes/reference/fb_cov.md)).

- **`fb_cov(M, type)`** wraps a covariance carrier and is passed via the
  `cov` argument: `vm(geno, cov = fb_cov(L, type = "chol"))`. The five
  carrier types are `"dense"`, `"chol"`, `"precision"`, `"blocks"`, and
  `"low_rank"` (the last is a reserved vocabulary entry at this
  release). The constructor returns a classed object carrying its
  `representation_class` and a construction-time `validation_summary`;
  it comes with
  [`is_fb_cov()`](https://aagi-aus.github.io/flexyBayes/reference/is_fb_cov.md)
  and a print method.
- **The legacy `vm()` / `ped()` keyword carriers are deprecated.** The
  four forms introduced in v0.3.7 — `vm(group, chol = L)`,
  `vm(group, precision = Q)`, `vm(group, blocks = list(...))`, and
  `vm(group, low_rank_factor = U, low_rank_scheme = "pca")` — now emit a
  `lifecycle` migration warning naming the
  [`fb_cov()`](https://aagi-aus.github.io/flexyBayes/reference/fb_cov.md)
  replacement. They continue to work in 0.4.0 and will be **removed at
  0.5.0**. The bare dense forms `vm(group, V)` / `ped(group, A)` are
  unchanged.

### New constructor nouns: `fb_engine()` and `fb_approx()`

Two named constructors join
[`fb_prior()`](https://aagi-aus.github.io/flexyBayes/reference/fb_prior.md),
so a model’s inference engine and any approximation are specified as
explicit, printable objects rather than bare strings.

- **`fb_engine(name, opts)`** names an inference engine (`"greta"`,
  `"inla"`, `"brms"`) and its sampler tuning, and is passed as the
  `backend` argument:
  `flexybayes(..., backend = fb_engine("greta", chains = 4L))`. It
  records the engine’s inference `paradigm` and a `toolchain_status`
  reflecting whether the engine’s package is installed. The bare-string
  form (`backend = "greta"`) continues to work unchanged.
- **`fb_approx(scheme, ...)`** names an approximation scheme — validated
  against the approximation registry — and its tuning, and is passed as
  a smooth representation:
  `s(x, representation = fb_approx("low_rank_smooth", rank = 5L))`. It
  carries a literature-referenced description of the scheme’s bias
  bound. An unregistered scheme is refused with the supported
  vocabulary.
- Both come with
  [`is_fb_engine()`](https://aagi-aus.github.io/flexyBayes/reference/is_fb_engine.md)
  /
  [`is_fb_approx()`](https://aagi-aus.github.io/flexyBayes/reference/is_fb_approx.md)
  predicates and print methods.

### `emmeans` and `marginaleffects` now work end-to-end

Fits now expose the standard model interface that the downstream
estimation ecosystem dispatches on, so estimated marginal means,
contrasts, predictions, slopes, and comparisons work directly on both
the greta and INLA backends.

- **`emmeans::emmeans(fit, ~ f)` and `contrast()`** work on greta- and
  INLA-backed fits. The estimation basis is built to match each
  backend’s fixed-effect parametrisation — treatment contrasts on INLA,
  the over-parameterised (intercept + all factor levels) basis on greta,
  the latter handled through a non-estimability basis so only estimable
  combinations are reported. Posterior summaries use z-intervals.
- **`marginaleffects::predictions()`, `avg_slopes()`, and
  `avg_comparisons()`** work on both backends via the `get_coef()` /
  `set_coef()` / `get_vcov()` / `get_predict()` accessors, with
  population-level (fixed-effect) predictions on the identity link.
- **Per-row INLA fits gain
  [`coef()`](https://rdrr.io/r/stats/coef.html),
  [`vcov()`](https://rdrr.io/r/stats/vcov.html),
  [`predict()`](https://rdrr.io/r/stats/predict.html),
  [`formula()`](https://rdrr.io/r/stats/formula.html), and
  [`family()`](https://rdrr.io/r/stats/family.html) methods.**
  [`vcov()`](https://rdrr.io/r/stats/vcov.html) returns a Monte-Carlo
  estimate of the joint posterior covariance of the fixed effects (its
  marginal standard deviations match the INLA fixed-effect summary);
  `predict(newdata = ...)` returns fixed-effect predictions.
- A model whose fixed-effect design cannot be reconciled one-to-one with
  its fitted coefficients is refused with a clear message pointing to
  the posterior-draws workflow, rather than silently mis-mapped.

### Triangulation now labels its convergence claim by independence axis

[`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md)
reports gain an `independence` axis label, so a cross-engine agreement
says *what kind* of convergence it is, not just how close. A small
distance between two HMC fits (“implementation” independence)
underwrites a weaker claim than the same distance between an HMC fit and
a Laplace-approximation fit (“algorithmic” independence).

- Every
  [`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md)
  result carries `independence` (a vector from the closed vocabulary
  `algorithmic` / `implementation` / `specification`) and
  `axis_justification` (a one-line explanation). The print method
  surfaces the label, colour-graded by methodological strength on a
  colour terminal (plain text everywhere else). The Wasserstein columns
  are unchanged, so existing consumers keep working. The label follows
  Gelman et al. (2020, *Bayesian Workflow*, arXiv:2011.01808) §6 on
  cross-checks across implementations.
- The three v0.3.x backend pairs (greta–inla, greta–brms, brms–inla) are
  labelled; same-backend or unregistered pairs render without the label
  rather than refusing.

### Aggregated triangulation and matched-prior transparency

- **[`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md)
  now works on greta-aggregated fits.** Aggregated greta fits previously
  did not expose their posterior draws in the layout the draw extractor
  expects, so
  [`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md),
  [`canonical_names()`](https://aagi-aus.github.io/flexyBayes/reference/canonical_names.md),
  [`confint()`](https://rdrr.io/r/stats/confint.html),
  [`plot()`](https://rdrr.io/r/graphics/plot.default.html), and
  [`predict()`](https://rdrr.io/r/stats/predict.html) failed on them;
  they now work.
- **Aggregated-gaussian fits report their prior parametrization.** A new
  `prior_parametrization` field (`"per_row_equivalent"` under the
  default precision prior, `"custom"` otherwise) is shown in the
  aggregated [`print()`](https://rdrr.io/r/base/print.html) /
  [`summary()`](https://rdrr.io/r/base/summary.html) and returned by
  [`canonical_names()`](https://aagi-aus.github.io/flexyBayes/reference/canonical_names.md),
  so it is clear whether the aggregated posterior matches the per-row
  posterior.
- **[`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md)
  documents the matched-prior caveat** for aggregated inputs,
  forward-linking
  [`prior_summary()`](https://aagi-aus.github.io/flexyBayes/reference/prior_summary.md).

### `fb_refusals()` — a browsable registry of refusal reasons

flexyBayes now ships a complete, locked vocabulary of the conditions
under which it declines to fit, route, or validate a model, exposed
through a new exported accessor and a precise condition-class contract.

- **New exported function
  `fb_refusals(reason_code = NULL, since_version = NULL)`.** Returns an
  `fb_refusals_table` data frame — one row per refusal reason carrying
  its `reason_code`, a one-line `description`, the `since_version` it
  was introduced in, and the related `plan_field` — with a compact print
  method. Optional filters narrow the listing to specific reason codes
  or to an introducing-version prefix
  (`fb_refusals(since_version = "0.4")`).
- **Precise, catchable refusal classes.** Every user-facing refusal now
  carries a condition class `flexybayes_refusal_<reason_code>` above its
  existing family class, so a specific refusal can be caught directly,
  for example
  `tryCatch(fit, flexybayes_refusal_precision_not_symmetric = handler)`.
  The registry holds the complete 39-reason vocabulary; routing-decision
  reasons and internal control-flow signals are deliberately excluded as
  they are not refusals a user can encounter.
- The aggregated-emit out-of-scope refusal’s reason code is now
  `rcov_type_unsupported_for_aggregation` (previously a less descriptive
  identifier).
- **Unsupported families now refuse through the registry.** Requesting a
  family flexyBayes cannot fit — for example a survival / time-to-event
  likelihood — is declined at the family gate with the catchable
  `unsupported_family` refusal, which lists the supported families and
  points to
  [`fb_refusals()`](https://aagi-aus.github.io/flexyBayes/reference/fb_refusals.md).
- **Parse-time spec refusals now route through the registry.** Early
  formula checks raise catchable refusals instead of bare errors: a
  one-sided formula (`formula_not_two_sided`), a response absent from
  `data` (`response_not_in_data`), a factor-analytic rank below one
  (`fa_rank_invalid`), and a smooth variable absent from `data`
  (`smooth_variable_not_in_data`). The `review_code` / `return_code`
  entry-point guards likewise raise catchable refusals
  (`review_code_backend_unsupported`, `code_flags_mutually_exclusive`).
- **Tensor-product smooths are now refused, not silently accepted.**
  `te()`, `ti()`, and `t2()` raise `tensor_smooth_unsupported` rather
  than being parsed as ordinary named terms; flexyBayes fits univariate
  penalised splines (`s()`, `spl()`) only. The README gains a **Known
  limitations** section documenting the spatial (AR1-only), smooth
  (univariate-only), survival / HMM (deferred), and missing-data scope
  boundaries.

### `validate_approximation()` + the `low_rank_smooth` smooth approximation

Completes the approximation contract end to end: the `low_rank_smooth`
scheme, its greta emit path, and the exported
[`validate_approximation()`](https://aagi-aus.github.io/flexyBayes/reference/validate_approximation.md)
verb land together so every registered scheme carries a working
validation procedure.

- **New exported verb `validate_approximation(fit, threshold = 0.99)`**
  — the sixth (and architecturally-final) exported verb. Returns an
  `<fb_approximation_validation>` object reporting, per approximated
  smooth, the realised Frobenius capture () against the pass threshold
  (default `0.99`), the overall pass / fail verdict, and a fallback
  hint. An exact fit refuses (`approximation_scheme_unknown`).
- **`low_rank_smooth` approximation scheme.** Request a rank-K
  principal-component truncation of a smooth basis with
  `s(x, representation = list(scheme = "low_rank_smooth", rank = K))`.
  The model then carries `K` basis coefficients (the truncated basis
  `B_K = B V_K`, with `V_K` the top-K right singular vectors of the
  basis `B`) instead of the full `k`; prediction projects the newdata
  basis through the same `V_K`. The rank refuses unless it is a positive
  integer no greater than `min(basis dimension, n)`.
- **Three-tier `exactness` vocabulary** — `exact`, `aggregated_exact`,
  and `approximate_<scheme>`. Approximate fits carry an
  `[APPROX: <scheme>]` badge on the `Representation:` print line and in
  [`fb_plan()`](https://aagi-aus.github.io/flexyBayes/reference/fb_plan.md);
  every pre-existing fit’s label is unchanged.
- **Greta backend only.** `low_rank_smooth` truncates the dense `mgcv`
  smooth basis, which only the greta backend materialises; an explicit
  `backend = "inla"` or `"brms"` request for a low-rank smooth refuses
  (`low_rank_requires_greta`) rather than silently fitting a different
  smooth representation, and `backend = "auto"` resolves to greta.
- **Representation registry** gains the `low_rank` class (sixteenth
  entry).
- Fix: the brms-formula ingest’s unsupported-feature refusal no longer
  errors on a multi-line
  [`deparse()`](https://rdrr.io/r/base/deparse.html); a long unsupported
  term now surfaces the intended clean refusal.

### C5 approximation-registry scaffold (ADR 0030 + ADR 0027, v0.4.0 Wave 1 Phase 1A substrate)

Ships the approximation-scheme registry *infrastructure* — a single
locked `.approximation_registry` environment populated at `.onLoad()`
and locked via `.lock_approximation_registry()`, with the
`.register_approximation()` (five-field ADR 0027 Decision 2 schema:
`scheme`, `bias_bound`, `validation_fn`, `fallback_hint`,
`registered_in_adr`), `.lookup_approximation()`, and
`.approximation_scheme()` helpers. Empty at this step by design.

- The container ships ahead of its first scheme, mirroring the v0.3.8 C7
  refusal-registry scaffold (container at v0.3.8, first population at
  v0.3.10). The first approximation scheme (`low_rank_smooth`) registers
  together with its emit path and the exported
  [`validate_approximation()`](https://aagi-aus.github.io/flexyBayes/reference/validate_approximation.md)
  surface, because the scheme’s `validation_fn` reads the truncated and
  full smooth-basis matrices off a fit object that only the emit path
  produces; landing the scheme, its validation procedure, and its
  producer in one end-to-end-verifiable change honours the registry
  invariant that every registered scheme carries a working validation
  procedure.
- No user-facing API change at this step.
  [`validate_approximation()`](https://aagi-aus.github.io/flexyBayes/reference/validate_approximation.md),
  the `low_rank_smooth` scheme, the `[APPROX: <scheme>]` print badge,
  and the three-tier `exactness` controlled vocabulary land in the Phase
  1B completion change.
- Nine acceptance criteria in
  `tests/testthat/test-approximation-registry.R` (container exists +
  locked; empty at the scaffold step; five-field input validation;
  locked-registry refusal; unknown-scheme refusal with the
  empty-vocabulary hint; non-string-input refusal;
  `.approximation_scheme()` refusal delegation; user-side
  [`assign()`](https://rdrr.io/r/base/assign.html) raises;
  empty-vocabulary snapshot for vocab-lock gating).

### C4 representation registry formalised (ADR 0030, v0.4.0 Wave 1 Phase 1A)

Phase 1A ratifies ADR 0030 contract C4 (closed-vocabulary representation
classes) end-to-end. The representation-class vocabulary previously
spread informally across `R/fb_preflight.R`, `R/fb_plan.R`, and
`R/methods_truth_display.R` as inline string literals now lives in a
single locked `.representation_registry` environment populated at
`.onLoad()` and locked immediately after via
`.lock_representation_registry()`. Consumer sites route every reference
through `.representation_class("<name>")`, so typos refuse at runtime
rather than silently propagating an unknown class through preflight /
planning / display.

- Fifteen entries at v0.4.0 open: the ten plan-named classes
  (`dense_cov`, `chol_cov`, `sparse_precision`,
  `pedigree_sparse_precision`, `block_diagonal`, `dense_smooth`,
  `sparse_smooth`, `banded_smooth`, `indexed_structured_known`,
  `indexed_structured_estimate`) plus five additional classes
  load-bearing in the v0.3.10 source and surfaced during the Phase 1A
  producer-site sweep (`indexed_random_intercept`, `dense_baseline`,
  `indexed_fixed_numeric`, `indexed_fixed_factor`,
  `indexed_fixed_factor_numeric`). `low_rank` registers in Phase 1B
  alongside the ADR 0027 approximation registry; the `axis_*`
  reservation lands in Phase 2B with the backend-independence axis
  vocabulary.
- Internal helpers:
  `.register_representation(name, description, category, registered_in_adr, since_version)`
  validates inputs, refuses duplicate names, and refuses any attempt to
  register after the registry locks. `.lookup_representation(name)`
  returns the full registered entry and refuses unknown names with the
  known-classes hint. `.representation_class(name)` is the edit-light
  thin wrapper consumer sites call to swap a bare string literal for a
  validated-name round-trip.
- Twelve acceptance criteria in
  `tests/testthat/test-representation-registry.R` (container exists +
  locked, vocabulary completeness, schema check on every entry, lookup
  round-trip, lookup refusal on unknown name + non-string input,
  `.representation_class()` round-trip, registration input validation,
  duplicate refusal, locked-registry refusal, user-side
  [`assign()`](https://rdrr.io/r/base/assign.html) raises, vocabulary
  snapshot for vocab-lock gating). The snapshot test forces every future
  vocabulary addition or removal through a conscious maintainer-review
  step rather than silently mutating the registry.
- No user-facing API change. Refusal messages on unknown representation
  classes surface earlier (at `.representation_class()` instead of at
  the consumer site downstream) but carry identical content; existing
  tests that assert specific refusal messages continue to pass.

## flexyBayes 0.3.10

### Stage 5A blocks emit + low_rank refusal-stub upgrade (ADR 0025 Decisions 3 + 4)

Phase A closes two of the three v0.3.8-deferred items that v0.3.9 did
not absorb. The block-diagonal carrier `vm(group, blocks = ...)` ships
end-to-end on greta + INLA; the low-rank refusal upgrades to name the
v0.4.0
[`validate_approximation()`](https://aagi-aus.github.io/flexyBayes/reference/validate_approximation.md)
forward export by reference, and three new reason codes register into
the v0.3.8 C7 refusal-registry scaffold as the first migration
(forward-pattern demonstration for the v0.4.0 Wave 1 Phase 1C bulk
migration).

- `vm(group, blocks = my_blocks)` — where `my_blocks` resolves to
  `list(V_1, ..., V_K)` — is active on greta + INLA. The greta path
  emits via `t(chol(as.matrix(Matrix::bdiag(...))))` through
  `.vm_ped_sqrt_expr()` (fits the v0.3.7 sqrt-expr architecture
  unchanged; “exact and boring” per the 2026-05-28 planning correction).
  The INLA path emits K independent
  `f(<var>_id_block_<k>, model = "generic0", Cmatrix = solve(V_k))`
  calls; per-block integer index columns + per-block precision matrices
  are pre-computed in `data_inla`.
- `vm(group, low_rank_factor = U, low_rank_scheme = "pca")` refuses with
  the upgraded message naming **ADR 0027** +
  [`validate_approximation()`](https://aagi-aus.github.io/flexyBayes/reference/validate_approximation.md)
  (v0.4.0 Wave 1 Phase 1B) and the actionable workaround
  `vm(group, V = U %*% t(U))` for the dense materialisation path.
- Two new structured refusals: `block_partition_incomplete` (sum of
  block sizes does not match the grouping factor’s level count) and
  `block_not_positive_definite` (offending block index named in the
  message text).
- [`fb_plan()`](https://aagi-aus.github.io/flexyBayes/reference/fb_plan.md)
  reports `representation_plan` entries with class `block_diagonal` for
  blocks-format vm/ped terms; the print form renders `(K blocks)`
  annotations from `known_matrices` resolution. The fit-side
  [`print.flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/print.flexybayes.md)
  Representation line renders `exact (block-diagonal, K blocks)` when
  blocks-format terms are present.
- `lgm_gate()` check 8 (`random_term_type_inla`) accepts vm/ped with
  `cov_representation$format == "blocks"`; the refusal text for
  `format %in% c("dense", "chol")` extends to mention the blocks carrier
  as a third structurally-INLA-eligible representation.
- The refusal-registry scaffold (ADR 0030 C7, shipped at v0.3.8 with
  zero entries) gains its first three entries via
  `.populate_refusal_registry_v0310()` — registered at `.onLoad()`
  before the registry locks. The full ~28-site migration follows the
  same `.register_refusal()` shape at v0.4.0 Wave 1 Phase 1C.

### Per-term INLA memory estimator (ADR 0024 §Consequences amendments (a) + (c))

Phase B replaces the v0.3.6 single-multiplier INLA memory check with a
per-term decomposition keyed on representation class.

- `<fb_preflight>` gains a `memory_estimate` slot carrying an
  `<fb_memory_estimate>` carrier with `$total` (bytes after the INLA
  overhead constant; default 2x; configurable via
  `flexyBayes.preflight_inla_overhead_factor`), `$breakdown` (a
  stable-shape data.frame with rows `term_label`, `representation`,
  `bytes`, `share` — ADR 0030 §C4 closed-vocabulary discipline), and the
  pre-overhead `$raw_total`. `as.numeric(pf$memory_estimate)` returns
  the total, so existing scalar-numeric consumers keep working
  unchanged.
- `lgm_gate()` rule 11 (`memory_feasibility_inla`) decomposes per term
  when `memory_estimate` is present: dense `n^2`, sparse precision
  `nnz(Q) * 16` (per Lindgren et al. 2011), block-diagonal
  `sum_k n_k^2 * 8`, indexed random `8K + 4N`, fixed effects
  `N * p * 8`. Refuses with the new reason code
  `memory_feasibility_inla_per_term` and names the largest contributor +
  its representation on the diagnostic line.
- [`fb_plan()`](https://aagi-aus.github.io/flexyBayes/reference/fb_plan.md)
  print form renders the breakdown rows under the headline memory line:
  total + overhead factor followed by one indented row per term with
  representation class + bytes.
- New vignette `flexyBayes-13-lgm-feasibility-memory` walks through the
  per-term model, how to read `memory_estimate$breakdown`, four patterns
  to negotiate a refusal, and the SPDE-mesh / approximate- scheme
  surfaces explicitly out of scope at v0.3.10.

## flexyBayes 0.3.9

### Test-isolation pass – three v0.3.8-deferred stochastic flakes closed

Four themed Phase commits close the three v0.3.8-deferred stochastic
flakes (`test-smooth.R:88`, `test-validation-lmer.R:31`,
`test-emit-gaussian-aggregated.R:299`) and consolidate the test-
isolation contract under a single-call umbrella. The
`[flake-test-infrastructure]` and `[flake-stochastic-rng]` classes in
`inst/skip-ledger.md` drop to zero residual entries; the replacement
entries under the Stress-only class are opt-in via
`FLEXYBAYES_RUN_STRESS=true` by design.

**Phase A `fix:` (emit-state latch encapsulation + bare-options leak
repair).**

- The once-per-session message latches (default-prior note,
  uniform-on-INLA approx note) migrate from the
  [`options()`](https://rdrr.io/r/base/options.html) namespace into a
  package-private environment in `R/emit_state.R`. Accessors
  `.emit_state_get` / `.emit_state_set` / `.init_emit_state` keep the
  state invisible to user code; the public-API
  `options(flexyBayes.silence_*)` toggles are unchanged. Test isolation
  gets a withr-scoped helper at `tests/testthat/helper-emit-state.R`;
  the regression suite at `tests/testthat/test-emit-state-isolation.R`
  pins the contract in 15 expectations across 7 `test_that` blocks.
- Six bare `options(flexyBayes.silence_default_prior_note = TRUE)` calls
  (one in `test-inla-verification-simple-slope-uncor.R`, five in
  `test-random-slopes-uncor.R`) migrate to
  [`withr::local_options()`](https://withr.r-lib.org/reference/with_options.html)
  so the silence flag does not leak across files in `tools/tally.R`’s
  single-process loop. Bisection during Phase A traced the v0.3.8 flake
  at `test-smooth.R:88` through the env migration to this leak as the
  upstream cause; either fix alone is insufficient.

**Phase B `fix:` (TF-RNG containment + hybrid sleepstudy validation).**

- New test helper `tests/testthat/helper-rng.R` exposes
  `local_tf_seed(seed, .local_envir, deterministic_ops = FALSE)` which
  reseeds both R (`set.seed`) and TensorFlow (`tf$random$set_seed` via
  [`requireNamespace("tensorflow")`](https://github.com/rstudio/tensorflow));
  `deterministic_ops = TRUE` additionally enables
  `tf$config$experimental$enable_op_determinism()` (opt-in;
  process-global state + 5–15% throughput cost).
- The sleepstudy
  [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)-vs-`lme4`
  validation test (`test-validation-lmer.R:31`) splits into a hybrid:
  primary always-on path at 1000+1000 budget + 1.5 \* REML SE
  fixed-effect tolerance + 30% VC tolerance; secondary stress-gated path
  at 2000+2000 + 1.0 \* REML SE / 25% (the original strict assertion).
  Both paths call `local_tf_seed(20260427L)` at entry. The stress-gated
  companion joins the existing stress- only blocks under
  `tools/profiles/stress.R`.

**Phase B’ `fix:` (aggregated INLA bit-exact identity tolerance
amendment).**

- The `INLA per-row + aggregated agree on beta` assertion
  (`test-emit-gaussian-aggregated.R:284`) splits: always-on band at
  `5e-3` (10x the spike’s `1e-4` theoretical bit-exact claim, 1.5x the
  v0.3.8 Phase D worst-case observation of `3.4e-3`) with a stress-gated
  companion at the original `1e-3` floor. Same shape as the v0.3.5
  BLAS-non-associativity amendment on ADR 0023 and the v0.3.7
  subtest (d) loosening on ADR 0025; the algebraic-identity claim
  documented at `R/emit_gaussian_aggregated.R:30-41` is unchanged.

**Phase C `feat:` (single-call test-isolation umbrella).**

- New helper `tests/testthat/helper-isolation.R` exposes
  `local_flexybayes_clean_state(seed = NULL, .local_envir, deterministic_ops = FALSE)`
  that composes `local_clean_emit_state()` unconditionally and
  `local_tf_seed()` when a `seed` is provided. The umbrella file header
  consolidates the three cross-helper discipline rules learned during
  Phase A + B + B’: never bare `options(flexyBayes.*)` without
  [`withr::local_options()`](https://withr.r-lib.org/reference/with_options.html);
  greta-MCMC numerical- agreement tests must call `local_tf_seed()`;
  emit-state- dependent tests must call `local_clean_emit_state()`. Each
  underlying helper remains the right entry point for single- surface
  tests.

**User-facing impact: zero.** All changes are test-infrastructure or
test-tolerance only. Public-API `options(flexyBayes.silence_*)` toggles
unchanged.
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
/
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
/
[`fb_plan()`](https://aagi-aus.github.io/flexyBayes/reference/fb_plan.md)
signatures unchanged. The internal `flexyBayes._..._emitted` option
names (leading-underscore, never declared API) are no longer consulted
by package code.

**Cumulative tally on the v0.3.9 release tree: PASS 1894 / FAIL 0 / SKIP
8** (was 1871 / 0 / 8 at v0.3.8; +23 PASS, equal SKIP count). The
skip-count parity is intentional – each closed flake-class skip is
replaced by an opt-in stress-gated skip exercising the strict assertion
under the release-rehearsal probe.

**Cairns**:
`ledger/r-package/2026-05-27-emit-state-latch-env-migration.cairn.md`
(Phase A, T3, alternatives bracketed: status-quo / env-keyed-CHOSEN /
withr-only / rlang-typed-message-deferred-v0.4.0);
`ledger/r-package/2026-05-27-tf-rng-containment-hybrid-sleepstudy.cairn.md`
(Phase B, T3, alternatives bracketed: status-quo / greta-opt-MAP-bypass
/ hybrid-CHOSEN / hybrid-plus-deterministic-ops-deferred);
`ledger/r-package/2026-05-27-aggregated-inla-tolerance-amendment.cairn.md`
(Phase B’, T2, alternatives bracketed: status-quo / hybrid-CHOSEN /
INLA-session-state-investigation-deferred /
unconditional-1e-2-loosening);
`ledger/r-package/2026-05-27-isolation-helper-umbrella.cairn.md` (Phase
C, T2, alternatives bracketed: separate-helpers / umbrella-CHOSEN /
inlined-monolith).

## flexyBayes 0.3.8

### Audit-close hardening + planner + truth display

Four themed Phase commits close the 2026-05-25 audit
(`feedback_v0.3.7_to_v0.4.0_2026-05-25.md`, five Critical Fixes and
thirteen sub-recommendations) and ratify ADR 0030 contracts C1 (planner
verb) + C7 (refusal-registry scaffold) + Decision 4 (`Representation:` /
`Engine:` two-line truth display).

**Phase A `fix:` (shared prediction kernel + alignment validators +
sparse-precision policy).**

- File-backed prediction and the in-memory path now share a single
  per-draw kernel (`R/predict_kernel.R`); the smooth-bypass bug on
  `predict(..., output_file = ...)` that lost partial contributions of
  spline terms is closed. Audit Critical Fix
  [\#1](https://github.com/AAGI-AUS/flexyBayes/issues/1).
- Known-matrix carriers passed via `known_matrices = list(...)` validate
  against the IR at fit time on both backends: dimension mismatches,
  level mismatches between `dimnames(M)` and the factor’s
  [`levels()`](https://rdrr.io/r/base/levels.html), and dimname
  misalignments raise typed refusals (`known_matrix_dim_mismatch`,
  `known_matrix_dimnames_mismatch`, `known_matrix_level_mismatch`)
  instead of crashing inside the emit. Audit Critical Fix
  [\#2](https://github.com/AAGI-AUS/flexyBayes/issues/2).
- The PD probe on user-supplied sparse precision matrices Q is now
  sparse-native – `Matrix::chol(forceSymmetric(Q))` rather than coercing
  to dense and calling base
  [`chol()`](https://rdrr.io/r/base/chol.html). The
  `flexyBayes.trust_pd` option allows callers who have already verified
  PD externally to skip the probe. Audit Critical Fix
  [\#3](https://github.com/AAGI-AUS/flexyBayes/issues/3).

**Phase B `feat:` (planner + truth display + refusal registry
scaffold).**

- New exported verb
  `fb_plan(formula, data, backend, priors, known_matrices, family, link, weights, aggregate, memory_ceiling_gb, predict_plan, ...)`.
  Returns a `<fb_plan>` object showing the pre-fit dispatch decision,
  representation plan, rejected-route trace, predict-shape derivation,
  and known-matrix summary – without running the fit.
  [`print()`](https://rdrr.io/r/base/print.html) surfaces a
  flight-checklist form;
  [`summary()`](https://rdrr.io/r/base/summary.html) adds per-term
  preflight detail;
  [`as.data.frame()`](https://rdrr.io/r/base/as.data.frame.html) coerces
  to a wide single row for tabular aggregation across plans.
  [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
  and
  [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
  accept `plan = FALSE` (default) -\> `TRUE` to short-circuit to the
  plan. ADR 0030 contract C1.
- [`print.flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/print.flexybayes.md)
  /
  [`summary.flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/summary.flexybayes.md)
  /
  [`print.flexybayes_aggregated()`](https://aagi-aus.github.io/flexyBayes/reference/print.flexybayes_aggregated.md)
  replace the single `Exact.:` line with two adjacent lines
  `Representation:` (the IR’s exactness vocabulary – `exact_index`,
  `aggregated_exact`, `legacy_inla_simple_slope`, etc.) and `Engine:`
  (the live engine name – `greta_MCMC`, `INLA_Laplace`, `stan_brms_HMC`
  – distinct from `Representation:` because several representations can
  run on the same engine). Closes audit Critical Fix
  [\#4](https://github.com/AAGI-AUS/flexyBayes/issues/4). ADR 0030
  Decision 4.
- New `.refusal_registry` environment + `.register_refusal()` /
  `.lookup_refusal()` helpers, empty + locked at end of `.onLoad()`.
  Per-site migration of the ~30 existing
  [`stop()`](https://rdrr.io/r/base/stop.html) refusals to
  registry-backed messages is deferred to v0.4.0 per
  `feedback_staged_release_pattern`; the v0.3.8 scaffold is
  forward-architecture for the v0.4.0 export of
  [`fb_refusals()`](https://aagi-aus.github.io/flexyBayes/reference/fb_refusals.md).
  ADR 0030 contract C7.

**Phase C `docs:` (audit-drift close + selective vignette refresh).**

- Workspace `AGENTS.md` rewritten as a thin pointer to `CLAUDE.md`
  (eliminates the stale `bayesreml` / `Codex (ctb)` references the audit
  flagged).
- Workspace `README.md` replaced (the 2026-04-26 pre-implementation
  review guide is now historical; current-state README documents v0.2.5
  -\> v0.3.7 release history + the local-tarball install path pending
  D8).
- Package `README.md`: install line replaces the 404-ing
  `remotes::install_github("AAGI-AUS/flexyBayes")` with
  `R CMD INSTALL release_tarballs/flexyBayes_0.3.8.tar.gz` plus a “will
  resume after D8” forward-pointer.
- `AMBITION_STAGE.md` §8.6: `v0.3.6` mis-label corrected (Stage 4 ADR
  0024, not Stage 5B ADR 0026); `v0.3.7` + `v0.3.8` rows added.
- ADR 0024 §Consequences amendments (a) per-term INLA estimator
  - 3.  vignette companion both updated to reflect the v0.3.7 -\> v0.3.8
        -\> follow-on deferral chain.
- Selective vignette re-precompile – only vignettes whose printed code
  chunks render `print(fit)` / `summary(fit)` and therefore show the new
  `Representation:` / `Engine:` lines. Full sweep deferred to v0.4.0
  alongside the vignette deck restructure (per the v0.3.8 plan §12.3
  ratification).
- `cran-comments.md`: v0.3.8 bump + 3-NOTE-sub-item reframing.

**Phase D `test:` (skip ledger + benchmark profiles).**

- New `tools/skip_ledger.R` parses every `tests/testthat/test-*.R` for
  `skip()` / `skip_if_not()` / `skip_on_cran()` /
  `skip_if_not_installed()` calls and classifies them against five
  reason classes (unavailable optional backend; CRAN/CI time budget;
  stress-only; external toolchain unavailable; deliberately deferred
  feature); writes `inst/skip-ledger.md` for users and reviewers.
- Four named benchmark profiles under `tools/profiles/`: `smoke.R` (~30
  s pure-R subset), `release.R` (5–10 min canonical release-ceremony
  gate), `stress.R` (sets `FLEXYBAYES_RUN_STRESS=true`; unblocks the
  greta MCMC posterior-equivalence tests), `huge_n_probe.R` (skeleton at
  v0.3.8; the actual `N = 5e6` runs land at v0.4.0 per the trust-release
  gate).
- `tools/tally.R` now refreshes `inst/skip-ledger.md` as its closing
  step.

### Corrections

- `emit_gaussian_aggregated()`: the aggregated INLA path now preserves
  the `flexybayes_inla` class label on the returned fit
  (`c("flexybayes_aggregated", "flexybayes_inla", "flexybayes")`). The
  previous shape dropped `flexybayes_inla`, so
  [`fb_as_draws_simple()`](https://aagi-aus.github.io/flexyBayes/reference/fb_as_draws_simple.md)
  dispatched to the greta extractor and crashed with “fit$`greta`$draws
  is missing” – silently breaking `triangulate(fit_g, fit_i)` on the
  aggregated path. Class-invariant test_that() blocks in
  `tests/testthat/test-emit-gaussian-aggregated.R` cover both backend
  shapes. The greta path stays at the two-element
  `c("flexybayes_aggregated", "flexybayes")` (no `flexybayes_greta`
  class is introduced; `fb_as_draws_simple.flexybayes` is the greta
  extractor). Decision recorded at
  `ledger/r-package/2026-05-26-aggregated-inla-dispatch-fix-class-vector.cairn.md`.
- `tests/testthat/test-fb-brms.R:284`
  [`backend_decision()`](https://aagi-aus.github.io/flexyBayes/reference/backend_decision.md)
  shape expectation updated from the 4-field ADR-0006 baseline to the
  8-field ADR-0024 shape (`backend` / `path` / `gate_checks` / `reason`
  / `preflight_summary` / `representation_plan` / `rejected_routes` /
  `routing_policy_version`). The test silently failed under
  `NOT_CRAN=true` since the v0.3.6 close.

## flexyBayes 0.3.7

### Stage 5A – known-covariance input formats

`vm()` and `ped()` now accept user-supplied covariance carriers beyond
the dense $`V`$ matrix. Three new formats activate in v0.3.7; two more
reserve their input slots for v0.3.8 / v0.4.0:

- **Cholesky factor** (greta backend):

  ``` r

  L <- t(chol(G))   # user pre-computes the lower-triangular factor
  flexybayes(
    yield ~ env, random = ~ vm(geno, chol = L),
    data = dat, known_matrices = list(L = L),
    backend = "greta"
  )
  ```

  Skips the `t(chol(V))` step at fit time. Useful when $`L`$ is already
  available (e.g., from a prior pre-processing step that factorised a
  kinship matrix once and serialised the factor).

- **Sparse precision** (greta + INLA backends):

  ``` r

  Q <- solve(G)     # or build sparse Q directly via ICAR / BYM2
  flexybayes(
    y ~ 1, random = ~ vm(cell, precision = Q),
    data = dat, known_matrices = list(Q = Q),
    backend = "inla"
  )
  ```

  Routes through INLA’s `f(<var>_id, model = "generic0", Cmatrix = Q)`
  interface (Rue & Held 2005, *Gaussian Markov Random Fields*; Lindgren
  et al. 2011) when `backend = "inla"`. Order-of-magnitude memory win on
  large sparse problems (BYM2 spatial models, sparse-inverse pedigree
  relationship matrices). On greta the precision matrix densifies at fit
  time (`as.matrix(solve(chol(Q)))`); use INLA for the sparse-efficiency
  win.

- **Pedigree sparse-precision** opt-in for `ped()`:

  ``` r

  ped(animal, A_inv, use_sparse_precision = TRUE)
  ```

  When the user has already inverted the pedigree to `A_inv = solve(A)`
  (or pulled the sparse $`A^{-1}`$ directly from `pedigreemm`), this
  flag routes through the precision codepath without a redundant
  inversion. The user is responsible for the inversion at construction
  time; flexyBayes does not depend on `pedigreemm` or any other
  pedigree-graph library.

The dense $`V`$ path (`vm(group, V = G)`) is **unchanged** –
byte-identical to v0.3.6. Existing fits saved as `.rds` reload without
IR migration: the new `cov_representation` IR slot is additive, and
legacy IRs default to `format = "dense"`.

Two more formats reserve their input slots in v0.3.7 but refuse cleanly
with forward-pointer messages: `blocks = list(V1, V2, ...)` defers to
v0.3.8 with `route_not_yet_emitted`; `low_rank_factor =` +
`low_rank_scheme = "pca"` defers to v0.4.0 (ADR 0027 approximation
registry) with `approximate_route_not_yet_registered`. Reserving the
input vocabulary now lets future releases ship without changing the
`vm()` / `ped()` call shape.

**Backend dispatch.** With `backend = "auto"`, INLA accepts vm/ped only
when the precision representation is supplied; dense or chol inputs
route to greta. With explicit `backend = "inla"`, dense or chol inputs
raise a structured `lgm_gate` refusal naming the actionable workaround
(re-express as `vm(group, precision = solve(V))`, or route via
`backend = "greta"`). The refusal text branches on the format to point
the user at the right remedy.

**Validation.** Each format passes through a typed structural validator
on the user-supplied matrix before the emit path runs:

- `chol` must be square and lower-triangular (refusals
  `chol_not_square`, `chol_not_triangular`).
- `precision` must be symmetric and positive-definite (refusals
  `precision_not_symmetric`, `precision_not_positive_definite`). The PD
  check uses base R [`chol()`](https://rdrr.io/r/base/chol.html) on the
  dense coercion; performance-grade sparse-PD probes land in v0.3.8.

Mutual exclusion across `V` / `chol` / `precision` / `blocks` /
`low_rank_factor` is enforced at parse time with the
`vm_redundant_specification` refusal.

**Routing audit anchor.** `backend_decision(fit)$routing_policy_version`
bumps from `"stage4_v1"` to `"stage5a_v1"` (per ADR 0024) to record that
INLA’s allowlist behaviour materially changed at v0.3.7.

## flexyBayes 0.3.6

### Stage 4 – backend routing trace + preflight metadata consumption

Two architectural additions complete the v0.2.6 -\> v0.3.x dispatch
story. The existing four-backend surface (`greta` / `inla` /
`brms`-passthrough / `gretaR`-scaffold) now routes deliberately and
reports its decisions reproducibly.

**`backend_decision(fit)` gains four new fields.** Every fit produced
under v0.3.6 carries the existing four fields (`backend` / `path` /
`gate_checks` / `reason`, per ADR 0006) plus:

- `preflight_summary` – the `.fb_preflight()` return value when
  preflight ran (\>1e5-row path); NULL on the small-data fast path by
  design.
- `representation_plan` – a slim list of one entry per IR term:
  `(term_id, representation_class, justification)`. Derived from
  `preflight_summary`; NULL when no preflight ran.
- `rejected_routes` – a list of `(backend, reason)` pairs for the
  backends considered but not chosen. Empty for explicit user requests
  (policy bypassed). For `backend = "auto"`, the list enumerates the
  non-chosen candidates from `{greta, inla, gretaR}` with per-backend
  reason codes.
- `routing_policy_version` – the policy version that decided this fit’s
  dispatch (e.g., `"stage4_v1"`). Bumping this string is the
  audit-anchor for reproducibility – a fit produced under an older
  policy carries the older string.

Legacy fits (those that recorded the v0.2 / v0.3.5 four-field trace
before v0.3.6 landed) read out via the accessor with NULL defaults on
the four new fields; downstream code reading
`backend_decision(fit)$chosen_backend` is unaffected.

**`lgm_gate(fb, preflight = NULL)`.** The gate signature gains an
optional second argument. When `preflight` is NULL (the v0.3.5 calling
convention), the gate behaves exactly as today – 10 structural rules.
When `preflight` is supplied, the gate runs an 11th rule,
`.lgm_check_memory_feasibility_inla(fb, preflight)`, that refuses when
the INLA path’s projected memory exceeds the active ceiling. The Stage 4
ship is a single-multiplier approximation: INLA memory ~= 3x the indexed
preflight total (the INLA dense intermediate inflation rule of thumb).
Per-term estimators are queued for a follow-on release alongside the
LGM-feasibility vignette; deferred at v0.3.6 close, deferred again at
v0.3.7 close to keep the Stage 5A known-covariance work the focus, and
deferred again at v0.3.8 close (audit hardening was prioritised). The
multiplier is configurable via
`options(flexyBayes.inla_memory_multiplier = <value>)`. **The new
refusal reason code is `memory_infeasibility_inla`** – distinct from the
existing structural reason codes (`fixed_term_type_inla` /
`random_term_type_inla` / `rcov_term_type_inla` from ADR 0017, the six
original family / predictor / distributional / re_prior / latent_class /
hyperparam_budget). The structural-vs-memory distinction is the central
new piece of dispatch information – distinguishable from
`rejected_routes` alone, without re-running the gate.

**Routing-policy registry.** The policy lives in
`.routing_policy_table()`, a small data.frame in `R/dispatch.R` that
encodes the (`user_request`, `gate_outcome`, `preflight_outcome`,
`inla_installed`) tuple -\> `(chosen_backend, reason_code)` mapping.
This is the single source of truth: the dispatch logic queries the table
via `.resolve_routing()` rather than re-deriving the decision from
nested ifs. Changing the policy is a table-edit, not a control-flow
surgery.

**Approximate-scheme guard.** Backend names carrying an
approximate-scheme exactness label (e.g., `"inla_pardiso_approximate"`,
`"variational_advi"`) now refuse at the entry function with
`approximate_route_not_yet_registered`, pointing to ADR 0027 (the future
approximation registry). The package’s identity rests on exactness
labelling (per Stage 3A / ADR 0022); silently routing an approximate
request would violate that contract.

Worked example – a memory-infeasible model on `backend = "auto"` now
produces a trace like:

``` r

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

The decision is now reproducible from `backend_decision(fit)` alone,
plus the policy version string. The reproducibility posture mirrors
`targets::tar_metadata()` (Landau 2021), which captures the chosen
execution plan plus the rejected alternatives + reasons on every
pipeline run.

The vignette companion (`flexyBayes-11-lgm-feasibility.Rmd.orig`
extension for the structural-vs-memory refusal distinction) is staged
for v0.3.7 alongside the per-term INLA memory estimator.

## flexyBayes 0.3.5

### Stage 3B (file-output) – file-backed prediction + sample activation

Two additions to `predict.flexybayes(newdata, ...)` complete the Stage
3B scope opened at 0.3.4.

**File-backed prediction output.** Three new arguments – `output_file`,
`format`, `interop` – route
[`predict()`](https://rdrr.io/r/stats/predict.html) to a disk-backed
tabular output when `output_file` is supplied. The file carries `point`,
`lower`, `upper` (95% posterior credible bounds) plus optional `se.fit`,
plus the columns of `newdata`, under the format resolved by:

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

The fst path is 30-40x faster than rds at N \>= 1e6 for essentially the
same on-disk size (single-platform benchmark under
`benchmark_results/fst_stage3b_2026-05-23`). `fst` is declared in
`Suggests` with a `>= 0.9.0` floor; `predict(..., format = "fst")` with
`fst` not installed raises a structured refusal naming the install
command and the `format = "rds"` override line. Refusing rather than
silently falling back is consistent with the package’s broader
no-silent-refusal posture. Pre-existing prediction grids are not
overwritten: if `output_file` already exists,
[`predict()`](https://rdrr.io/r/stats/predict.html) raises a structured
stop suggesting [`unlink()`](https://rdrr.io/r/base/unlink.html) rather
than overwriting silently.

The posterior intervals follow posterior expected-response quantile
semantics (mirrors `brms::posterior_epred()`; Gelman et al. 2013,
*Bayesian Data Analysis*, section 15.4 on linear-predictor posteriors):
the linear predictor is evaluated under each retained posterior draw,
the link inverse is applied per draw, and `point` / `lower` / `upper`
are read off the rowwise mean and 2.5% / 97.5% quantiles. **These are
intervals on the expected response, not posterior-predictive intervals**
— they do not include residual observation noise. For full
posterior-predictive intervals (observation noise included), route the
in-memory draws through external tooling such as
`brms::posterior_predict()` on a refit, or add a residual-noise draw per
row using `fit$sigma`. Chunked vs unchunked file output is equivalent at
floating-point precision; BLAS non-associativity at the matrix-size
boundary introduces ULP-level differences (~2e-16) but no numerically
meaningful drift.

**`allow_new_levels = "sample"` is now active.** The label was stable at
0.3.4; the implementation ships here. Unknown factor levels in `newdata`
get a fresh `Normal(0, tau_group)` random-effect realisation layered
onto the linear predictor per posterior draw (mirrors
`brms::posterior_epred(..., sample_new_levels = "gaussian")`). Caller’s
[`set.seed()`](https://rdrr.io/r/base/Random.html) controls
reproducibility. The in-memory return reports the posterior-mean point
estimate; the sampled-RE contribution averages toward zero across draws
so the in-memory point estimate sits close to the population baseline –
the file-backed return captures the proper per-row posterior interval
reflecting sampled-RE uncertainty. INLA fits do not currently expose
per-draw access and route to a structured refusal; an INLA draws adapter
is queued for a future release.

### Internals

- New `R/predict_file_output.R` (`.fst_available`, `.resolve_format`,
  `.predict_write_file`, `.predict_to_file`).
- New `R/predict_posterior.R` (`.predict_per_draw`,
  `.predict_intervals`, `.predict_sample_re_for_unknowns`,
  `.predict_in_memory_sample`).
- `R/predict_chunked.R` – `.predict_resolve_factors()` drops the 0.3.4
  deferred-stop on `"sample"`; the new branch tags unknown rows via
  `attr(newdata, "sample_re_summary")` for downstream per-draw
  consumption.
- `R/methods.R` –
  [`predict.flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/predict.flexybayes.md)
  gains `output_file`, `format`, `interop` arguments and two new
  dispatch branches.

### Test coverage

- New `tests/testthat/test-predict-file-output.R` (16 blocks) covering
  the pure-path resolution table, the structured fst refusal,
  csv/rds/fst round-trip with factor preservation, chunked invariance,
  format = “auto” end-to-end with mocked fst availability, the interop
  branch, and overwrite refusal.
- New `tests/testthat/test-predict-sample-new-levels.R` (7 blocks)
  covering active success on mixed known+unknown rows,
  caller-seed-driven non-determinism, posterior-interval variance
  scaling, backward-compat with legacy fits, deferred-stop removal
  confirmation, and the no-draws fit refusal.

Total test counts: PASS 1317 / FAIL 0 / SKIP 73 (0.3.4 baseline was
1262/0/73; +55 expectations across 22 new blocks).

## flexyBayes 0.3.4

### Stage 3B (core) – chunked indexed prediction + factor-dictionary handling

Three new pieces on the `predict.flexybayes(newdata, ...)` surface for
prediction grids large enough to warrant chunked iteration and for cases
where `newdata` carries factor levels not seen at fit time.

**Dictionary-backed factor handling.** Fits now carry a metadata- only
`<fb_dataset>` descriptor (frozen factor-level dictionaries plus
column-type cache) on `fit$extras$fb_dataset`. At `predict(newdata)`
time, factor columns in `newdata` resolve against this dictionary
instead of being re-derived from `newdata`. The change closes a latent
silent-re-levelling bug where the v0.3.3 prediction path could permute a
random-effect contribution under specific `newdata` orderings.

**`allow_new_levels = c("population", "sample", "refuse")`.** Policy for
factor values in `newdata` that are not in the fit- time dictionary.
`"population"` (default) coerces unknown-level rows to NA on the
affected column and emits a warning naming the count; downstream
prediction returns the population-level prediction for those rows.
`"refuse"` raises a structured stop on the first unknown level, naming
the column and (up to five) unknown values. `"sample"` (fresh
random-effect draw per unknown level) is reserved at 0.3.4 – the label
is stable but the implementation ships at 0.3.5 alongside the
file-backed prediction output.

**`chunk_size` argument.** When supplied and
`nrow(newdata) > chunk_size`, prediction iterates over chunks of the
requested size and concatenates the per-chunk results. Default `NULL`
preserves the single-pass behaviour. `chunk_size` is a wall-time / peak-
memory knob – the numerical output is identical to the single- pass
call. A typical setting at large `newdata` is `chunk_size = 10000L`.

The file-backed prediction output formats
(`format = c("auto", "csv", "rds", "fst")` + `output_file` argument)
ship together at 0.3.5; this release covers the in-memory prediction
surface only.

------------------------------------------------------------------------

## flexyBayes 0.3.3

### Stage 3A – Gaussian aggregated emit (greta path)

Completes the aggregated-gaussian path by activating the greta backend
alongside INLA. `fb_brms(..., backend = "greta", aggregate = TRUE)` and
`flexybayes(..., backend = "greta", aggregate = TRUE)` now route through
the same sufficient-statistics emit as the INLA path. The greta
implementation factorises the cell-mean weighted gaussian observation
against a gamma observation on the within-cell sum of squares; together
these recover the per-row gaussian log- likelihood exactly (the
algebraic identity proof is in Searle, Casella & McCulloch (1992)
*Variance Components* §3). On a fixed- seed synthetic dataset with N =
800, J = 20, the aggregated greta posterior recovers a known (beta,
sigma, tau) triple within MC tolerance; the backend-fidelity check is
shipped as a stress-gated test (`FLEXYBAYES_RUN_STRESS=true`).

**Known caveat.** The aggregated INLA path still uses an explicit
`loggamma(1, 5e-5)` precision prior on random-intercept terms when the
user has not supplied a prior via `prior = fb_prior(...)`, for the
data-scale-stability reason in the 0.3.2 caveat. Unifying the
default-prior behaviour across per-row and aggregated paths remains
queued. The greta aggregated path follows the same default prior shape
(sd-scale) as the per-row greta path; matched-prior comparisons within
greta are therefore consistent without extra configuration.

**Heterogeneous residual.** `at(f):units` on greta now flows through the
aggregated path end-to-end (when `f` is in the cell key). The
multi-likelihood INLA stack required for the same on the INLA aggregated
path remains queued.

------------------------------------------------------------------------

## flexyBayes 0.3.2

### Stage 3A – Gaussian aggregated emit (INLA path)

Wires the sufficient-statistics aggregation foundation (introduced in
0.3.0 as `<fb_aggregated>` + `<fb_aggregation_plan>`) into the live
dispatch path. Gaussian-identity LMMs whose linear predictor is
cell-constant – fixed numeric / factor effects plus random intercepts on
factor groupings – now have an aggregated emit path that fits the same
posterior on per-cell sufficient statistics rather than per-observation
likelihood contributions. The aggregated log-likelihood is the algebraic
identity of the per-row form (no approximation; see Searle, Casella &
McCulloch (1992) *Variance Components* §3 and Bates et al. (2015) §3 on
the profiled-deviance shortcut); the bit-exact equivalence is gated by a
property-based test in `tests/testthat/test-aggregate-gaussian.R`.

**API.** A new `aggregate = c("auto", TRUE, FALSE)` argument joins
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
and
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md).
The default `"auto"` consults the plan and silently routes through the
aggregated emit when the IR is in scope and compression is productive
(`K/N <= 0.5`); falls through to the per-row path when out of scope.
`TRUE` forces aggregation – raises a structured refusal naming the
plan’s reason code when ineligible. `FALSE` skips the gate entirely.

**Exactness field.** Every flexybayes fit now carries an `$exactness`
slot. Per-row paths populate it as `"exact"`; aggregated paths populate
it as `"aggregated_exact"`. The dispatch trace’s `path` slot reads
`"aggregated_gaussian"` on aggregated fits.
[`summary()`](https://rdrr.io/r/base/summary.html) and a new
[`print.flexybayes_aggregated()`](https://aagi-aus.github.io/flexyBayes/reference/print.flexybayes_aggregated.md)
/
[`summary.flexybayes_aggregated()`](https://aagi-aus.github.io/flexyBayes/reference/summary.flexybayes_aggregated.md)
surface the field plus a compression-ratio line when N/K \>= 2
(suppressed on smaller datasets to avoid misleading claims).

**Backend coverage at 0.3.2.** INLA-backed aggregation is shipped
end-to-end (cell-mean weighted gaussian + a custom precision-prior
expression that absorbs the within-cell sum-of-squares correction; the
algebra is documented in the file header). Greta-backed aggregation is
deferred to a follow-on – the algebraic pattern (cell-mean weighted
gaussian plus a gamma observation on the within-cell SS) is viable, but
the package wiring needs a codegen-without-runtime-parse workaround for
an R S3 dispatch context-sensitivity that surfaces only inside the
package namespace. `aggregate = TRUE` on `backend = "greta"` refuses
cleanly with a deferred-feature message; `aggregate = "auto"` on greta
silently falls through to the per-row path.

**Heterogeneous residual.** `at(f):units` is supported on the aggregated
path when `f` is a cell-key term (so each cell has a single residual
variance). When the residual factor is not a cell key the per-row /
per-cell algebraic identity breaks and the emit refuses with a
structured `heterogeneous_residual_factor_not_in_- cell_key` reason
code.

**Known caveat.** The aggregated INLA path uses an explicit
`loggamma(1, 5e-5)` precision prior on random-intercept terms when the
user has not supplied a prior via `prior = fb_prior(...)`, because
INLA’s data-scale-dependent default would otherwise produce different
effective priors on the per-row and aggregated data scales.
Matched-prior comparisons between per-row and aggregated paths therefore
require either passing an explicit
[`fb_prior()`](https://aagi-aus.github.io/flexyBayes/reference/fb_prior.md)
or accepting that the residual / random-intercept posteriors will differ
on tail behaviour. The fixed-effect posteriors remain bit-exactly
equivalent under the algebraic identity. Unifying the per-row
default-prior behaviour with the aggregated path is queued for a
follow-on.

------------------------------------------------------------------------

## flexyBayes 0.3.1

### Trust Pass – preflight + aggregation honesty hardening

A focused three-phase pass on the public API’s honesty contract,
spanning the preflight layer, the aggregation taxonomy, and the
public-facing metadata. Closes a deep review of the v0.3.0.9000
development tip end-to-end. No user-facing API signature changes; every
revision tightens behaviour the package already promised.

**Trust bugs.** A session-level
`options(flexyBayes.review_code_default = TRUE)` no longer slips past
the unsupported-backend refusal on `backend = "inla"` / `"auto"` for
either
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
or
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
– option resolution now runs before the backend guard. The preflight
refusal headline no longer claims “the design exceeds the active memory
ceiling” when the refusal is actually
`representation_unknown_for_preflight`; the headline now branches on the
reason code so an unknown-representation refusal does not falsely send
the user down the ceiling-override path.

**Preflight taxonomy.** Structured-covariance random terms are split
into known-indexed forms (`vm`, `ped`, `ar1`, `ar1_spatial`) that keep
the tested heuristic estimator, and everything else (`at`, `us`, `fa`,
`at_simple`, `us_gxe`, `fa_gxe`, `vm_gxe`, …) that now routes to
`representation_unknown_for_preflight` rather than silently
under-estimating the design memory at large N. The previous “single
level” fallback in `.preflight_term_level_count()` was replaced with
`NA_integer_`; every consumer branch (structured-cov, random intercept,
uncorrelated random slope, fixed factor, factor :numeric interaction)
now treats an unresolvable level count as the signal to escalate to an
unknown-representation refusal.

**Aggregation refusal codes.** The Stage 3A out-of-scope taxonomy was
renamed and aligned across the two emitters that report it:
`.assert_aggregate_in_scope()` (the runtime gate) and
`.fb_aggregation_plan()` (the model-level planner) now produce the same
reason code for the same model. The previous catch-all
`random_slope_in_scope` is replaced by three positively-named codes
(`random_slope_not_aggregatable`, `structured_random_not_aggregatable`,
`smooth_term_not_aggregatable`); the planner’s
`compression_data_dependent` is renamed
`continuous_cell_key_data_dependent` for clarity.

**Public-facing metadata.** The `codemeta.json` version field, the
`cran-comments.md` build description, `SECURITY.md`, `SUPPORT.md`, and
the README’s `review_code` support row are all refreshed for the 0.3.x
line. `API_STABILITY.md` splits the structured-covariance default-priors
row by actual implemented behaviour (`vm`/`ped` on the uniform-on-SD
default; `at`/`us`/`fa`/`ar1`/`spl` on the legacy lognormal).
`CONTRIBUTING.md` documents the source-directory `R CMD check` footgun
and recommends the build-then-check workflow.

The AAGI-AUS GitHub URL declared in `DESCRIPTION` is the agreed forward
destination; until the upstream repository rename ships, the
CRAN-incoming feasibility check raises a sub-NOTE for the URL.
`cran-comments.md` itemises this and the other structural NOTE sub-items
in full.

### Test coverage

`PASS 1187 / FAIL 0 / SKIP 72` on `tools/tally.R` (was 1151/0/72 at the
deep-review baseline; +36 expectations across the Trust Pass). 9 new
`test_that` blocks pin the structured-covariance preflight split and the
renamed aggregation taxonomy; 8 ordered cases pin the `review_code`
option-default ordering across both formula verbs.

## flexyBayes 0.3.0.9000

### Stage 3A foundation – exact Gaussian aggregation via sufficient statistics

Internal `.fb_aggregate_gaussian()` collapses a per-row
Gaussian-identity mixed model into one row per cell, where a cell is the
maximal subset of observations sharing the same linear-predictor value.
Three sufficient statistics per cell (`n_k`, `S1_k = sum(y)`,
`S2_k = sum(y^2)`) carry all the information the Gaussian-identity
log-likelihood needs.

The implementation is foundation-only at this release: the algebraic
correctness gate landed, the backend emit path is not yet wired. A
property-based test draws twenty random in-scope intermediate
representations across three N scales (100, 500, 2000) with random
coefficients and confirms that the aggregated log-likelihood matches the
raw per-row form to relative error below `1e-12` in every case. The
biased cell-mean shortcut is exposed only so the same test can confirm a
regression would be caught.

The scope envelope refuses (typed condition
`flexybayes_aggregate_out_of_scope`) on: non-Gaussian family,
non-identity link, smooth fixed-effect term, or any random slope – all
of which break the cell-constant linear predictor.

Internal-only at v0.3.0.9000; surfaces user-facing in v0.3.2 alongside
the greta / INLA aggregated emit path and the `$exactness` slot.

### Stage 3A foundation – memory shape correction + model-level plan

Two follow-up changes to the Stage 3A foundation surfaced by the
2026-05-23 audit:

- `<fb_aggregated>$design_matrix` (the full `N x p` per-row design
  matrix) is replaced by `$cell_design` (the `K x p` per-cell form). The
  aggregated emit path only needs the per-cell linear predictor;
  carrying the per-row matrix defeated the compression contract at large
  `N` and was not an implementation shape compatible with the
  10M-100M-row roadmap. Per-row equivalence verification (the bit-exact
  log-likelihood gate) now rebuilds the per-row design locally via
  [`stats::model.matrix()`](https://rdrr.io/r/stats/model.matrix.html).

- New internal `.fb_aggregation_plan()` returning a model-level
  `<fb_aggregation_plan>` with seven slots: `eligible`, `reason_codes`,
  `cell_key_terms`, `requires_materialisation`, `K_est`, `N`,
  `compression_est`. The plan reads only IR + dataset metadata; no
  design materialised. `.fb_preflight()` attaches the plan to its result
  for diagnostic visibility. The plan is informational at v0.3.0.9000:
  the per-term `aggregated_likelihood_candidate` flag remains the
  dispatcher contract through v0.3.1. In v0.3.2 the plan supersedes
  per-term flags as the dispatch input when the aggregated emit path
  lands.

  Productivity threshold: `K_est / N <= 0.5` (at least 2:1 compression
  expected from metadata). Below the threshold the plan reports
  `eligible = TRUE`; above it reports
  `reason_codes = "compression_unproductive"`. Continuous fixed terms
  make the cell count data-dependent (cannot estimate from metadata) and
  the plan reports `reason_codes = "compression_data_dependent"`.

### Preflight hardening – smooth/spline estimators + unknown-term refusal

The Stage 2 preflight layer now characterises every term class the
asreml and brms parsers can emit. Five new branches:

- Mgcv smooth terms (`s(x)`, `smooth_mgcv` in the IR) on either side of
  the formula: dense `N x k` basis estimate using the resolved `term$k`
  from
  [`mgcv::smoothCon()`](https://rdrr.io/pkg/mgcv/man/smoothCon.html).
  Previously parser-emitted smooths fell through to a single-column
  estimate – a factor-of-`k` under-estimate that could let a large
  smooth model pass preflight when the actual basis exceeded the
  ceiling.
- P-spline terms (`spl(x)`): dense `N x df` basis with `df = 8` matching
  the codegen default.
- Factor:factor interactions: dense treatment-coded `N x (prod(L) - 1)`
  estimate; the audit-named high-cardinality scary case.
- Factor:continuous interactions (ADR 0019 indexed slope): integer index
  column + continuous column + `(L - 1)` per-level slope coefficients.
- Polynomial terms (`pol(x, d)`): dense `N x d` basis.

The fixed and random fallthrough branches no longer record a
single-dense-column estimate framed as “conservative lower bound” – a
lower bound is the opposite of conservative for a refusal gate.
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

### Behaviour change – default RAM fraction lowered from 80% to 60%

The default design-memory ceiling is now `60%` of system RAM (was
`80%`). This is conservative for shared workstations, CI runners, and
interactive laptops where the user expects the rest of the machine to
remain responsive under load. A new global option
`flexyBayes.preflight_ram_fraction` exposes the fraction for per-host
tuning:

``` r

options(flexyBayes.preflight_ram_fraction = 0.5)   # tighter
options(flexyBayes.preflight_ram_fraction = 0.9)   # looser, single-user host
```

The fraction is validated as `(0, 1]`. The 8 GiB fallback (used when
neither the `benchmarkme` nor the `memuse` RAM probe is installed) is
unaffected – the fallback is already a conservative absolute floor.

## flexyBayes 0.3.0

### Stage 2 design-memory preflight

flexyBayes now estimates the design-representation memory of a model
upstream of the backend dispatch and refuses with a structured
diagnostic when the estimate exceeds an active ceiling. The aim is to
replace the v0.2 silent-allocation antipattern
(`Error: cannot allocate vector of size 3.2 Gb` from
[`model.matrix()`](https://rdrr.io/r/stats/model.matrix.html) mid-fit)
with an explicit, per-term refusal that names the binding term and a
numeric override.

The default ceiling is 80% of system RAM, probed via `benchmarkme` or
`memuse` when either is installed; otherwise an 8 GiB fallback applies.
Users can set a stricter cap via the global option
`flexyBayes.preflight_ceiling_gb` (e.g. on shared hosts where the full
RAM should not be claimed for a single fit).

The check runs only on fits with `n_rows >= 1e5` so the v0.2 user
surface is unchanged at small scales. On larger fits the check reads
only `n_rows`, factor-level counts, and column types – no row-wise data
scan – so the runtime is `O(terms)` regardless of `n_rows`. A 1e8-row
metadata-only check completes in milliseconds on the development laptop.

The refusal is a typed condition `flexybayes_preflight_refusal` carrying
the binding term name, its byte estimate, the active ceiling, and a
suggested override. On `flexybayes(..., review_code = TRUE)` and
`fb_brms(..., review_code = TRUE)` the resulting `<flexybayes_review>`
token now carries a `$preflight` slot; the preflight summary appears in
`print(rev)` above the
[`cat_code()`](https://aagi-aus.github.io/flexyBayes/reference/cat_code.md)
prompt.

The `aggregated_likelihood_candidate` flag on each per-term entry is a
forward-looking promise to the gaussian-identity aggregated backend
path; the flag has no runtime effect at v0.3.0 (no aggregation runs yet)
but is consumed by later stages.

## flexyBayes 0.2.6

### Correctness fix – factor:continuous interaction (ADR 0019)

`flexybayes(y ~ x * f, data = ...)` where `f` is a factor and `x` is
numeric previously emitted the interaction term using a coefficient
broadcast that did not match base R’s treatment-coded model matrix –
producing posterior estimates that disagreed with `lme4::lmer` by more
than three standard deviations on simulated data. The fix emits the
interaction as a treatment-coded indexed slope: the reference level’s
slope is fixed to zero; the L-1 non- reference levels carry their own
slope deviations sampled from the prior, indexed back to the observation
vector via the factor’s level codes. Posterior estimates now match
`lme4::lmer` within MCMC tolerance and the linear-predictor equality
`eta_flexybayes == model.matrix(~ f * x) %*% beta` holds at tolerance
`1e-10` for any compatible coefficient vector.

The new term class `factor_numeric_interaction` registers the
canonical-name family `slope_<f>_<x>[<level>]` per non-reference level
for both the greta and brms backends. The dispatch trace records which
emit branch fired via `fit$extras$parse_info$factor_continuous_emit`
(`"option_c"` for the greta-native concatenation idiom; `"option_d"` for
the per- observation lookup-vector fallback gated on
`options(flexyBayes.force_option_d = TRUE)`).

Unsupported contrast types (`contr.helmert`, `contr.sdif`, `contr.sum`,
ordered factors, user-supplied custom contrast matrices) refuse at
ingest with a structured `flexybayes_contrast_unsupported` condition
carrying `contrast`, `factor_name`, and `deferral_target` slots; the
message points at the v0.3 representation IR for general contrast
support.

The INLA mapper for the new term class registers only after a
three-arbitrator verification test (INLA vs greta vs `lme4::lmer`)
passes on the host; on hosts where INLA verification cannot complete the
gate refuses INLA dispatch with a v0.3 deferral message rather than
silently shipping an unverified translation.

### Feature – uncorrelated random slopes (x \|\| g) (ADR 0020)

`fb_brms(y ~ x + (x || g), ...)` now parses and emits the uncorrelated
random-effect form – in lme4 / brms semantics each level of `g` carries
an independent intercept deviation AND an independent slope deviation,
both drawn from their own univariate- normal priors (no correlation
parameter shared between intercept and slope). The explicit
`(1 + x || g)` shape is equivalent; `(0 + x || g)` suppresses the
intercept block, yielding a slope- only random effect. The correlated
form `(x | g)` continues to refuse with a v0.3 deferral message pointing
to ADR 0025 (Stage 5A known-covariance inputs), which will admit the
user- supplied Cholesky factor that makes the correlated form tractable;
the refusal raises a typed condition
(`flexybayes_correlated_slope_unsupported`) carrying `grouping_factor`,
`slope_variable`, `deferral_target`, and `workaround` slots so
downstream tooling can pattern-match.

Canonical-name family `sd_<x>_<g>` registered on the greta + brms
backends – the brms-side `sd_<g>__<x>` parameter (brms’s
double-underscore Stan convention) maps to the canonical `sd_<x>_<g>`.
INLA mapping is gated by a three-arbitrator verification test (INLA vs
greta vs lme4) on a simple fixture following the §3.4 verification
policy in `plan-indexing-bigdata-merged-2026-05-23-v2.md`; until the
verification artefact records pass, the INLA backend refuses `(x || g)`
with a v0.3 deferral message naming `backend = "greta"` as the
workaround. Triangulation between greta and brms on `(x || g)` fits
agrees on slope-variance posteriors within `W_1 <= 0.20 * tau_true` (the
loosened envelope per merged-v2 §5.6 risk 3 – slope-variance posteriors
are intrinsically less identified than intercept-variance ones at modest
J).

### Representation benchmarks (Stage 1C per merged-v2 plan section 4.2.3)

The benchmark harness gains three new rows per term class:
`generated_code_size_bytes`, `pre_fit_object_size_bytes`, and
`code_generation_time_sec`. Snapshot tests assert that the greta
fit-time codegen path does not call
[`model.matrix()`](https://rdrr.io/r/stats/model.matrix.html) for
supported indexed term classes – the indexed-emit path replaces the
dense matrix at any `n`, so generated code size stays nearly constant in
`n`.

Benchmark filename rename: `tools/benchmark_flexyBayes_0.2.5.R` -\>
`tools/benchmark_flexyBayes.R` (version stamp dropped; the harness runs
against whichever version is installed, and names its output directory
accordingly at run time).

## flexyBayes 0.2.5.9000

### Correctness fix – predict(newdata) on smooths (ADR 0018)

`predict.flexybayes(..., newdata = ...)` on fits containing one or more
`s()` smooth terms now uses retained `mgcv` `Smooth` objects via
[`mgcv::PredictMat()`](https://rdrr.io/pkg/mgcv/man/smoothCon.html),
restoring correctness on `newdata` containing `x` values inside or near
the training range. Previously the basis was implicitly re-derived from
`newdata` via
[`stats::model.matrix()`](https://rdrr.io/r/stats/model.matrix.html),
producing correct-by-coincidence values inside the training range and
silently wrong values near or beyond. The fix retains the
[`mgcv::smoothCon()`](https://rdrr.io/pkg/mgcv/man/smoothCon.html)
output on the IR (internal slot `random_terms[[i]]$smooth_obj`) and
threads it via `extras$parse_info$smooths`. `fb_brms(backend = "brms")`
and
[`fb_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_greta.md)
are exempt – both already correct.

A correctness refusal fires on legacy fits saved before this fix: re-fit
on the current version to enable `predict(newdata)`.

### Code-size fix – smooth emit literal-matrix storage

The `greta` emit path for `s()` smooths no longer inlines the n-row
basis matrix as a literal in the generated code. The basis is bound into
the model environment as `B_s_<varname>` and the emitted code references
`as_data(B_s_<varname>)` instead. `nchar(return_code(fit))` for `s(x)`
at `n = 10000` dropped from ~10 MB to under 10 kB.

### Gate truth = emit truth (ADR 0017)

`lgm_gate(fb) == accept` is now a sufficient condition for the INLA emit
path to succeed structurally. Three new gate rules
(`fixed_term_type_inla`, `random_term_type_inla`, `rcov_term_type_inla`)
fold the prior emit-time refusal sites into `lgm_gate()` so users see
refusals before the INLA machinery is invoked. `backend = "auto"` no
longer carries a separate emit-time fall-back path; dispatch trace’s
auto-non-LGM path is uniformly `"auto_lgm_refuse"`.

### Visual-regression test tier upgraded (AMBITION_STAGE §1.1)

The `vdiffr` SVG-snapshot tests in `test-plot-vdiffr.R` (which had been
skipped unconditionally due to MCMC-float-drift fragility) are replaced
with numerical snapshots on the plotted data structure. Equivalent
coverage for “did the plot get built correctly” without the SVG-diff
fragility.

### Structured-cov default priors – vm() + ped() now uniform-on-SD

`.default_uniform_prior()` (extending ADR 0004) now fires on `vm()` and
`ped()` random-term inputs, closing the documented inconsistency where
`simple`/`ide`/`id` RE SDs defaulted to uniform-on-SD while `vm`/`ped`
fell back to legacy lognormal. The other structured forms (`at`, `us`,
`fa`, `ar1`) remain on the legacy default for now.

## flexyBayes 0.2.0 (development)

### Four-verb API

`flexyBayes` exposes four user-facing entry points covering the
formula-grammar × backend-ambition cross-product:

| Verb | Grammar | Backend choices | Use when |
|----|----|----|----|
| [`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md) | ASReml (`fixed` / `random` / `rcov`) | `greta`, `inla`, `auto` | ASReml syntax; agricultural / variance-component workflows. |
| [`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md) | brms / lme4 (`y ~ x + (1 | g)`) | `greta`, `inla`, `brms`, `auto` | brms or lme4 syntax; Stan passthrough on `backend = "brms"`. |
| [`fb_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_greta.md) | direct greta model graph | `greta` | Expert escape hatch; supplies a pre-built greta model. |
| [`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md) | n/a | n/a | Pairwise cross-engine posterior comparison. |

[`fb()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md)
remains as a literal alias for
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md).

### Dispatch trace

Every fit records a structured
[`backend_decision()`](https://aagi-aus.github.io/flexyBayes/reference/backend_decision.md)
describing which backend ran and why:

``` r

fit <- flexybayes(yield ~ env, random = ~ geno, data = trial)
backend_decision(fit)
#> $backend     "greta"
#> $path        "auto_inla_refuse"
#> $gate_checks <list of lgm_gate rules + pass/fail>
#> $reason      "lgm_gate refused at check `hyperparam_budget`."
```

`backend = "auto"` runs `lgm_gate()` and routes to INLA on acceptance,
otherwise to greta. `auto` never routes to Stan — brms’s first-call Stan
compile (typically 30–60 s) is incompatible with the auto-fast- path
promise; Stan is opt-in only via explicit `backend = "brms"` on
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md).

### Stan passthrough on `fb_brms(backend = "brms")`

[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
builds the flexyBayes intermediate representation (IR), translates the
prior, hands off to `brms::brm()`, and wraps the returned `brmsfit` in a
`c("flexybayes_brms", "flexybayes")` subclass. The live `brmsfit` is
exposed on the `$brms` slot so brms’s own posterior tooling (`loo()`,
`posterior_predict()`, `bayes_factor()`) remains directly available.

``` r

fit_s <- fb_brms(Reaction ~ Days + (1 | Subject),
                 data = sleepstudy, backend = "brms")
fit_g <- fb_brms(Reaction ~ Days + (1 | Subject),
                 data = sleepstudy, backend = "greta")
triangulate(fit_s, fit_g)
```

`review_code = TRUE` on the Stan path returns Stan source via
`brms::make_stancode()` — compile-free inspection before any Stan
compilation fires.

### Cross-engine triangulation

`triangulate(fit_a, fit_b)` computes mean difference, SD ratio, tail
drift, Wasserstein-1, and R-hat-on-means on every parameter the two fits
have in common. Canonical-name resolution (see below) means the caller
usually does not need to pass a `name_map`.

``` r

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

### `canonical_names()` registry

Each backend names parameters differently (greta’s `sigma_g`, INLA’s
`Precision for g` on the precision scale, brms’s `sd_g__Intercept`,
etc.).
[`canonical_names()`](https://aagi-aus.github.io/flexyBayes/reference/canonical_names.md)
resolves backend-native names to a single canonical name and applies the
appropriate scale transform — most visibly, INLA’s precision draws are
flipped to the SD scale before comparison.

``` r

canonical_names(fit_i)
#>   native                canonical    transform
#>   "(Intercept)"         "(Intercept)" identity
#>   "Precision for g"     "sd_g"        1/sqrt(.)
#>   "Precision for the Gaussian observations" "sigma" 1/sqrt(.)
```

[`triangulate()`](https://aagi-aus.github.io/flexyBayes/reference/triangulate.md)
uses the registry to align parameters before computing metrics.

### `prior_summary()` accessor

A new exported S3 generic surfaces the resolved priors used to fit the
model. The summary distinguishes three resolution paths:

- **auto-default** — bounded uniform on SD per Gelman (2006); fires when
  neither a user
  [`fb_prior()`](https://aagi-aus.github.io/flexyBayes/reference/fb_prior.md)
  nor a legacy `prior_vc_sd` scalar is supplied.
- **user-supplied** — the
  [`fb_prior()`](https://aagi-aus.github.io/flexyBayes/reference/fb_prior.md)
  object the caller passed via the `prior` argument.
- **legacy-scalar** — the `prior_fixed_sd` / `prior_vc_sd` bridge,
  preserved verbatim when `prior_vc_sd` is passed explicitly.

``` r

fit <- flexybayes(Reaction ~ Days, random = ~ Subject,
                  data = sleepstudy)
prior_summary(fit)
#> <prior_summary>  backend = greta
#>   Source: auto-default bounded uniform on SD (Gelman 2006)
#>     Upper bound U = 282.7
#>     Scale basis    = 5 * sd(Reaction)
```

On
[`fb_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_greta.md)
fits the summary is flagged `declaration_only = TRUE` because flexyBayes
does not re-prior the user-built greta graph; the prior records what the
user declared the model encodes.

### `review_code = TRUE` workflow

A new optional argument on
[`flexybayes()`](https://aagi-aus.github.io/flexyBayes/reference/flexybayes.md),
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md),
and
[`fb_greta()`](https://aagi-aus.github.io/flexyBayes/reference/fb_greta.md)
lets users inspect the generated backend code before any sampling fires,
then advance into the fit when ready:

``` r

rev <- flexybayes(yield ~ env, random = ~ geno, data = trial,
                  review_code = TRUE)
rev                  # two-line summary: backend + IR dimensions
cat_code(rev)        # emit the generated greta (or Stan) code
fit <- proceed(rev)  # fit; a second proceed(rev) returns the cache
```

The returned `<flexybayes_review>` object carries the generated code,
the parsed IR, the resolved prior, the captured call, and a snapshot of
`.Random.seed`. The seed snapshot is restored on
[`proceed()`](https://aagi-aus.github.io/flexyBayes/reference/proceed.md)
entry so a direct call and a review-then-proceed pair reproduce the same
R-RNG state.

`review_code = TRUE` and `return_code = TRUE` (the older
code-string-only option) are mutually exclusive. Default is `FALSE`;
session-level override via
`options(flexyBayes.review_code_default = TRUE)`.

### Prior contract

Auto-default (no `prior` and no `prior_vc_sd` supplied):

| Target | Default | Notes |
|----|----|----|
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
interlingua (Simpson et al. 2017) for translation across greta / INLA /
brms.

The `prior_fixed_sd` default was raised from 10 to 100 in this cycle;
the previous value was too tight for responses on the natural data scale
(e.g., `sleepstudy$Reaction` with mean ≈ 298 ms) and induced a
substantial intercept bias against the REML reference.

[`fb_prior()`](https://aagi-aus.github.io/flexyBayes/reference/fb_prior.md)
accepts the targets `sigma`, `sd(group)`, `b(name)`, `cor(group)`,
`smooth(var)`, and the families `pc`, `normal`, `student_t`,
`half_normal`, `half_cauchy`, `cauchy`, `gamma`, `exponential`, `lkj`,
`uniform`.

### LGM feasibility filter

`lgm_gate(fb)` runs a structural feasibility check on the parsed IR
before INLA dispatch. The filter returns either an acceptance or an
`lgm_refusal` object carrying every rule that failed, the diagnostic,
the suggested re-route (`backend = "brms"` via
[`fb_brms()`](https://aagi-aus.github.io/flexyBayes/reference/fb_brms.md)
for the Stan passthrough; greta for the broader flexyBayes formula
path), and a two-key-armed override path.

The structural refusals currently live in two places (the gate plus
`emit_inla()`); folding the emit-time refusals into the gate is the ADR
0017 v0.2.5 work.

### `gretaR` slot

A dormant scaffold for the `gretaR` backend is registered:
[`gretaR_status()`](https://aagi-aus.github.io/flexyBayes/reference/gretaR_status.md)
reports `activated = FALSE` and explains the activation procedure. The
four touch-points (`match.arg` extension, canonical-name mapper,
dispatch branch, status helper) are in place so v0.3 activation reduces
to a single short patch plus the `emit_gretaR.R` body — once the gretaR
package goes public and audit-clean.

### Vignettes

Twelve numbered vignettes ship with the package:

1.  Getting started · 2. ASReml-shaped formulas · 3. Foundational
    regression · 4. Hierarchical models · 5. Structured covariance ·
2.  Priors and regularisation · 7. METs and genomic selection ·
3.  Downstream analysis · 9. Spatio-temporal models · 10. Cross- engine
    triangulation · 11. LGM feasibility filter · 12. Backend internals.

Heavy MCMC vignettes use a `.Rmd.orig` precompile pattern
(`vignettes/_precompile.R`); the `.Rmd` that ships in the package
tarball is the pre-evaluated static output.

### References

- Gelman, A. (2006). Prior distributions for variance parameters in
  hierarchical models. *Bayesian Analysis* 1(3): 515–534.
- Simpson, D., Rue, H., Riebler, A., Martins, T. G., & Sørbye, S. H.
  (2017). Penalising model component complexity: a principled, practical
  approach to constructing priors. *Statistical Science* 32(1): 1–28.
- Rue, H., Martino, S., & Chopin, N. (2009). Approximate Bayesian
  inference for latent Gaussian models by using integrated nested
  Laplace approximations. *JRSS: Series B* 71(2): 319–392.
