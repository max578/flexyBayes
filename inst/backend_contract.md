# flexyBayes backend contract (v1)

<!-- constellation-contract: machine-readable header; charter at flexyBayes_dev/CONSTELLATION.md -->
```yaml
contract: backend_contract
id: C1
version: 1
kind: interface
owner: flexyBayes
consumers: [greta, INLA, brms, gretaR, koine]
conformance_test: "backend conformance battery + triangulate() agreement within the SBC-calibrated threshold"
charter: flexyBayes_dev/CONSTELLATION.md
```

The interface any inference backend must honour to be a first-class flexyBayes
engine. flexyBayes depends on **this contract**, never on a backend's internals,
so backends (greta, INLA, brms/Stan, **gretaR**, **koine**) can evolve and be
released independently without breaking flexyBayes. This is the seam that keeps
the co-evolving projects in sync.

Status legend: [R] required, [O] optional/graceful.

## 1. Construction -- an IR-targetable, re-entrant model builder [R]

flexyBayes must be able to build a model **from data structures** (its IR: a
design matrix with named columns, a response, a family/link, optional random /
structured-covariance terms, prior specs) -- not from a parsed formula or a
`match.call()`-deparsed front-end, and not via a session-global graph that
forbids a second model in the same process.

- greta: flexyBayes emits greta code (the `emit_greta` codegen path).
- gretaR: `gretaR::model_from_arrays(targets, likelihood, names, precision)`
  (since v0.3.0.9000 / commit `689dac3`) -- re-entrant and deparse-free. **Met.**
- koine: an equivalent programmatic builder (to be confirmed against this clause).

## 2. Output -- `posterior::draws_array` [R]

The sampler returns (or flexyBayes can coerce to) a chain-structured
`posterior::draws_array`. gretaR returns this natively (`fit$draws`); greta
returns coda (flexyBayes coerces); INLA/Stan via their paths.

## 3. Canonical parameter names [R]

Posterior draws are labelled with flexyBayes's canonical tokens -- the design
column names for fixed effects (`(Intercept)`, `x`, ...), `sigma` for the
residual SD, group-SD tokens for random effects -- so `triangulate()` aligns
parameters across engines with no per-engine relabel.

- gretaR: `model_from_arrays(names = ...)` carries caller-supplied per-element
  names straight through to the draws (verified: a gaussian GLM returned
  `(Intercept)`, `x`, `sigma` directly). **Met -- no shim required.**
- A backend that cannot name parameters supplies a `canonical_names` mapper
  instead (the registry stub mechanism in `R/canonical_names.R`).

## 4. Determinism -- `seed=` [R]

A seed argument that fixes the sampler RNG, for reproducible fits and
SBC/conformance runs. gretaR: `mcmc(seed=)`. **Met.**

## 5. Capability declaration -- `capability_predicate` [R]

The backend (via its flexyBayes registry entry, `R/backend_registry.R`) declares
**which model classes it can fit**, as `function(fb) TRUE | <reason>`. The `auto`
router and `triangulate()` use only capable backends for a given model; an
incapable backend is skipped or refused with a clear message -- **never a break**.
This is how a backend "catches up" capability-by-capability: it widens its
predicate as it implements more, with no flexyBayes change. gretaR's initial
predicate covers GLMs + mixed (random intercept); structured-covariance
(`vm`/`ped`/`fa`/`us`) is its declared catch-up boundary.

## 6. Version floor + probe [R]

flexyBayes pins a minimum backend version (the one whose contract it tested
against) and probes install + version + capability at load. Below floor ->
**dormant** with a structured reason (`R/gretaR_slot.R` pattern), never silently
wrong. gretaR floor: the version carrying `model_from_arrays` + the GB1 NUTS fix
(>= 0.3.0.9000 / `689dac3`).

## 7. Process isolation [O, but required when symbols clash]

greta (TensorFlow) and gretaR (torch) export the same symbols
(`normal`/`model`/`mcmc`/...) and cannot co-load. flexyBayes therefore drives
gretaR through an **out-of-process worker** (`inst/gretaR_worker.R`): the worker
loads only gretaR, builds + samples, and returns a `draws_array`. This also
isolates a backend's heavy runtime state from flexyBayes's session.

---

## Conformance + drift detection (how sync is enforced)

1. **Executable conformance suite.** A backend-agnostic test battery asserts a
   backend honours clauses 1-4: it builds from the IR, returns a `draws_array`,
   recovers a known posterior, and **agrees with the reference backends within
   the SBC-calibrated `triangulate()` threshold**. Run in flexyBayes CI against
   the pinned backend version, plus a HEAD "canary" job for early warning.
2. **Triangulation as the live drift signal.** `triangulate()` already measures
   SBC-calibrated cross-engine agreement; a backend regression (wrong posterior,
   sampler bug) surfaces as disagreement beyond the calibrated null. The project's
   signature output doubles as the cross-project regression detector.
3. **Shared ledger.** Cross-project contract changes are recorded as cairns in
   both the flexyBayes and the backend ledgers.

A backend that passes the conformance suite at the pinned version is in sync; a
red canary against backend HEAD is the early warning that the contract is
drifting -- caught at the boundary, before it ships.
