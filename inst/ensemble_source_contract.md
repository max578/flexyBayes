# flexyBayes ensemble-source contract (C5, v1)

The interface a **simulation ensemble** must honour to be ingested by flexyBayes
for the methods-intense work downstream of a process-based simulator (emulators,
distribution-preserving surrogates, mechanistic-statistical calibration,
multi-environment generalisation). It is contract **C5** in the flexyBayes
Constellation (`CONSTELLATION.md`).

The design rule it encodes: **APSIM data reaches flexyBayes through a contract,
not through a package monopoly and not by flexyBayes executing APSIM.** A
parameter→output ensemble is a *kind of data*; many producers can emit it
(a PESTO calibration manifest, a raw `apsimx` run, a saved file). flexyBayes
depends on **this shape**, never on a producer's internals.

Status legend: [R] required, [O] optional.

## Execution layer (named external upstream, not a member)

APSIM is executed by **`apsimx`** (F. Miguez, CRAN) -- the portfolio's single
APSIM-execution layer. No constellation member re-implements APSIM I/O; PESTO's
`apsim_callback()` is an *adapter for `apsimx`*, and flexyBayes never runs APSIM
itself. `apsimx` (or the partner's pipeline) sits upstream of every producer
below and is not part of this contract beyond producing conforming ensembles.

## The canonical object -- `fb_ensemble`

A list of class `c("fb_ensemble", "list")` with components:

- **`params`** [R] -- a `data.frame`, one row per parameter set, columns = the
  simulator's input parameters. The row order is the ensemble key.
- **`outputs`** [R] -- a `data.frame`, **row-aligned to `params`** (row *i* of
  `outputs` is the simulator's response to row *i* of `params`), columns = output
  dimensions. `nrow(outputs) == nrow(params)`.
- **`output_dims`** [O] -- a `data.frame` with one row per `outputs` column,
  labelling it with `(site, season, day, variable)` (the long/labelled view of
  ADR 0009 `fb_apsim_observations()`). `NULL` when outputs are unlabelled.
- **`observed`** [O] -- a named numeric (or one-row `data.frame`) of target
  observations, names a subset of `colnames(outputs)`. `NULL` for a pure
  forward ensemble (no calibration target).
- **`provenance`** [R] -- a list carrying at least `source` (the producer kind),
  and where known `apsim_version`, `seed`, `n_sets`, `simulator` (a callable or
  `NULL`), `created_via`.

`params` + `outputs` are exactly the `(X, Y)` an emulator / surrogate trains on;
`output_dims` + `observed` add the calibration framing when present.

## Conformance -- `verify_fb_ensemble()`

A producer conforms iff `verify_fb_ensemble(e)` returns `ok = TRUE`. It checks:
`params` / `outputs` are data.frames with equal, positive row counts; any
`observed` names are a subset of `colnames(outputs)`; any `output_dims` has one
row per `outputs` column; `provenance$source` is present. Failures return
`ok = FALSE` with a message naming the first violation (never a silent pass).

## Conforming producers

| Producer | Kind | How it conforms |
|---|---|---|
| **PESTO** | `pesto` | A `pesto_ensemble_manifest` (S7) carries `params`, `outputs` (row-aligned), `obs_target`, `apsim_version` -- a superset; `as_fb_ensemble()` maps it (adds `observed = obs_target`, `provenance$source = "pesto"`). This is the C2 → C5 bridge; PESTO's calibration framing (`weights`, hashes) is preserved in provenance, not required by C5. |
| **raw `apsimx` / in-memory** | `raw` | `fb_ensemble(params, outputs, ...)` directly, after the caller extracts an `apsimx` ensemble into two row-aligned data.frames. flexyBayes never calls `apsimx`; the caller (or a future thin adapter) does. |
| **file** | `file` | `read_fb_ensemble(path)` reads a saved `fb_ensemble` (or a `list(params, outputs, ...)`) from `.rds`. |
| **future (koine, surrogate)** | (registered) | Any new producer registers a coercer via `register_ensemble_source(class, coercer)` -- no flexyBayes edit. |

## Why a contract, not a monopoly

- **Standalone-functional** (constellation invariant 1): flexyBayes ingests an
  ensemble with no sibling installed -- `raw` and `file` need nothing; `pesto` is
  capability-gated and dormant-correct when PESTO is absent.
- **Decoupled clocks** (invariant 2): a methods study consumes a raw `apsimx`
  ensemble without waiting on PESTO's calibration release.
- **Acyclic** (invariant 5): `apsimx` is a leaf upstream; producers fan into the
  one `fb_ensemble` shape flexyBayes (the hub) consumes.

## Consumers (downstream; not built here)

`fb_pesto()` (the C2 calibrated-ensemble verb), the shared surrogate seam
(CME / GP / RFF), and `fb_apsim()` (the online simulator-in-likelihood verb,
ADR 0009, partner-gated) all build on `fb_ensemble`. This contract is the ingest
floor they share; each is provisioned in its own pass.
