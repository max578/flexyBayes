---
id: 2026-05-25-adr-0028-stan-brms-backend-verifier
schema_version: 1.1
date: 2026-05-25
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: proposed
title: "ADR 0028 -- brms as Suggests-gated stan_brms backend (verifier role)"
tags: [adr-0028, stan_brms, backend, brms, triangulation, suggests-gated, v040, audit-2026-05-25]
triggers:
  - public_api_change
  - adr_class_commitment
  - new_external_dependency
reversal_cost: high
decision_pressure: audit_close
supersedes: []
superseded_by: null
related:
  - 2026-05-25-adr-0029-triangulation-axis-vocabulary
  - 2026-05-25-adr-0030-architectural-final-v040
---

## Status

Proposed 2026-05-25 in the post-v0.3.7-release architectural session
triggered by the external audit `feedback_v0.3.7_to_v0.4.0_2026-05-25.md`
and Max's mid-session question about cross-engine convergence framing
(*"if we emphasise triangulation, and use gretaR with Stan and one of
backends, to be triangulated with brms, how does it reconcile with our
triangulation goal?"*). Ratified at the ADR level; release-slot decision
is **gated on three team-coordination questions** per project §8 (roster
ordering, methods-paper framing, toolchain default) and therefore lands
at v0.4.0 if team coord clears in time, otherwise v0.4.1. Pair-coupled
with ADR 0029 (the axis-vocabulary correction); the two ADRs release
together or not at all. Anchored in:

- `design-notes-priors-brms-lgm.md` ADR 0028 (~L3239, ~160 lines)
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §2 (narrative)
  + §8.1 (five-decision alternatives-bracketing matrix)
- `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` (the audit that triggered
  the session, though brms-as-backend was not in the audit's explicit
  recommendation set; the architectural extension was Max-side per the
  *check-against-signature-claim* move documented in the crossroads
  doc §1.1 steps 2--5)
- AMBITION_STAGE §2.8 (the slot reserved for ADR 0028 + 0029)

Supersedes the v0.1 draft ADR 0015 (`fb_brms(backend = "brms")` Stan
passthrough), which sketched brms-as-backend without the axis-honesty
framing or the opt-in toolchain gate.

## Alternatives considered

The crossroads was *how flexyBayes should incorporate brms*. brms
already enters the package as the formula-ingest surface (ADR 0014);
the new question was whether brms should also enter as an inference
backend, and if so under what activation discipline.

| Option | One-line description |
|---|---|
| A | No brms backend -- keep brms as formula-ingest surface only (ADR 0014); triangulation stays gretaR-vs-INLA. |
| B (CHOSEN) | brms as Suggests-gated `stan_brms` backend in the verifier role, opt-in via `options(flexyBayes.use_stan_brms = TRUE)`, cmdstanr default. |
| C | brms as an Imports-default backend, always available, no opt-in gate. |
| D | Direct Stan emission -- write Stan code from flexyBayes IR, bypass brms entirely. |

## Rationale for rejection

### Option A -- no brms backend

Leaves the project's signature claim (multi-engine triangulation)
under-evidenced. With only gretaR-vs-INLA on the convergence report,
the methods paper can claim algorithmic-axis convergence only on the
LGM-eligible subset (where INLA is applicable). Outside that subset,
the triangulation surface degenerates to gretaR alone -- a single-engine
claim wearing multi-engine framing. The audit's `feedback_v0.3.7_to_v0.4.0`
naming of *"can this remain simple and trustworthy as capability grows"*
as the central risk implicitly requires more than one cross-check
pathway; a second backend is the structural answer.

### Option C -- Imports-default brms

brms + rstan + cmdstanr together carry approximately 200 MB and eight
transitive dependencies. Making this load-bearing for every flexyBayes
install is disproportionate to the verifier role -- the typical user
does not need a second engine to fit their model; the second engine
matters for the explicit cross-check, not the routine fit. Silent
auto-detection (`requireNamespace("brms", quietly = TRUE)`) rewards
users for installing brms by enabling a backend they may not have
requested; the explicit opt-in posture matches the *"approximations are
first-class iff they tell you when not to trust them"* discipline
transposed from Vehtari, Gelman & Gabry (2017) to the multi-engine
triangulation surface.

### Option D -- direct Stan emission

Architecturally cleaner long-term (no brms intermediary; one less
moving part), but wrong-scoped for the v0.4.0 release. Direct Stan
emission requires (1) a Stan code-generator from the flexyBayes IR;
(2) maintenance of that generator against Stan's evolving language;
(3) parity testing against brms-emitted Stan to avoid silent semantic
drift. brms is the maintained gold-standard for *"formula to Stan"* in
R; reusing it as the verifier route delegates that maintenance burden
to a well-resourced upstream project. Direct Stan emission is held
open as a future ADR (the `backend = "stan"` label is deliberately
unclaimed by ADR 0028; see Forward cost).

## Implemented option (B) -- sub-decisions ratified within this ADR

Five design parameters lock the chosen path; each is itself an
internal-to-ADR-0028 ratification documented at
`adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §8.1.1--§8.1.5:

1. **Backend label `stan_brms`** (not `stan`, not `brms`). The
   algorithm name (`stan`) is reserved for a future direct-emit ADR;
   the package name (`brms`) is taken by the formula-ingest surface
   (ADR 0014). `stan_brms` names the *route* (Stan via brms), the
   correct architectural primitive.
2. **Activation: Suggests-gated + explicit opt-in** via
   `options(flexyBayes.use_stan_brms = TRUE)`, default `FALSE`. Two-step
   user discipline (install brms; flip option) preserves the
   verifier-role posture without disabling the route for first-time
   triangulation.
3. **`priors_to_brms()` as a hard prerequisite** with KS-equivalence
   coverage on every distribution flexyBayes emits. Ships before any
   `stan_brms` user-visible call site; translation correctness is the
   load-bearing test gate.
4. **`aggregate = TRUE` refused at first ship** with forward-pointer.
   The algebra (composing brms `prior` with the aggregated `family =
   gaussian` likelihood) is sound but lacks test discipline; shipping
   without coverage violates the structural-disclosure posture.
5. **Toolchain default cmdstanr** (rstan tolerated). Team-coordination
   call per project §8. cmdstanr matches the brms community's stated
   2023--2024 direction and side-steps the rstan-CRAN-binary issues
   on Mac arm64 + Linux.

Two invocation modes share one runtime path: standalone fit
(`flexybayes(..., backend = "stan_brms")`) and triangulation pair
(`triangulate(engines = c("greta", "stan_brms"))`). Same dispatch, same
refusal codes (three new: `stan_brms_not_installed`,
`stan_brms_option_not_set`, `stan_brms_aggregate_refused`).

## Forward cost

- **Suggests dependency on brms.** Pinned at the minimum version that
  exposes the prior-translation surfaces `priors_to_brms()` needs (TBD
  at implementation time; brms `>=` 2.20 is the current lower bound
  under evaluation). The CRAN incoming check inherits the brms
  dependency graph in its `Suggests:` analysis.
- **Two-step user activation** documented as a worked example in the
  v0.4.0 *triangulation* vignette. Users who install brms but forget
  the `options()` flip get a refusal naming the next step.
- **cmdstanr requires out-of-band Stan install** via
  `cmdstanr::install_cmdstan()`. The v0.4.0 *getting-started* vignette
  adds this step in a clearly-flagged section so first-time users are
  not surprised by the additional build dependency.
- **`stan` backend label reserved.** Future direct-Stan-emit ADR can
  register cleanly as `backend = "stan"` (one `fb_engine()` registry
  entry); the label is not poached by ADR 0028.
- **`aggregate = TRUE` deferral carries a future enabler ADR.** No
  commitment to ever enable it on `stan_brms` -- conditional on
  observed user demand. Refusal message embeds the ADR-pointer so
  users probing find the forward-state.
- **Pair-coupled release commitment.** ADR 0028 and ADR 0029 must
  ship together. If team-coordination on Q1--Q3 (roster ordering,
  methods-paper framing, toolchain) does not clear in time for v0.4.0
  branch cut, the pair slips cleanly to v0.4.1 -- no decoupled release.
- **Methods-paper headline claim extends.** v0.4.0 ships with three-
  engine triangulation evidence on hand (gretaR + INLA + `stan_brms`)
  rather than two; preprint window opens stronger but requires the
  three-row axis-label diagram in the methods section of the
  companion paper.

## References

### Methodological

- Bürkner, P.-C. (2017). brms: An R package for Bayesian multilevel
  models using Stan. *Journal of Statistical Software*, 80(1), 1--28.
  doi:10.18637/jss.v080.i01 -- the brms engine paper; load-bearing for
  the verifier-role choice (brms is the maintained `formula to Stan`
  gold standard in R).
- Gelman, A., Vehtari, A., Simpson, D., Margossian, C. C., Carpenter,
  B., Yao, Y., Kennedy, L., Gabry, J., Bürkner, P.-C., & Modrák, M.
  (2020). Bayesian workflow. *arXiv* 2011.01808. §6 on cross-implementation
  posture -- the methodological anchor for *why* a verifier backend
  matters even when the primary backend (greta) is sound.
- Vehtari, A., Gelman, A., & Gabry, J. (2017). Practical Bayesian model
  evaluation using leave-one-out cross-validation and WAIC. *Statistics
  and Computing*, 27(5), 1413--1432. doi:10.1007/s11222-016-9696-4 --
  source of the *"approximations are first-class iff they tell you when
  not to trust them"* posture transposed to multi-engine triangulation.

### Empirical

- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §1.1 (steps
  2--5) -- the design-thinking arc that produced ADR 0028 from Max's
  mid-session question.
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §2.1 (decision
  summary) + §8.1 (alternatives-bracketing matrix on five sub-decisions).
- `design-notes-priors-brms-lgm.md` ADR 0014 -- the brms-as-surface
  ratification; ADR 0028 partitions brms's architectural roles by
  separating surface from backend.
- `design-notes-priors-brms-lgm.md` ADR 0015 (v0.1 draft) -- the
  superseded sketch of brms-as-backend; ADR 0028 carries the framing
  ADR 0015 did not name.

### Operational

- Cairn: `2026-05-25-adr-0029-triangulation-axis-vocabulary.cairn.md`
  (this project) -- the pair-coupled axis-vocabulary cairn.
- Cairn: `2026-05-25-adr-0030-architectural-final-v040.cairn.md` (this
  project) -- the meta-ADR that absorbs ADR 0028 into the
  architectural-final contract via `fb_engine()` constructor noun.
- Cairn: `2026-05-25-v038-plan-12-ratifications.cairn.md` (this
  project) -- the v0.3.8 release plan ratifications; ADR 0028
  implementation explicitly not in v0.3.8 scope (per §2.2 deferral).
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0028 at ~L3239.
- AMBITION_STAGE.md §2.8 -- the release-slot reservation for the
  pair-coupled ADR 0028 + 0029.
