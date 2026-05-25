---
id: 2026-05-25-adr-0030-architectural-final-v040
schema_version: 1.1
date: 2026-05-25
tier: T4
classification: open
export_status: local_only
consensus_mode: required
domain: r-package
project: flexyBayes
status: accepted
title: "ADR 0030 -- Architectural-final v0.4.0 contract (TERMINAL on API-surface arc)"
tags: [adr-0030, architectural-final, terminal, seven-contracts, four-constructors, six-verbs, v040, meta-adr, audit-2026-05-25]
triggers:
  - irreversible_without_major_bump
  - project_identity_scope
  - adr_class_commitment
  - long_lived_commitment
reversal_cost: severe
decision_pressure: audit_close
supersedes:
  - 2026-04-XX-adr-0015-fb-brms-stan-passthrough  # v0.1 draft ADR; conceptually absorbed (no cairn yet)
superseded_by: null
related:
  - 2026-05-25-adr-0028-stan-brms-backend-verifier
  - 2026-05-25-adr-0029-triangulation-axis-vocabulary
  - 2026-05-25-v038-plan-12-ratifications
  - 2026-05-25-predict-kernel-extraction
---

## Status

**Accepted 2026-05-25** in the same architectural session that
produced ADR 0028 + 0029. Ratified by Max during the mid-session
review pass (`v038-plan-2026-05-25.md` §12.6 (5)); ADR header at
`design-notes-priors-brms-lgm.md` ~L3570 flipped `Proposed` -->
`Accepted 2026-05-25` in the same revision. The most architecturally
consequential decision of the 2026-05-25 session.

ADR 0030 is a **meta-ADR**: it emits no code itself; it ratifies the
architectural shape that all subsequent per-contract ADRs and
implementation register *into*. Parallel structurally to ADR 0027
(terminal on the approximation-surface arc); the package now carries
two architecturally-final arcs ratified, each closed by a meta-ADR
whose role is to lock the shape that future work registers into rather
than re-litigates.

Anchored in:

- `design-notes-priors-brms-lgm.md` ADR 0030 (~L3569, ~175 lines;
  status `Accepted 2026-05-25` at L3570)
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §4 (narrative
  + walkthrough anchors) + §8.3 (seven-decision alternatives-bracketing
  matrix)
- `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` (the audit whose
  five-contract consolidation surface was extended to seven by the
  *check-against-signature-claim* move)
- `v038-plan-2026-05-25.md` §12.6 (5) -- the ratification block

## Alternatives considered

The crossroads was *what shape commits flexyBayes to architectural
finality at v0.4.0*. The audit recommended a five-contract
consolidation surface; the architectural question was whether to
accept that as-is, extend it, or use a different ratification posture
entirely.

| Option | One-line description |
|---|---|
| A | Accept audit literal -- five contracts, one constructor (`fb_cov`), no terminal-ADR framing; revisit per release. |
| B (CHOSEN) | Seven contracts + four constructor nouns + six verbs, ratified TERMINAL at v0.4.0; closed-vocabulary discipline across four registries. |
| C | Eight contracts (add `validation` contract distinct from `validate_approximation()`); maximalist architectural shape. |
| D | Defer ratification until v1.0; v0.4.0 ships with explicitly-not-final API. |
| E | Quasi-terminal -- API final but reserved-to-change with one-version notice. |

## Rationale for rejection

### Option A -- audit literal (five contracts, one constructor)

Five misses the triangulation axis-vocabulary contract (ADR 0029) --
flexyBayes' signature claim is multi-engine triangulation; if the
contract set doesn't cover the signature claim, the
*check-against-signature-claim* move flags the gap. Five also misses
the refusal-taxonomy contract -- the structural disclosure regulated
reviewers expect (and the audit itself names in §Structural
Recommendations under a different heading). One constructor (`fb_cov`
alone) stops the pattern at the immediate elegance gain; the *pattern*
generalises to every kind of structured input the user passes (priors,
covariance carriers, approximations, engine handles). brms / tidymodels
/ ggplot2 all use constructor-noun + small-verb composition; the audit
named one constructor because that was the immediate covariance-
carrier ergonomics win. Stopping at one is the easier engineering
choice but the worse architectural choice.

### Option C -- eight contracts (add a `validation` contract)

The proposed eighth `validation` contract is the union of C5
(approximation validation) + C2 (prediction-kernel chunk-invariance)
+ C7 (refusal taxonomy) and would double-count. Architectural
maximalism for its own sake. **Seven is what falls out of
systematically mapping truth claims to surface elements, not an
arithmetic target;** ADR 0030 §Decision 1 makes this explicit. Adding
an eighth contract would also weaken the closed-vocabulary discipline
by inviting *"if eight, why not nine?"* drift.

### Option D -- defer to v1.0

Means v0.4.0 ships with an explicitly-not-final API. The audit's
central question -- *"can this remain simple and trustworthy as
capability grows?"* -- is answered *"wait until v1.0 to find out"*.
Each per-contract ADR (C3 covariance carrier, C5 approximation, C6
axis vocab) would re-litigate the architectural framing in its own
justification; the framing drifts across ADRs. Retrospective
ratification at v1.0 cannot fix the implementation choices made
under an unratified architecture.

### Option E -- quasi-terminal with one-version notice

*"Terminal except when it isn't"* offers no protection against API
drift. Reviewers and downstream users cannot make long-arc stability
commitments against an API that is reserved-to-change. The
forcing-function value of a terminal claim comes from its hard edge:
every post-v0.4.0 verb/registry change requires an explicit ADR
amendment with cost-benefit accounting. Quasi-terminal removes that
gate by making the change-cost a one-version notice rather than an
ADR-amendment cycle.

## Implemented option (B) -- the seven-by-four-by-six shape

**Seven truth contracts** (closed list, each anchored to its own ADR
or roadmap slot):

| # | Contract | Anchor |
|---|---|---|
| C1 | Planner | `fb_plan()`, ratified v0.3.8 Phase B |
| C2 | Prediction kernel | `.predict_linear_draws()`, ratified v0.3.8 Phase A (cairn `2026-05-25-predict-kernel-extraction`) |
| C3 | Covariance carrier | `fb_cov()`, v0.4.0 |
| C4 | Representation registry | `Representation:` print noun + internal registry; v0.4.0 |
| C5 | Approximation registry | ADR 0027, v0.4.0 |
| C6 | Triangulation axis vocabulary | ADR 0029, v0.4.0 / v0.4.1 |
| C7 | Refusal taxonomy | `R/refusal_taxonomy.R` scaffold v0.3.8; full registry + `fb_refusals()` export v0.4.0 |

**Four constructor nouns** (closed list): `fb_cov` + `fb_prior` (exists
since v0.3.x) + `fb_approx` + `fb_engine`. Each carries a classed-object
schema + a snapshot test on the schema.

**Six exported verbs** (closed list): `flexybayes`, `fb_brms`,
`fb_greta`, `fb_plan`, `triangulate`, `validate_approximation`.

**Two-line truth display** on `print.flexybayes()`: `Representation:`
+ `Engine:` -- closes audit Critical Fix #4 on the exactness
conflation.

**Deprecation discipline:** clean break at v0.4.0 on the v0.3.7
`vm(group, chol = L)` kwarg forms; one-version deprecation window;
hard removal at v0.5.0. *The constructor is the API.*

**Closed-vocabulary discipline** across all four registries with
snapshot-test enforcement; every post-v0.4.0 vocabulary addition
requires an ADR amendment.

## Forward cost

- **Every post-v0.4.0 verb/registry change requires an ADR amendment**
  with cost-benefit accounting. This is the forcing function on API
  growth. The cost is procedural friction on legitimate additions; the
  benefit is the long-arc stability promise that reviewers and
  downstream users can rely on.
- **`flexybayes` verb count locked at six.** A new exported verb is an
  ADR-amendment event. New capability registers via the four
  constructor nouns into the four closed-vocabulary registries; verb-
  surface growth is closed.
- **`vm(group, chol = L)` kwarg forms hard-removed at v0.5.0.** v0.4.0
  carries warning messages on every legacy-kwarg call site (~6 in
  `vm()` / `ped()` + ~3 in vignettes); v0.5.0 removes the parser
  branches. Users who do not migrate during the v0.4.x window break at
  v0.5.0 -- by design.
- **Two new registries at v0.4.0** (`.backend_independence_registry`
  per ADR 0029; `.refusal_registry` per C7). Each carries a release-
  versioned snapshot test; vocabulary changes are detectable in CI.
- **Three net-new constructors at v0.4.0** (`fb_cov`, `fb_approx`,
  `fb_engine`). Each carries a classed-object schema + a snapshot test
  on the schema; total NAMESPACE growth approximately five exports.
- **Configuration shape locked as R-code constructors** -- no YAML /
  JSON / TOML config layer admitted. Users who want declarative config
  build it themselves on top of the constructors. The package does not
  commit to a config-format roadmap.
- **`triangulate_all()` automatic peer enumeration deferred** to a
  subsequent ADR after C6 + C7 ship; not part of the architectural-
  final commitment.
- **`fb_data()` rejected as a fifth constructor noun** for v0.4.0;
  reserved as a v0.5.0+ option if user feedback surfaces a need.
- **Vignette deck restructure (3 canonical + N specialist) locked at
  v0.4.0.** Not v0.3.8.
- **Methods-paper companion subsection draft** ships alongside v0.4.0
  -- the seven-contract architecture is the methods paper's
  architectural narrative.

## References

### Methodological

- Bürkner, P.-C. (2017). brms: An R package for Bayesian multilevel
  models using Stan. *Journal of Statistical Software*, 80(1), 1--28.
  doi:10.18637/jss.v080.i01 -- exemplar of long-arc API stability via
  small-verb + rich-constructor composition (~7 verbs + rich
  constructor/accessor layer over 8 years).
- Kuhn, M., & Vaughan, D. (2020). *Tidymodels: A collection of packages
  for modeling and machine learning using tidyverse principles*. CRAN.
  https://www.tidymodels.org -- exemplar of engine-registry-as-
  extension-surface; ~10 verbs across the metaverse stabilised by the
  registry pattern; transposed to flexyBayes' `fb_engine()`.
- Wickham, H. (2010). A layered grammar of graphics. *Journal of
  Computational and Graphical Statistics*, 19(1), 3--28.
  doi:10.1198/jcgs.2009.07098 -- exemplar of small-verb + layered-noun
  composition; 5 core verbs + noun composition with 12+ years of API
  stability. ADR 0030's six-verb / four-constructor / four-registry
  shape is brms / tidymodels / ggplot2 synthesised one verb tighter.

### Empirical

- `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` -- the external audit
  whose five-contract consolidation surface was extended to seven by
  the *check-against-signature-claim* move; load-bearing for the
  ratification timing.
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §1.1 + §4.4
  -- the design-thinking arc and walkthrough anchors that produced
  the seven-contract framing.
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §8.3 -- the
  seven-decision alternatives-bracketing matrix.
- `design-notes-priors-brms-lgm.md` §ADR 0027 -- the prior terminal-ADR
  (approximation-surface arc); ADR 0030 is the parallel terminal on
  the API-surface arc.

### Operational

- Cairn: `2026-05-25-adr-0028-stan-brms-backend-verifier.cairn.md`
  (this project) -- absorbed into the architectural-final shape as
  the `fb_engine()` registry slot for `stan_brms`.
- Cairn: `2026-05-25-adr-0029-triangulation-axis-vocabulary.cairn.md`
  (this project) -- contract C6.
- Cairn: `2026-05-25-predict-kernel-extraction.cairn.md` (this project)
  -- contract C2; v0.3.8 Phase A implementation.
- Cairn: `2026-05-25-v038-plan-12-ratifications.cairn.md` (this
  project) -- the implementation distribution: v0.3.8 ships C1 + C2 +
  C7 scaffold; v0.4.0 ships C3 + C4 + C5 + C6 + constructor nouns +
  deprecation cycle.
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0030 at ~L3569; status
  `Accepted 2026-05-25` at L3570.

## References audit

### Methodological refs

- **Bürkner (2017) brms JSS**: Quality A (peer-reviewed JSS, primary
  package paper, author maintains brms 8+ years); Validity locator
  abstract + §3 on the formula-to-Stan compilation pipeline (paraphrased
  support for *"brms is the maintained `formula to Stan` gold standard
  in R"*; fair-use paraphrase, not verbatim quote); Trustworthiness
  `current` (brms 2.20+ in active maintenance as of 2026-05-25; no
  superseding paper from same author).
- **Kuhn & Vaughan (2020) tidymodels**: Quality A (canonical CRAN
  metaverse, maintained by Posit team); Validity locator
  https://www.tidymodels.org *Get Started* + *Books* (paraphrased
  support for engine-registry pattern; the registry-as-extension-surface
  claim is the well-known tidymodels architectural posture);
  Trustworthiness `current` (active 2024--2026; no superseding
  framework). Flag: web-resource reference rather than versioned paper
  -- non-blocking but should be paired with a specific tidymodels-paper
  citation when one becomes canonical.
- **Wickham (2010) ggplot2 JCGS**: Quality A (peer-reviewed JCGS, the
  canonical layered-grammar paper); Validity locator §3 on layered
  composition + §4 on small-verb-set design (paraphrased support for
  the 5-verb-plus-noun-composition pattern); Trustworthiness `current`
  (the layered-grammar model has not been superseded by a later Wickham
  framework paper; ggplot2 v3.5.x in active maintenance as of
  2026-05-25).

### Empirical refs

- **`feedback_v0.3.7_to_v0.4.0_2026-05-25.md`**: Quality A (external
  audit, dated, structurally-recommendation-organised); Validity
  locator §Critical Fixes + §Structural Recommendations (verbatim
  recommends the five-contract consolidation that ADR 0030 extended
  to seven); Trustworthiness `current` (audit dated 2026-05-25; no
  superseding revision).
- **`adr-crossroads-and-walkthrough-anchors-2026-05-25.md`**: Quality
  A (project-internal, curated, dated, single-author); Validity
  locator §1.1 + §4.4 + §8.3 (verbatim documents the seven-contract
  rationale and the alternatives-bracketing matrix); Trustworthiness
  `current` (companion document to this ADR; ratified same session).
- **`design-notes-priors-brms-lgm.md` §ADR 0027**: Quality A (project-
  internal ADR ledger, ratified); Validity locator the ADR 0027
  acceptance block (paraphrased structural mirror for the terminal-
  meta-ADR pattern; fair-use paraphrase); Trustworthiness `current`
  (ADR 0027 accepted in the project ledger; no supersession).

### Operational refs

- **Cairn `2026-05-25-adr-0028-stan-brms-backend-verifier`**: Quality
  A (project-internal, ratified, this session); Validity locator the
  cairn's Forward cost block (verbatim names the `fb_engine()` registry
  absorption); Trustworthiness `current` (sibling cairn this session).
- **Cairn `2026-05-25-adr-0029-triangulation-axis-vocabulary`**:
  Quality A (project-internal, ratified, this session); Validity
  locator the cairn's Implemented option block (verbatim names the
  C6 contract role); Trustworthiness `current`.
- **Cairn `2026-05-25-predict-kernel-extraction`**: Quality A (project-
  internal, ratified, accepted); Validity locator the cairn's Status
  block (verbatim names the C2 contract role); Trustworthiness
  `current`.
- **Cairn `2026-05-25-v038-plan-12-ratifications`**: Quality A
  (project-internal, ratified, this session); Validity locator the
  cairn's Implemented option block (verbatim names the v0.3.8 / v0.4.0
  contract distribution); Trustworthiness `current`.

**Audit verdict**: all references pass

## Independent review

**Primary ranking**: B > A > E > D > C
**Reviewer ranking**: not_attempted
**Verdict**: `not_attempted`
**Input digest**: sha256:not_attempted_pre_p4
**Reviewer evidence scope**: not_attempted

### Reviewer ranking + rationale (independent)

Not attempted: the `/ledger review` independent-review protocol (P4
in `ledger_dev`'s phase roadmap) is pre-implementation as of
2026-05-25. P4 ships the blinded-reviewer + ranked-alternatives +
named-missing-evidence + input-digest mechanics; until then, T4
cairns ratified this session land with `Verdict: not_attempted` and
surface the gap explicitly rather than silently skipping the
consensus mechanism (per `~/Projects/CLAUDE_PROJECTS_LOCAL/ledger_dev/CLAUDE.md`
§3 hard rule 4). Re-review queued for first invocation of `/ledger
review` once P4 lands; the cairn's `review_trigger` field is set to
`null` here because the trigger is the protocol going live, not a
date or a project event.

### Reviewer's named missing evidence

- The independent-review protocol itself (the load-bearing missing
  evidence; once it exists, the rest of the audit fills out).
- One downstream user's reaction to the seven-contract framing (the
  audit was a single reviewer; the broader external-review surface
  has not yet been exercised). Queued for v0.4.0 release-window
  external feedback.
- Empirical evidence on the constructor-noun discoverability claim
  (brms / tidymodels / ggplot2 are cited as exemplars; the
  *transposition* claim assumes the patterns generalise to flexyBayes'
  domain. Validation requires post-v0.4.0 user feedback on whether
  the four-constructor surface actually reduces cognitive load
  relative to the v0.3.7 kwarg-laden surface).

### Agreement notes

No reviewer pass has been run. The Primary ranking + the alternatives-
bracketing matrix in §8.3 of `adr-crossroads-and-walkthrough-anchors-2026-05-25.md`
together provide the structural defence of the chosen option; a future
reviewer is invited to start there. The cairn's status (`accepted`) is
load-bearing on Max's ratification at `v038-plan-2026-05-25.md` §12.6
(5); the independent-review gap is informational, not blocking on the
ratification per the schema's `not_attempted` verdict allowance.
