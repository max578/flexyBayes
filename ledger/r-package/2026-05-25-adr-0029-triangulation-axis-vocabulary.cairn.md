---
id: 2026-05-25-adr-0029-triangulation-axis-vocabulary
schema_version: 1.1
date: 2026-05-25
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: proposed
title: "ADR 0029 -- Triangulation independence-axis vocabulary (algorithmic/implementation/specification)"
tags: [adr-0029, triangulate, axis-vocabulary, closed-vocabulary, registry, v040, audit-2026-05-25]
triggers:
  - public_api_change
  - adr_class_commitment
  - methodology_change_downstream
reversal_cost: high
decision_pressure: audit_close
supersedes: []
superseded_by: null
related:
  - 2026-05-25-adr-0028-stan-brms-backend-verifier
  - 2026-05-25-adr-0030-architectural-final-v040
---

## Status

Proposed 2026-05-25 in the same architectural session that produced
ADR 0028. The motivating diagnosis came from Max's mid-session
question (recorded in `adr-crossroads-and-walkthrough-anchors-2026-05-25.md`
§1.1 step 2): adding a Stan-via-brms backend alongside gretaR's NUTS
sampler means the canonical `gretaR` vs. `stan_brms` pair is
HMC-vs-HMC, structurally an *implementation* cross-check rather than
an *algorithmic* one. Without explicit axis labelling, the
`triangulate()` report would overstate the new pair (treating it as
algorithmic-axis convergence) and simultaneously understate the
headline gretaR-vs-INLA pair (describing it in the same flat language
as the new pair). ADR 0029 ratifies the closed three-axis vocabulary
that fixes both framing failures enforceably (registry + print
extension + snapshot gate) rather than editorially. **Pair-coupled
with ADR 0028.** Anchored in:

- `design-notes-priors-brms-lgm.md` ADR 0029 (~L3399, ~170 lines)
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §3 (decision
  summary + walkthrough anchors) + §8.2 (three-decision
  alternatives-bracketing matrix)
- ADR 0027 (approximation-scheme vocabulary) -- structural mirror;
  same closed-vocabulary + internal-registry + print-extension pattern

## Alternatives considered

The crossroads was *how to make the triangulation report distinguish
algorithmic-axis from implementation-axis convergence claims*. Four
options, all on the table once the framing diagnosis was made:

| Option | One-line description |
|---|---|
| A | Open-string vocabulary -- users add their own axes; no closed registry. |
| B (CHOSEN) | Closed three-axis vocabulary (`algorithmic` / `implementation` / `specification`), internal registry, print extension, snapshot gate. |
| C | Two-axis closed vocabulary (`algorithmic` + `implementation`); drop the `specification` placeholder. |
| D | Four-axis closed vocabulary; add a `documentation` placeholder for cross-doc verification. |

## Rationale for rejection

### Option A -- open-string vocabulary

Re-introduces vocabulary drift across releases. The same release
could carry `triangulate()` reports labelled "different code base"
in one vignette, "implementation independence" in another, and
"different package" in a third -- with no single source of truth on
what flexyBayes *means* by either phrase. The closed-vocabulary
discipline is the architectural posture ratified at ADR 0030 §Decision
6; ADR 0029 is the first vocabulary registry to exercise that
discipline. Open strings also defeat the snapshot-test gate that
catches silent vocabulary change between releases.

### Option C -- two-axis closure (drop `specification`)

Closing the vocabulary at two axes (`algorithmic` + `implementation`)
forecloses a future ADR registering multiple parameterisations within
a single backend -- for example, a Stan centred-vs-non-centred random-
effects cross-check, which is structurally a *specification*-axis
check (same algorithm, same implementation, different model
specification). When that case arrives, the ADR amendment is more
expensive than reserving the placeholder up-front: the existing
backend-independence registry would need a schema migration, every
`triangulate()` report carrying the new axis would need a new label,
and the snapshot tests would need a coordinated update. The
placeholder costs one line of documentation now and saves the
migration later.

### Option D -- four-axis with `documentation` placeholder

`documentation` is an editorial-process axis (different documentation
sources said the same thing), not a triangulation axis (different
inference paths agreed on the same answer). Conflating the two would
confuse readers and reviewers -- *"the methods paper and the vignette
agree"* is a documentation cross-check; *"gretaR and INLA agree"* is
a triangulation cross-check. The two belong in different
infrastructure (the documentation cross-check belongs to the vignette/
manuscript build pipeline, not to `triangulate()`).

## Implemented option (B) -- the three axes + registry mechanics

**Closed three-axis vocabulary:**

- `"algorithmic"` -- different inference paradigms (e.g.,
  gretaR-NUTS vs. INLA-Laplace, or gretaR-NUTS vs. variational
  Bayes). The strongest cross-check; agreement here is evidence
  against algorithmic bias.
- `"implementation"` -- same paradigm, different code base (e.g.,
  gretaR-NUTS vs. `stan_brms`-NUTS; both HMC, both Hamiltonian, but
  different sampler implementations + different reparameterisation
  pipelines). Agreement here is evidence against implementation bugs;
  weaker than algorithmic-axis agreement.
- `"specification"` -- reparameterisation cross-check within a single
  backend (e.g., centred vs. non-centred random effects in Stan).
  Placeholder at first ship; no backend pair exercises it alone.

**Registry mechanics:** `.backend_independence_registry` is an internal
`environment` populated at `.onLoad()` with the per-pair canonical
axis classification, symmetry-canonicalised so the lookup is
order-independent (`(a, b)` and `(b, a)` produce the same axis label).
**`triangulate()` return shape extends** with two new per-row fields:
`independence` (character vector; the axis labels for the pair) +
`axis_justification` (character scalar; the one-sentence rationale for
the axis assignment). Both are snapshot-tested against a
release-versioned reference to catch silent vocabulary change.

## Forward cost

- **`triangulate()` API extension.** Two new per-row fields
  (`independence`, `axis_justification`) on the return shape; existing
  consumers of `triangulate()` output must accommodate. Mitigated by
  the v0.4.0 verb count being closed at six (ADR 0030 Decision 3) --
  `triangulate()` is in the closed verb roster, so extension cost is
  one-time at v0.4.0 rather than per-release.
- **Methods-paper structure commitment.** The methods paper must
  carry a subsection (~300 words) naming the three axes and
  explaining the convergence-claim hierarchy, per ADR 0029 §3.2 Q2
  (team-coordination decision; recommended answer Yes). Same paper
  gains a three-row axis-label column on the gretaR/INLA/`stan_brms`
  triangulation figure.
- **`"specification"` placeholder commitment.** At first ship, the
  placeholder has no exercising backend pair; documented as an
  explicit forward-extension hook in `triangulate()`'s `@references`.
  When the first specification-axis pair lands (future ADR), the
  registry gains the new pair without an ADR-amendment cycle on
  ADR 0029.
- **Snapshot-gate maintenance.** The release-versioned snapshot of
  the axis labels + justifications must update with every backend-
  pair addition. Procedural cost: one snapshot regeneration per new
  pair, reviewed at ADR-amendment time.
- **Pair-coupled release commitment with ADR 0028.** The two ADRs
  share their release slot (v0.4.0 or v0.4.1 depending on
  team-coordination resolution). Releasing ADR 0029 alone (axis
  vocabulary without the second backend) would carry only the
  `specification` placeholder -- no exercising pair -- which fails
  the *"vocabulary closure must be motivated by a real pair"* test.
  Releasing ADR 0028 alone re-introduces the framing failure ADR 0029
  exists to prevent.
- **Vocabulary versioning discipline.** Any future axis-label change
  is a breaking change to the `triangulate()` output schema, requires
  an ADR amendment, and triggers a snapshot regeneration. Closed
  vocabularies are easier to maintain than open ones precisely because
  this discipline is mandatory.

## References

### Methodological

- Gelman, A., Vehtari, A., Simpson, D., Margossian, C. C., Carpenter,
  B., Yao, Y., Kennedy, L., Gabry, J., Bürkner, P.-C., & Modrák, M.
  (2020). Bayesian workflow. *arXiv* 2011.01808. §6 distinction
  between *"fake-data simulation"* (implementation-axis cross-check),
  *"different parameterisations"* (specification-axis cross-check),
  and *"different algorithms"* (algorithmic-axis cross-check) -- the
  three workflow cross-checks promoted to first-class user-report
  vocabulary in ADR 0029.
- Vehtari, A., Gelman, A., & Gabry, J. (2017). Practical Bayesian model
  evaluation using leave-one-out cross-validation and WAIC. *Statistics
  and Computing*, 27(5), 1413--1432. doi:10.1007/s11222-016-9696-4 --
  the *"approximations are first-class iff they tell you when not to
  trust them"* posture; ADR 0029 transposes the same posture to
  multi-engine triangulation reports (the report tells you which axis
  of independence it spans).

### Empirical

- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §1.1 step 3
  -- the analysis that produced the two-tier convergence diagnosis
  from Max's mid-session question.
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §3.3 -- the
  vocabulary-closure rationale and the structural mirror to ADR 0027.
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §8.2 -- the
  three-decision alternatives-bracketing matrix.
- `design-notes-priors-brms-lgm.md` §ADR 0027 -- the approximation-
  scheme vocabulary ADR; same structural pattern (closed vocabulary +
  internal registry + print extension + ADR-amendment-forced
  expansion).

### Operational

- Cairn: `2026-05-25-adr-0028-stan-brms-backend-verifier.cairn.md`
  (this project) -- the pair-coupled backend cairn.
- Cairn: `2026-05-25-adr-0030-architectural-final-v040.cairn.md` (this
  project) -- the meta-ADR ratifying ADR 0029 as contract C6 (the
  triangulation axis-vocabulary contract) in the seven-contract
  architectural-final shape.
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0029 at ~L3399.
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0027 -- the
  approximation-vocabulary registry that ADR 0029 mirrors.
