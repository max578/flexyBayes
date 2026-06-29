# flexyBayes — validation & benchmark report

This folder is the public evidence bundle for **flexyBayes** — flexible Bayesian
mixed models specified with ASReml- or brms-style formula syntax and estimated via
the greta, INLA, or brms backends. It collects a reproducible validation study that
checks flexyBayes against independent reference implementations.

## What is validated

flexyBayes translates a single formula specification into backend-specific code, so
the central question is **correctness and translation fidelity**: does a model fit
through flexyBayes reproduce the same model written directly in the backend, and
does it agree with an established independent reference? Each card answers that with
numbers computed from a runnable benchmark — never hand-typed.

| Card | Model | Independent oracles | Status |
|------|-------|---------------------|--------|
| `fb` | Gaussian linear regression, coefficient recovery | `lm()` (exact OLS) + known data-generating truth | **Pass** — agrees with `lm()` to ≤ 3.4e-6 |
| `fb_inla` | Random-intercept LMM on `sleepstudy` | standalone `INLA::inla()` + `lme4::lmer()` (REML) | **Pass** — identical to standalone INLA; within 1.5·SE of lme4 |
| `fb_greta` | Random-intercept LMM via greta (TensorFlow HMC) | `lme4::lmer()` (REML) | Authored & runnable; run separately (HMC takes minutes) |

The headline result: flexyBayes via INLA is **numerically identical** to a
hand-written `INLA::inla()` fit of the same model, and both agree with the `lme4`
REML reference — direct evidence that the formula-to-backend translation is exact
for these models.

## Folder map

```
report/
├── README.md            you are here
└── validation/          the reproducible validation study
    ├── cards/            one .qmd per card (rationale, maths, code, results)
    ├── bench/            the runnable benchmarks (compute the numbers)
    │   └── results/      cached .rds the cards read
    ├── ai/evidence.json  machine-readable card/oracle/conformance index
    ├── build.R           render driver
    └── reproduce.R       one-command reproduction entry point
```

## Reproduce

The benchmarks are self-contained R scripts. From this folder:

```sh
cd validation
Rscript bench/fb-correctness.R          # Gaussian recovery vs lm()  (seconds)
Rscript bench/fb-inla-correctness.R     # LMM vs standalone INLA + lme4  (seconds)
Rscript bench/fb-greta-correctness.R    # LMM via greta/TF-HMC vs lme4  (minutes)
```

Each writes a cached result the corresponding card reads, so the rendered study
always reflects a real run. Requires R with `lme4`, `INLA`, and (for the greta
card) `greta` available.
