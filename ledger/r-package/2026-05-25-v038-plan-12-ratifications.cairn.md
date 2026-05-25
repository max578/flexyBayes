---
id: 2026-05-25-v038-plan-12-ratifications
schema_version: 1.1
date: 2026-05-25
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "v0.3.8 release plan §12 ratifications -- six ratified scope and discipline calls"
tags: [v038, release-plan, ratification, audit-close, audit-2026-05-25, scope, deprecation-prep]
triggers:
  - adr_class_commitment
  - methodology_change_downstream
  - breaking_change_with_deprecation
reversal_cost: medium
decision_pressure: audit_close
supersedes: []
superseded_by: null
related:
  - 2026-05-25-adr-0030-architectural-final-v040
  - 2026-05-25-predict-kernel-extraction
  - 2026-05-25-adr-0028-stan-brms-backend-verifier
  - 2026-05-25-adr-0029-triangulation-axis-vocabulary
---

## Status

Ratified 2026-05-25 by Max during the mid-session review pass on
`v038-plan-2026-05-25.md` §12.6. All five §12.1--§12.5 decision points
answered (one rolled up into six concrete sub-ratifications captured
here). The §14 approval-checklist at the end of `v038-plan-2026-05-25.md`
has all ten items flipped to ratified state in the same revision.
Work proceeds per §13 (the runnable command sequence) at next-session
pickup. Anchored in:

- `v038-plan-2026-05-25.md` §12.6 (ratification block) + §14 (approval
  checklist) + §13 (runnable command sequence)
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §5 (the
  five gating decisions) + §8.4 (six-decision alternatives-bracketing
  matrix)
- `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` (the audit whose Critical
  Fixes #1--#5 the v0.3.8 plan closes)
- ADR 0030 (the architectural-final shape whose distribution this plan
  implements -- v0.3.8 ships contracts C1 + C2 + C7 scaffold; v0.4.0
  ships the remaining four)

## Alternatives considered

The crossroads was *what shape commits the v0.3.8 hardening release*.
Three coherent overall plan shapes were on the table once the audit
input landed, before §12 ratification narrowed to the chosen one:

| Option | One-line description |
|---|---|
| A | Audit-close only -- four Phase commits restricted to the five Critical Fixes; no scaffolding of v0.4.0 contracts. |
| B (CHOSEN) | Audit-close + scaffolding (3 of 7 contracts ship at v0.3.8); selective vignette refresh; six concrete §12.6 ratifications across scope, nomenclature, discipline. |
| C | Full v0.4.0 sprint -- ship C3 + C5 + C6 + constructor nouns + deprecation cycle in one release; skip v0.3.8 as a release boundary. |
| D | Stage-by-stage -- one ADR-contract per minor release; v0.3.8 ships C1 only, v0.3.9 ships C2 only, etc. |

## Rationale for rejection

### Option A -- audit-close only

Defers C1 + C2 + C7 scaffolding to v0.4.0. v0.4.0 then carries both
the audit-close residue (anything not closed at v0.3.8) and the full
architectural rollout (constructor nouns + remaining four contracts +
deprecation cycle + vignette deck restructure + huge-N probe) in one
release. The v0.4.0 trust-release implementation risk concentrates.
Splitting the substrate work (C1 + C2 + C7 scaffold) into v0.3.8
reduces v0.4.0 implementation risk by giving v0.4.0 a clean substrate
to build on; the audit-close work that depends on the substrate
(Critical Fix #4 print extension consumes C7 scaffold; Critical Fix
#1 prediction-kernel extraction *is* C2) ships in the same release as
the scaffold, so the dependency is internal to v0.3.8.

### Option C -- full v0.4.0 sprint

3--4 months L99 commitment without an intermediate checkpoint. The
validated release rhythm since v0.3.0 (approximately 3 weeks per
minor, per the v0.3.1 through v0.3.7 cadence) suggests two staged
minors are safer than one big-bang. The methods-paper publication
window also opens before a single 3--4 month sprint would close,
weakening the preprint's headline-claim evidence base. The audit
itself was scoped to be closeable; not closing it in the next
release cycle would leave the audit's structural recommendations
sitting against a moving target.

### Option D -- stage-by-stage

Extends the v0.4.0 timeline past the methods-paper publication
window (which is the load-bearing external deadline). Per-release
contract granularity also means each release has minimal scope
content beyond its one contract -- release ceremony overhead
(version bump + tarball + check + tag + dev-bump) dominates the
release effort. Cadence math: 7 contracts / 1-per-release = 7
release cycles = ~21 weeks at the validated rhythm; B compresses
to two releases (v0.3.8 + v0.4.0) = ~7 weeks.

## Implemented option (B) -- six concrete §12.6 sub-ratifications

1. **§12.6 (1) -- v0.3.8 scope.** Four Phase commits per §2.1:
   Phase A `fix:` shared prediction kernel + known-matrix alignment +
   sparse-precision policy; Phase B `feat:` `fb_plan()` + truth-display
   print + refusal-registry scaffold; Phase C `docs:` truth sweep;
   Phase D `test:` skip ledger + benchmark profiles. Six deferrals
   per §2.2 respected. Stage 5A `blocks` emit slips cleanly to v0.3.9
   (does not race even if Phase A + B close ahead of schedule).
2. **§12.6 (2) -- `<fb_plan>` print noun.** `Exactness label:` ->
   `Representation:` so the planner pre-fit surface and the post-fit
   `print.flexybayes()` two-line truth display use the same noun.
   Closes the conflation audit Critical Fix #4 addresses on the
   post-fit surface; prevents re-introducing it on the pre-fit
   surface. Applied to `v038-plan-2026-05-25.md` §5.3 sketch in the
   same revision.
3. **§12.6 (3) -- vignette refresh scope.** Selective subset. Re-
   precompile only vignettes whose `print(fit)` / `summary(fit)`
   output prose changes under the new `Representation:` / `Engine:`
   print extension. Full 11-vignette sweep deferred to v0.4.0
   alongside the vignette deck restructure. `--all-stale` fallback
   remains available if Phase A + B close ahead of schedule. Applied
   to §6.2, §6.3, §10 row 3, §13 in the same revision.
4. **§12.6 (4) -- discretionary tarball checkpoint at v0.3.8.** Keeps
   the post-v0.3.1 retention cadence (seven consecutive releases now);
   skipping would be the first cadence break. AMBITION_STAGE §8.6
   named v0.3.0 / v0.3.6 / v0.4.0 as Max-mandated checkpoints; v0.3.8
   lands as a discretionary checkpoint at the implementer's call --
   audit-close releases warrant retention.
5. **§12.6 (5) -- ADR 0030 ratification before branch cut.** ADR 0030
   status header at `design-notes-priors-brms-lgm.md` ~L3570 flipped
   `Proposed` -> `Accepted 2026-05-25` in the same revision; Phase B
   commit messages reference ADR 0030 §C1 / §C7 / Decision 4 by
   section anchor, which require the anchors to exist at commit-write
   time, which requires ratification to precede the branch cut.
6. **§12.6 (implicit) -- L99 effort budget approved.** ~3 weeks,
   ~15 L99 days. Hard scope-lock at §2.1; anything not in the four
   Phase commits + the release ceremony slips cleanly to v0.3.9.

The six sub-ratifications together unblock the §13 runnable command
sequence; Phase A starts at next-session pickup.

## Forward cost

- **`hardening-pass-2026-05-26-v038` branch off `4dd7079`** is the
  committed work substrate. Branch name carries the originally-
  anticipated date (a foreign artefact preserved verbatim per the
  cairn `2026-05-25-predict-kernel-extraction` Status note).
- **Phase ordering A -> B -> C -> D is locked.** B before C because
  C re-precompiles vignettes that consume B's print extension; A
  before B because B's `<fb_plan>` consumes A's known-matrix
  alignment validators; C before D because D's skip-ledger reads
  the NEWS.md C refreshes. Out-of-order execution invalidates the
  selective-vignette scope optimisation.
- **Tarball at v0.3.8 commits to the eighth consecutive retention.**
  Cadence break would be visible to a future audit; keeping
  consistent.
- **`Representation:` noun is canonical across pre-fit and post-fit
  surfaces from v0.3.8 onwards.** Any future surface that needs to
  display representation information uses the same noun; vocabulary
  drift on this surface is now an ADR-amendment event (under ADR
  0030's closed-vocabulary discipline at C4).
- **Selective vignette refresh leaves session-info drift on the
  unmodified vignettes.** Acknowledged debt; cleared at the v0.4.0
  vignette deck restructure. Documented in NEWS.md and in the
  cran-comments.md for the v0.3.8 submission (if CRAN submission is
  ever attempted on v0.3.8; current posture is local-tag-only).
- **Stage 5A `blocks` emit deferral to v0.3.9 commits v0.3.9 to a
  focused-scope release.** v0.3.9 opens as Stage 5A blocks + low_rank
  refusal-stub release; v0.4.0 trust release starts from a cleaner
  v0.3.9 baseline.
- **ADR 0030 ratification at v0.3.8 plan time commits all v0.3.8
  Phase B commit messages to reference ADR 0030 by section anchor.**
  No silent retrofit; the anchors must remain stable through v0.4.0.

## References

### Methodological

- Conventional Commits 1.0.0 (2019). https://www.conventionalcommits.org/
  -- the `fix:` / `feat:` / `docs:` / `test:` prefix discipline applied
  to the four Phase commits.
- *Audit-close methodology* (`feedback_audit_close_methodology`,
  project-memory artefact validated twice in 2026-05-23 + 2026-05-24
  hardening passes) -- the themed Phase-commit + no-ff merge + release
  ceremony pattern; v0.3.8 plan §1.2 + §3 + §8 apply it verbatim.
- *Release-ceremony checklist* (`feedback_release_ceremony_checklist`,
  project-memory artefact reaffirmed six times across v0.3.2 through
  v0.3.7) -- lockstep DESCRIPTION + inst/CITATION + CITATION.cff
  version bump.

### Empirical

- `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` §Critical Fixes 1--5 +
  §Documentation And Governance Drift + §Test And Benchmark Advice --
  the specification this plan closes end-to-end.
- `v038-plan-2026-05-25.md` §1.3 (audit anchors verified table) --
  the five Critical Fixes cross-checked against the live source at
  HEAD `4dd7079`.
- `v038-plan-2026-05-25.md` §12.6 -- the ratification block; this
  cairn IS the durable ledger record of that block.
- `v038-plan-2026-05-25.md` §14 -- the ten-item approval checklist
  in ratified state.
- `adr-crossroads-and-walkthrough-anchors-2026-05-25.md` §8.4 -- the
  six-decision alternatives-bracketing matrix; structurally
  identical to this cairn's Rationale section.

### Operational

- Cairn: `2026-05-25-adr-0030-architectural-final-v040.cairn.md` (this
  project) -- the meta-ADR whose distribution this plan implements.
- Cairn: `2026-05-25-predict-kernel-extraction.cairn.md` (this project)
  -- Phase A's ratified output; the first contract this plan ships.
- Cairn: `2026-05-25-adr-0028-stan-brms-backend-verifier.cairn.md`
  (this project) -- explicitly deferred to v0.4.0 per §2.2.
- Cairn: `2026-05-25-adr-0029-triangulation-axis-vocabulary.cairn.md`
  (this project) -- explicitly deferred to v0.4.0 per §2.2.
- Commit: `4dd7079` (v0.3.7 release merge) -- the branch base.
- Branch: `hardening-pass-2026-05-26-v038` -- the substrate for the
  four Phase commits.
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0030 -- status
  `Accepted 2026-05-25` at L3570 per §12.6 (5).
