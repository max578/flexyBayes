# flexyBayes validation study

A reproducible validation-and-benchmark study for **flexyBayes**. Four flagship
cards check that a model fit *through* flexyBayes reproduces the same model written
directly in the backend, and agrees with an established independent reference —
every number computed by a runnable script, none hand-typed.

The readable summary is **[`index.html`](index.html)**; the machine-readable index
is **[`ai/evidence.json`](ai/evidence.json)**.

## Layout

```
validation/
├── index.html      summary of the four cards (start here)
├── cards/          one .qmd per card (rationale, maths, code, results)
├── bench/          the runnable benchmarks that compute the numbers
│   └── results/    cached .rds the cards read
├── ai/evidence.json   machine-readable card / oracle / conformance index
├── build.R         render driver
└── reproduce.R     one-command reproduction entry point
```

## Reproduce

Requires R with `flexyBayes`, `lme4`, `INLA`, `greta`, and `brms` available.

```sh
Rscript bench/fb-correctness.R       # Gaussian recovery vs lm()            (seconds)
Rscript bench/fb-inla-correctness.R  # LMM vs standalone INLA + lme4        (seconds)
Rscript bench/fb-greta-correctness.R # LMM via greta / TensorFlow-HMC vs lme4  (~1 min)
Rscript bench/fb-brms-correctness.R  # LMM via brms / Stan-HMC vs standalone brms + lme4
```

Each writes a cached result the corresponding card reads, so the rendered study
always reflects a real run.
