# flexyBayes — validation, walkthrough & primer

This folder is the public evidence bundle for **flexyBayes** — flexible Bayesian
mixed models specified with ASReml- or brms-style formula syntax and estimated via
the greta, INLA, or brms backends. It collects a reproducible validation study, a
two-actor walkthrough on real public data, and a methods-deep primer.

Open `index.html` for the landing page that links all three.

## What is validated

flexyBayes translates a single formula specification into backend-specific code, so
the central questions are **correctness** (does a fit recover the right answer
against an independent reference?) and **translation fidelity** (does a fit through
flexyBayes reproduce the same model written directly in the backend?). Every number
is computed by a runnable benchmark and read from a cache — never hand-typed.

| Card | Model | Independent oracles | Result |
|------|-------|---------------------|--------|
| `flexybayes` (fixed effects) | Gaussian linear regression, coefficient recovery | `lm()` (exact OLS) + known data-generating truth | recovers coefficients to **3.45e-6** of `lm()` |
| `flexybayes` via INLA | Random-intercept LMM on `sleepstudy` | standalone `INLA::inla()` + `lme4::lmer()` REML | reproduces a hand-written INLA fit to **1.04e-4**; fixed effects within 1.5·SE of lme4 |
| `flexybayes` via greta | Random-intercept LMM, TensorFlow HMC | `lme4::lmer()` REML | fixed effects within 1.5·SE of lme4 (largest difference 3.49) |
| `flexybayes` via brms | Random-intercept LMM, Stan HMC | standalone `brms::brm()` + `lme4::lmer()` REML | Days slope agrees to 0.013 of lme4 |

All four cards ran with real numbers. The headline: one formula specification fitted
three ways gives concordant **fixed-effect** estimates, and the INLA fit reproduces a
hand-written INLA fit of the same model to numerical precision. The validation here
is of the fixed-effect inference; the variance-component scale is discussed honestly
in the INLA card (the subject-variance posterior collapses toward zero on these data,
matching a hand-written INLA fit under the default group hyperprior).

A **full-surface input-conformance sweep** complements the flagship cards: it
exercises the 42-function exported surface two-sided (valid inputs graded against an
oracle, bad inputs required to be rejected cleanly). 29 cells, 1 finding
(`fb_cov(NA)` is accepted silently), two-sided coverage 0.119 — the rest of the
surface carries a clean-rejection negative case.

## Folder map

```
report/
├── index.html           landing page (start here)
├── README.md            you are here
├── assets/              shared stylesheet
├── tutorial/            methods-deep primer (ASReml -> Bayesian origins -> flexyBayes -> its reach)
├── walkthrough/         two-actor reproduce-in-30-min narrative on sleepstudy (index.html + walkthrough.qmd)
└── validation/          the reproducible validation study
    ├── pdf/             rendered dossiers: all-in-one.pdf (comprehensive), crisp.pdf, and per-view PDFs
    ├── site/index.html  the interactive HTML explorer (re-group cards live)
    ├── cards/           one .qmd per card (meaning, maths, code, validation, competitors)
    ├── bench/           runnable benchmarks (compute the numbers)
    │   ├── results/     cached .rds the cards read
    │   └── contract-full.R   the full-surface conformance sweep
    ├── ai/evidence.json machine-readable card / oracle / conformance index
    ├── build.R          render driver
    └── reproduce.R      one-command reproduction entry point
```

## Reproduce

The card benchmarks are self-contained R scripts. From `validation/`:

```sh
Rscript bench/fb-correctness.R          # Gaussian recovery vs lm()  (seconds)
Rscript bench/fb-inla-correctness.R     # LMM vs standalone INLA + lme4  (seconds)
Rscript bench/fb-greta-correctness.R    # LMM via greta/TF-HMC vs lme4  (minutes)
Rscript bench/fb-brms-correctness.R     # LMM via brms/Stan vs standalone brms + lme4  (minutes)
Rscript bench/contract-full.R           # full-surface input-conformance sweep  (seconds)
```

Each card benchmark writes a cached result the corresponding card reads, so the
rendered study always reflects a real run. To re-render the PDFs and the explorer
from the caches, set `PV_ENGINE` to the validation engine directory and run
`Rscript build.R render`. Requires R with `lme4`, `INLA`, `brms`, and (for the greta
card) `greta` available.
