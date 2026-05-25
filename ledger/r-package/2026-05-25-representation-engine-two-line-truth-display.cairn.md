---
id: 2026-05-25-representation-engine-two-line-truth-display
schema_version: 1.1
date: 2026-05-25
tier: T3
classification: open
export_status: local_only
consensus_mode: none
domain: r-package
project: flexyBayes
status: accepted
title: "Representation:/Engine: two-line truth display (ADR 0030 Decision 4)"
tags: [print, truth_display, exactness, adr_0030, v038_phase_b, audit_critical_fix_4]
triggers:
  - public_api_change
  - adr_class_commitment
reversal_cost: medium
decision_pressure: audit_close
review_due: null
review_trigger: null
supersedes: []
superseded_by: null
related: [2026-05-25-fb-plan-verb-exported-as-single-planning-surface]
---

## Status

Ratified 2026-05-25 alongside the `fb_plan()` ship, in the same v0.3.8 Phase B session. Closes 2026-05-25 audit Critical Fix #4 ("exactness conflation"). The pre-v0.3.8 `print.flexybayes()` rendered the fit's `$exactness` slot as a single line `Exact. : aggregated_exact`, which silently conflated *representation* (aggregated exact sufficient statistics vs per-row exact) with *inference engine* (greta MCMC vs INLA Laplace vs brms / Stan HMC). The two-line replacement disambiguates: `Representation: aggregated_exact (compression 5:1)` + `Engine: INLA Laplace (aggregated)`. Shipped in `R/methods.R` (print.flexybayes / summary.flexybayes / print.flexybayes_aggregated) plus new `R/methods_truth_display.R` housing the two shared helpers `.repr_label_for_fit()` and `.engine_label_for_fit()`.

## Alternatives considered

| Option | One-line description |
|---|---|
| A | Keep the single `Exact.:` line; document the conflation in the help page |
| B | Replace with a single `Engine:` line; drop representation rendering entirely |
| C | Replace with a single composite line: `Engine: INLA Laplace [aggregated_exact, 5:1]` |
| D (CHOSEN) | Two adjacent lines `Representation:` then `Engine:` -- structurally distinct surfaces |
| E | Drop the print rendering entirely; require users to consult `backend_decision()` |

## Rationale for rejection

### Option A

The audit named the conflation as Critical Fix #4 -- a documented misunderstanding is still a misunderstanding. Users do not read help pages mid-debug; they read the print output. The conflation showed up in support questions as "why does my INLA fit say `exact` -- I thought INLA was an approximation?", which the two-line display answers correctly (Representation says how the data is shaped; Engine says how the inference runs).

### Option B

Engine-only loses the aggregated-vs-per-row distinction, which is operationally important: an aggregated_exact INLA fit and a per-row exact INLA fit have different scaling behaviour, different posterior identifiability under sparse cells, and different prediction-time semantics. Hiding the representation regime would be worse than the conflation.

### Option C

Composite single line scans faster but loses the structural pair semantics. Future engine + representation expansions (e.g., a greta MCMC fit on an aggregated representation when that becomes possible, or a Stan / brms fit with new representation regimes from ADR 0027) would force the composite line to grow inline or wrap awkwardly. Two adjacent lines absorb the expansion cleanly.

### Option E

Same failure mode as Critical Fix #5 reasoning -- users should not have to type a second function to see information about a fit they just printed. `backend_decision()` is the forensic surface; `print()` is the inspection surface; both should exist.

## Implemented option (D)

```
  Representation: aggregated_exact (compression 5:1)
  Engine:         INLA Laplace (aggregated)
```

Two adjacent lines, aligned at column 19. `Representation:` reads off `fit$exactness` directly (the canonical slot since ADR 0022) with an `(compression N:K)` suffix when aggregated and N/K $\geq$ 2 (per ADR 0022 Decision 6's "avoid misleading claims" mitigation). `Engine:` maps `bd$backend` + `bd$path` via `.engine_label_for_fit()` to one of five labels: `greta MCMC`, `brms / Stan HMC`, `INLA Laplace`, `INLA Laplace (aggregated)`, `gretaR (R-native; dormant at v0.3.x)`. Shared helpers in `R/methods_truth_display.R` keep the three print methods (`print.flexybayes`, `summary.flexybayes`, `print.flexybayes_aggregated`) consistent and provide the same labelling surface to `fb_plan()`'s `representation_label` / `engine_label` slots. Eight test_that blocks in `tests/testthat/test-print-truth.R` snapshot the renderings + verify adjacency.

## Forward cost

- **The print surface is now a tested contract** (snapshot tests on the three engine labels + adjacency check). Renaming a label (e.g., `INLA Laplace` -> `R-INLA Laplace`) is a deprecation-cycle change.
- **The `$exactness` slot stays load-bearing** -- the renderer reads it directly, not via `backend_decision()$path`. Removing `$exactness` from the fit object would silently fall through to "no truth display" rather than raising. ADR 0022 Decision 5 (the slot's introduction) is reinforced.
- **The five engine labels are now an enumerated set**. Future backends (a v0.3.9 gretaR-activated path, an external Stan-direct path, an approximate-scheme `inla_pardiso_approximate` per ADR 0027) require explicit cases in `.engine_label_for_fit()`. Falling through to `<backend-name>` is a defensive fallback but is not the polished surface.
- **The `Agg.` line on `summary.flexybayes()` remains separate** from the Representation line -- it carries the explicit N -> K compression numerics with cell counts. Users see both pieces of information (representation label *and* numeric compression) under summary, only the label under print. This is a deliberate verbose-vs-tight asymmetry, not redundancy.
- **Snapshot tests do NOT cover full-fit objects** (greta / INLA fits are slow + version-drift-prone). They cover the helpers `.repr_label_for_fit()` + `.engine_label_for_fit()` against synthesised fit-shaped objects. The fit-integration path is covered transitively by the existing aggregated-emit tests.

## References

### Methodological

- Rue, H., Riebler, A., Sorbye, S. H., Illian, J. B., Simpson, D. P., & Lindgren, F. K. (2017). *Bayesian computing with INLA: A review*. Annual Review of Statistics and Its Application 4:395--421. (Reference for the INLA Laplace approximation regime distinct from greta MCMC; motivates the engine vocabulary.)
- Burkner, P.-C. (2017). *brms: An R package for Bayesian multilevel models using Stan*. Journal of Statistical Software 80(1):1--28. (Reference for the brms / Stan HMC label.)

### Empirical

- `R/methods.R:33--41` -- the two-line surface in `print.flexybayes()`.
- `R/methods.R:88--94` -- the two-line surface in `summary.flexybayes()`.
- `R/methods.R:182--186` -- the two-line surface in `print.flexybayes_aggregated()`.
- `R/methods_truth_display.R` -- the two shared helpers + their docstrings.
- `tests/testthat/test-print-truth.R` -- 8 test_that blocks covering 4 engine labels + adjacency + no-legacy-rendering check.
- Audit: `feedback_v0.3.7_to_v0.4.0_2026-05-25.md` Critical Fix #4 -- "exactness conflation between representation and engine".

### Operational

- ADR: `design-notes-priors-brms-lgm.md` §ADR 0030 Decision 4 (Representation:/Engine: two-line surface).
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0022 Decision 5 (the `$exactness` slot the renderer reads).
- ADR: `design-notes-priors-brms-lgm.md` §ADR 0022 Decision 6 (the `N/K >= 2` mitigation for the compression-ratio rendering).
- Plan: `v038-plan-2026-05-25.md` §5 (Phase B audit Critical Fix #4 closure).
- Cairn: `2026-05-25-fb-plan-verb-exported-as-single-planning-surface.cairn.md` -- the planning-side companion (same labels surface on `<fb_plan>`).
- Branch: `hardening-pass-2026-05-26-v038` (off `4dd7079` v0.3.7 release).
